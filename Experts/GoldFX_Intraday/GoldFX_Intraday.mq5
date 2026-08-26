//+------------------------------------------------------------------+
//| GoldFX_Intraday.mq5 — XAUUSD 选择性日内框架（Titan 风格能力）       |
//| 选择性入场 · 无网格/无马丁 · 独立仓位管理 · 八档风险 · 回撤保护     |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property link      ""
#property version   "2.00"
#property description "XAUUSD选择性架构: 质量门控入场, 预设止损, 保本/追踪/动能离场, 八档风险, 无网格无马丁"

#include <GoldFX/Common.mqh>
#include <GoldFX/RegimeDetector.mqh>
#include <GoldFX/TrendStrategy.mqh>
#include <GoldFX/RangeStrategy.mqh>
#include <GoldFX/RiskManager.mqh>
#include <GoldFX/SelectivityFilter.mqh>
#include <GoldFX/PositionManager.mqh>
#include <GoldFX/TradeManager.mqh>
#include <GoldFX/ParamPanel.mqh>

//======================== 输入参数 ========================
input group "=== 运行（即插即用默认已偏 XAUUSD）==="
input ENUM_RUN_MODE    InpRunMode           = MODE_AUTO;      // 运行模式
input ENUM_MONEY_MODE  InpMoneyMode         = MM_AUTO_LEVEL;  // 资金管理方式
input ENUM_RISK_LEVEL  InpRiskLevel         = RISK_L4;        // 八档风险（默认R4）
input bool             InpShowPanel         = true;           // 图表控制台
input bool             InpAllowTrade        = true;           // 允许下单
input int              InpMagic             = 20260826;       // Magic
input int              InpSlippage          = 30;             // 滑点(点)

input group "=== 体制识别 ==="
input int              InpADXPeriod         = 14;
input double           InpADXTrend          = 25.0;
input double           InpADXRange          = 20.0;
input int              InpATRPeriod         = 14;
input double           InpBBWidthRangeMax   = 0.012;
input int              InpMAFast            = 20;
input int              InpMASlow            = 50;

input group "=== 趋势 / 震荡 ==="
input double           InpTrendSL_ATR       = 1.5;
input double           InpTrendTP_ATR       = 2.5;
input int              InpRSIPeriod         = 14;
input double           InpRSIOversold       = 30.0;
input double           InpRSIOverbought     = 70.0;
input double           InpRangeSL_ATR       = 1.0;
input double           InpRangeTP_ATR       = 1.2;

input group "=== 选择性入场（质量>频率）==="
input int              InpMinQuality        = 60;     // 最低质量分(可被风险档覆盖)
input int              InpMaxTradesDay      = 3;      // 日最大开仓次数
input int              InpCooldownBars      = 4;      // 成交后冷却K线
input double           InpMaxSpread         = 0.50;   // 最大点差(价格, XAU)
input bool             InpPreferLondonNY    = true;   // 优先伦敦/纽约窗口

input group "=== 仓位管理（开仓即保护）==="
input bool             InpUseBreakeven      = true;
input double           InpBETriggerATR      = 1.0;    // 浮盈达N×ATR→保本
input double           InpBELockATR         = 0.10;   // 保本锁定
input bool             InpUseTrailing       = true;
input double           InpTrailStartATR     = 1.5;
input double           InpTrailStepATR      = 0.80;
input bool             InpUseMomentumExit   = true;   // 动能减弱离场
input int              InpMaxHoldMinutes    = 240;    // 最长持仓分钟(0不限)
input bool             InpUsePartialClose   = true;
input double           InpPartialAtATR      = 1.2;
input double           InpPartialPercent    = 50.0;

input group "=== 风控覆盖（Money≠AUTO时生效为主）==="
input double           InpFixedLot          = 0.01;
input double           InpRiskPercent       = 0.75;
input double           InpLotPer1k          = 0.02;
input double           InpMaxDailyLossPct   = 2.5;
input double           InpMaxEquityDDPct    = 10.0;
input int              InpMaxPositions      = 1;      // 禁止网格: 建议1

input group "=== 会话过滤（服务器时间）==="
input bool             InpUseSessionFilter  = true;
input int              InpSessionStartHour  = 8;
input int              InpSessionEndHour    = 22;

//======================== 模块 ========================
SRuntimeParams      g_params;
CRegimeDetector     g_regime;
CTrendStrategy      g_trend;
CRangeStrategy      g_range;
CRiskManager        g_risk;
CSelectivityFilter  g_filter;
CPositionManager    g_posman;
CTradeManager       g_trade;
CParamPanel         g_panel;

datetime            g_last_bar = 0;
ENUM_MARKET_REGIME  g_active_regime = REGIME_UNKNOWN;

