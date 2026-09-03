//+------------------------------------------------------------------+
//| GoldFX_OrderFlow.mq5 — 日内订单流（Delta/CVD/VWAP/POC）            |
//| 复用风控/过滤器/Telegram/仪表盘；独立 Magic，不改七条件默认行为     |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.00"
#property description "黄金/外汇日内订单流：Tape Delta CVD VWAP POC + 可选DOM"

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
#include <GoldFX/Dashboard.mqh>
#include <GoldFX/OrderFlowTape.mqh>
#include <GoldFX/VolumeProfile.mqh>
#include <GoldFX/OrderFlowBook.mqh>
#include <GoldFX/OrderFlowStrategy.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

input group "=== 运行 ==="
input ENUM_RUN_MODE        InpRunMode        = MODE_AUTO;
input ENUM_MONEY_MODE      InpMoneyMode      = MM_ADAPTIVE;
input ENUM_RISK_LEVEL      InpRiskLevel      = RISK_L3;
input bool                 InpShowDashboard  = true;
input bool                 InpAllowTrade     = true;
input int                  InpMagic          = 20260903;
input int                  InpSlippage       = 30;
input int                  InpMinBars        = 120;

input group "=== 订单流信号 ==="
input int                  InpOfStackBars    = 3;
input int                  InpOfMinPosDelta  = 2;
input double               InpOfImbalancePct = 35.0;
input int                  InpOfCvdSlopeBars = 5;
input bool                 InpOfAllowDiv     = true;
input bool                 InpOfUseAbsorb    = true;
input double               InpOfAbsorbVolMult= 1.8;
input double               InpOfAbsorbRange  = 0.45;
input bool                 InpOfUseHtf       = true;
input int                  InpOfHtfEma       = 50;
input double               InpOfSLATR        = 1.0;
input double               InpOfTPATR        = 2.0;
input double               InpOfSLATRMax     = 1.8;
input double               InpOfMinRR        = 1.5;
input int                  InpOfSwingSLBars  = 8;
input double               InpOfVaPct        = 0.70;
input int                  InpOfBucketPts    = 10;
input bool                 InpOfUseBook      = true;
input bool                 InpOfDrawLevels   = true;
input bool                 InpOfExitDeltaFlip= true;
input bool                 InpOfExitCvdDiv   = true;
input int                  InpATRPeriod      = 14;

input group "=== 选择性与过滤器 ==="
input int                  InpMinQuality     = 60;
input int                  InpMaxTradesDay   = 3;
input int                  InpCooldownBars   = 4;
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
input double               InpBETrig         = 1.0;
input double               InpBELock         = 0.12;
input bool                 InpTrail          = true;
input double               InpTrailStart     = 1.8;
input double               InpTrailStep      = 0.9;
input bool                 InpMomExit        = false;
input int                  InpMaxHoldMin     = 240;
input bool                 InpPartial        = true;
input double               InpPartialATR     = 1.6;
input double               InpPartialPct     = 40.0;

input group "=== 风控 / 自适应 ==="
input double               InpFixedLot       = 0.01;
input double               InpRiskPct        = 0.50;
input double               InpLotPer1k       = 0.02;
input double               InpMaxDailyLoss   = 2.0;
input double               InpMaxEqDD        = 8.0;
input int                  InpMaxPosSym      = 1;
input int                  InpMaxPortfolio   = 1;
input bool                 InpCorrGuard      = true;
input bool                 InpAutoPauseDD    = true;
input bool                 InpAdaptDD        = true;
input bool                 InpAdaptATR       = true;
input bool                 InpAdaptKelly     = true;
input double               InpAdaptATRRef    = 0.0;

input group "=== Telegram ==="
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
CDashboard           g_dash;
COrderFlowTape       g_tape;
CVolumeProfile       g_vp;
COrderFlowBook       g_book;
COrderFlowStrategy   g_strat;
CTrade               g_exit_trade;
string               g_status = "";
datetime             g_last_ui = 0;
datetime             g_last_level_bar = 0;
ulong                m_vp_last_msc = 0;

