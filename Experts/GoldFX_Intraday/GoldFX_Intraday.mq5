//+------------------------------------------------------------------+
//| GoldFX_Intraday.mq5 — v3 SafeScalper/Prime 能力整合版              |
//| 七条件入场 · 多品种组合 · 自适应风险 · Telegram · 仪表盘 · 持久化  |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "3.10"
#property description "七条件回调入场+ADX+结构止损 · 多品种 · 自适应风险"

#include <GoldFX/Common.mqh>
#include <GoldFX/Persistence.mqh>
#include <GoldFX/AdaptiveRisk.mqh>
#include <GoldFX/SessionNewsFilter.mqh>
#include <GoldFX/SelectivityFilter.mqh>
#include <GoldFX/RiskManager.mqh>
#include <GoldFX/PositionManager.mqh>
#include <GoldFX/TradeManager.mqh>
#include <GoldFX/TradeJournal.mqh>
#include <GoldFX/TelegramBridge.mqh>
#include <GoldFX/PortfolioEngine.mqh>
#include <GoldFX/Dashboard.mqh>
#include <GoldFX/SevenConditionStrategy.mqh>

input group "=== 运行 ==="
input ENUM_STRATEGY_ENGINE InpStrategy       = STRAT_SEVEN_COND; // 策略引擎
input ENUM_RUN_MODE        InpRunMode        = MODE_AUTO;
input ENUM_MONEY_MODE      InpMoneyMode      = MM_ADAPTIVE;      // 默认自适应
input ENUM_RISK_LEVEL      InpRiskLevel      = RISK_L4;
input string               InpSymbols        = "";               // 多品种CSV，空=仅图表；最多8
input bool                 InpShowDashboard  = true;
input bool                 InpAllowTrade     = true;
input int                  InpMagic          = 20260826;
input int                  InpSlippage       = 30;
input int                  InpMinBars        = 300;              // 最小K线保护

input group "=== 七条件（v3.1 回调优化）==="
input int                  InpScEmaFast      = 89;
input int                  InpScEmaSlow      = 233;
input double               InpScMinGapATR    = 0.25;
input int                  InpScBreakBars    = 12;
input double               InpScBreakBufATR  = 0.08;
input int                  InpRSIPeriod      = 14;
input double               InpScRsiLLo       = 45;
input double               InpScRsiLHi       = 58;
input double               InpScRsiSLo       = 42;
input double               InpScRsiSHi       = 55;
input bool                 InpScUseHTF       = true;
input int                  InpScHtfFast      = 50;
input int                  InpScHtfSlow      = 200;
input double               InpScSLATR        = 1.2;
input double               InpScTPATR        = 2.8;
input double               InpScMinADX       = 22.0;
input double               InpScMaxExtATR    = 1.30;
input bool                 InpScUsePullback  = true;
input int                  InpScPullbackBars = 4;
input int                  InpScSwingSLBars  = 8;
input double               InpScMinRR        = 1.8;
input double               InpScSLATRMax     = 1.8;
input int                  InpATRPeriod      = 14;

input group "=== 体制引擎备用参数 ==="
input int                  InpADXPeriod      = 14;
input double               InpADXTrend       = 25;
input double               InpADXRange       = 20;
input double               InpBBWidthMax     = 0.012;
input int                  InpMAFast         = 20;
input int                  InpMASlow         = 50;
input double               InpTrendSL        = 1.5;
input double               InpTrendTP        = 2.5;
input double               InpRsiOS          = 30;
input double               InpRsiOB          = 70;
input double               InpRangeSL        = 1.0;
input double               InpRangeTP        = 1.2;

input group "=== 选择性与过滤器 ==="
input int                  InpMinQuality     = 65;
input int                  InpMaxTradesDay   = 2;
input int                  InpCooldownBars   = 6;
input double               InpMaxSpread      = 0.50;
input bool                 InpPreferLNY      = true;
input bool                 InpUseNews        = true;
input int                  InpNewsBefore     = 30;
input int                  InpNewsAfter      = 30;
input bool                 InpFridayCut      = true;
input int                  InpFridayHour     = 16;
input bool                 InpUseSession     = true;
input int                  InpSessStart      = 8;
input int                  InpSessEnd        = 20;

