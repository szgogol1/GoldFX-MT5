//+------------------------------------------------------------------+
//| Common.mqh — GoldFX BoxBreakout shared types                     |
//+------------------------------------------------------------------+
#ifndef GOLDFX_BOX_COMMON_MQH
#define GOLDFX_BOX_COMMON_MQH

enum ENUM_BOX_SIGNAL
  {
   BOX_SIGNAL_NONE = 0,
   BOX_SIGNAL_BUY  = 1,
   BOX_SIGNAL_SELL = -1
  };

struct SBoxSignal
  {
   ENUM_BOX_SIGNAL signal;
   string          symbol;
   double          entry;
   double          sl;
   double          tp;
   double          atr;
   int             quality;
   string          reason;
  };

struct SBoxParams
  {
   int    atr_period;
   int    adx_period;
   int    lookback;
   int    min_bars;
   double width_min_atr;
   double width_max_atr;
   double break_buf_atr;
   int    ema_fast;
   int    ema_slow;
   double min_adx;
   double sl_buf_atr;
   double tp_height_mult;
   double min_rr;
   bool   use_htf;
   int    htf_fast;
   int    htf_slow;
   int    touch_min;
  };

void BoxSignalClear(SBoxSignal &s)
  {
   s.signal  = BOX_SIGNAL_NONE;
   s.symbol  = "";
   s.entry   = 0.0;
   s.sl      = 0.0;
   s.tp      = 0.0;
   s.atr     = 0.0;
   s.quality = 0;
   s.reason  = "";
  }

string BoxSignalText(const ENUM_BOX_SIGNAL s)
  {
   if(s == BOX_SIGNAL_BUY)  return "BUY";
   if(s == BOX_SIGNAL_SELL) return "SELL";
   return "NONE";
  }

int BoxDigits(const string sym)
  {
   return (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
  }

double BoxNormPrice(const double price, const string sym)
  {
   return NormalizeDouble(price, BoxDigits(sym));
  }

double BoxSpreadPrice(const string sym)
  {
   MqlTick t;
   if(!SymbolInfoTick(sym, t))
      return 999999.0;
   return (t.ask - t.bid);
  }

#endif