#define OF_LVL_PREFIX "GFXof_"

//------------------------------------------------------------------
bool ValidateInputs(string &err)
  {
   err = "";
   if(InpOfStackBars < 2 || InpOfMinPosDelta < 1 || InpOfMinPosDelta > InpOfStackBars)
     { err="堆叠失衡参数无效"; return false; }
   if(InpOfImbalancePct < 10.0 || InpOfImbalancePct > 90.0)
     { err="失衡%需在[10,90]"; return false; }
   if(InpOfMinRR < 1.0 || InpOfMinRR > 5.0)
     { err="最低盈亏比需在[1,5]"; return false; }
   if(InpOfVaPct < 0.5 || InpOfVaPct > 0.9)
     { err="VA占比需在[0.5,0.9]"; return false; }
   if(InpRiskPct <= 0 || InpRiskPct > 10)
     { err="风险%需在(0,10]"; return false; }
   if(InpMinBars < 50)
     { err="最小K线过小"; return false; }
   return true;
  }

//------------------------------------------------------------------
void BuildParams(SRuntimeParams &p)
  {
   ZeroMemory(p);
   p.strategy_engine = STRAT_ORDER_FLOW;
   p.run_mode = InpRunMode;
   p.money_mode = InpMoneyMode;
   p.risk_level = InpRiskLevel;
   p.show_dashboard = InpShowDashboard;
   p.magic = InpMagic;
   p.slippage = InpSlippage;
   p.min_bars_required = InpMinBars;
   p.atr_period = InpATRPeriod;
   p.adx_period = 14;

   p.of_stack_bars = InpOfStackBars;
   p.of_min_pos_delta = InpOfMinPosDelta;
   p.of_imbalance_pct = InpOfImbalancePct;
   p.of_cvd_slope_bars = InpOfCvdSlopeBars;
   p.of_allow_divergence = InpOfAllowDiv;
   p.of_use_absorption = InpOfUseAbsorb;
   p.of_absorb_vol_mult = InpOfAbsorbVolMult;
   p.of_absorb_range_atr = InpOfAbsorbRange;
   p.of_use_htf = InpOfUseHtf;
   p.of_htf_ema = InpOfHtfEma;
   p.of_sl_atr = InpOfSLATR;
   p.of_tp_atr = InpOfTPATR;
   p.of_sl_atr_max = InpOfSLATRMax;
   p.of_min_rr = InpOfMinRR;
   p.of_swing_sl_bars = InpOfSwingSLBars;
   p.of_va_pct = InpOfVaPct;
   p.of_bucket_points = InpOfBucketPts;
   p.of_use_book = InpOfUseBook;
   p.of_draw_levels = InpOfDrawLevels;
   p.of_exit_delta_flip = InpOfExitDeltaFlip;
   p.of_exit_cvd_div = InpOfExitCvdDiv;

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
   p.symbols_csv = "";

   p.telegram_enable = InpTgEnable;
   p.telegram_token = InpTgToken;
   p.telegram_chat_id = InpTgChatId;
   p.export_trade_log = InpExportLog;

   if(p.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(p);
  }

//------------------------------------------------------------------
void ApplyParams(const SRuntimeParams &p)
  {
   g_params = p;
   g_params.allow_martingale = false;
   g_params.strategy_engine = STRAT_ORDER_FLOW;
   if(g_params.money_mode == MM_AUTO_LEVEL)
      ApplyRiskLevelToParams(g_params);

   g_risk.Configure(g_params);
   g_filter.Configure(g_params);
   g_posman.Configure(g_params);
   g_trade.Configure(g_params);
   g_tg.Configure(g_params);
   g_journal.Configure(g_params, g_params.magic);
   g_sessnews.Configure(g_params, InpSessStart, InpSessEnd, InpUseSession);
   g_vp.Configure(g_params.of_bucket_points, g_params.of_va_pct);
   g_strat.Configure(g_params);
  }

//------------------------------------------------------------------
void DrawLevel(const string name, const double price, const color clr, const string text)
  {
   if(price <= 0.0) return;
   const string n = OF_LVL_PREFIX + name;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_HLINE, 0, 0, price);
      ObjectSetInteger(0, n, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_BACK, true);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
   ObjectSetDouble(0, n, OBJPROP_PRICE, price);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
  }

