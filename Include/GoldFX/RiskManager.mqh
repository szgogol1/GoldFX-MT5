//+------------------------------------------------------------------+
//| RiskManager.mqh — 多种资金管理 + 日内/净值回撤保护（无马丁）         |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_RISK_MANAGER_MQH
#define GOLDFX_RISK_MANAGER_MQH

#include "Common.mqh"
#include <Trade\PositionInfo.mqh>

class CRiskManager
  {
private:
   string            m_symbol;
   int               m_magic;
   ENUM_MONEY_MODE   m_money_mode;
   ENUM_RISK_LEVEL   m_risk_level;
   double            m_risk_pct;
   double            m_fixed_lot;
   double            m_lot_per_1k;
   double            m_max_daily_loss_pct;
   double            m_max_equity_dd_pct;
   int               m_max_positions;
   bool              m_allow_martingale;
   double            m_day_start_equity;
   double            m_peak_equity;
   int               m_day_stamp;

   int TodayStamp(void) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void RefreshBaselines(void)
     {
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(eq > m_peak_equity)
         m_peak_equity = eq;

      const int today = TodayStamp();
      if(today != m_day_stamp)
        {
         m_day_stamp = today;
         m_day_start_equity = eq;
        }
     }

   double NormalizeLot(double lot) const
     {
      double lot_min  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lot_max  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(lot_step <= 0.0)
         lot_step = 0.01;
      lot = MathFloor(lot / lot_step) * lot_step;
      return MathMax(lot_min, MathMin(lot_max, lot));
     }

public:
                     CRiskManager(void)
                       : m_symbol(_Symbol),
                         m_magic(20260826),
                         m_money_mode(MM_AUTO_LEVEL),
                         m_risk_level(RISK_L4),
                         m_risk_pct(0.75),
                         m_fixed_lot(0.01),
                         m_lot_per_1k(0.02),
                         m_max_daily_loss_pct(2.5),
                         m_max_equity_dd_pct(10.0),
                         m_max_positions(1),
                         m_allow_martingale(false),
                         m_day_start_equity(0.0),
                         m_peak_equity(0.0),
                         m_day_stamp(0)
                     {
                     }

   void Init(const string symbol, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      m_day_stamp = 0;
      Configure(p);
      RefreshBaselines();
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic              = p.magic;
      m_money_mode         = p.money_mode;
      m_risk_level         = p.risk_level;
      m_risk_pct           = MathMax(0.01, p.risk_percent);
      m_fixed_lot          = MathMax(0.0, p.fixed_lot);
      m_lot_per_1k         = MathMax(0.01, p.balance_lot_per_1k);
      m_max_daily_loss_pct = MathMax(0.1, p.max_daily_loss_pct);
      m_max_equity_dd_pct  = MathMax(0.5, p.max_equity_dd_pct);
      m_max_positions      = MathMax(1, p.max_positions);
      m_allow_martingale   = false; // 强制关闭马丁
     }

   ENUM_RISK_LEVEL RiskLevel(void) const { return m_risk_level; }
   ENUM_MONEY_MODE MoneyMode(void) const { return m_money_mode; }

   int CountOurPositions(void) const
     {
      CPositionInfo pos;
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol() == m_symbol && pos.Magic() == m_magic)
            count++;
        }
      return count;
     }

   bool DailyLossExceeded(void)
     {
      RefreshBaselines();
      if(m_day_start_equity <= 0.0)
         return false;
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd = SafeDiv(m_day_start_equity - eq, m_day_start_equity, 0.0) * 100.0;
      return (dd >= m_max_daily_loss_pct);
     }

   bool EquityDrawdownExceeded(void)
     {
      RefreshBaselines();
      if(m_peak_equity <= 0.0)
         return false;
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd = SafeDiv(m_peak_equity - eq, m_peak_equity, 0.0) * 100.0;
      return (dd >= m_max_equity_dd_pct);
     }

   double DayPnLPercent(void)
     {
      RefreshBaselines();
      if(m_day_start_equity <= 0.0)
         return 0.0;
      return SafeDiv(AccountInfoDouble(ACCOUNT_EQUITY) - m_day_start_equity,
                     m_day_start_equity, 0.0) * 100.0;
     }

   double EquityDDPercent(void)
     {
      RefreshBaselines();
      if(m_peak_equity <= 0.0)
         return 0.0;
      return SafeDiv(m_peak_equity - AccountInfoDouble(ACCOUNT_EQUITY),
                     m_peak_equity, 0.0) * 100.0;
     }

   bool CanOpenNew(string &reason)
     {
      reason = "";
      if(DailyLossExceeded())
        {
         reason = StringFormat("日内亏损保护 %.1f%%", m_max_daily_loss_pct);
         return false;
        }
      if(EquityDrawdownExceeded())
        {
         reason = StringFormat("净值回撤保护 %.1f%%（峰值起）", m_max_equity_dd_pct);
         return false;
        }
      const int open_n = CountOurPositions();
      if(open_n >= m_max_positions)
        {
         reason = StringFormat("持仓上限 %d（禁止网格堆仓）", m_max_positions);
         return false;
        }
      // 无马丁：已有亏损仓时不允许同向加仓摊平
      if(!m_allow_martingale && open_n > 0)
        {
         CPositionInfo pos;
         for(int i = PositionsTotal() - 1; i >= 0; --i)
           {
            if(!pos.SelectByIndex(i))
               continue;
            if(pos.Symbol() != m_symbol || pos.Magic() != m_magic)
               continue;
            if(pos.Profit() < 0.0)
              {
               reason = "禁止马丁：已有亏损仓，不摊平加仓";
               return false;
              }
           }
        }
      return true;
     }

   double CalcLot(const double entry, const double sl)
     {
      ENUM_MONEY_MODE mode = m_money_mode;
      if(mode == MM_AUTO_LEVEL)
         mode = MM_RISK_PERCENT; // 八档自动 → 用档位写入的 risk_percent

      if(mode == MM_FIXED_LOT)
         return NormalizeLot(m_fixed_lot);

      if(mode == MM_BALANCE_PCT)
        {
         const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
         return NormalizeLot(m_lot_per_1k * (bal / 1000.0));
        }

      // MM_RISK_PERCENT
      const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (m_risk_pct / 100.0);
      const double stop_dist  = MathAbs(entry - sl);
      if(stop_dist <= 0.0)
         return NormalizeLot(m_fixed_lot);

      const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
         return NormalizeLot(m_fixed_lot);

      double lot = risk_money / (SafeDiv(stop_dist, tick_size, 0.0) * tick_value);
      return NormalizeLot(lot);
     }
  };

#endif
//+------------------------------------------------------------------+
