//+------------------------------------------------------------------+
//| GoldFX_BasisArb.mq4 — 黄金期现基差套利 / 价差提醒（MT4）            |
//| 安装：复制到 MQL4\Experts 后 F7 编译；需同时复制 Include\GoldFX     |
//| 或使用仓库根目录 install_to_MT4.bat 一键安装                        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property link      "https://github.com/szgogol1/GoldFX-MT5"
#property version   "1.20"
#property strict
#property description "黄金现货-期货基差Z分：双K对比配合，价差大开仓/收敛盈利平仓提醒"

#include <GoldFX/BasisArbitrage.mqh>
#include <GoldFX/TelegramBridge.mqh>

//=== 品种 ===
input string InpSpotSymbol      = "XAUUSD.s"; // 现货
input string InpFutSymbol       = "GC";       // 期货
input int    InpTF              = PERIOD_M15; // 统计周期

//=== 基差模型 ===
input int    InpSpreadMode      = 0;          // 0=F-S 1=比率 2=对数
input int    InpLookback        = 60;         // 滚动窗口
input double InpEntryZ          = 2.0;        // 入场|Z|
input double InpExitZ           = 0.40;       // 出场|Z|
input double InpStopZ           = 3.5;        // 止损|Z|
input double InpMinCorr         = 0.88;       // 最低相关
input int    InpMinBars         = 120;
input int    InpMaxHoldBars     = 48;         // 超时平仓
input int    InpCooldownBars    = 4;
input double InpMinProfitMoney  = 5.0;        // 回归平仓最小浮盈

//=== 仓位 / 风控 ===
input double InpLotSpot         = 0.10;       // 现货手数
input bool   InpAutoHedge       = true;       // 名义对冲
input double InpMaxDailyLossPct = 2.0;
input double InpMaxSpreadSpot   = 0.60;
input double InpMaxSpreadFut    = 0.80;
input bool   InpAllowTrade      = true;
input bool   InpStartManual     = true;       // 启动为手动（只提醒，推荐）
input int    InpMagic           = 20260827;
input int    InpSlippage        = 40;

//=== 提醒 ===
input bool   InpUseAlert        = true;
input bool   InpUsePush         = true;
input bool   InpTelegramEnable  = false;
input string InpTelegramToken   = "";
input string InpTelegramChatId  = "";
input bool   InpShowPanel       = true;

//=== 时段 ===
input bool   InpUseSession      = true;
input int    InpSessStart       = 1;
input int    InpSessEnd         = 22;
input bool   InpFridayCut       = true;
input int    InpFridayHour      = 18;

#define PANEL_PREFIX "GFXBA4_"
#define BTN_MODE     "GFXBA4_btnMode"

CBasisArbitrage g_engine;
CTelegramBridge g_tg;
string          g_status = "";
datetime        g_day_stamp = 0;
double          g_day_start_eq = 0;
bool            g_paused = false;
int             g_last_alert_act = -1;
datetime        g_last_alert_bar = 0;
bool            g_manual = true;   // true=手动观察(仅提醒)  false=自动交易

void NotifySignal(const int act, const string msg);
void RenderPanel();

//------------------------------------------------------------------
bool IsManualMode()
  {
   return g_manual;
  }

void UpdateModeButton()
  {
   if(ObjectFind(BTN_MODE)<0)
     {
      ObjectCreate(BTN_MODE, OBJ_BUTTON, 0, 0, 0);
      ObjectSet(BTN_MODE, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSet(BTN_MODE, OBJPROP_XDISTANCE, 160);
      ObjectSet(BTN_MODE, OBJPROP_YDISTANCE, 20);
      ObjectSet(BTN_MODE, OBJPROP_XSIZE, 150);
      ObjectSet(BTN_MODE, OBJPROP_YSIZE, 28);
      ObjectSet(BTN_MODE, OBJPROP_SELECTABLE, true);
     }
   if(g_manual)
     {
      ObjectSetText(BTN_MODE, "模式: 手动观察", 10, "Arial", White);
      ObjectSet(BTN_MODE, OBJPROP_BGCOLOR, C'40,90,140');
      ObjectSet(BTN_MODE, OBJPROP_COLOR, White);
     }
   else
     {
      ObjectSetText(BTN_MODE, "模式: 自动交易", 10, "Arial", White);
      ObjectSet(BTN_MODE, OBJPROP_BGCOLOR, C'160,70,40');
      ObjectSet(BTN_MODE, OBJPROP_COLOR, White);
     }
   ObjectSetInteger(0, BTN_MODE, OBJPROP_STATE, false);
   ChartRedraw();
  }

void ToggleManualAuto()
  {
   g_manual = !g_manual;
   if(g_manual)
     {
      g_status = "已切换【手动观察】— 只提醒不开仓";
      NotifySignal(99, "GoldFX: 切换为手动观察（仅提醒）");
     }
   else
     {
      g_status = "已切换【自动交易】— 将按信号双边下单";
      NotifySignal(98, "GoldFX: 切换为自动交易（实盘对冲）");
     }
   UpdateModeButton();
   RenderPanel();
  }

bool InSession()
  {
   const int dow = TimeDayOfWeek(TimeCurrent());
   const int hour = TimeHour(TimeCurrent());
   if(InpFridayCut && dow==5 && hour>=InpFridayHour) return false;
   if(!InpUseSession) return true;
   if(InpSessStart < InpSessEnd)
      return (hour>=InpSessStart && hour<InpSessEnd);
   return (hour>=InpSessStart || hour<InpSessEnd);
  }

void RefreshDay()
  {
   datetime d = StringToTime(TimeToStr(TimeCurrent(), TIME_DATE));
   if(d != g_day_stamp)
     {
      g_day_stamp = d;
      g_day_start_eq = AccountEquity();
      g_paused = false;
     }
   if(g_day_start_eq>0 && InpMaxDailyLossPct>0)
     {
      const double dd = 100.0*(g_day_start_eq-AccountEquity())/g_day_start_eq;
      if(dd >= InpMaxDailyLossPct) g_paused = true;
     }
  }

int CountMagicOrders(const string sym)
  {
   int n=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()>OP_SELL) continue;
      if(StringLen(sym)>0 && OrderSymbol()!=sym) continue;
      n++;
     }
   return n;
  }

