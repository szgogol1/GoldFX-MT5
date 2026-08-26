//+------------------------------------------------------------------+
//| RiskManager.mqh — 资金管理 + 组合敞口 + 回撤暂停（无马丁/无网格）   |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_RISK_MANAGER_MQH
#define GOLDFX_RISK_MANAGER_MQH

#include "Common.mqh"
#include "AdaptiveRisk.mqh"
#include "Persistence.mqh"
#include <Trade\PositionInfo.mqh>

class CRiskManager
  {
private:
   int               m_magic;
   ENUM_MONEY_MODE   m_money_mode;
   ENUM_RISK_LEVEL   m_risk_level;
   double            m_risk_pct;
   double            m_fixed_lot;
   double            m_lot_per_1k;
   double            m_max_daily_loss_pct;
   double            m_max_equity_dd_pct;
   int               m_max_positions;      // 每品种
   int               m_max_portfolio;
   bool              m_corr_guard;
   bool              m_auto_pause;
   bool              m_paused;
   double            m_day_start_equity;
   double            m_peak_equity;
   int               m_day_stamp;
   double            m_last_eff_risk;
   CAdaptiveRisk     m_adapt;
   CPersistence     *m_persist;

   int TodayStamp(void) const
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return dt.year*10000+dt.mon*100+dt.day;
     }

   void RefreshBaselines(void)
     {
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_peak_equity)
        {
         m_peak_equity = eq;
         if(m_persist != NULL) m_persist.SavePeakEquity(m_peak_equity);
        }
      const int today = TodayStamp();
      if(today != m_day_stamp)
        {
         m_day_stamp = today;
         m_day_start_equity = eq;
        }
     }

   double NormalizeLot(const string symbol, double lot) const
     {
      double lot_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lot_max  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      if(lot_step <= 0.0) lot_step = 0.01;
      lot = MathFloor(lot / lot_step) * lot_step;
      return MathMax(lot_min, MathMin(lot_max, lot));
     }

