//+------------------------------------------------------------------+
//| GoldFX_BoxBreakout.mq5 — 顺势小箱体突破（独立包）                   |
//| 与 GoldFX_Intraday 完全分离，单独编译、单独安装                    |
//+------------------------------------------------------------------+
#property copyright "GoldFX BoxBreakout"
#property version   "1.00"
#property description "顺势小箱体突破独立 EA（上涨只做上破，下跌只做下破）"

#include <GoldFX_Box/Common.mqh>
#include <GoldFX_Box/BoxBreakoutStrategy.mqh>
#include <GoldFX_Box/PositionTrail.mqh>
#include <Trade\Trade.mqh>

input group "=== 运行 ==="
input bool   InpAllowTrade   = true;
input int    InpMagic        = 20260913;
input int    InpSlippage     = 30;
input int    InpMinBars      = 300;
input int    InpMinQuality   = 60;
input int    InpMaxTradesDay = 3;
input int    InpCooldownBars = 4;
input double InpMaxSpread    = 0.50;

input group "=== 箱体 ==="
input int    InpBoxLookback  = 8;
input int    InpBoxMinBars   = 5;
input double InpBoxWMinATR   = 0.35;
input double InpBoxWMaxATR   = 1.20;
input double InpBoxBreakBuf  = 0.05;
input int    InpBoxEmaFast   = 50;
input int    InpBoxEmaSlow   = 200;
input double InpBoxMinADX    = 20.0;
input double InpBoxSLBufATR  = 0.10;
input double InpBoxTPHeight  = 2.0;
input double InpBoxMinRR     = 1.5;
input bool   InpBoxUseHTF    = true;
input int    InpBoxHtfFast   = 50;
input int    InpBoxHtfSlow   = 200;
input int    InpBoxTouchMin  = 1;
input int    InpATRPeriod    = 14;
input int    InpADXPeriod    = 14;

input group "=== 资金 ==="
input bool   InpUseRiskPct   = true;
input double InpRiskPct      = 0.75;
input double InpFixedLot     = 0.01;

input group "=== 时段 ==="
input bool   InpUseSession   = true;
input int    InpSessStart    = 8;
input int    InpSessEnd      = 20;
input bool   InpFridayCut    = true;
input int    InpFridayHour   = 16;

input group "=== 动态离场 ==="
input bool   InpBE           = true;
input double InpBETrig       = 1.0;
input double InpBELock       = 0.10;
input bool   InpTrail        = true;
input double InpTrailStart   = 1.8;
input double InpTrailStep    = 0.9;
input bool   InpPartial      = true;
input double InpPartialATR   = 1.8;
input double InpPartialPct   = 40.0;
input int    InpMaxHoldMin   = 360;

CBoxBreakoutStrategy g_box;
CPositionTrail       g_trail;
CTrade               g_trade;
datetime             g_last_bar = 0;
datetime             g_cooldown_until = 0;
int                  g_day_trades = 0;
int                  g_day_stamp = 0;
string               g_status = "";

bool ValidateInputs(string &err)
  {
   err = "";
   if(InpBoxLookback < 4 || InpBoxMinBars < 3 || InpBoxMinBars > InpBoxLookback)
     { err="箱体回看/最少根数无效"; return false; }
   if(InpBoxWMinATR <= 0.0 || InpBoxWMaxATR <= InpBoxWMinATR)
     { err="箱宽 ATR 区间无效"; return false; }
   if(InpBoxEmaFast < 2 || InpBoxEmaSlow <= InpBoxEmaFast)
     { err="趋势 EMA 无效"; return false; }
   if(InpBoxMinRR < 1.0 || InpBoxTPHeight < 0.5)
     { err="TP/RR 无效"; return false; }
   if(InpFixedLot <= 0.0)
     { err="固定手数无效"; return false; }
   return true;
  }

void FillBoxParams(SBoxParams &p)
  {
   ZeroMemory(p);
   p.atr_period = InpATRPeriod;
   p.adx_period = InpADXPeriod;
   p.box_lookback = InpBoxLookback;
   p.box_min_bars = InpBoxMinBars;
   p.box_width_min_atr = InpBoxWMinATR;
   p.box_width_max_atr = InpBoxWMaxATR;
   p.box_break_buf_atr = InpBoxBreakBuf;
   p.box_ema_fast = InpBoxEmaFast;
   p.box_ema_slow = InpBoxEmaSlow;
   p.box_min_adx = InpBoxMinADX;
   p.box_sl_buf_atr = InpBoxSLBufATR;
   p.box_tp_height_mult = InpBoxTPHeight;
   p.box_min_rr = InpBoxMinRR;
   p.box_use_htf = InpBoxUseHTF;
   p.box_htf_fast = InpBoxHtfFast;
   p.box_htf_slow = InpBoxHtfSlow;
   p.box_touch_min = InpBoxTouchMin;
  }

bool SessionOK(string &why)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpFridayCut && dt.day_of_week==5 && dt.hour>=InpFridayHour)
     { why="周五截止"; return false; }
   if(!InpUseSession) return true;
   if(InpSessStart==InpSessEnd) return true;
   if(InpSessStart < InpSessEnd)
     {
      if(dt.hour < InpSessStart || dt.hour >= InpSessEnd)
        { why="非交易时段"; return false; }
     }
   else if(dt.hour < InpSessStart && dt.hour >= InpSessEnd)
     { why="非交易时段"; return false; }
   return true;
  }