void RefreshLevels(void)
  {
   if(!g_params.of_draw_levels || !g_vp.Valid()) return;
   DrawLevel("vwap", g_vp.Vwap(), clrDodgerBlue, "VWAP");
   DrawLevel("poc",  g_vp.Poc(),  clrOrange,     "POC");
   DrawLevel("vah",  g_vp.Vah(),  clrSeaGreen,   "VAH");
   DrawLevel("val",  g_vp.Val(),  clrTomato,     "VAL");
  }

void ClearLevels(void)
  {
   ObjectsDeleteAll(0, OF_LVL_PREFIX);
  }

//------------------------------------------------------------------
void FeedVolumeProfileFromTicks(void)
  {
   // 用与 Tape 相同的增量窗口，把成交记入会话分布
   MqlTick ticks[];
   const ulong from_msc = (m_vp_last_msc > 0 ? m_vp_last_msc + 1 : (ulong)(TimeCurrent() - 60) * 1000);
   const int n = CopyTicks(_Symbol, ticks, COPY_TICKS_ALL, from_msc, 100000);
   if(n <= 0)
     {
      MqlTick tk;
      if(SymbolInfoTick(_Symbol, tk) && (ulong)tk.time_msc > m_vp_last_msc)
        {
         const double px = (tk.last > 0.0 ? tk.last :
                            (tk.bid > 0.0 && tk.ask > 0.0 ? 0.5*(tk.bid+tk.ask) : tk.bid));
         double w = 1.0;
         if(tk.volume_real > 0.0) w = (double)tk.volume_real;
         else if(tk.volume > 0) w = (double)tk.volume;
         if(px > 0.0) g_vp.AddTrade(px, w);
         m_vp_last_msc = (ulong)tk.time_msc;
        }
      return;
     }
   for(int i=0;i<n;++i)
     {
      const double px = (ticks[i].last > 0.0 ? ticks[i].last :
                         (ticks[i].bid > 0.0 && ticks[i].ask > 0.0
                          ? 0.5*(ticks[i].bid+ticks[i].ask) : ticks[i].bid));
      double w = 1.0;
      if(ticks[i].volume_real > 0.0) w = (double)ticks[i].volume_real;
      else if(ticks[i].volume > 0) w = (double)ticks[i].volume;
      if(px > 0.0) g_vp.AddTrade(px, w);
      m_vp_last_msc = (ulong)ticks[i].time_msc;
     }
  }

