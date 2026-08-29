//+------------------------------------------------------------------+
//|                                   GoldFX_BasisPro.mq4            |
//|   MT4 黄金期现基差套利 EA — 监控面板 + 手/自动 + 下单/平仓/止损    |
//|   配合 GoldFX_BasisPro_Overlay / Spread 指标使用                  |
//+------------------------------------------------------------------+
#property copyright   "GoldFX Intraday Framework"
#property link        "https://github.com/szgogol1/GoldFX-MT5"
#property version     "1.10"
#property strict

//--- 品种
input string InpSpotSymbol     = "";             // 现货(空=图表品种)
input string InpFutSymbol      = "GC";           // 期货品种
input int    InpMagic          = 20260829;       // Magic Number
input int    InpSlippage       = 30;             // 滑点(点)

//--- 基差 Z 分
input int    InpLookback       = 60;             // 滚动窗口
input int    InpMinBars        = 30;             // 最少 K 线
input double InpEntryZ         = 2.0;            // 入场 |Z|
input double InpExitZ          = 0.40;           // 出场 |Z|
input double InpStopZ          = 3.5;            // Z 止损 |Z|
input double InpMinCorr        = 0.85;           // 最低相关
input int    InpMaxHoldBars    = 48;             // 超时平仓(K线)
input int    InpCooldownBars   = 4;              // 平仓后冷却

//--- 仓位
input double InpLotSpot        = 0.10;           // 现货基准手数
input bool   InpAutoHedge      = true;           // 名义价值对冲期货手数

//--- 风控
input double InpMaxDailyLossPct= 2.0;            // 日最大亏损%
input bool   InpUseSession     = true;           // 启用交易时段
input int    InpSessStart      = 1;
input int    InpSessEnd        = 22;
input bool   InpFridayCut      = true;
input int    InpFridayHour     = 18;

//--- 面板
input bool   InpShowPanel      = true;           // 显示面板
input int    InpPanelX         = 12;             // 面板 X
input int    InpPanelY         = 28;             // 面板 Y

//--- 前缀
#define PFX "GFBPro_"

//--- 持仓方向
#define SIDE_FLAT  0
#define SIDE_SHORT 1   // 空基差: 空期+多现
#define SIDE_LONG  2   // 多基差: 多期+空现

//--- 运行模式
#define MODE_AUTO   0
#define MODE_MANUAL 1

//--- 快照
struct SBasisSnap
  {
   double spot;
   double fut;
   double basis;
   double mean;
   double stdev;
   double z;
   double corr;
  };

//--- 全局
string   g_spot;
string   g_fut;
string   g_status    = "就绪";
int      g_runMode   = MODE_AUTO;      // 自动/手动
bool     g_autoStop  = true;           // Z 止损+回归出场
int      g_openSide  = SIDE_FLAT;
datetime g_lastBar   = 0;
datetime g_entryBar  = 0;
int      g_cooldown  = 0;
datetime g_dayStamp  = 0;
double   g_dayStartEq= 0;
bool     g_paused    = false;