void ResetDayIfNeeded(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   const int stamp = dt.year*10000 + dt.mon*100 + dt.day;
   if(stamp != g_day_stamp)
     {
      g_day_stamp = stamp;
      g_day_trades = 0;
     }
  }

double CalcLot(const double entry, const double sl)
  {
   if(!InpUseRiskPct || InpRiskPct<=0.0)
      return NormalizeDouble(InpFixedLot, 2);

   const double tick_val = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   const double tick_sz  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tick_val<=0.0 || tick_sz<=0.0) return InpFixedLot;
   const double risk_money = AccountInfoDouble(ACCOUNT_EQUITY)*(InpRiskPct/100.0);
   const double dist = MathAbs(entry-sl);
   if(dist<=0.0) return InpFixedLot;
   double lot = risk_money / (dist/tick_sz*tick_val);
   double vmin = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double vmax = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double vstep= SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(vstep<=0.0) vstep=0.01;
   lot = MathFloor(lot/vstep)*vstep;
   lot = MathMax(vmin, MathMin(vmax, lot));
   return NormalizeDouble(lot, 2);
  }

bool OpenSignal(const SSignalResult &sig, string &msg)
  {
   if(sig.signal==SIGNAL_NONE){ msg="无信号"; return false; }
   if(sig.sl<=0.0){ msg="无止损"; return false; }
   if(sig.quality < InpMinQuality)
     { msg=StringFormat("质量不足 Q=%d", sig.quality); return false; }
   if(CurrentSpreadPrice(_Symbol) > InpMaxSpread)
     { msg="点差过大"; return false; }
   if(g_trail.CountMine(_Symbol) > 0)
     { msg="已有持仓"; return false; }
   if(g_day_trades >= InpMaxTradesDay)
     { msg="日笔数上限"; return false; }

   const double lot = CalcLot(sig.entry, sig.sl);
   if(lot<=0.0){ msg="手数无效"; return false; }

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   g_trade.SetTypeFillingBySymbol(_Symbol);

   const string cmt = StringFormat("BOX Q%d", sig.quality);
   bool ok=false;
   if(sig.signal==SIGNAL_BUY)
      ok=g_trade.Buy(lot, _Symbol, 0.0, sig.sl, sig.tp, cmt);
   else
      ok=g_trade.Sell(lot, _Symbol, 0.0, sig.sl, sig.tp, cmt);

   if(!ok)
     {
      msg=StringFormat("下单失败 %d", g_trade.ResultRetcode());
      return false;
     }

   g_day_trades++;
   g_cooldown_until = iTime(_Symbol, PERIOD_CURRENT, 0)
                      + (datetime)(PeriodSeconds(PERIOD_CURRENT)*InpCooldownBars);
   msg=StringFormat("开仓 %s lot=%.2f SL=%.2f TP=%.2f | %s",
                    SignalToString(sig.signal), lot, sig.sl, sig.tp, sig.reason);
   return true;
  }

void RefreshUI(void)
  {
   Comment(StringFormat(
      "GoldFX BoxBreakout（独立包）\n状态: %s\n点差 %.2f | 今日 %d/%d | 持仓 %d\n%s",
      g_box.LastStatus(),
      CurrentSpreadPrice(_Symbol),
      g_day_trades, InpMaxTradesDay,
      g_trail.CountMine(_Symbol),
      g_status));
  }

int OnInit()
  {
   string err;
   if(!ValidateInputs(err))
     {
      Print(err);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(Bars(_Symbol, PERIOD_CURRENT) < InpMinBars)
      PrintFormat("警告: 当前K线 %d < 建议最小 %d",
                  Bars(_Symbol, PERIOD_CURRENT), InpMinBars);

   SBoxParams bp;
   FillBoxParams(bp);
   if(!g_box.Init(_Symbol, PERIOD_CURRENT, bp))
      return INIT_FAILED;

   g_trail.Configure(InpMagic, InpSlippage, InpATRPeriod, PERIOD_CURRENT,
                     InpBE, InpBETrig, InpBELock,
                     InpTrail, InpTrailStart, InpTrailStep,
                     InpPartial, InpPartialATR, InpPartialPct,
                     InpMaxHoldMin);

   g_status="顺势箱体独立包已启动";
   RefreshUI();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   g_box.Release();
  }

void OnTick()
  {
   ResetDayIfNeeded();
   if(g_trail.CountMine(_Symbol) > 0)
      g_trail.Manage();

   const datetime bar = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(bar==0 || bar==g_last_bar)
     {
      RefreshUI();
      return;
     }
   g_last_bar = bar;

   if(!InpAllowTrade)
     {
      g_status="交易关闭";
      RefreshUI();
      return;
     }

   string why;
   if(!SessionOK(why))
     {
      g_status=why;
      RefreshUI();
      return;
     }

   if(bar < g_cooldown_until)
     {
      g_status="冷却中";
      RefreshUI();
      return;
     }

   SSignalResult sig = g_box.Evaluate();
   if(sig.signal != SIGNAL_NONE)
     {
      string msg;
      OpenSignal(sig, msg);
      g_status=msg;
     }
   else
      g_status=g_box.LastStatus();

   RefreshUI();
  }
//+------------------------------------------------------------------+