//------------------------------------------------------------------
void RefreshUI(const string extra="")
  {
   if(StringLen(extra)>0) g_status = extra;
   const SOrderFlowSnapshot snap = g_strat.LastSnapshot();
   string acct = StringFormat("净值%.2f 余额%.2f 日盈亏%.2f%%",
                              AccountInfoDouble(ACCOUNT_EQUITY),
                              AccountInfoDouble(ACCOUNT_BALANCE),
                              g_risk.DayPnLPercent());
   string risk = StringFormat("DD%.2f%%/%0.1f 暂停=%s 自适应×%.2f 有效风险%%=%.2f",
                              g_risk.EquityDDPercent(), g_params.max_equity_dd_pct,
                              g_risk.Paused()?"Y":"N",
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().Multiplier():1.0),
                              g_risk.LastEffRisk());
   string filt = g_sessnews.LastReason();
   if(StringLen(filt)==0) filt = "过滤器待命";
   string perf = StringFormat("滚动胜率%.0f%% (%d笔) 今日开仓%d 引擎=订单流",
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().RollWinRate()*100.0:50.0),
                              (g_risk.Adapt()!=NULL? g_risk.Adapt().RollTrades():0),
                              g_filter.DayTrades());
   string port = StringFormat("持仓%d/%d 资金=%s Magic=%d",
                              g_risk.CountPortfolio(),
                              g_params.max_open_portfolio, MoneyModeToString(g_params.money_mode),
                              g_params.magic);
   string oflags = OrderFlowFlags(snap);
   if(StringLen(snap.fail_reason)>0)
      oflags = oflags + " | " + snap.fail_reason;
   string sig = StringFormat("点差%.2f 模式=%s Book=%s",
                             CurrentSpreadPrice(_Symbol), ModeToString(g_params.run_mode),
                             (g_book.Available()?"Y":"N"));

   Comment(acct,"\n",oflags,"\n",risk,"\n",port,"\n",g_status);
   g_dash.Update(acct, sig, oflags, risk, filt, perf, port, g_status);
  }

//------------------------------------------------------------------
void ProcessOrderFlowExits(void)
  {
   if(!InpOfExitDeltaFlip && !InpOfExitCvdDiv)
      return;
   if(g_risk.CountPortfolio() <= 0)
      return;

   CPositionInfo pos;
   for(int i=PositionsTotal()-1;i>=0;--i)
     {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic()!=g_params.magic) continue;
      if(pos.Symbol()!=_Symbol) continue;

      string why;
      bool exit = false;
      if(pos.PositionType()==POSITION_TYPE_BUY)
         exit = g_strat.ShouldExitLong(InpOfExitDeltaFlip, InpOfExitCvdDiv, why);
      else
         exit = g_strat.ShouldExitShort(InpOfExitDeltaFlip, InpOfExitCvdDiv, why);
      if(!exit) continue;

      g_exit_trade.SetExpertMagicNumber(g_params.magic);
      g_exit_trade.SetDeviationInPoints(MathMax(1, g_params.slippage));
      g_exit_trade.SetTypeFillingBySymbol(pos.Symbol());
      const double pnl = pos.Profit();
      if(g_exit_trade.PositionClose(pos.Ticket()))
        {
         g_status = why;
         if(g_tg.Enabled()) g_tg.NotifyExit(pos.Symbol(), why, pnl);
         if(g_risk.Adapt()!=NULL) g_risk.Adapt().OnTradeClosed(pnl >= 0.0);
         Print("订单流离场: ", why);
        }
     }
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

   SSignalResult sig = g_strat.Evaluate(true);
   if(sig.signal == SIGNAL_NONE)
     {
      g_status = (StringLen(sig.reason)>0 ? sig.reason : "等待订单流条件");
      return;
     }

   string msg;
   g_trade.OpenBySignal(sig, msg);
   g_status = msg;
  }