// 面板按钮标志
bool g_btnShortSpread = false;
bool g_btnLongSpread  = false;
bool g_btnCloseAll    = false;
bool g_btnAutoMode    = false;
bool g_btnManualMode  = false;
bool g_btnToggleStop  = false;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_spot = InpSpotSymbol;
   StringTrimLeft(g_spot);
   StringTrimRight(g_spot);
   if(StringLen(g_spot) == 0)
      g_spot = Symbol();

   g_fut = InpFutSymbol;
   StringTrimLeft(g_fut);
   StringTrimRight(g_fut);

   if(StringLen(g_fut) == 0)
     {
      Alert("GoldFX_BasisPro: 请设置 InpFutSymbol");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(g_spot == g_fut)
     {
      Alert("GoldFX_BasisPro: 现货与期货不能相同");
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(!SymbolSelect(g_spot, true) || !SymbolSelect(g_fut, true))
     {
      Alert("GoldFX_BasisPro: 无法选择品种，请加入报价窗口");
      return(INIT_FAILED);
     }

   SyncSideFromOrders();
   RefreshDay();
   if(InpShowPanel)
      PanelCreate();
   else
      PanelDestroy();

   g_status = "基差 EA 就绪";
   Print("GoldFX_BasisPro spot=", g_spot, " fut=", g_fut,
         " mode=", (g_runMode==MODE_AUTO?"AUTO":"MANUAL"));
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   PanelDestroy();
   Comment("");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   RefreshDay();
   SyncSideFromOrders();

   SBasisSnap snap;
   if(!CalcBasis(0, snap))
     {
      g_status = "数据不足";
      PanelUpdate(snap);
      return;
     }

   datetime barTime = iTime(g_spot, Period(), 0);
   bool isNewBar = (barTime != g_lastBar && barTime > 0);
   if(isNewBar)
     {
      g_lastBar = barTime;
      if(g_cooldown > 0)
         g_cooldown--;
     }

   //--- 面板按钮
   if(g_btnAutoMode)   { g_runMode = MODE_AUTO;   g_btnAutoMode = false; }
   if(g_btnManualMode) { g_runMode = MODE_MANUAL; g_btnManualMode = false; }
   if(g_btnToggleStop){ g_autoStop = !g_autoStop; g_btnToggleStop = false; }

   if(g_btnCloseAll)
     {
      g_btnCloseAll = false;
      CloseAll("面板: 全平");
      PanelUpdate(snap);
      return;
     }

   if(g_btnShortSpread)
     {
      g_btnShortSpread = false;
      OpenSpread(SIDE_SHORT, "面板: 空基差");
      PanelUpdate(snap);
      return;
     }

   if(g_btnLongSpread)
     {
      g_btnLongSpread = false;
      OpenSpread(SIDE_LONG, "面板: 多基差");
      PanelUpdate(snap);
      return;
     }

   if(g_paused)
     {
      g_status = "日亏损达限，暂停";
      PanelUpdate(snap);
      return;
     }

   //--- 自动止损/出场 (自动模式 或 开启自动止损)
   if(g_openSide != SIDE_FLAT && g_autoStop)
     {
      int act = Decide(snap, true);
      if(act == 3 || act == 4)
        {
         CloseAll(g_status);
         PanelUpdate(snap);
         return;
        }
     }

   //--- 自动模式开仓
   if(g_runMode == MODE_AUTO && isNewBar)
     {
      if(g_openSide == SIDE_FLAT)
        {
         int act = Decide(snap, false);
         if(act == 1 && InSession())
            OpenSpread(SIDE_SHORT, g_status);
         else if(act == 2 && InSession())
            OpenSpread(SIDE_LONG, g_status);
         else if(act == 0)
            g_status = BuildWatchMsg(snap);
        }
     }
   else if(g_runMode == MODE_MANUAL)
     {
      g_status = "手动模式 | " + BuildWatchMsg(snap);
     }

   PanelUpdate(snap);
  }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id != CHARTEVENT_OBJECT_CLICK)
      return;
   if(StringFind(sparam, PFX) != 0)
      return;

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   ChartRedraw();

   if(sparam == PFX "btnAuto")    { g_btnAutoMode = true; return; }
   if(sparam == PFX "btnManual")  { g_btnManualMode = true; return; }
   if(sparam == PFX "btnShort")   { g_btnShortSpread = true; return; }
   if(sparam == PFX "btnLong")    { g_btnLongSpread = true; return; }
   if(sparam == PFX "btnClose")   { g_btnCloseAll = true; return; }
   if(sparam == PFX "btnStop")    { g_btnToggleStop = true; return; }
  }

//+------------------------------------------------------------------+
bool InSession()
  {
   datetime t = TimeCurrent();
   int dow = TimeDayOfWeek(t);
   int hr  = TimeHour(t);
   if(InpFridayCut && dow == 5 && hr >= InpFridayHour)
      return(false);
   if(!InpUseSession)
      return(true);
   if(InpSessStart < InpSessEnd)
      return(hr >= InpSessStart && hr < InpSessEnd);
   return(hr >= InpSessStart || hr < InpSessEnd);
  }

