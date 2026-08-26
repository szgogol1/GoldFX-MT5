//+------------------------------------------------------------------+
//| Common.mqh — 共享类型（SafeScalper/Prime 能力扩展）                 |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_COMMON_MQH
#define GOLDFX_COMMON_MQH

enum ENUM_MARKET_REGIME { REGIME_UNKNOWN=0, REGIME_TREND=1, REGIME_RANGE=2 };

enum ENUM_RUN_MODE { MODE_AUTO=0, MODE_TREND=1, MODE_RANGE=2, MODE_FLAT=3 };

enum ENUM_STRATEGY_ENGINE
  {
   STRAT_SEVEN_COND  = 0,  // 七条件同时满足（SafeScalper 风格，默认）
   STRAT_REGIME_AUTO = 1   // 趋势/震荡体制切换
  };

enum ENUM_MONEY_MODE
  {
   MM_FIXED_LOT    = 0,
   MM_RISK_PERCENT = 1,
   MM_BALANCE_PCT  = 2,
   MM_AUTO_LEVEL   = 3,
   MM_ADAPTIVE     = 4     // 自适应风险引擎（回撤/波动/胜率）
  };

enum ENUM_RISK_LEVEL
  {
   RISK_L1=1, RISK_L2=2, RISK_L3=3, RISK_L4=4,
   RISK_L5=5, RISK_L6=6, RISK_L7=7, RISK_L8=8
  };

enum ENUM_SIGNAL { SIGNAL_NONE=0, SIGNAL_BUY=1, SIGNAL_SELL=-1 };

// 七条件诊断快照（日志/仪表盘）
struct SSevenCondSnapshot
  {
   bool   ema_trend;
   bool   ema_strength;
   bool   price_pos;
   bool   breakout;
   bool   rsi_ok;
   bool   momentum;
   bool   htf_ok;
   double ema_fast;
   double ema_slow;
   double ema_gap_atr;
   double rsi;
   double atr;
   string fail_reason;
  };

struct SSignalResult
  {
   ENUM_SIGNAL signal;
   string      symbol;
   double      entry;
   double      sl;
   double      tp;
   double      atr;
   int         quality;
   double      risk_pct_used;
   string      reason;
   SSevenCondSnapshot seven;
  };

struct SRuntimeParams
  {
   ENUM_RUN_MODE         run_mode;
   ENUM_STRATEGY_ENGINE  strategy_engine;
   ENUM_MONEY_MODE       money_mode;
   ENUM_RISK_LEVEL       risk_level;
   // 体制（REGIME 引擎）
   int    adx_period;
   double adx_trend_threshold;
   double adx_range_threshold;
   int    atr_period;
   double bb_width_range_max;
   int    ma_fast;
   int    ma_slow;
   double trend_sl_atr_mult;
   double trend_tp_atr_mult;
   int    rsi_period;
   double rsi_oversold;
   double rsi_overbought;
   double range_sl_atr_mult;
   double range_tp_atr_mult;
   // 七条件引擎
   int    sc_ema_fast;          // 150
   int    sc_ema_slow;          // 510
   double sc_min_gap_atr;       // EMA间距最小 ATR 倍数
   int    sc_breakout_bars;     // N 根高低突破
   double sc_breakout_atr_buf;  // 突破 ATR 缓冲
   double sc_rsi_long_lo;
   double sc_rsi_long_hi;
   double sc_rsi_short_lo;
   double sc_rsi_short_hi;
   bool   sc_use_htf;
   int    sc_htf_fast;          // H1 EMA50
   int    sc_htf_slow;          // H1 EMA200
   double sc_sl_atr;
   double sc_tp_atr;
   // 选择性 / 过滤器
   int    min_quality_score;
   int    max_trades_per_day;
   int    cooldown_bars;
   double max_spread_price;
   bool   prefer_london_ny;
   bool   use_news_filter;
   int    news_pause_minutes_before;
   int    news_pause_minutes_after;
   bool   friday_cutoff;
   int    friday_cutoff_hour;   // 服务器时间
   int    min_bars_required;    // 最小 K 线保护
   // 仓位管理
   bool   use_breakeven;
   double be_trigger_atr;
   double be_lock_atr;
   bool   use_trailing;
   double trail_start_atr;
   double trail_step_atr;
   bool   use_momentum_exit;
   int    max_hold_minutes;
   bool   use_partial_close;
   double partial_at_atr;
   double partial_percent;
   // 风控
   double risk_percent;
   double fixed_lot;
   double balance_lot_per_1k;
   double max_daily_loss_pct;
   double max_equity_dd_pct;
   int    max_positions;
   bool   allow_martingale;
   bool   auto_pause_on_dd;
   // 自适应风险
   bool   adapt_dd_scale;       // 回撤时降仓
   bool   adapt_atr_scale;      // ATR 反比缩放
   bool   adapt_kelly_scale;    // 滚动胜率调整
   double adapt_atr_ref;        // 参考 ATR（价格），0=自动滚动中位
   // 多品种
   string symbols_csv;          // 空=仅图表品种；最多8个
   bool   correlation_guard;
   double max_corr_same_side;   // 简化：同货币组同时最多 N 单
   int    max_open_portfolio;   // 组合最大持仓
   // Telegram
   bool   telegram_enable;
   string telegram_token;
   string telegram_chat_id;
   // 其它
   int    magic;
   int    slippage;
   bool   show_dashboard;
   bool   export_trade_log;
  };