input group "=== 仓位管理 ==="
input bool                 InpBE             = true;
input double               InpBETrig         = 1.2;
input double               InpBELock         = 0.15;
input bool                 InpTrail          = true;
input double               InpTrailStart     = 2.0;
input double               InpTrailStep      = 1.0;
input bool                 InpMomExit        = true;
input int                  InpMaxHoldMin     = 360;
input bool                 InpPartial        = true;
input double               InpPartialATR     = 2.0;
input double               InpPartialPct     = 40.0;

input group "=== 风控 / 自适应 / 组合 ==="
input double               InpFixedLot       = 0.01;
input double               InpRiskPct        = 0.75;
input double               InpLotPer1k       = 0.02;
input double               InpMaxDailyLoss   = 2.5;
input double               InpMaxEqDD        = 10.0;
input int                  InpMaxPosSym      = 1;
input int                  InpMaxPortfolio   = 3;
input bool                 InpCorrGuard      = true;
input bool                 InpAutoPauseDD    = true;
input bool                 InpAdaptDD        = true;
input bool                 InpAdaptATR       = true;
input bool                 InpAdaptKelly     = true;
input double               InpAdaptATRRef    = 0.0;

input group "=== Telegram（需允许 WebRequest）==="
input bool                 InpTgEnable       = false;
input string               InpTgToken        = "";
input string               InpTgChatId       = "";
input bool                 InpExportLog      = true;

//--- globals
SRuntimeParams       g_params;
CPersistence         g_persist;
CSessionNewsFilter   g_sessnews;
CSelectivityFilter   g_filter;
CRiskManager         g_risk;
CPositionManager     g_posman;
CTradeJournal        g_journal;
CTelegramBridge      g_tg;
CTradeManager        g_trade;
CPortfolioEngine     g_portfolio;
CDashboard           g_dash;
string               g_status = "";
datetime             g_last_ui = 0;

//------------------------------------------------------------------
bool ValidateInputs(string &err)
  {
   err = "";
   if(InpScEmaFast < 2 || InpScEmaSlow <= InpScEmaFast)
     { err="七条件 EMA 周期无效"; return false; }
   if(InpScMinGapATR <= 0 || InpScBreakBars < 3)
     { err="突破/间距参数无效"; return false; }
   if(InpScMinRR < 1.0 || InpScMinRR > 5.0)
     { err="最低盈亏比需在 [1,5]"; return false; }
   if(InpScMinADX < 10.0 || InpScMaxExtATR < 0.3)
     { err="ADX/延伸参数无效"; return false; }
   if(InpScRsiLLo >= InpScRsiLHi || InpScRsiSLo >= InpScRsiSHi)
     { err="RSI 区间无效"; return false; }
   if(InpRiskPct <= 0 || InpRiskPct > 10)
     { err="风险% 需在 (0,10]"; return false; }
   if(InpMaxEqDD < 1)
     { err="最大回撤% 过小"; return false; }
   if(InpMinBars < InpScEmaSlow)
     { err="最小K线应 >= 慢EMA"; return false; }
   if(InpMaxPortfolio < 1 || InpMaxPosSym < 1)
     { err="持仓上限无效"; return false; }
   return true;
  }