//+------------------------------------------------------------------+
void RefreshDay()
  {
   datetime d = StrToTime(TimeToString(TimeCurrent(), TIME_DATE));
   if(d != g_dayStamp)
     {
      g_dayStamp = d;
      g_dayStartEq = AccountEquity();
      g_paused = false;
     }
   if(g_dayStartEq > 0 && InpMaxDailyLossPct > 0)
     {
      double dd = 100.0 * (g_dayStartEq - AccountEquity()) / g_dayStartEq;
      if(dd >= InpMaxDailyLossPct)
         g_paused = true;
     }
  }

//+------------------------------------------------------------------+
double NormLot(const string sym, double lot)
  {
   double mn = MarketInfo(sym, MODE_MINLOT);
   double mx = MarketInfo(sym, MODE_MAXLOT);
   double st = MarketInfo(sym, MODE_LOTSTEP);
   if(st <= 0) st = 0.01;
   lot = MathFloor(lot / st + 1e-8) * st;
   if(mn > 0) lot = MathMax(lot, mn);
   if(mx > 0) lot = MathMin(lot, mx);
   return(NormalizeDouble(lot, 2));
  }

//+------------------------------------------------------------------+
double HedgeLotFut(const double lotSpot)
  {
   if(!InpAutoHedge)
      return(NormLot(g_fut, lotSpot));
   double cs_s = MarketInfo(g_spot, MODE_LOTSIZE);
   double cs_f = MarketInfo(g_fut, MODE_LOTSIZE);
   if(cs_s <= 0) cs_s = 100;
   if(cs_f <= 0) cs_f = 100;
   double ps = MarketInfo(g_spot, MODE_BID);
   double pf = MarketInfo(g_fut, MODE_BID);
   if(ps <= 0 || pf <= 0)
      return(NormLot(g_fut, lotSpot));
   double tv_s = cs_s * ps * lotSpot;
   double tv_f = cs_f * pf;
   if(tv_f <= 0)
      return(NormLot(g_fut, lotSpot));
   return(NormLot(g_fut, tv_s / tv_f));
  }

//+------------------------------------------------------------------+
bool CalcBasis(const int shift, SBasisSnap &s)
  {
   ZeroMemory(s);
   const int lb = MathMax(5, InpLookback);
   double sum = 0, sum2 = 0;
   double sum_s = 0, sum_f = 0, sum_sf = 0, sum_s2 = 0, sum_f2 = 0;
   int cnt = 0;

   for(int j = 0; j < lb; j++)
     {
      int idx = shift + j;
      double cs = iClose(g_spot, Period(), idx);
      double cf = iClose(g_fut, Period(), idx);
      if(cs <= 0 || cf <= 0)
         continue;
      double sp = cf - cs;
      sum  += sp;
      sum2 += sp * sp;
      sum_s += cs; sum_f += cf;
      sum_sf += cs * cf;
      sum_s2 += cs * cs;
      sum_f2 += cf * cf;
      cnt++;
     }

   if(cnt < MathMin(InpMinBars, lb))
      return(false);

   s.mean = sum / cnt;
   double var = MathMax(0.0, sum2 / cnt - s.mean * s.mean);
   s.stdev = MathSqrt(var);

   s.spot = MarketInfo(g_spot, MODE_BID);
   s.fut  = MarketInfo(g_fut, MODE_BID);
   if(s.spot <= 0 || s.fut <= 0)
      return(false);

   s.basis = s.fut - s.spot;
   s.z = (s.stdev > 1e-12) ? (s.basis - s.mean) / s.stdev : 0;

   double ms = sum_s / cnt, mf = sum_f / cnt;
   double cov = sum_sf / cnt - ms * mf;
   double vs = MathMax(1e-12, sum_s2 / cnt - ms * ms);
   double vf = MathMax(1e-12, sum_f2 / cnt - mf * mf);
   s.corr = cov / MathSqrt(vs * vf);
   return(true);
  }