double FloatingProfitMagic()
  {
   double pnl=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()>OP_SELL) continue;
      pnl += OrderProfit()+OrderSwap()+OrderCommission();
     }
   return pnl;
  }

bool CloseLeg(const string sym)
  {
   bool ok=true;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderSymbol()!=sym) continue;
      if(OrderType()>OP_SELL) continue;
      const int typ = OrderType();
      const double lots = OrderLots();
      const int ticket = OrderTicket();
      double price = (typ==OP_BUY) ? MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK);
      if(!OrderClose(ticket, lots, price, InpSlippage, clrNONE))
        {
         Print("平仓失败 ", sym, " #", ticket, " err=", GetLastError());
         ok=false;
        }
     }
   return ok;
  }

void NotifySignal(const int act, const string msg)
  {
   const datetime bar = iTime(g_engine.SpotSymbol(), InpTF, 0);
   if(act==g_last_alert_act && bar==g_last_alert_bar) return;
   g_last_alert_act = act;
   g_last_alert_bar = bar;
   Print(msg);
   if(InpUseAlert) Alert(msg);
   if(InpUsePush) SendNotification(msg);
   if(g_tg.Enabled()) g_tg.NotifyEvent(msg);
  }

bool CloseAllLegs(const string why)
  {
   const double pnl = FloatingProfitMagic();
   bool ok1 = CloseLeg(g_engine.SpotSymbol());
   bool ok2 = CloseLeg(g_engine.FutSymbol());
   g_engine.NotifyClosed();
   g_status = why;
   Print("基差平仓: ", why);
   NotifySignal(3, StringFormat("【平仓】%s 盈=%.2f", why, pnl));
   return ok1 && ok2;
  }

bool OpenOrder(const string sym, const int cmd, const double lots, const string cmt)
  {
   RefreshRates();
   double price = (cmd==OP_BUY) ? MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
   const int ticket = OrderSend(sym, cmd, lots, price, InpSlippage, 0, 0, cmt, InpMagic, 0, clrNONE);
   if(ticket<0)
     {
      Print("开仓失败 ", sym, " cmd=", cmd, " lot=", lots, " err=", GetLastError());
      return false;
     }
   return true;
  }

bool OpenSpread(const ENUM_BASIS_SIDE side, const string why)
  {
   if(IsManualMode())
     {
      g_status = "信号:"+why;
      g_engine.SetOpenSide(side);
      const int act = (side==BASIS_SHORT_SPREAD ? 1 : 2);
      const string tag = (side==BASIS_SHORT_SPREAD)
         ? "【开仓提醒】空基差(空期+多现) "
         : "【开仓提醒】多基差(多期+空现) ";
      NotifySignal(act, tag+why);
      return true;
     }

   if(CountMagicOrders("")>0)
     {
      g_status = "已有持仓，跳过开仓";
      return false;
     }

   double lot_s, lot_f;
   g_engine.LotsForSide(side, lot_s, lot_f);
   if(lot_s<=0 || lot_f<=0)
     {
      g_status = "手数无效";
      return false;
     }

   const string spot = g_engine.SpotSymbol();
   const string fut  = g_engine.FutSymbol();
   bool ok_f=false, ok_s=false;
   const string cmt = "BasisZ";

   if(side==BASIS_SHORT_SPREAD)
     {
      ok_f = OpenOrder(fut, OP_SELL, lot_f, cmt);
      if(ok_f) ok_s = OpenOrder(spot, OP_BUY, lot_s, cmt);
     }
   else if(side==BASIS_LONG_SPREAD)
     {
      ok_f = OpenOrder(fut, OP_BUY, lot_f, cmt);
      if(ok_f) ok_s = OpenOrder(spot, OP_SELL, lot_s, cmt);
     }

   if(!ok_f || !ok_s)
     {
      Print("开仓失败 — 回滚");
      CloseLeg(spot);
      CloseLeg(fut);
      g_status = "开仓失败已回滚";
      return false;
     }

   g_engine.SetOpenSide(side);
   g_status = why;
   const string tag = (side==BASIS_SHORT_SPREAD)
      ? "【开仓】空基差(空期+多现) " : "【开仓】多基差(多期+空现) ";
   NotifySignal(side==BASIS_SHORT_SPREAD?1:2, tag+why);
   return true;
  }

