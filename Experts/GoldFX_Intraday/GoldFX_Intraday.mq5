//+------------------------------------------------------------------+
//| GoldFX_Intraday.mq5 — 黄金/外汇日内交易初步框架                     |
//| 功能：趋势/震荡自动识别 · 策略切换 · 图表参数面板 · 基础风控         |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property link      ""
#property version   "1.00"
#property strict
#property description "黄金/外汇日内框架：ADX+布林带宽体制识别，趋势EMA交叉 / 震荡均值回归，图表可调参"

#include <GoldFX/Common.mqh>
#include <GoldFX/RegimeDetector.mqh>
#include <GoldFX/TrendStrategy.mqh>
#include <GoldFX/RangeStrategy.mqh>
#include <GoldFX/RiskManager.mqh>
#include <GoldFX/TradeManager.mqh>
#include <GoldFX/ParamPanel.mqh>

//======================== 输入参数（EA 属性面板） ========================
input group "=== 运行 ==="
input ENUM_RUN_MODE InpRunMode           = MODE_AUTO;   // 初始运行模式
input bool          InpShowPanel         = true;        // 显示图表参数面板
input bool          InpAllowTrade        = true;        // 允许实盘/模拟下单
input int           InpMagic             = 20260826;    // Magic Number
input int           InpSlippage          = 30;          // 滑点(点)

input group "=== 体制识别 ==="
input int           InpADXPeriod         = 14;          // ADX 周期
input double        InpADXTrend          = 25.0;        // ADX ≥ 此值偏趋势
input double        InpADXRange          = 20.0;        // ADX ≤ 此值偏震荡
input int           InpATRPeriod         = 14;          // ATR 周期
input double        InpBBWidthRangeMax   = 0.012;       // 布林带宽上限(相对中轨)判震荡
input int           InpMAFast            = 20;          // 快均线
input int           InpMASlow            = 50;          // 慢均线

input group "=== 趋势策略 ==="
input double        InpTrendSL_ATR       = 1.5;         // 止损 = ATR ×
input double        InpTrendTP_ATR       = 2.5;         // 止盈 = ATR ×

input group "=== 震荡策略 ==="
input int           InpRSIPeriod         = 14;          // RSI 周期
input double        InpRSIOversold       = 30.0;        // RSI 超卖
input double        InpRSIOverbought     = 70.0;        // RSI 超买
input double        InpRangeSL_ATR       = 1.0;         // 止损 = ATR ×
input double        InpRangeTP_ATR       = 1.2;         // 止盈 = ATR ×（若无中轨则用）

input group "=== 风控 ==="
input bool          InpUseFixedLot       = true;        // true=固定手数 / false=按风险%
input double        InpFixedLot          = 0.01;        // 固定手数
input double        InpRiskPercent       = 0.5;         // 单笔风险占净值%
input double        InpMaxDailyLossPct   = 3.0;         // 日内最大亏损%
input int           InpMaxPositions      = 1;           // 同品种最大持仓数

input group "=== 会话过滤（服务器时间）==="
input bool          InpUseSessionFilter  = true;        // 启用交易时段过滤
input int           InpSessionStartHour  = 8;           // 开始小时
input int           InpSessionEndHour    = 22;          // 结束小时（不含）

//======================== 全局模块 ========================
SRuntimeParams   g_params;
CRegimeDetector  g_regime;
CTrendStrategy   g_trend;
CRangeStrategy   g_range;
CRiskManager     g_risk;
CTradeManager    g_trade;
CParamPanel      g_panel;

datetime         g_last_bar = 0;
ENUM_MARKET_REGIME g_active_regime = REGIME_UNKNOWN;
string           g_last_msg = "";

//------------------------------------------------------------------
void BuildParamsFromInputs(SRuntimeParams &p)
  {
   ZeroMemory(p);
   p.run_mode             = InpRunMode;
   p.adx_period           = InpADXPeriod;
   p.adx_trend_threshold  = InpADXTrend;
   p.adx_range_threshold  = InpADXRange;
   p.atr_period           = InpATRPeriod;
   p.bb_width_range_max   = InpBBWidthRangeMax;
   p.ma_fast              = InpMAFast;
   p.ma_slow              = InpMASlow;
   p.trend_sl_atr_mult    = InpTrendSL_ATR;
   p.trend_tp_atr_mult    = InpTrendTP_ATR;
   p.rsi_period           = InpRSIPeriod;
   p.rsi_oversold         = InpRSIOversold;
   p.rsi_overbought       = InpRSIOverbought;
   p.range_sl_atr_mult    = InpRangeSL_ATR;
   p.range_tp_atr_mult    = InpRangeTP_ATR;
   p.risk_percent         = InpRiskPercent;
   p.fixed_lot            = InpFixedLot;
   p.use_fixed_lot        = InpUseFixedLot;
   p.max_daily_loss_pct   = InpMaxDailyLossPct;
   p.max_positions        = InpMaxPositions;
   p.magic                = InpMagic;
   p.slippage             = InpSlippage;
  }

