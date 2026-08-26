//+------------------------------------------------------------------+
//| Common.mqh — 共享类型、常量与工具（Titan 风格选择性架构）            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_COMMON_MQH
#define GOLDFX_COMMON_MQH

//--- 市场状态
enum ENUM_MARKET_REGIME
  {
   REGIME_UNKNOWN = 0,
   REGIME_TREND   = 1,
   REGIME_RANGE   = 2
  };

//--- 运行模式
enum ENUM_RUN_MODE
  {
   MODE_AUTO  = 0,
   MODE_TREND = 1,
   MODE_RANGE = 2,
   MODE_FLAT  = 3
  };

//--- 资金管理方式（多种理财方法）
enum ENUM_MONEY_MODE
  {
   MM_FIXED_LOT    = 0,  // 固定手数
   MM_RISK_PERCENT = 1,  // 按止损距离风险%
   MM_BALANCE_PCT  = 2,  // 按余额比例估算手数
   MM_AUTO_LEVEL   = 3   // 由八档风险等级自动映射
  };

//--- 八档自动风险等级（即插即用）
enum ENUM_RISK_LEVEL
  {
   RISK_L1 = 1,  // 极保守
   RISK_L2 = 2,
   RISK_L3 = 3,
   RISK_L4 = 4,  // 默认推荐
   RISK_L5 = 5,
   RISK_L6 = 6,
   RISK_L7 = 7,
   RISK_L8 = 8   // 激进
  };

enum ENUM_SIGNAL
  {
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
  };

struct SSignalResult
  {
   ENUM_SIGNAL signal;
   double      entry;
   double      sl;
   double      tp;
   double      atr;
   int         quality;   // 0-100，选择性门槛
   string      reason;
  };

struct SRuntimeParams
  {
   ENUM_RUN_MODE   run_mode;
   ENUM_MONEY_MODE money_mode;
   ENUM_RISK_LEVEL risk_level;
   // 体制识别
   int    adx_period;
   double adx_trend_threshold;
   double adx_range_threshold;
   int    atr_period;
   double bb_width_range_max;
   int    ma_fast;
   int    ma_slow;
   // 趋势 / 震荡
   double trend_sl_atr_mult;
   double trend_tp_atr_mult;
   int    rsi_period;
   double rsi_oversold;
   double rsi_overbought;
   double range_sl_atr_mult;
   double range_tp_atr_mult;
   // 选择性入场
   int    min_quality_score;     // 最低质量分
   int    max_trades_per_day;    // 日最大开仓次数（质量>频率）
   int    cooldown_bars;         // 成交后冷却 K 线数
   double max_spread_price;      // 最大点差（价格单位，XAU 常用 0.30~0.80）
   bool   prefer_london_ny;      // 优先伦敦/纽约黄金活跃时段
   // 仓位管理（开仓即保护 + 智能利润保护）
   bool   use_breakeven;
   double be_trigger_atr;        // 浮盈达此 ATR 倍数 → 保本
   double be_lock_atr;           // 保本锁定利润（ATR 倍数，可 0）
   bool   use_trailing;
   double trail_start_atr;       // 开始追踪的浮盈 ATR
   double trail_step_atr;        // 追踪步长 ATR
   bool   use_momentum_exit;     // 动能减弱提前减仓/离场
   int    max_hold_minutes;      // 最长持仓（短线，0=不限）
   bool   use_partial_close;
   double partial_at_atr;        // 浮盈达此 ATR 部分平仓
   double partial_percent;       // 部分平仓比例%
   // 风控 / 回撤保护
   double risk_percent;
   double fixed_lot;
   double balance_lot_per_1k;    // MM_BALANCE_PCT: 每 1000 余额对应手数
   double max_daily_loss_pct;
   double max_equity_dd_pct;     // 相对峰值净值最大回撤%
   int    max_positions;         // 禁止网格：默认 1
   bool   allow_martingale;      // 默认 false，禁止马丁
   int    magic;
   int    slippage;
  };

//--- 八档风险预设值
struct SRiskPreset
  {
   double risk_percent;
   double fixed_lot_per_1k;   // 相对每 1000 美元建议手数（再按账户缩放）
   double max_daily_loss_pct;
   double max_equity_dd_pct;
   int    max_trades_per_day;
   int    min_quality_score;
   int    max_positions;
  };

SRiskPreset GetRiskPreset(const ENUM_RISK_LEVEL level)
  {
   SRiskPreset p;
   // 无网格、无马丁：仓位上限始终为 1（L7/L8 最多 2，仍禁止加仓摊平）
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

// 将八档预设写入运行时参数（保留策略/面板其它字段）
void ApplyRiskLevelToParams(SRuntimeParams &rp)
  {
   const SRiskPreset pre = GetRiskPreset(rp.risk_level);
   rp.risk_percent        = pre.risk_percent;
   rp.max_daily_loss_pct  = pre.max_daily_loss_pct;
   rp.max_equity_dd_pct   = pre.max_equity_dd_pct;
   rp.max_trades_per_day  = pre.max_trades_per_day;
   rp.min_quality_score   = pre.min_quality_score;
   rp.max_positions       = pre.max_positions;
   rp.balance_lot_per_1k  = pre.fixed_lot_per_1k;
   // 固定手数按账户规模估算（至少品种最小手）
   const double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   rp.fixed_lot = MathMax(0.01, NormalizeDouble(pre.fixed_lot_per_1k * (bal / 1000.0), 2));
   if(rp.money_mode == MM_AUTO_LEVEL)
     {
      // 自动档位默认用风险%（有明确止损结构）
      // 实际 CalcLot 在 RiskManager 内按 money_mode 分支
     }
   rp.allow_martingale = false;
  }

double SafeDiv(const double a, const double b, const double fallback = 0.0)
  {
   if(MathAbs(b) < DBL_EPSILON)
      return fallback;
   return a / b;
  }

double SymbolPointValue()
  {
   return SymbolInfoDouble(_Symbol, SYMBOL_POINT);
  }

int SymbolDigitsValue()
  {
   return (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
  }

double NormalizePrice(const double price)
  {
   return NormalizeDouble(price, SymbolDigitsValue());
  }

double CurrentSpreadPrice(const string symbol)
  {
   MqlTick t;
   if(!SymbolInfoTick(symbol, t))
      return 999999.0;
   return (t.ask - t.bid);
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

string MoneyModeToString(const ENUM_MONEY_MODE m)
  {
   switch(m)
     {
      case MM_FIXED_LOT:    return "固定手数";
      case MM_RISK_PERCENT: return "风险%";
      case MM_BALANCE_PCT:  return "余额比例";
      case MM_AUTO_LEVEL:   return "八档自动";
      default:              return "?";
     }
  }

string RiskLevelToString(const ENUM_RISK_LEVEL lv)
  {
   return StringFormat("R%d", (int)lv);
  }

string SignalToString(const ENUM_SIGNAL s)
  {
   if(s == SIGNAL_BUY)  return "BUY";
   if(s == SIGNAL_SELL) return "SELL";
   return "NONE";
  }

void InitSignal(SSignalResult &r)
  {
   r.signal  = SIGNAL_NONE;
   r.entry   = 0;
   r.sl      = 0;
   r.tp      = 0;
   r.atr     = 0;
   r.quality = 0;
   r.reason  = "";
  }

#endif
//+------------------------------------------------------------------+
