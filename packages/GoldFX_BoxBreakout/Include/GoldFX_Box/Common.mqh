//+------------------------------------------------------------------+
//| Common.mqh — 顺势箱体独立包共享类型                                |
//+------------------------------------------------------------------+
#property copyright "GoldFX BoxBreakout"
#property strict

#ifndef GOLDFX_BOX_COMMON_MQH
#define GOLDFX_BOX_COMMON_MQH

enum ENUM_SIGNAL { SIGNAL_NONE=0, SIGNAL_BUY=1, SIGNAL_SELL=-1 };

struct SSignalResult
  {
   ENUM_SIGNAL signal;
   string      symbol;
   double      entry;
   double      sl;
   double      tp;
   double      atr;
   int         quality;
   string      reason;
  };

struct SBoxParams
  {
   int    atr_period;
   int    adx_period;
   int    box_lookback;
   int    box_min_bars;
   double box_width_min_atr;
   double box_width_max_atr;
   double box_break_buf_atr;
   int    box_ema_fast;
   int    box_ema_slow;
   double box_min_adx;
   double box_sl_buf_atr;
   double box_tp_height_mult;
   double box_min_rr;
   bool   box_use_htf;
   int    box_htf_fast;
   int    box_htf_slow;
   int    box_touch_min;
  };

double SafeDiv(const double a, const double b, const double fallback=0.0)
  {
   if(MathAbs(b) < DBL_EPSILON) return fallback;
   return a / b;
  }

int SymbolDigitsOf(const string sym="")
  {
   const string s = (sym=="" ? _Symbol : sym);
   return (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
  }

double NormalizePriceSym(const double price, const string sym="")
  {
   return NormalizeDouble(price, SymbolDigitsOf(sym));
  }

double CurrentSpreadPrice(const string symbol)
  {
   MqlTick t;
   if(!SymbolInfoTick(symbol, t)) return 999999.0;
   return (t.ask - t.bid);
  }

void InitSignal(SSignalResult &r)
  {
   r.signal=SIGNAL_NONE;
   r.symbol="";
   r.entry=0.0;
   r.sl=0.0;
   r.tp=0.0;
   r.atr=0.0;
   r.quality=0;
   r.reason="";
  }

string SignalToString(const ENUM_SIGNAL s)
  {
   if(s==SIGNAL_BUY) return "BUY";
   if(s==SIGNAL_SELL) return "SELL";
   return "NONE";
  }

#endif
//+------------------------------------------------------------------+