//------------------------------------------------------------------
void HandleTelegram(void)
  {
   string cmd, arg;
   if(!g_tg.PollCommand(cmd, arg))
      return;
   if(cmd=="status")
     {
      g_tg.NotifyEvent(StringFormat("OF STATUS eq=%.2f dd=%.2f paused=%d cvd=%.0f",
                                    AccountInfoDouble(ACCOUNT_EQUITY), g_risk.EquityDDPercent(),
                                    (int)g_risk.Paused(), g_tape.Cvd()));
     }
   else if(cmd=="stop" || cmd=="pause")
     {
      g_trade.CloseAll("TG pause");
      g_risk.SetPaused(true);
      g_tg.NotifyEvent("OF PAUSED");
      RefreshUI("Telegram 暂停");
     }
   else if(cmd=="resume")
     {
      g_risk.SetPaused(false);
      g_tg.NotifyEvent("OF RESUMED");
      RefreshUI("Telegram 恢复");
     }
   else if(cmd=="risk")
     {
      double v = StringToDouble(arg);
      if(v > 0.05 && v <= 5.0)
        {
         g_params.risk_percent = v;
         g_params.money_mode = MM_RISK_PERCENT;
         ApplyParams(g_params);
         g_tg.NotifyEvent(StringFormat("OF RISK %.2f%%", v));
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

   if(!g_tape.Init(_Symbol, PERIOD_CURRENT))
      return INIT_FAILED;
   if(!g_vp.Init(_Symbol, g_params.of_bucket_points, g_params.of_va_pct))
      return INIT_FAILED;
   if(!g_book.Init(_Symbol, g_params.of_use_book))
      return INIT_FAILED;
   if(!g_strat.Init(_Symbol, PERIOD_CURRENT,
                    GetPointer(g_tape), GetPointer(g_vp), GetPointer(g_book), g_params))
      return INIT_FAILED;

   // 预热成交量分布（与 tape 预热窗口对齐）
   m_vp_last_msc = 0;
   FeedVolumeProfileFromTicks();
   g_vp.Rebuild();

   g_dash.Create(ChartID(), g_params);
   EventSetTimer(15);
   RefreshLevels();
   RefreshUI("订单流 EA 已启动");
   if(g_tg.Enabled())
      g_tg.NotifyEvent(StringFormat("GoldFX OrderFlow started on %s", _Symbol));

   PrintFormat("GoldFX OrderFlow | money=%s R%d magic=%d book=%d",
               MoneyModeToString(g_params.money_mode), (int)g_params.risk_level,
               g_params.magic, (int)g_book.Available());
   return INIT_SUCCEEDED;
  }

//------------------------------------------------------------------
void OnDeinit(const int reason)
  {
   EventKillTimer();
   Comment("");
   ClearLevels();
   g_dash.Destroy();
   g_book.Release();
   g_strat.Release();
   g_posman.Release();
  }

//------------------------------------------------------------------
void OnTimer()
  {
   HandleTelegram();
  }

//------------------------------------------------------------------
void OnBookEvent(const string symbol)
  {
   if(symbol == _Symbol)
      g_book.Refresh();
  }

//------------------------------------------------------------------
void OnTick()
  {
   if(Bars(_Symbol, PERIOD_CURRENT) < g_params.min_bars_required)
      return;

   // 会话换日：重置 CVD + 分布
   if(g_vp.EnsureSession())
     {
      g_tape.ResetSessionCvd();
      ClearLevels();
     }

   g_tape.ProcessNewTicks();
   FeedVolumeProfileFromTicks();
   g_vp.Rebuild();

   if(g_risk.CountPortfolio() > 0)
     {
      g_posman.ManageAll();
      ProcessOrderFlowExits();
     }

   if(g_risk.EquityDrawdownExceeded())
     {
      if(g_params.auto_pause_on_dd)
         g_risk.SetPaused(true);
      if(g_risk.CountPortfolio() > 0)
        {
         g_trade.CloseAll("回撤自动暂停");
         if(g_tg.Enabled()) g_tg.NotifyEvent("OF DRAWDOWN AUTOPAUSE");
        }
     }

   ProcessSignals();

   const datetime bar0 = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar0 != g_last_level_bar)
     {
      g_last_level_bar = bar0;
      RefreshLevels();
     }

   if(TimeCurrent() - g_last_ui >= 3)
     {
      g_last_ui = TimeCurrent();
      // 非信号刷新快照
      g_strat.Evaluate(false);
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
      g_params.strategy_engine = STRAT_ORDER_FLOW;
      RefreshUI("模式切换");
     }
   if(g_dash.ConsumeRisk())
     {
      g_params = g_dash.Params();
      ApplyParams(g_params);
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
      RefreshUI("手动按钮：请用订单流信号");
  }
//+------------------------------------------------------------------+