struct SRiskPreset
  {
   double risk_percent;
   double fixed_lot_per_1k;
   double max_daily_loss_pct;
   double max_equity_dd_pct;
   int    max_trades_per_day;
   int    min_quality_score;
   int    max_positions;
  };

SRiskPreset GetRiskPreset(const ENUM_RISK_LEVEL level)
  {
   SRiskPreset p;
   switch(level)
     {
      case RISK_L1: p.risk_percent=0.25; p.fixed_lot_per_1k=0.01; p.max_daily_loss_pct=1.0; p.max_equity_dd_pct=5.0;  p.max_trades_per_day=1; p.min_quality_score=75; p.max_positions=1; break;
      case RISK_L2: p.risk_percent=0.35; p.fixed_lot_per_1k=0.01; p.max_daily_loss_pct=1.5; p.max_equity_dd_pct=6.0;  p.max_trades_per_day=2; p.min_quality_score=70; p.max_positions=1; break;
      case RISK_L3: p.risk_percent=0.50; p.fixed_lot_per_1k=0.02; p.max_daily_loss_pct=2.0; p.max_equity_dd_pct=8.0;  p.max_trades_per_day=2; p.min_quality_score=65; p.max_positions=1; break;
      case RISK_L4: p.risk_percent=0.75; p.fixed_lot_per_1k=0.02; p.max_daily_loss_pct=2.5; p.max_equity_dd_pct=10.0; p.max_trades_per_day=3; p.min_quality_score=60; p.max_positions=1; break;
      case RISK_L5: p.risk_percent=1.00; p.fixed_lot_per_1k=0.03; p.max_daily_loss_pct=3.0; p.max_equity_dd_pct=12.0; p.max_trades_per_day=3; p.min_quality_score=55; p.max_positions=1; break;
      case RISK_L6: p.risk_percent=1.25; p.fixed_lot_per_1k=0.04; p.max_daily_loss_pct=3.5; p.max_equity_dd_pct=14.0; p.max_trades_per_day=4; p.min_quality_score=50; p.max_positions=1; break;
      case RISK_L7: p.risk_percent=1.50; p.fixed_lot_per_1k=0.05; p.max_daily_loss_pct=4.0; p.max_equity_dd_pct=16.0; p.max_trades_per_day=4; p.min_quality_score=50; p.max_positions=2; break;
      case RISK_L8: p.risk_percent=2.00; p.fixed_lot_per_1k=0.06; p.max_daily_loss_pct=5.0; p.max_equity_dd_pct=20.0; p.max_trades_per_day=5; p.min_quality_score=45; p.max_positions=2; break;
      default:      p.risk_percent=0.75; p.fixed_lot_per_1k=0.02; p.max_daily_loss_pct=2.5; p.max_equity_dd_pct=10.0; p.max_trades_per_day=3; p.min_quality_score=60; p.max_positions=1; break;
     }
   return p;
  }

void ApplyRiskLevelToParams(SRuntimeParams &rp)
  {
   const SRiskPreset pre = GetRiskPreset(rp.risk_level);
   rp.risk_percent       = pre.risk_percent;
   rp.max_daily_loss_pct = pre.max_daily_loss_pct;
   rp.max_equity_dd_pct  = pre.max_equity_dd_pct;
   rp.max_trades_per_day = pre.max_trades_per_day;
   rp.min_quality_score  = pre.min_quality_score;
   rp.max_positions      = pre.max_positions;
   rp.balance_lot_per_1k = pre.fixed_lot_per_1k;
   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   rp.fixed_lot = MathMax(0.01, NormalizeDouble(pre.fixed_lot_per_1k * (bal / 1000.0), 2));
   rp.allow_martingale = false;
  }