//------------------------------------------------------------------
void BuildParamsFromInputs(SRuntimeParams &p)
  {
   ZeroMemory(p);
   p.run_mode            = InpRunMode;
   p.money_mode          = InpMoneyMode;
   p.risk_level          = InpRiskLevel;
   p.adx_period          = InpADXPeriod;
   p.adx_trend_threshold = InpADXTrend;
   p.adx_range_threshold = InpADXRange;
   p.atr_period          = InpATRPeriod;
   p.bb_width_range_max  = InpBBWidthRangeMax;
   p.ma_fast             = InpMAFast;
   p.ma_slow             = InpMASlow;
   p.trend_sl_atr_mult   = InpTrendSL_ATR;
   p.trend_tp_atr_mult   = InpTrendTP_ATR;
   p.rsi_period          = InpRSIPeriod;
   p.rsi_oversold        = InpRSIOversold;
   p.rsi_overbought      = InpRSIOverbought;
   p.range_sl_atr_mult   = InpRangeSL_ATR;
   p.range_tp_atr_mult   = InpRangeTP_ATR;
   p.min_quality_score   = InpMinQuality;
   p.max_trades_per_day  = InpMaxTradesDay;
   p.cooldown_bars       = InpCooldownBars;
   p.max_spread_price    = InpMaxSpread;
   p.prefer_london_ny    = InpPreferLondonNY;
   p.use_breakeven       = InpUseBreakeven;
   p.be_trigger_atr      = InpBETriggerATR;
   p.be_lock_atr         = InpBELockATR;
   p.use_trailing        = InpUseTrailing;
   p.trail_start_atr     = InpTrailStartATR;
   p.trail_step_atr      = InpTrailStepATR;
   p.use_momentum_exit   = InpUseMomentumExit;
   p.max_hold_minutes    = InpMaxHoldMinutes;
   p.use_partial_close   = InpUsePartialClose;
   p.partial_at_atr      = InpPartialAtATR;
   p.partial_percent     = InpPartialPercent;
   p.fixed_lot           = InpFixedLot;
   p.risk_percent        = InpRiskPercent;
   p.balance_lot_per_1k  = InpLotPer1k;
   p.max_daily_loss_pct  = InpMaxDailyLossPct;
   p.max_equity_dd_pct   = InpMaxEquityDDPct;
   p.max_positions       = MathMax(1, InpMaxPositions);
   p.allow_martingale    = false;
   p.magic               = InpMagic;
   p.slippage            = InpSlippage;

   // 八档自动：用预设覆盖风险相关字段
   if(p.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(p);
  }

//------------------------------------------------------------------
bool ApplyRuntimeParams(const SRuntimeParams &p, const bool rebuild)
  {
   g_params = p;
   g_params.allow_martingale = false;
   if(g_params.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(g_params);

   g_risk.Configure(g_params);
   g_filter.Configure(g_params);
   g_trade.Configure(g_params);

   if(rebuild)
     {
      if(!g_regime.Configure(g_params)) return false;
      if(!g_trend.Configure(g_params))  return false;
      if(!g_range.Configure(g_params))  return false;
      if(!g_posman.Configure(g_params)) return false;
     }
   else
     {
      // 仓位管理参数也可热更新
      g_posman.Configure(g_params);
     }
   return true;
  }

//------------------------------------------------------------------
bool InTradingSession(void)
  {
   if(!InpUseSessionFilter)
      return true;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpSessionStartHour == InpSessionEndHour)
      return true;
   if(InpSessionStartHour < InpSessionEndHour)
      return (dt.hour >= InpSessionStartHour && dt.hour < InpSessionEndHour);
   return (dt.hour >= InpSessionStartHour || dt.hour < InpSessionEndHour);
  }

//------------------------------------------------------------------
ENUM_MARKET_REGIME ResolveEffectiveRegime(const ENUM_MARKET_REGIME detected)
  {
   switch(g_params.run_mode)
     {
      case MODE_TREND: return REGIME_TREND;
      case MODE_RANGE: return REGIME_RANGE;
      case MODE_FLAT:  return REGIME_UNKNOWN;
      default:         return detected;
     }
  }

//------------------------------------------------------------------
void UpdateStatusUI(const string extra = "")
  {
   string line = StringFormat("%s | %s/%s | 生效=%s | 日%.2f%% 回撤%.2f%% | 今日单%d",
                              g_regime.Diagnostics(),
                              ModeToString(g_params.run_mode),
                              RiskLevelToString(g_params.risk_level),
                              RegimeToString(g_active_regime),
                              g_risk.DayPnLPercent(),
                              g_risk.EquityDDPercent(),
                              g_filter.DayTrades());
   if(StringLen(extra) > 0)
      line += " | " + extra;
   Comment(line +
           "\n无网格·无马丁·独立止损·保本/追踪/动能离场 | " +
           MoneyModeToString(g_params.money_mode));
   if(InpShowPanel)
      g_panel.SetStatus(line);
  }

//------------------------------------------------------------------
void ProcessNewBar(void)
  {
   const ENUM_MARKET_REGIME detected = g_regime.Evaluate(true);
   g_active_regime = ResolveEffectiveRegime(detected);

   if(g_params.run_mode == MODE_FLAT)
     {
      UpdateStatusUI("仅观察");
      return;
     }
   if(!InpAllowTrade)
     {
      UpdateStatusUI("交易关闭");
      return;
     }
   if(!InTradingSession())
     {
      UpdateStatusUI("非交易时段");
      return;
     }

   SSignalResult sig;
   InitSignal(sig);

   if(g_active_regime == REGIME_TREND)
      sig = g_trend.Evaluate();
   else if(g_active_regime == REGIME_RANGE)
      sig = g_range.Evaluate();
   else
     {
      UpdateStatusUI("体制未知，等待");
      return;
     }

   if(sig.signal == SIGNAL_NONE)
     {
      UpdateStatusUI(sig.reason);
      return;
     }

   string msg;
   if(g_trade.OpenBySignal(sig, msg))
      UpdateStatusUI(msg);
   else
      UpdateStatusUI(msg); // 含“等待更好机会”等选择性拒绝
  }

//------------------------------------------------------------------
int OnInit()
  {
   // 提醒：对冲账户更匹配独立仓位管理
   const long margin_mode = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(margin_mode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("提示: 建议使用对冲(Hedging)账户；净额账户下买卖会相互抵消。");

   BuildParamsFromInputs(g_params);

   if(!g_regime.Init(_Symbol, PERIOD_CURRENT, g_params)) return INIT_FAILED;
   if(!g_trend.Init(_Symbol, PERIOD_CURRENT, g_params))  return INIT_FAILED;
   if(!g_range.Init(_Symbol, PERIOD_CURRENT, g_params))  return INIT_FAILED;
   if(!g_posman.Init(_Symbol, PERIOD_CURRENT, g_params)) return INIT_FAILED;

   g_risk.Init(_Symbol, g_params);
   g_filter.Init(_Symbol, PERIOD_CURRENT, g_params);
   g_trade.Init(_Symbol, GetPointer(g_risk), GetPointer(g_filter), g_params);

   if(InpShowPanel)
     {
      if(!g_panel.Create(ChartID(), g_params))
         Print("控制台创建失败，仍可用 EA 属性调参");
     }

   g_last_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   g_regime.Evaluate(true);
   g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
   UpdateStatusUI("已启动 v2");

   PrintFormat("GoldFX_Intraday v2 | %s %s | %s | %s | 无网格无马丁",
               _Symbol, EnumToString(Period()),
               MoneyModeToString(g_params.money_mode),
               RiskLevelToString(g_params.risk_level));
   return INIT_SUCCEEDED;
  }

//------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   Comment("");
   g_panel.Destroy();
   g_regime.Release();
   g_trend.Release();
   g_range.Release();
   g_posman.Release();
  }

//------------------------------------------------------------------
void OnTick()
  {
   // 持仓管理：每个 Tick 独立评估（保本/追踪/动能/超时）
   if(g_risk.CountOurPositions() > 0)
      g_posman.ManageAll();

   // 回撤保护触发时主动减仓
   if(g_risk.EquityDrawdownExceeded() && g_risk.CountOurPositions() > 0)
     {
      g_trade.CloseAll("净值回撤保护");
      UpdateStatusUI("已触发净值回撤保护平仓");
     }

   const datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar == g_last_bar)
     {
      static datetime last_ui = 0;
      if(TimeCurrent() - last_ui >= 5)
        {
         last_ui = TimeCurrent();
         g_regime.Evaluate(false);
         g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
         UpdateStatusUI();
        }
      return;
     }
   g_last_bar = bar;
   ProcessNewBar();
  }

