//+------------------------------------------------------------------+
//| SelectivityFilter.mqh — 选择性入场闸门（质量 > 频率）               |
//| 无网格 / 无马丁；等待条件齐备才允许开仓                             |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_SELECTIVITY_FILTER_MQH
#define GOLDFX_SELECTIVITY_FILTER_MQH

#include "Common.mqh"

class CSelectivityFilter
  {
private:
   string            m_symbol;
   int               m_magic;
   int               m_min_quality;
   int               m_max_trades_day;
   int               m_cooldown_bars;
   double            m_max_spread;
   bool              m_prefer_london_ny;
   ENUM_TIMEFRAMES   m_tf;
   datetime          m_last_entry_bar;
   int               m_day_stamp;
   int               m_day_trades;

   int TodayStamp(void) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void RefreshDay(void)
     {
      const int t = TodayStamp();
      if(t != m_day_stamp)
        {
         m_day_stamp  = t;
         m_day_trades = CountDayEntries();
        }
     }

   // 统计今日本 EA 开仓成交数
   int CountDayEntries(void)
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      const datetime day_start = StructToTime(dt);
      if(!HistorySelect(day_start, TimeCurrent()))
         return 0;

      int count = 0;
      const int total = HistoryDealsTotal();
      for(int i = 0; i < total; ++i)
        {
         const ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0)
            continue;
         if(HistoryDealGetString(ticket, DEAL_SYMBOL) != m_symbol)
            continue;
         if((int)HistoryDealGetInteger(ticket, DEAL_MAGIC) != m_magic)
            continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN)
            continue;
         count++;
        }
      return count;
     }

   bool InPreferredGoldSession(void) const
     {
      if(!m_prefer_london_ny)
         return true;
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // 以服务器时间近似：伦敦~NY 黄金活跃窗 8–20（可按经纪商时区在参数中配合会话过滤）
      return (dt.hour >= 8 && dt.hour < 20);
     }

public:
                     CSelectivityFilter(void)
                       : m_symbol(_Symbol),
                         m_magic(20260826),
                         m_min_quality(60),
                         m_max_trades_day(3),
                         m_cooldown_bars(4),
                         m_max_spread(0.50),
                         m_prefer_london_ny(true),
                         m_tf(PERIOD_CURRENT),
                         m_last_entry_bar(0),
                         m_day_stamp(0),
                         m_day_trades(0)
                     {
                     }

   void Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf     = tf;
      Configure(p);
      m_day_stamp = 0;
      RefreshDay();
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic             = p.magic;
      m_min_quality       = MathMax(0, p.min_quality_score);
      m_max_trades_day    = MathMax(1, p.max_trades_per_day);
      m_cooldown_bars     = MathMax(0, p.cooldown_bars);
      m_max_spread        = MathMax(0.0, p.max_spread_price);
      m_prefer_london_ny  = p.prefer_london_ny;
     }

   int DayTrades(void)
     {
      RefreshDay();
      return m_day_trades;
     }

   void NotifyEntryFilled(void)
     {
      RefreshDay();
      m_day_trades++;
      m_last_entry_bar = iTime(m_symbol, m_tf, 0);
     }

   bool Pass(const SSignalResult &sig, string &reason)
     {
      reason = "";
      RefreshDay();

      if(sig.signal == SIGNAL_NONE)
        {
         reason = "无信号";
         return false;
        }
      // 强制：必须有预设止损（独立仓位风险结构）
      if(sig.sl <= 0.0 || MathAbs(sig.entry - sig.sl) < SymbolPointValue())
        {
         reason = "拒绝：无有效预设止损";
         return false;
        }
      if(sig.quality < m_min_quality)
        {
         reason = StringFormat("质量分不足 %d<%d（等待更好机会）", sig.quality, m_min_quality);
         return false;
        }
      if(m_day_trades >= m_max_trades_day)
        {
         reason = StringFormat("今日开仓已达上限 %d（选择性）", m_max_trades_day);
         return false;
        }

      const double spread = CurrentSpreadPrice(m_symbol);
      if(m_max_spread > 0.0 && spread > m_max_spread)
        {
         reason = StringFormat("点差过大 %.2f>%.2f", spread, m_max_spread);
         return false;
        }

      if(!InPreferredGoldSession())
        {
         reason = "非黄金优选时段，观望";
         return false;
        }

      if(m_cooldown_bars > 0 && m_last_entry_bar > 0)
        {
         const int shift = iBarShift(m_symbol, m_tf, m_last_entry_bar, true);
         if(shift >= 0 && shift < m_cooldown_bars)
           {
            reason = StringFormat("冷却中（剩约 %d 根K）", m_cooldown_bars - shift);
            return false;
           }
        }

      reason = "选择性闸门通过";
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