double SafeDiv(const double a, const double b, const double fallback=0.0)
  {
   if(MathAbs(b) < DBL_EPSILON) return fallback;
   return a / b;
  }

double SymbolPointValue(const string sym="")
  {
   string s = (sym=="" ? _Symbol : sym);
   return SymbolInfoDouble(s, SYMBOL_POINT);
  }

int SymbolDigitsValue(const string sym="")
  {
   string s = (sym=="" ? _Symbol : sym);
   return (int)SymbolInfoInteger(s, SYMBOL_DIGITS);
  }

double NormalizePriceSym(const double price, const string sym="")
  {
   return NormalizeDouble(price, SymbolDigitsValue(sym));
  }

double NormalizePrice(const double price) { return NormalizePriceSym(price, _Symbol); }

double CurrentSpreadPrice(const string symbol)
  {
   MqlTick t;
   if(!SymbolInfoTick(symbol, t)) return 999999.0;
   return (t.ask - t.bid);
  }

string RegimeToString(const ENUM_MARKET_REGIME r)
  {
   if(r==REGIME_TREND) return "趋势";
   if(r==REGIME_RANGE) return "震荡";
   return "未知";
  }

string ModeToString(const ENUM_RUN_MODE m)
  {
   if(m==MODE_AUTO) return "自动";
   if(m==MODE_TREND) return "强制趋势";
   if(m==MODE_RANGE) return "强制震荡";
   if(m==MODE_FLAT) return "仅观察";
   return "?";
  }

string StratToString(const ENUM_STRATEGY_ENGINE e)
  {
   if(e==STRAT_SEVEN_COND) return "七条件";
   return "体制切换";
  }

string MoneyModeToString(const ENUM_MONEY_MODE m)
  {
   switch(m)
     {
      case MM_FIXED_LOT:    return "固定手数";
      case MM_RISK_PERCENT: return "风险%";
      case MM_BALANCE_PCT:  return "余额比例";
      case MM_AUTO_LEVEL:   return "八档自动";
      case MM_ADAPTIVE:     return "自适应";
      default: return "?";
     }
  }

string RiskLevelToString(const ENUM_RISK_LEVEL lv) { return StringFormat("R%d",(int)lv); }

string SignalToString(const ENUM_SIGNAL s)
  {
   if(s==SIGNAL_BUY) return "BUY";
   if(s==SIGNAL_SELL) return "SELL";
   return "NONE";
  }

void InitSignal(SSignalResult &r)
  {
   r.signal=SIGNAL_NONE; r.symbol=""; r.entry=0; r.sl=0; r.tp=0;
   r.atr=0; r.quality=0; r.risk_pct_used=0; r.reason="";
   ZeroMemory(r.seven);
   r.seven.fail_reason="";
  }

// 解析 CSV 品种列表，最多 8 个
int ParseSymbolsCSV(const string csv, string &out[], const string fallback_symbol)
  {
   ArrayResize(out, 0);
   string raw = csv;
   StringTrimLeft(raw); StringTrimRight(raw);
   if(StringLen(raw) == 0)
     {
      ArrayResize(out, 1);
      out[0] = fallback_symbol;
      return 1;
     }
   string parts[];
   const int n = StringSplit(raw, ',', parts);
   for(int i=0; i<n && ArraySize(out)<8; ++i)
     {
      string s = parts[i];
      StringTrimLeft(s); StringTrimRight(s);
      StringToUpper(s);
      if(StringLen(s)==0) continue;
      // 去重
      bool dup=false;
      for(int j=0;j<ArraySize(out);++j)
         if(out[j]==s){ dup=true; break; }
      if(dup) continue;
      const int k=ArraySize(out);
      ArrayResize(out, k+1);
      out[k]=s;
     }
   if(ArraySize(out)==0)
     {
      ArrayResize(out,1);
      out[0]=fallback_symbol;
     }
   return ArraySize(out);
  }

// 简化货币组标签（相关性保护）
string CurrencyGroupTag(const string symbol)
  {
   string s = symbol;
   StringToUpper(s);
   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0) return "XAU";
   if(StringFind(s,"XAG")>=0 || StringFind(s,"SILVER")>=0) return "XAG";
   if(StringFind(s,"USD")>=0) return "USD_PAIR";
   if(StringFind(s,"EUR")>=0) return "EUR";
   if(StringFind(s,"GBP")>=0) return "GBP";
   if(StringFind(s,"JPY")>=0) return "JPY";
   return s;
  }

bool IsTesterMode(void)
  {
   return (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
  }

#endif
//+------------------------------------------------------------------+