//------------------------------------------------------------------
void BuildParams(SRuntimeParams &p)
  {
   ZeroMemory(p);
   p.strategy_engine = InpStrategy;
   p.run_mode = InpRunMode;
   p.money_mode = InpMoneyMode;
   p.risk_level = InpRiskLevel;
   p.symbols_csv = InpSymbols;
   p.show_dashboard = InpShowDashboard;
   p.magic = InpMagic;
   p.slippage = InpSlippage;
   p.min_bars_required = InpMinBars;

   p.sc_ema_fast = InpScEmaFast;
   p.sc_ema_slow = InpScEmaSlow;
   p.sc_min_gap_atr = InpScMinGapATR;
   p.sc_breakout_bars = InpScBreakBars;
   p.sc_breakout_atr_buf = InpScBreakBufATR;
   p.rsi_period = InpRSIPeriod;
   p.sc_rsi_long_lo = InpScRsiLLo;
   p.sc_rsi_long_hi = InpScRsiLHi;
   p.sc_rsi_short_lo = InpScRsiSLo;
   p.sc_rsi_short_hi = InpScRsiSHi;
   p.sc_use_htf = InpScUseHTF;
   p.sc_htf_fast = InpScHtfFast;
   p.sc_htf_slow = InpScHtfSlow;
   p.sc_sl_atr = InpScSLATR;
   p.sc_tp_atr = InpScTPATR;
   p.sc_min_adx = InpScMinADX;
   p.sc_max_ext_atr = InpScMaxExtATR;
   p.sc_use_pullback = InpScUsePullback;
   p.sc_pullback_bars = InpScPullbackBars;
   p.sc_swing_sl_bars = InpScSwingSLBars;
   p.sc_min_rr = InpScMinRR;
   p.sc_sl_atr_max = InpScSLATRMax;
   p.atr_period = InpATRPeriod;

   p.adx_period = InpADXPeriod;
   p.adx_trend_threshold = InpADXTrend;
   p.adx_range_threshold = InpADXRange;
   p.bb_width_range_max = InpBBWidthMax;
   p.ma_fast = InpMAFast;
   p.ma_slow = InpMASlow;
   p.trend_sl_atr_mult = InpTrendSL;
   p.trend_tp_atr_mult = InpTrendTP;
   p.rsi_oversold = InpRsiOS;
   p.rsi_overbought = InpRsiOB;
   p.range_sl_atr_mult = InpRangeSL;
   p.range_tp_atr_mult = InpRangeTP;

   p.min_quality_score = InpMinQuality;
   p.max_trades_per_day = InpMaxTradesDay;
   p.cooldown_bars = InpCooldownBars;
   p.max_spread_price = InpMaxSpread;
   p.prefer_london_ny = InpPreferLNY;
   p.use_news_filter = InpUseNews;
   p.news_pause_minutes_before = InpNewsBefore;
   p.news_pause_minutes_after = InpNewsAfter;
   p.friday_cutoff = InpFridayCut;
   p.friday_cutoff_hour = InpFridayHour;

   p.use_breakeven = InpBE;
   p.be_trigger_atr = InpBETrig;
   p.be_lock_atr = InpBELock;
   p.use_trailing = InpTrail;
   p.trail_start_atr = InpTrailStart;
   p.trail_step_atr = InpTrailStep;
   p.use_momentum_exit = InpMomExit;
   p.max_hold_minutes = InpMaxHoldMin;
   p.use_partial_close = InpPartial;
   p.partial_at_atr = InpPartialATR;
   p.partial_percent = InpPartialPct;

   p.fixed_lot = InpFixedLot;
   p.risk_percent = InpRiskPct;
   p.balance_lot_per_1k = InpLotPer1k;
   p.max_daily_loss_pct = InpMaxDailyLoss;
   p.max_equity_dd_pct = InpMaxEqDD;
   p.max_positions = InpMaxPosSym;
   p.max_open_portfolio = InpMaxPortfolio;
   p.correlation_guard = InpCorrGuard;
   p.auto_pause_on_dd = InpAutoPauseDD;
   p.allow_martingale = false;
   p.adapt_dd_scale = InpAdaptDD;
   p.adapt_atr_scale = InpAdaptATR;
   p.adapt_kelly_scale = InpAdaptKelly;
   p.adapt_atr_ref = InpAdaptATRRef;

   p.telegram_enable = InpTgEnable;
   p.telegram_token = InpTgToken;
   p.telegram_chat_id = InpTgChatId;
   p.export_trade_log = InpExportLog;

   if(p.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(p);
  }

//------------------------------------------------------------------
void ApplyParams(const SRuntimeParams &p, const bool rebuild_portfolio)
  {
   g_params = p;
   g_params.allow_martingale = false;
   if(g_params.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(g_params);

   g_risk.Configure(g_params);
   g_filter.Configure(g_params);
   g_posman.Configure(g_params);
   g_trade.Configure(g_params);
   g_tg.Configure(g_params);
   g_journal.Configure(g_params, g_params.magic);
   g_sessnews.Configure(g_params, InpSessStart, InpSessEnd, InpUseSession);

   if(rebuild_portfolio)
      g_portfolio.Init(g_params.symbols_csv, PERIOD_CURRENT, g_params);
   else
      g_portfolio.Reconfigure(g_params);
  }

//------------------------------------------------------------------
string SevenFlags(const SSevenCondSnapshot &s)
  {
   return StringFormat("条件 %s%s%s%s%s%s%s ADX=%s EXT=%s | EMA%.1f/%.1f gap=%.2f RSI=%.1f ADX=%.1f ext=%.2f",
                       s.ema_trend?"1":"-", s.ema_strength?"2":"-", s.price_pos?"3":"-",
                       s.breakout?"4":"-", s.rsi_ok?"5":"-", s.momentum?"6":"-", s.htf_ok?"7":"-",
                       s.adx_ok?"Y":"N", s.not_extended?"Y":"N",
                       s.ema_fast, s.ema_slow, s.ema_gap_atr, s.rsi, s.adx, s.ext_atr);
  }

//------------------------------------------------------------------
void RefreshUI(const string extra="")
  {
   if(StringLen(extra)>0) g_status = extra;
   const SSevenCondSnapshot snap = g_portfolio.DashSnapshot();
   string acct = StringFormat("净值%.2f 余额%.2f 日盈亏%.2f%%",
                              AccountInfoDouble(ACCOUNT_EQUITY),
                              AccountInfoDouble(ACCOUNT_BALANCE),
                              g_risk.DayPnLPercent());
   string risk = StringFormat("DD%.2f%%/%0.1f 暂停=%s 自适应×%.2f 有效风险%%=%.2f 档=%s",
                              g_risk.EquityDDPercent(), g_params.max_equity_dd_pct,
                              g_risk.Paused()?"Y":"N",
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().Multiplier():1.0),
                              g_risk.LastEffRisk(), RiskLevelToString(g_params.risk_level));
   string filt = g_sessnews.LastReason();
   if(StringLen(filt)==0) filt = "过滤器待命";
   string perf = StringFormat("滚动胜率%.0f%% (%d笔) 今日开仓%d 引擎=%s",
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().RollWinRate()*100.0:50.0),
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().RollTrades():0),
                              g_filter.DayTrades(), StratToString(g_params.strategy_engine));
   string port = StringFormat("品种数%d 组合持仓%d/%d 资金=%s",
                              g_portfolio.Count(), g_risk.CountPortfolio(),
                              g_params.max_open_portfolio, MoneyModeToString(g_params.money_mode));
   string sig = StringFormat("点差%.2f 模式=%s", CurrentSpreadPrice(_Symbol), ModeToString(g_params.run_mode));

   Comment(acct,"\n",SevenFlags(snap),"\n",risk,"\n",port,"\n",g_status);
   g_dash.Update(acct, sig, SevenFlags(snap), risk, filt, perf, port, g_status);
  }