void SyncOpenSideFromOrders()
  {
   if(IsManualMode() && CountMagicOrders("")==0)
      return;

   const string spot = g_engine.SpotSymbol();
   const string fut  = g_engine.FutSymbol();
   int spot_buy=0, spot_sell=0, fut_buy=0, fut_sell=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()>OP_SELL) continue;
      if(OrderSymbol()==spot)
        {
         if(OrderType()==OP_BUY) spot_buy++; else spot_sell++;
        }
      else if(OrderSymbol()==fut)
        {
         if(OrderType()==OP_BUY) fut_buy++; else fut_sell++;
        }
     }
   if(spot_buy>0 && fut_sell>0) g_engine.SetOpenSide(BASIS_SHORT_SPREAD);
   else if(spot_sell>0 && fut_buy>0) g_engine.SetOpenSide(BASIS_LONG_SPREAD);
   else if(CountMagicOrders("")==0) g_engine.NotifyClosed();
  }

void PanelSet(const string name, const int y, const string text, const color clr)
  {
   const string n = PANEL_PREFIX+name;
   if(ObjectFind(n)<0)
     {
      ObjectCreate(n, OBJ_LABEL, 0, 0, 0);
      ObjectSet(n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(n, OBJPROP_XDISTANCE, 8);
      ObjectSetText(n, text, 9, "Consolas", clr);
     }
   ObjectSet(n, OBJPROP_YDISTANCE, y);
   ObjectSetText(n, text, 9, "Consolas", clr);
  }

void DestroyPanel()
  {
   for(int i=ObjectsTotal()-1; i>=0; i--)
     {
      const string name = ObjectName(i);
      if(StringFind(name, PANEL_PREFIX)==0)
         ObjectDelete(name);
     }
  }

void RenderPanel()
  {
   SBasisSnapshot s = g_engine.Snapshot();
   string side = "FLAT";
   if(g_engine.OpenSide()==BASIS_SHORT_SPREAD) side="空基差(空期+多现)";
   else if(g_engine.OpenSide()==BASIS_LONG_SPREAD) side="多基差(多期+空现)";
   const double pnl = FloatingProfitMagic();
   const string mode = IsManualMode() ? "手动观察" : "自动交易";

   Comment("");
   if(!InpShowPanel)
     {
      Comment(
         "GoldFX MT4 基差套利 v1.2 [", mode, "]\n",
         "现货 ", g_engine.SpotSymbol(), " = ", DoubleToStr(s.spot_mid, 2),
         " | 期货 ", g_engine.FutSymbol(), " = ", DoubleToStr(s.fut_mid, 2), "\n",
         "基差 ", DoubleToStr(s.spread, 4),
         " Z=", DoubleToStr(s.zscore, 2),
         " Corr=", DoubleToStr(s.corr, 2), "\n",
         "持仓: ", side, " 浮盈=", DoubleToStr(pnl, 2), "\n",
         "右上角按钮切换 手动/自动\n",
         g_status
      );
      return;
     }

   color zcol = Silver;
   if(s.zscore>=InpEntryZ) zcol = OrangeRed;
   else if(s.zscore<=-InpEntryZ) zcol = Lime;
   else if(MathAbs(s.zscore)<=InpExitZ) zcol = Gold;

   PanelSet("t0", 18, "GoldFX MT4 基差 v1.2  ["+mode+"]", Aqua);
   PanelSet("t1", 34, StringFormat("现货 %s = %.2f   期货 %s = %.2f",
            g_engine.SpotSymbol(), s.spot_mid, g_engine.FutSymbol(), s.fut_mid), White);
   PanelSet("t2", 50, StringFormat("基差 %.4f  均值 %.4f  σ %.4f",
            s.spread, s.mean, s.stdev), DodgerBlue);
   PanelSet("t3", 66, StringFormat("Z=%.2f  Corr=%.2f  Hedge=%.3f  浮盈=%.2f",
            s.zscore, s.corr, s.hedge_ratio, pnl), zcol);
   PanelSet("t4", 82, StringFormat("持仓: %s%s", side, g_paused?" | 日亏损暂停":""), Silver);
   PanelSet("t5", 98, g_status, Khaki);
  }

//------------------------------------------------------------------
int OnInit()
  {
   string spot = InpSpotSymbol;
   StringTrimLeft(spot); StringTrimRight(spot);
   if(StringLen(spot)==0) spot = Symbol();

   string fut = InpFutSymbol;
   StringTrimLeft(fut); StringTrimRight(fut);
   if(StringLen(fut)==0)
     {
      Print("请填写 InpFutSymbol（期货/远期黄金品种）");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(spot==fut)
     {
      Print("现货与期货品种不能相同");
      return INIT_PARAMETERS_INCORRECT;
     }

   SBasisParams p;
   p.spot_symbol = spot;
   p.fut_symbol  = fut;
   p.tf = InpTF;
   p.spread_mode = InpSpreadMode;
   p.lookback = InpLookback;
   p.entry_z = InpEntryZ;
   p.exit_z = InpExitZ;
   p.stop_z = InpStopZ;
   p.min_corr = InpMinCorr;
   p.min_bars = InpMinBars;
   p.max_hold_bars = InpMaxHoldBars;
   p.lot_spot = InpLotSpot;
   p.auto_hedge = InpAutoHedge;
   p.max_spread_spot = InpMaxSpreadSpot;
   p.max_spread_fut = InpMaxSpreadFut;
   p.trade_both_legs = !IsManualMode();
   p.magic = InpMagic;
   p.slippage = InpSlippage;
   p.cooldown_bars = InpCooldownBars;
   p.min_profit_money = InpMinProfitMoney;

   if(!g_engine.Init(p))
      return INIT_FAILED;

   g_manual = InpStartManual;
   g_tg.ConfigureDirect(InpTelegramEnable, InpTelegramToken, InpTelegramChatId);
   RefreshDay();
   SyncOpenSideFromOrders();
   g_status = g_manual ? "手动观察就绪 — 只提醒，确认后点右上角切自动"
                       : "自动交易就绪 — 等待Z分开仓";
   g_last_alert_act = -1;
   g_last_alert_bar = 0;
   UpdateModeButton();
   PrintFormat("BasisArb MT4 spot=%s fut=%s TF=%d entryZ=%.1f manual=%d",
               spot, fut, InpTF, InpEntryZ, (int)g_manual);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   DestroyPanel();
   ObjectDelete(BTN_MODE);
  }

void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id==CHARTEVENT_OBJECT_CLICK && sparam==BTN_MODE)
      ToggleManualAuto();
  }

