//+------------------------------------------------------------------+
//| AdaptiveRisk.mqh — 回撤感知 + ATR 波动缩放 + 滚动胜率/凯利调整      |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_ADAPTIVE_RISK_MQH
#define GOLDFX_ADAPTIVE_RISK_MQH

#include "Common.mqh"
#include "Persistence.mqh"

class CAdaptiveRisk
  {
private:
   bool              m_use_dd;
   bool              m_use_atr;
   bool              m_use_kelly;
   double            m_atr_ref;
   double            m_base_risk;
   double            m_max_dd_pct;
   int               m_roll_wins;
   int               m_roll_trades;
   double            m_mult;          // 综合乘数
   CPersistence     *m_persist;
   static const int  ROLL_MAX = 20;

public:
                     CAdaptiveRisk(void)
                       : m_use_dd(true), m_use_atr(true), m_use_kelly(true),
                         m_atr_ref(0.0), m_base_risk(0.75), m_max_dd_pct(10.0),
                         m_roll_wins(0), m_roll_trades(0), m_mult(1.0), m_persist(NULL)
                     {
                     }

   void Init(CPersistence *persist, const SRuntimeParams &p)
     {
      m_persist = persist;
      Configure(p);
      if(m_persist != NULL)
        {
         m_persist.LoadRollStats(m_roll_wins, m_roll_trades);
         m_mult = m_persist.LoadAdaptMult(1.0);
        }
     }

   void Configure(const SRuntimeParams &p)
     {
      m_use_dd     = p.adapt_dd_scale;
      m_use_atr    = p.adapt_atr_scale;
      m_use_kelly  = p.adapt_kelly_scale;
      m_atr_ref    = p.adapt_atr_ref;
      m_base_risk  = MathMax(0.05, p.risk_percent);
      m_max_dd_pct = MathMax(1.0, p.max_equity_dd_pct);
     }

   double Multiplier(void) const { return m_mult; }
   int    RollTrades(void) const { return m_roll_trades; }
   double RollWinRate(void) const
     {
      if(m_roll_trades <= 0) return 0.5;
      return (double)m_roll_wins / (double)m_roll_trades;
     }

   void OnTradeClosed(const bool win)
     {
      // 滚动窗口近似：超过 20 笔时按比例衰减
      if(m_roll_trades >= ROLL_MAX)
        {
         m_roll_wins   = (int)MathRound(m_roll_wins * 0.9);
         m_roll_trades = (int)MathRound(m_roll_trades * 0.9);
        }
      m_roll_trades++;
      if(win) m_roll_wins++;
      if(m_persist != NULL)
         m_persist.SaveRollStats(m_roll_wins, m_roll_trades);
     }

   // 返回最终应用的风险%（已乘自适应系数，封顶/保底）
   double EffectiveRiskPercent(const double equity_dd_pct, const double current_atr)
     {
      double mult = 1.0;

      // 1) 回撤感知：DD 达上限时风险降至 50%
      if(m_use_dd && m_max_dd_pct > 0.0)
        {
         const double ratio = MathMin(1.0, MathMax(0.0, equity_dd_pct / m_max_dd_pct));
         const double dd_mult = 1.0 - 0.5 * ratio; // 1.0 → 0.5
         mult *= dd_mult;
        }

      // 2) ATR 反比：波动升高则降仓
      if(m_use_atr && current_atr > 0.0)
        {
         double ref = m_atr_ref;
         if(ref <= 0.0)
            ref = current_atr; // 首笔建立参考
         if(m_atr_ref <= 0.0)
            m_atr_ref = current_atr;
         else
            m_atr_ref = 0.9 * m_atr_ref + 0.1 * current_atr; // 慢速跟踪
         ref = m_atr_ref;
         double atr_mult = SafeDiv(ref, current_atr, 1.0);
         atr_mult = MathMax(0.5, MathMin(1.5, atr_mult));
         mult *= atr_mult;
        }

      // 3) 滚动胜率 / 简化凯利：f ~ WR - (1-WR) 缩放到 0.6~1.2
      if(m_use_kelly && m_roll_trades >= 5)
        {
         const double wr = RollWinRate();
         const double edge = wr - (1.0 - wr); // 2*wr-1
         double k_mult = 1.0 + 0.4 * edge;   // wr=0.5→1.0; wr=0.7→1.16; wr=0.3→0.84
         k_mult = MathMax(0.6, MathMin(1.2, k_mult));
         mult *= k_mult;
        }

      mult = MathMax(0.35, MathMin(1.5, mult));
      m_mult = mult;
      if(m_persist != NULL)
         m_persist.SaveAdaptMult(m_mult);

      double risk = m_base_risk * mult;
      // 防止静默截断：显式夹紧并保证下限
      risk = MathMax(0.05, MathMin(5.0, risk));
      return risk;
     }
  };

#endif
//+------------------------------------------------------------------+