//+------------------------------------------------------------------+
string BuildWatchMsg(const SBasisSnap &s)
  {
   return(StringFormat("Z=%.2f Corr=%.2f | 空≥+%.1f 多≤-%.1f 出≤%.1f 损≥%.1f",
                       s.z, s.corr, InpEntryZ, InpEntryZ, InpExitZ, InpStopZ));
  }

//+------------------------------------------------------------------+
int Decide(const SBasisSnap &s, const bool managing)
  {
   if(s.stdev <= 1e-12)
     {
      g_status = "σ无效";
      return(0);
     }

   if(managing && g_openSide != SIDE_FLAT)
     {
      // 超时
      if(InpMaxHoldBars > 0 && g_entryBar > 0)
        {
         int held = iBarShift(g_spot, Period(), g_entryBar, true);
         if(held >= InpMaxHoldBars)
           {
            g_status = StringFormat("超时平仓 held=%d", held);
            return(4);
           }
        }
      // Z 止损
      if(g_openSide == SIDE_SHORT && s.z >= InpStopZ)
        {
         g_status = StringFormat("Z止损 %.2f≥%.2f", s.z, InpStopZ);
         return(4);
        }
      if(g_openSide == SIDE_LONG && s.z <= -InpStopZ)
        {
         g_status = StringFormat("Z止损 %.2f≤-%.2f", s.z, InpStopZ);
         return(4);
        }
      // 回归出场
      if(MathAbs(s.z) <= InpExitZ)
        {
         g_status = StringFormat("回归出场 |Z|=%.2f", MathAbs(s.z));
         return(3);
        }
      g_status = StringFormat("持仓中 Z=%.2f", s.z);
      return(0);
     }

   // 开仓
   if(g_cooldown > 0)
     {
      g_status = StringFormat("冷却 %d 棒", g_cooldown);
      return(0);
     }
   if(s.corr < InpMinCorr)
     {
      g_status = StringFormat("相关不足 %.2f", s.corr);
      return(0);
     }
   if(s.z >= InpEntryZ)
     {
      g_status = StringFormat("信号: 空基差 Z=%.2f", s.z);
      return(1);
     }
   if(s.z <= -InpEntryZ)
     {
      g_status = StringFormat("信号: 多基差 Z=%.2f", s.z);
      return(2);
     }
   g_status = BuildWatchMsg(s);
   return(0);
  }

//+------------------------------------------------------------------+
int CountOurOrders(const string sym)
  {
   int n = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagic)
         continue;
      if(StringLen(sym) > 0 && OrderSymbol() != sym)
         continue;
      n++;
     }
   return(n);
  }

//+------------------------------------------------------------------+
void SyncSideFromOrders()
  {
   int sb = 0, ss = 0, fb = 0, fs = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagic)
         continue;
      if(OrderSymbol() == g_spot)
        {
         if(OrderType() == OP_BUY) sb++;
         else if(OrderType() == OP_SELL) ss++;
        }
      else if(OrderSymbol() == g_fut)
        {
         if(OrderType() == OP_BUY) fb++;
         else if(OrderType() == OP_SELL) fs++;
        }
     }
   if(sb > 0 && fs > 0)
      g_openSide = SIDE_SHORT;
   else if(ss > 0 && fb > 0)
      g_openSide = SIDE_LONG;
   else if(CountOurOrders("") == 0)
      g_openSide = SIDE_FLAT;
  }

//+------------------------------------------------------------------+
double FloatingPL()
  {
   double pl = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagic)
         continue;
      pl += OrderProfit() + OrderSwap() + OrderCommission();
     }
   return(pl);
  }