public:
                     CRiskManager(void)
                       : m_magic(20260826), m_money_mode(MM_ADAPTIVE), m_risk_level(RISK_L4),
                         m_risk_pct(0.75), m_fixed_lot(0.01), m_lot_per_1k(0.02),
                         m_max_daily_loss_pct(2.5), m_max_equity_dd_pct(10.0),
                         m_max_positions(1), m_max_portfolio(3), m_corr_guard(true),
                         m_auto_pause(true), m_paused(false),
                         m_day_start_equity(0), m_peak_equity(0), m_day_stamp(0),
                         m_last_eff_risk(0.75), m_persist(NULL)
                     {
                     }

   void Init(CPersistence *persist, const SRuntimeParams &p)
     {
      m_persist = persist;
      Configure(p);
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      m_peak_equity = (m_persist!=NULL) ? m_persist.LoadPeakEquity(eq) : eq;
      if(m_peak_equity < eq) m_peak_equity = eq;
      m_paused = (m_persist!=NULL) ? m_persist.LoadPaused() : false;
      m_day_stamp = 0;
      RefreshBaselines();
      m_adapt.Init(persist, p);
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic = p.magic;
      m_money_mode = p.money_mode;
      m_risk_level = p.risk_level;
      m_risk_pct = MathMax(0.05, p.risk_percent);
      m_fixed_lot = MathMax(0.0, p.fixed_lot);
      m_lot_per_1k = MathMax(0.01, p.balance_lot_per_1k);
      m_max_daily_loss_pct = MathMax(0.1, p.max_daily_loss_pct);
      m_max_equity_dd_pct = MathMax(0.5, p.max_equity_dd_pct);
      m_max_positions = MathMax(1, p.max_positions);
      m_max_portfolio = MathMax(1, p.max_open_portfolio);
      m_corr_guard = p.correlation_guard;
      m_auto_pause = p.auto_pause_on_dd;
      m_adapt.Configure(p);
     }

   CAdaptiveRisk *Adapt(void) { return GetPointer(m_adapt); }
   bool Paused(void) const { return m_paused; }
   void SetPaused(const bool v)
     {
      m_paused = v;
      if(m_persist != NULL) m_persist.SavePaused(v);
     }
   double LastEffRisk(void) const { return m_last_eff_risk; }

   int CountSymbolPositions(const string symbol) const
     {
      CPositionInfo pos; int c=0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()==m_magic && pos.Symbol()==symbol) c++;
        }
      return c;
     }

   int CountPortfolio(void) const
     {
      CPositionInfo pos; int c=0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()==m_magic) c++;
        }
      return c;
     }

   int CountOurPositions(void) const { return CountPortfolio(); }

   int CountGroup(const string tag) const
     {
      CPositionInfo pos; int c=0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()!=m_magic) continue;
         if(CurrencyGroupTag(pos.Symbol())==tag) c++;
        }
      return c;
     }

   bool DailyLossExceeded(void)
     {
      RefreshBaselines();
      if(m_day_start_equity<=0) return false;
      const double dd = SafeDiv(m_day_start_equity-AccountInfoDouble(ACCOUNT_EQUITY), m_day_start_equity,0)*100.0;
      return (dd >= m_max_daily_loss_pct);
     }

   bool EquityDrawdownExceeded(void)
     {
      RefreshBaselines();
      if(m_peak_equity<=0) return false;
      const double dd = SafeDiv(m_peak_equity-AccountInfoDouble(ACCOUNT_EQUITY), m_peak_equity,0)*100.0;
      return (dd >= m_max_equity_dd_pct);
     }

   double DayPnLPercent(void)
     {
      RefreshBaselines();
      if(m_day_start_equity<=0) return 0;
      return SafeDiv(AccountInfoDouble(ACCOUNT_EQUITY)-m_day_start_equity, m_day_start_equity,0)*100.0;
     }

   double EquityDDPercent(void)
     {
      RefreshBaselines();
      if(m_peak_equity<=0) return 0;
      return SafeDiv(m_peak_equity-AccountInfoDouble(ACCOUNT_EQUITY), m_peak_equity,0)*100.0;
     }

   // 保证金安全检查（避免不安全回退）
   bool MarginSafe(const string symbol, const double lot, const ENUM_ORDER_TYPE type, string &reason) const
     {
      reason = "";
      double margin = 0;
      double price = SymbolInfoDouble(symbol, (type==ORDER_TYPE_BUY)?SYMBOL_ASK:SYMBOL_BID);
      if(!OrderCalcMargin(type, symbol, lot, price, margin))
        {
         reason = "OrderCalcMargin失败，拒绝开仓";
         return false;
        }
      const double free = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(margin <= 0.0 || free < margin * 1.2)
        {
         reason = StringFormat("保证金不足 need=%.2f free=%.2f", margin, free);
         return false;
        }
      return true;
     }

   bool CanOpenNew(const string symbol, const ENUM_SIGNAL side, string &reason)
     {
      reason = "";
      RefreshBaselines();

      if(m_paused)
        {
         reason = "EA已暂停（回撤/远程）";
         return false;
        }
      if(DailyLossExceeded())
        {
         reason = StringFormat("日内亏损保护 %.1f%%", m_max_daily_loss_pct);
         return false;
        }
      if(EquityDrawdownExceeded())
        {
         if(m_auto_pause) SetPaused(true);
         reason = StringFormat("净值回撤保护 %.1f%%", m_max_equity_dd_pct);
         return false;
        }
      if(CountSymbolPositions(symbol) >= m_max_positions)
        {
         reason = StringFormat("%s 持仓上限 %d（无网格）", symbol, m_max_positions);
         return false;
        }
      if(CountPortfolio() >= m_max_portfolio)
        {
         reason = StringFormat("组合敞口上限 %d", m_max_portfolio);
         return false;
        }
      if(m_corr_guard)
        {
         const string tag = CurrencyGroupTag(symbol);
         if(CountGroup(tag) >= 1 && (tag=="USD_PAIR" || tag=="XAU" || tag=="XAG"))
           {
            // 同组已有仓：禁止再开高度相关敞口
            reason = StringFormat("相关性保护：组 %s 已有仓", tag);
            return false;
           }
        }
      // 无马丁：同品种亏损仓不摊平
      CPositionInfo pos;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()!=m_magic || pos.Symbol()!=symbol) continue;
         if(pos.Profit() < 0.0)
           {
            reason = "禁止马丁：已有亏损仓";
            return false;
           }
        }
      return true;
     }

   double CalcLot(const string symbol, const double entry, const double sl, const double atr)
     {
      ENUM_MONEY_MODE mode = m_money_mode;
      double risk_pct = m_risk_pct;

      if(mode == MM_AUTO_LEVEL)
         mode = MM_RISK_PERCENT;
      if(mode == MM_ADAPTIVE)
        {
         risk_pct = m_adapt.EffectiveRiskPercent(EquityDDPercent(), atr);
         m_last_eff_risk = risk_pct;
         mode = MM_RISK_PERCENT;
        }
      else
         m_last_eff_risk = risk_pct;

      if(mode == MM_FIXED_LOT)
         return NormalizeLot(symbol, m_fixed_lot);
      if(mode == MM_BALANCE_PCT)
        {
         const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         return NormalizeLot(symbol, m_lot_per_1k * (bal/1000.0));
        }

      const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (risk_pct/100.0);
      const double stop_dist = MathAbs(entry - sl);
      if(stop_dist <= 0.0)
         return NormalizeLot(symbol, m_fixed_lot);

      const double tick_size  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
         return NormalizeLot(symbol, m_fixed_lot);

      double lot = risk_money / (SafeDiv(stop_dist, tick_size, 0.0) * tick_value);
      // 显式夹紧，避免静默截断无日志
      const double before = lot;
      lot = NormalizeLot(symbol, lot);
      if(MathAbs(before - lot) / MathMax(before, 1e-8) > 0.25)
         PrintFormat("手数夹紧 %.4f -> %.4f (%s risk%%=%.3f)", before, lot, symbol, risk_pct);
      return lot;
     }
  };

#endif
//+------------------------------------------------------------------+