void OnTick()
  {
   RefreshDay();
   const bool newbar = g_engine.Update(true);
   SyncOpenSideFromOrders();

   const double pnl_real = FloatingProfitMagic();
   double pnl = pnl_real;
   if(IsManualMode() && CountMagicOrders("")==0 && g_engine.OpenSide()!=BASIS_FLAT)
      pnl = MathMax(pnl_real, InpMinProfitMoney);

   if(!InpAllowTrade || g_paused)
     {
      g_status = g_paused ? "日亏损达限，暂停" : "交易关闭";
      RenderPanel();
      return;
     }

   string why;
   const int act = g_engine.Decide(why, pnl);

   if(act==3 || act==4)
     {
      if(IsManualMode())
        {
         g_status = why;
         const string tag = (act==4) ? "【止损/超时提醒】" : "【平仓提醒】";
         NotifySignal(act, tag+why+StringFormat(" 浮盈=%.2f", pnl));
         if(CountMagicOrders("")>0)
            CloseAllLegs(why);
         else
            g_engine.NotifyClosed();
         RenderPanel();
         return;
        }
      CloseAllLegs(why);
      RenderPanel();
      return;
     }

   if(!InSession())
     {
      if(StringLen(g_status)==0 || StringFind(why,"观望")>=0 || StringFind(why,"持仓")>=0)
         g_status = "非交易时段 | "+why;
      else
         g_status = why;
      RenderPanel();
      return;
     }

   if(newbar && act==1)
      OpenSpread(BASIS_SHORT_SPREAD, why);
   else if(newbar && act==2)
      OpenSpread(BASIS_LONG_SPREAD, why);
   else
      g_status = why;

   if(IsManualMode() && newbar && g_engine.OpenSide()!=BASIS_FLAT &&
      StringFind(why, "回归待利")==0)
      NotifySignal(10, "【待平仓】"+why);

   RenderPanel();
  }
//+------------------------------------------------------------------+