//------------------------------------------------------------------
void ProcessSignals(void)
  {
   if(Bars(_Symbol, PERIOD_CURRENT) < g_params.min_bars_required)
      return;

   if(g_params.run_mode == MODE_FLAT || !InpAllowTrade)
      return;
   if(g_risk.Paused())
      return;

   string fr;
   if(!g_sessnews.AllowTrade(fr))
     {
      g_status = fr;
      return;
     }

   SSignalResult sigs[];
   const int n = g_portfolio.ScanNewBars(sigs, g_params.run_mode);
   if(n <= 0)
     {
      g_status = "等待回调+ADX条件 / 新K线";
      return;
     }

   for(int i=0;i<n;++i)
     {
      string msg;
      g_trade.OpenBySignal(sigs[i], msg);
      g_status = msg;
     }
  }

//------------------------------------------------------------------
void HandleTelegram(void)
  {
   string cmd, arg;
   if(!g_tg.PollCommand(cmd, arg))
      return;
   if(cmd=="status")
     {
      g_tg.NotifyEvent(StringFormat("STATUS eq=%.2f dd=%.2f paused=%d positions=%d",
                                    AccountInfoDouble(ACCOUNT_EQUITY), g_risk.EquityDDPercent(),
                                    (int)g_risk.Paused(), g_risk.CountPortfolio()));
     }
   else if(cmd=="stop" || cmd=="pause")
     {
      if(StringLen(arg)>0)
         g_trade.CloseAll("TG pause symbol", arg);
      g_risk.SetPaused(true);
      g_tg.NotifyEvent("PAUSED");
      RefreshUI("Telegram 暂停");
     }
   else if(cmd=="resume")
     {
      g_risk.SetPaused(false);
      g_tg.NotifyEvent("RESUMED");
      RefreshUI("Telegram 恢复");
     }
   else if(cmd=="risk")
     {
      double v = StringToDouble(arg);
      if(v > 0.05 && v <= 5.0)
        {
         g_params.risk_percent = v;
         g_params.money_mode = MM_RISK_PERCENT;
         ApplyParams(g_params, false);
         g_tg.NotifyEvent(StringFormat("RISK set to %.2f%%", v));
         RefreshUI("远程风险已更新");
        }
     }
  }