//+------------------------------------------------------------------+
bool CloseSymbol(const string sym)
  {
   bool ok = true;
   RefreshRates();
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;
      if(OrderMagicNumber() != InpMagic)
         continue;
      if(OrderSymbol() != sym)
         continue;
      double price = (OrderType() == OP_BUY) ?
                     MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK);
      if(!OrderClose(OrderTicket(), OrderLots(), price, InpSlippage, clrNONE))
        {
         Print("平仓失败 ", sym, " err=", GetLastError());
         ok = false;
        }
     }
   return(ok);
  }

//+------------------------------------------------------------------+
bool CloseAll(const string why)
  {
   bool ok1 = CloseSymbol(g_spot);
   bool ok2 = CloseSymbol(g_fut);
   g_openSide = SIDE_FLAT;
   g_entryBar = 0;
   g_cooldown = InpCooldownBars;
   g_status = why;
   Print("GoldFX_BasisPro 平仓: ", why);
   return(ok1 && ok2);
  }

//+------------------------------------------------------------------+
int SendMkt(const string sym, const int cmd, const double lots, const string cmt)
  {
   RefreshRates();
   double price = (cmd == OP_BUY) ?
                  MarketInfo(sym, MODE_ASK) : MarketInfo(sym, MODE_BID);
   int tk = OrderSend(sym, cmd, lots, price, InpSlippage, 0, 0, cmt, InpMagic, 0, clrNONE);
   if(tk < 0)
      Print("OrderSend失败 ", sym, " cmd=", cmd, " err=", GetLastError());
   return(tk);
  }

//+------------------------------------------------------------------+
bool OpenSpread(const int side, const string why)
  {
   if(CountOurOrders("") > 0)
     {
      g_status = "已有持仓";
      return(false);
     }

   double lot_s = NormLot(g_spot, InpLotSpot);
   double lot_f = HedgeLotFut(lot_s);
   if(lot_s <= 0 || lot_f <= 0)
     {
      g_status = "手数无效";
      return(false);
     }

   int tk_f = -1, tk_s = -1;
   string cmt = "BasisPro";

   if(side == SIDE_SHORT)
     {
      tk_f = SendMkt(g_fut, OP_SELL, lot_f, cmt);
      tk_s = SendMkt(g_spot, OP_BUY, lot_s, cmt);
     }
   else if(side == SIDE_LONG)
     {
      tk_f = SendMkt(g_fut, OP_BUY, lot_f, cmt);
      tk_s = SendMkt(g_spot, OP_SELL, lot_s, cmt);
     }
   else
      return(false);

   if(tk_f < 0 || tk_s < 0)
     {
      Print("开仓失败，回滚");
      CloseSymbol(g_spot);
      CloseSymbol(g_fut);
      g_status = "开仓失败已回滚";
      return(false);
     }

   g_openSide = side;
   g_entryBar = iTime(g_spot, Period(), 0);
   g_status = why;
   PrintFormat("开仓 OK side=%d spot=%.2f fut=%.2f | %s", side, lot_s, lot_f, why);
   return(true);
  }

