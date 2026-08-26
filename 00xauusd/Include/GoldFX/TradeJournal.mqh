//+------------------------------------------------------------------+
//| TradeJournal.mqh — 成交元数据 CSV 导出                             |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TRADE_JOURNAL_MQH
#define GOLDFX_TRADE_JOURNAL_MQH

#include "Common.mqh"

class CTradeJournal
  {
private:
   bool              m_enable;
   string            m_path;
   bool              m_header_ok;

public:
                     CTradeJournal(void): m_enable(false), m_path(""), m_header_ok(false) {}

   void Configure(const SRuntimeParams &p, const int magic)
     {
      m_enable = p.export_trade_log && !IsTesterMode();
      m_path = StringFormat("GoldFX_Journal_%d.csv", magic);
     }

   void EnsureHeader(void)
     {
      if(!m_enable || m_header_ok)
         return;
      int h = FileOpen(m_path, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h != INVALID_HANDLE)
        {
         FileClose(h);
         m_header_ok = true;
         return;
        }
      h = FileOpen(m_path, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE)
         return;
      FileWriteString(h, "time,symbol,side,lot,entry,sl,tp,atr,quality,risk_pct,spread,reason,c1,c2,c3,c4,c5,c6,c7\n");
      FileClose(h);
      m_header_ok = true;
     }

   void LogEntry(const SSignalResult &sig, const double lot, const double risk_pct)
     {
      if(!m_enable)
         return;
      EnsureHeader();
      int h = FileOpen(m_path, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(h == INVALID_HANDLE)
         return;
      FileSeek(h, 0, SEEK_END);
      const double spread = CurrentSpreadPrice(sig.symbol);
      string line = StringFormat("%s,%s,%s,%.2f,%.5f,%.5f,%.5f,%.5f,%d,%.3f,%.5f,%s,%d,%d,%d,%d,%d,%d,%d\n",
                                 TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
                                 sig.symbol, SignalToString(sig.signal), lot,
                                 sig.entry, sig.sl, sig.tp, sig.atr, sig.quality, risk_pct, spread,
                                 sig.reason,
                                 (int)sig.seven.ema_trend, (int)sig.seven.ema_strength,
                                 (int)sig.seven.price_pos, (int)sig.seven.breakout,
                                 (int)sig.seven.rsi_ok, (int)sig.seven.momentum, (int)sig.seven.htf_ok);
      FileWriteString(h, line);
      FileClose(h);
     }

   string Path(void) const { return m_path; }
  };

#endif
//+------------------------------------------------------------------+