//------------------------------------------------------------------
int OnInit()
  {
   string err;
   if(!ValidateInputs(err))
     {
      Print("输入验证失败: ", err);
      return INIT_PARAMETERS_INCORRECT;
     }

   long mm = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   if(mm != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("提示: 建议对冲账户以支持多品种独立仓位");

   BuildParams(g_params);
   g_persist.Init(g_params.magic);
   g_risk.Init(GetPointer(g_persist), g_params);
   g_filter.Init(_Symbol, PERIOD_CURRENT, g_params);
   g_posman.Init(PERIOD_CURRENT, g_params);
   g_journal.Configure(g_params, g_params.magic);
   g_tg.Configure(g_params);
   g_sessnews.Configure(g_params, InpSessStart, InpSessEnd, InpUseSession);
   g_trade.Init(GetPointer(g_risk), GetPointer(g_filter),
                GetPointer(g_journal), GetPointer(g_tg), g_params);

   if(!g_portfolio.Init(g_params.symbols_csv, PERIOD_CURRENT, g_params))
      return INIT_FAILED;

   g_dash.Create(ChartID(), g_params);
   EventSetTimer(15);
   RefreshUI("v3.1 回调优化已启动");
   if(g_tg.Enabled())
      g_tg.NotifyEvent(StringFormat("GoldFX v3 started on %s symbols=%d", _Symbol, g_portfolio.Count()));

   PrintFormat("GoldFX v3 | engine=%s money=%s R%d symbols=%d",
               StratToString(g_params.strategy_engine), MoneyModeToString(g_params.money_mode),
               (int)g_params.risk_level, g_portfolio.Count());
   return INIT_SUCCEEDED;
  }

//------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   g_dash.Destroy();
   g_portfolio.Release();
   g_posman.Release();
  }

//------------------------------------------------------------------
void OnTimer()
  {
   HandleTelegram();
  }

//------------------------------------------------------------------
void OnTick()
  {
   // 最小K线保护
   if(Bars(_Symbol, PERIOD_CURRENT) < g_params.min_bars_required)
      return;

   if(g_risk.CountPortfolio() > 0)
      g_posman.ManageAll();

   if(g_risk.EquityDrawdownExceeded())
     {
      if(g_params.auto_pause_on_dd)
         g_risk.SetPaused(true);
      if(g_risk.CountPortfolio() > 0)
        {
         g_trade.CloseAll("回撤自动暂停");
         if(g_tg.Enabled()) g_tg.NotifyEvent("DRAWDOWN AUTOPAUSE");
        }
     }

   ProcessSignals();

   if(TimeCurrent() - g_last_ui >= 5)
     {
      g_last_ui = TimeCurrent();
      g_portfolio.RefreshDashSnapshot();
      RefreshUI();
     }
  }

//------------------------------------------------------------------
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(!g_dash.HandleChartEvent(id, lparam, dparam, sparam))
      return;

   if(g_dash.ConsumeMode())
     {
      g_params = g_dash.Params();
      RefreshUI("模式切换");
     }
   if(g_dash.ConsumeRisk())
     {
      g_params = g_dash.Params();
      ApplyParams(g_params, false);
      g_dash.SetParams(g_params);
      RefreshUI("风险/资金已更新");
     }
   if(g_dash.ConsumeClose())
     {
      int n = g_trade.CloseAll("仪表盘全平");
      RefreshUI(StringFormat("已平 %d", n));
     }
   if(g_dash.ConsumeResume())
     {
      g_risk.SetPaused(false);
      RefreshUI("已恢复交易");
     }
   if(g_dash.ConsumeManualBuy() || g_dash.ConsumeManualSell())
     {
      // 驾驶舱手动：仅在七条件快照允许时提示，不绕过风控乱开
      RefreshUI("手动按钮：请用策略信号；或切观察后自行下单");
     }
  }
//+------------------------------------------------------------------+
