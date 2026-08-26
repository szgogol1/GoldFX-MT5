//+------------------------------------------------------------------+
//| Common.mqh — 共享类型、常量与工具函数                               |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_COMMON_MQH
#define GOLDFX_COMMON_MQH

//--- 市场状态
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN = 0,   // 未判定
   REGIME_TREND   = 1,   // 趋势
   REGIME_RANGE   = 2    // 震荡
  };

//--- 运行模式（可人工覆盖自动识别）
enum ENUM_RUN_MODE
  {
   MODE_AUTO  = 0,       // 自动：按识别结果切换策略
   MODE_TREND = 1,       // 强制趋势策略
   MODE_RANGE = 2,       // 强制震荡策略
   MODE_FLAT  = 3        // 仅观察，不交易
  };

//--- 交易方向信号
enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

//--- 策略信号结果
struct SSignalResult
  {
   ENUM_SIGNAL signal;
   double      entry;
   double      sl;
   double      tp;
   string      reason;
  };

//--- 面板可热更新的运行时参数（与 input 初始值同步）
struct SRuntimeParams
  {
   ENUM_RUN_MODE run_mode;
   // 体制识别
   int    adx_period;
   double adx_trend_threshold;
   double adx_range_threshold;
   int    atr_period;
   double bb_width_range_max;   // 布林带宽上限判震荡
   int    ma_fast;
   int    ma_slow;
   // 趋势策略
   double trend_sl_atr_mult;
   double trend_tp_atr_mult;
   // 震荡策略
   int    rsi_period;
   double rsi_oversold;
   double rsi_overbought;
   double range_sl_atr_mult;
   double range_tp_atr_mult;
   // 风控
   double risk_percent;
   double fixed_lot;
   bool   use_fixed_lot;
   double max_daily_loss_pct;
   int    max_positions;
   int    magic;
   int    slippage;
  };

//--- 安全除法
double SafeDiv(const double a, const double b, const double fallback = 0.0)
  {
   if(MathAbs(b) < DBL_EPSILON)
      return fallback;
   return a / b;
  }

//--- 点值（适配 XAUUSD 等）
double SymbolPoint()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  }

int SymbolDigits()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  }

double NormalizePrice(const double price)
  {
   return NormalizeDouble(price, SymbolDigits());
  }

string RegimeToString(const ENUM_MARKET_REGIME r)
  {
   switch(r)
     {
      case REGIME_TREND: return "趋势";
      case REGIME_RANGE: return "震荡";
      default:           return "未知";
     }
  }

string ModeToString(const ENUM_RUN_MODE m)
  {
   switch(m)
     {
      case MODE_AUTO:  return "自动";
      case MODE_TREND: return "强制趋势";
      case MODE_RANGE: return "强制震荡";
      case MODE_FLAT:  return "仅观察";
      default:         return "?";
     }
  }

string SignalToString(const ENUM_SIGNAL s)
  {
   if(s == SIGNAL_BUY)  return "BUY";
   if(s == SIGNAL_SELL) return "SELL";
   return "NONE";
  }

#endif
//+------------------------------------------------------------------+