//------------------------------------------------------------------
bool ApplyRuntimeParams(const SRuntimeParams &p, const bool rebuild_indicators)
  {
   g_params = p;
   g_risk.Configure(g_params);
   g_trade.Configure(g_params);

   if(rebuild_indicators)
     {
      if(!g_regime.Configure(g_params))
         return false;
      if(!g_trend.Configure(g_params))
         return false;
      if(!g_range.Configure(g_params))
         return false;
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
   // 跨日
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
      case MODE_AUTO:
      default:         return detected;
     }
  }

//------------------------------------------------------------------
void UpdateStatusUI(const string extra = "")
  {
   string line = StringFormat("%s | 模式=%s | 识别=%s | 生效=%s | 日盈亏=%.2f%%",
                              g_regime.Diagnostics(),
                              ModeToString(g_params.run_mode),
                              RegimeToString(g_regime.LastRegime()),
                              RegimeToString(g_active_regime),
                              g_risk.DayPnLPercent());
   if(StringLen(extra) > 0)
      line += " | " + extra;
   g_last_msg = line;
   Comment(line);
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
   ZeroMemory(sig);

   if(g_active_regime == REGIME_TREND)
      sig = g_trend.Evaluate();
   else if(g_active_regime == REGIME_RANGE)
      sig = g_range.Evaluate();

   if(sig.signal == SIGNAL_NONE)
     {
      UpdateStatusUI(sig.reason);
      return;
     }

   string msg;
   if(g_trade.OpenBySignal(sig, msg))
      UpdateStatusUI(msg);
   else
      UpdateStatusUI(msg);
  }

//------------------------------------------------------------------
int OnInit()
  {
   BuildParamsFromInputs(g_params);

   if(!g_regime.Init(_Symbol, PERIOD_CURRENT, g_params))
      return INIT_FAILED;
   if(!g_trend.Init(_Symbol, PERIOD_CURRENT, g_params))
      return INIT_FAILED;
   if(!g_range.Init(_Symbol, PERIOD_CURRENT, g_params))
      return INIT_FAILED;

   g_risk.Init(_Symbol, g_params);
   g_trade.Init(_Symbol, GetPointer(g_risk), g_params);

   if(InpShowPanel)
     {
      if(!g_panel.Create(ChartID(), g_params))
         Print("参数面板创建失败，仍可使用 EA 属性面板调参");
     }

   g_last_bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   g_regime.Evaluate(true);
   g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
   UpdateStatusUI("已启动");

   PrintFormat("GoldFX_Intraday 启动 | %s %s | 模式=%s",
               _Symbol, EnumToString(Period()), ModeToString(g_params.run_mode));
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
  }

//------------------------------------------------------------------
void OnTick()
  {
   // 面板事件驱动的请求（平仓 / 应用参数）在 OnChartEvent 处理；
   // 这里只做新 K 线逻辑，降低 Tick 负担。
   const datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar == g_last_bar)
     {
      // 轻量刷新状态（非必要可不每 Tick）
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

   // 模式切换：立即生效，无需重建指标
   if(g_panel.ConsumeModeChanged())
     {
      g_params = g_panel.Params();
      g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
      UpdateStatusUI("模式已切换");
     }

   if(g_panel.ConsumeCloseRequest())
     {
      const int n = g_trade.CloseAll("面板一键平仓");
      UpdateStatusUI(StringFormat("已平仓 %d 笔", n));
     }

   if(g_panel.ConsumeApplyRequest())
     {
      SRuntimeParams p = g_panel.Params();
      // 面板已把编辑框写入 Params；模式以面板为准
      if(!ApplyRuntimeParams(p, true))
        {
         UpdateStatusUI("参数应用失败");
         return;
        }
      g_panel.SetParams(g_params);
      g_regime.Evaluate(true);
      g_active_regime = ResolveEffectiveRegime(g_regime.LastRegime());
      UpdateStatusUI("参数已应用并重识别");
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
   // 预留：可在此记录成交、统计胜率、推送通知
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
     {
      // PrintFormat("成交 deal=%I64u", trans.deal);
     }
  }
//+------------------------------------------------------------------+