//+------------------------------------------------------------------+
//| 面板 UI                                                          |
//+------------------------------------------------------------------+
void PanelRect(const string n, int x, int y, int w, int h, color bg)
  {
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, n, OBJPROP_COLOR, C'45,55,70');
   ObjectSetInteger(0, n, OBJPROP_BACK, false);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void PanelLabel(const string n, int x, int y, const string txt, int fs, color c)
  {
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(0, n, OBJPROP_COLOR, c);
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void PanelBtn(const string n, int x, int y, int w, int h,
              const string txt, color bg)
  {
   if(ObjectFind(0, n) < 0)
      ObjectCreate(0, n, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, n, OBJPROP_YSIZE, h);
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
   ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_BORDER_COLOR, C'70,80,95');
   ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
void PanelCreate()
  {
   const int x = InpPanelX, y = InpPanelY, w = 300, h = 248;
   color bg = C'18,24,32';
   color fg = C'220,228,235';
   color accent = C'40,150,120';
   color btn = C'50,65,80';
   color bad = C'160,55,50';

   PanelRect(PFX "bg", x, y, w, h, bg);
   PanelLabel(PFX "title", x+8, y+6, "GoldFX BasisPro 面板", 10, fg);

   int cy = y + 26;
   PanelLabel(PFX "L1", x+8, cy, "行情...", 8, fg); cy += 16;
   PanelLabel(PFX "L2", x+8, cy, "基差...", 8, fg); cy += 16;
   PanelLabel(PFX "L3", x+8, cy, "持仓...", 8, fg); cy += 16;
   PanelLabel(PFX "L4", x+8, cy, "账户...", 8, fg); cy += 20;

   PanelLabel(PFX "modeLbl", x+8, cy, "运行模式", 8, fg); cy += 14;
   PanelBtn(PFX "btnAuto",   x+8,   cy, 88, 22, "自动", accent);
   PanelBtn(PFX "btnManual", x+100, cy, 88, 22, "手动", btn);
   PanelBtn(PFX "btnStop",   x+192, cy, 96, 22, "止损:开", accent);
   cy += 28;

   PanelBtn(PFX "btnShort", x+8,   cy, 92, 26, "空基差", bad);
   PanelBtn(PFX "btnLong",  x+104, cy, 92, 26, "多基差", accent);
   PanelBtn(PFX "btnClose", x+200, cy, 88, 26, "全平", bad);
   cy += 32;

   PanelLabel(PFX "status", x+8, cy, "状态: 就绪", 8, clrGold);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
void PanelDestroy()
  {
   ObjectsDeleteAll(0, PFX);
  }

//+------------------------------------------------------------------+
void PanelUpdate(const SBasisSnap &s)
  {
   if(!InpShowPanel)
      return;

   color accent = C'40,150,120';
   color btn = C'50,65,80';
   color bad = C'160,55,50';

   string sideTxt = "空仓";
   if(g_openSide == SIDE_SHORT) sideTxt = "空基差(空期+多现)";
   else if(g_openSide == SIDE_LONG) sideTxt = "多基差(多期+空现)";

   double pl = FloatingPL();
   string pls = (pl >= 0 ? "+" : "") + DoubleToString(pl, 2);

   ObjectSetString(0, PFX "L1", OBJPROP_TEXT,
      StringFormat("现货 %s %.2f  |  期货 %s %.2f",
                   g_spot, s.spot, g_fut, s.fut));
   ObjectSetString(0, PFX "L2", OBJPROP_TEXT,
      StringFormat("基差 %.2f  μ=%.2f  σ=%.2f  Z=%.2f  ρ=%.2f",
                   s.basis, s.mean, s.stdev, s.z, s.corr));
   ObjectSetString(0, PFX "L3", OBJPROP_TEXT,
      StringFormat("持仓: %s  |  浮盈: %s", sideTxt, pls));
   ObjectSetString(0, PFX "L4", OBJPROP_TEXT,
      StringFormat("净值 %.2f  |  模式 %s  |  %s",
                   AccountEquity(),
                   (g_runMode==MODE_AUTO?"自动":"手动"),
                   (g_paused?"日损暂停":(InSession()?"时段OK":"时段外"))));

   ObjectSetInteger(0, PFX "btnAuto",
                    OBJPROP_BGCOLOR, (g_runMode==MODE_AUTO ? accent : btn));
   ObjectSetInteger(0, PFX "btnManual",
                    OBJPROP_BGCOLOR, (g_runMode==MODE_MANUAL ? accent : btn));
   ObjectSetString(0, PFX "btnStop", OBJPROP_TEXT,
                   g_autoStop ? "止损:开" : "止损:关");
   ObjectSetInteger(0, PFX "btnStop",
                    OBJPROP_BGCOLOR, g_autoStop ? accent : btn);

   string st = g_status;
   if(StringLen(st) > 52)
      st = StringSubstr(st, 0, 52) + "...";
   ObjectSetString(0, PFX "status", OBJPROP_TEXT, "状态: " + st);

   ChartRedraw();
  }
//+------------------------------------------------------------------+