//------------------------------------------------------------------
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!InpShowPanel)
      return;
   if(!g_panel.HandleChartEvent(id, lparam, dparam, sparam))
      return;

   if(g_panel.ConsumeModeChanged())
     {
      g_params = g_panel.Params();
      g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
      UpdateStatusUI("模式已切换");
     }

   if(g_panel.ConsumeRiskChanged())
     {
      SRuntimeParams p = g_panel.Params();
      ApplyRuntimeParams(p, false);
      g_panel.SetParams(g_params);
      UpdateStatusUI("风险/资金管理已更新");
     }

   if(g_panel.ConsumeCloseRequest())
     {
      const int n = g_trade.CloseAll("面板一键平仓");
      UpdateStatusUI(StringFormat("已平仓 %d 笔", n));
     }

   if(g_panel.ConsumeApplyRequest())
     {
      SRuntimeParams p = g_panel.Params();
      if(!ApplyRuntimeParams(p, true))
        {
         UpdateStatusUI("参数应用失败");
         return;
        }
      g_panel.SetParams(g_params);
      g_regime.Evaluate(true);
      g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
      UpdateStatusUI("参数已应用");
     }

   if(g_panel.ConsumeRefreshRequest())
     {
      g_regime.Evaluate(true);
      g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
      UpdateStatusUI("已强制重识别");
     }
  }

//------------------------------------------------------------------
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   // 预留绩效统计
  }
//+------------------------------------------------------------------+
