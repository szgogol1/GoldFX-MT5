//+------------------------------------------------------------------+
//| RiskManager.mqh — 仓位与日内风控                                   |
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
   double            m_risk_pct;
   double            m_fixed_lot;
   bool              m_use_fixed;
   double            m_max_daily_loss_pct;
   int               m_max_positions;
   double            m_day_start_equity;
   int               m_day_stamp;          // YYYYMMDD

   int TodayStamp(void) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void RefreshDayBaseline(void)
     {
      const int today = TodayStamp();
      if(today != m_day_stamp)
        {
         m_day_stamp = today;
         m_day_start_equity = AccountInfoDouble(ACCOUNT_EQUITY);
        }
     }

public:
                     CRiskManager(void)
                       : m_symbol(_Symbol),
                         m_magic(20260826),
                         m_risk_pct(0.5),
                         m_fixed_lot(0.01),
                         m_use_fixed(true),
                         m_max_daily_loss_pct(3.0),
                         m_max_positions(1),
                         m_day_start_equity(0.0),
                         m_day_stamp(0)
                     {
                     }

   void Init(const string symbol, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      Configure(p);
      m_day_stamp = 0;
      RefreshDayBaseline();
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic              = p.magic;
      m_risk_pct           = MathMax(0.01, p.risk_percent);
      m_fixed_lot          = MathMax(0.0, p.fixed_lot);
      m_use_fixed          = p.use_fixed_lot;
      m_max_daily_loss_pct = MathMax(0.1, p.max_daily_loss_pct);
      m_max_positions      = MathMax(1, p.max_positions);
     }

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
      RefreshDayBaseline();
      if(m_day_start_equity <= 0.0)
         return false;
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd = SafeDiv(m_day_start_equity - eq, m_day_start_equity, 0.0) * 100.0;
      return (dd >= m_max_daily_loss_pct);
     }

   double DayPnLPercent(void)
     {
      RefreshDayBaseline();
      if(m_day_start_equity <= 0.0)
         return 0.0;
      return SafeDiv(AccountInfoDouble(ACCOUNT_EQUITY) - m_day_start_equity,
                     m_day_start_equity, 0.0) * 100.0;
     }

   bool CanOpenNew(string &reason)
     {
      reason = "";
      if(DailyLossExceeded())
        {
         reason = StringFormat("触及日内亏损上限 %.1f%%", m_max_daily_loss_pct);
         return false;
        }
      if(CountOurPositions() >= m_max_positions)
        {
         reason = StringFormat("持仓数已达上限 %d", m_max_positions);
         return false;
        }
      return true;
     }

   double CalcLot(const double entry, const double sl)
     {
      double lot_min  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double lot_max  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      if(lot_step <= 0.0)
         lot_step = 0.01;

      if(m_use_fixed)
        {
         double lot = m_fixed_lot;
         lot = MathFloor(lot / lot_step) * lot_step;
         return MathMax(lot_min, MathMin(lot_max, lot));
        }

      const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY) * (m_risk_pct / 100.0);
      const double stop_dist  = MathAbs(entry - sl);
      if(stop_dist <= 0.0)
         return lot_min;

      const double tick_size  = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      const double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(tick_size <= 0.0 || tick_value <= 0.0)
         return lot_min;

      double lot = risk_money / (SafeDiv(stop_dist, tick_size, 0.0) * tick_value);
      lot = MathFloor(lot / lot_step) * lot_step;
      return MathMax(lot_min, MathMin(lot_max, lot));
     }
  };

#endif
//+------------------------------------------------------------------+
