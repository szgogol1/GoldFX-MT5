//+------------------------------------------------------------------+
//| GoldFX_BasisCompare.mq4 — 黄金期现双K对比 + 基差副图（MT4）         |
//| 挂现货图；主图叠加期货K线；副图基差/均值/入场带与箭头                 |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property link      "https://github.com/szgogol1/GoldFX-MT5"
#property version   "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_color1 DodgerBlue
#property indicator_color2 Silver
#property indicator_color3 Tomato
#property indicator_color4 LimeGreen
#property indicator_color5 OrangeRed
#property indicator_color6 Lime
#property indicator_width1 2
#property indicator_width2 1
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 2
#property indicator_width6 2

input string InpFutSymbol      = "";          // 期货/远期（必填）
input int    InpLookback       = 60;          // 滚动窗口
input double InpEntryZ         = 2.0;         // 入场|Z|
input double InpExitZ          = 0.40;        // 出场|Z|（标记）
input int    InpSpreadMode     = 0;           // 0=F-S 1=比率 2=对数
input int    InpMinBars        = 120;
input int    InpMaxDrawBars    = 400;
input bool   InpDrawFutCandles = true;        // 主图叠加期货K线
input color  InpFutBull        = C'32,120,140';
input color  InpFutBear        = C'160,70,60';
input int    InpCandleWidth    = 60;          // 实体宽度%

#define OBJ_PREFIX "GFXBC4_"

double BufBasis[];
double BufMean[];
double BufUpper[];
double BufLower[];
double BufArrowShort[];
double BufArrowLong[];
double BufZ[];

string g_fut = "";
int    g_lookback = 60;

//------------------------------------------------------------------
double RawSpread(const double fut, const double spot)
  {
   if(spot<=0.0) return 0.0;
   if(InpSpreadMode==1) return fut/spot-1.0;
   if(InpSpreadMode==2) return MathLog(fut/spot);
   return fut-spot;
  }

int PeriodSec()
  {
   switch(_Period)
     {
      case PERIOD_M1:  return 60;
      case PERIOD_M5:  return 300;
      case PERIOD_M15: return 900;
      case PERIOD_M30: return 1800;
      case PERIOD_H1:  return 3600;
      case PERIOD_H4:  return 14400;
      case PERIOD_D1:  return 86400;
      case PERIOD_W1:  return 604800;
      case PERIOD_MN1: return 2592000;
     }
   return 60*_Period;
  }

void DeleteFutObjects()
  {
   for(int i=ObjectsTotal()-1; i>=0; i--)
     {
      const string name = ObjectName(i);
      if(StringFind(name, OBJ_PREFIX)==0)
         ObjectDelete(name);
     }
  }

void DrawFutCandle(const int idx, const datetime t,
                   const double o, const double h, const double l, const double c,
                   const int period_sec)
  {
   const string body = StringFormat("%sb%d", OBJ_PREFIX, idx);
   const string wick = StringFormat("%sw%d", OBJ_PREFIX, idx);
   const color col = (c>=o) ? InpFutBull : InpFutBear;
   int half = period_sec * MathMax(30, MathMin(90, InpCandleWidth)) / 200;
   if(half<1) half=1;
   const datetime t1 = t-half;
   const datetime t2 = t+half;
   double top = MathMax(o, c);
   double bot = MathMin(o, c);
   if(MathAbs(top-bot) < Point) top = bot+Point;

   if(ObjectFind(body)<0)
      ObjectCreate(body, OBJ_RECTANGLE, 0, t1, top, t2, bot);
   else
     {
      ObjectMove(body, 0, t1, top);
      ObjectMove(body, 1, t2, bot);
     }
   ObjectSet(body, OBJPROP_COLOR, col);
   ObjectSet(body, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSet(body, OBJPROP_WIDTH, 1);
   ObjectSet(body, OBJPROP_BACK, true);
   ObjectSet(body, OBJPROP_SELECTABLE, false);

   if(ObjectFind(wick)<0)
      ObjectCreate(wick, OBJ_TREND, 0, t, h, t, l);
   else
     {
      ObjectMove(wick, 0, t, h);
      ObjectMove(wick, 1, t, l);
     }
   ObjectSet(wick, OBJPROP_COLOR, col);
   ObjectSet(wick, OBJPROP_RAY, false);
   ObjectSet(wick, OBJPROP_BACK, true);
   ObjectSet(wick, OBJPROP_SELECTABLE, false);
  }

void UpdatePanel(const double basis, const double mean, const double stdev,
                 const double z, const double spot, const double fut)
  {
   const string n = OBJ_PREFIX "panel";
   string txt = StringFormat("GoldFX 期现对比(MT4)\n现货 %s %.2f\n期货 %s %.2f\n基差 %.4f 均值 %.4f σ %.4f\nZ=%.2f Entry±%.1f Exit±%.1f",
                             Symbol(), spot, g_fut, fut, basis, mean, stdev, z, InpEntryZ, InpExitZ);
   if(ObjectFind(n)<0)
     {
      ObjectCreate(n, OBJ_LABEL, 0, 0, 0);
      ObjectSet(n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(n, OBJPROP_XDISTANCE, 8);
      ObjectSet(n, OBJPROP_YDISTANCE, 20);
      ObjectSet(n, OBJPROP_SELECTABLE, false);
     }
   ObjectSetText(n, txt, 9, "Consolas", WhiteSmoke);
  }

//------------------------------------------------------------------
int OnInit()
  {
   g_fut = InpFutSymbol;
   StringTrimLeft(g_fut); StringTrimRight(g_fut);
   if(StringLen(g_fut)==0)
     {
      Print("GoldFX_BasisCompare: 请填写 InpFutSymbol");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_fut==Symbol())
     {
      Print("GoldFX_BasisCompare: 期货与现货不能相同");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!SymbolSelect(g_fut, true))
     {
      Print("GoldFX_BasisCompare: 无法选择期货 ", g_fut);
      return INIT_FAILED;
     }

   g_lookback = MathMax(20, InpLookback);

   SetIndexBuffer(0, BufBasis);   SetIndexStyle(0, DRAW_LINE);
   SetIndexBuffer(1, BufMean);    SetIndexStyle(1, DRAW_LINE, STYLE_DOT);
   SetIndexBuffer(2, BufUpper);   SetIndexStyle(2, DRAW_LINE, STYLE_DASH);
   SetIndexBuffer(3, BufLower);   SetIndexStyle(3, DRAW_LINE, STYLE_DASH);
   SetIndexBuffer(4, BufArrowShort); SetIndexStyle(4, DRAW_ARROW);
   SetIndexArrow(4, 234);
   SetIndexBuffer(5, BufArrowLong);  SetIndexStyle(5, DRAW_ARROW);
   SetIndexArrow(5, 233);
   SetIndexBuffer(6, BufZ);       SetIndexStyle(6, DRAW_NONE);

   SetIndexLabel(0, "Basis");
   SetIndexLabel(1, "Mean");
   SetIndexLabel(2, "Upper");
   SetIndexLabel(3, "Lower");
   SetIndexLabel(4, "ShortBasis");
   SetIndexLabel(5, "LongBasis");
   SetIndexLabel(6, "Z");

   SetIndexEmptyValue(4, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);
   SetIndexEmptyValue(6, EMPTY_VALUE);

   IndicatorShortName(StringFormat("GoldFX Basis %s vs %s", Symbol(), g_fut));
   IndicatorDigits(4);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteFutObjects();
   ObjectDelete(OBJ_PREFIX "panel");
  }

//------------------------------------------------------------------
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpMinBars || rates_total < g_lookback+5)
      return 0;

   // MT4 默认缓冲：索引 0 = 最旧；与 time[]/close[] 一致，不用 AsSeries
   const int limit = MathMin(rates_total - g_lookback - 1, InpMaxDrawBars);
   // 从左向右填，bar 下标 rates_total-1 为当前
   int start_bar = rates_total - 1 - limit;
   if(start_bar < g_lookback) start_bar = g_lookback;
   if(prev_calculated > g_lookback + 2)
      start_bar = MathMax(g_lookback, rates_total - 4);

   const int period_sec = PeriodSec();
   const int bars_f = iBars(g_fut, Period());

   for(int i=start_bar; i<rates_total; i++)
     {
      const int sh = rates_total - 1 - i; // 相对当前的 shift（0=当前）
      BufArrowShort[i] = EMPTY_VALUE;
      BufArrowLong[i]  = EMPTY_VALUE;

      double sum=0, sum2=0;
      int cnt=0;
      bool ok=true;
      for(int k=1; k<=g_lookback; k++)
        {
         const int bi = i - k; // 更旧的 bar 索引
         if(bi < 0){ ok=false; break; }
         const datetime ti = time[bi];
         const int fi = iBarShift(g_fut, Period(), ti);
         if(fi<0 || fi>=bars_f){ ok=false; break; }
         const double sp = RawSpread(iClose(g_fut, Period(), fi), close[bi]);
         sum += sp; sum2 += sp*sp; cnt++;
        }
      if(!ok || cnt<g_lookback)
        {
         BufBasis[i]=EMPTY_VALUE; BufMean[i]=EMPTY_VALUE;
         BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE;
         BufZ[i]=EMPTY_VALUE;
         continue;
        }

      const double mean = sum/cnt;
      const double var  = MathMax(0.0, sum2/cnt - mean*mean);
      const double stdev = MathSqrt(var);

      int fi_now = iBarShift(g_fut, Period(), time[i]);
      if(fi_now<0 || fi_now>=bars_f)
        {
         BufBasis[i]=EMPTY_VALUE;
         continue;
        }

      double fut_c = iClose(g_fut, Period(), fi_now);
      double spot_c = close[i];
      if(i==rates_total-1)
        {
         RefreshRates();
         const double sb = MarketInfo(Symbol(), MODE_BID);
         const double sa = MarketInfo(Symbol(), MODE_ASK);
         const double fb = MarketInfo(g_fut, MODE_BID);
         const double fa = MarketInfo(g_fut, MODE_ASK);
         if(sb>0 && sa>0) spot_c = 0.5*(sb+sa);
         if(fb>0 && fa>0) fut_c  = 0.5*(fb+fa);
        }

      const double basis = RawSpread(fut_c, spot_c);
      const double z = (stdev>1e-12) ? (basis-mean)/stdev : 0.0;

      BufBasis[i]=basis; BufMean[i]=mean;
      BufUpper[i]=mean+InpEntryZ*stdev;
      BufLower[i]=mean-InpEntryZ*stdev;
      BufZ[i]=z;

      if(i>0 && BufZ[i-1]!=EMPTY_VALUE)
        {
         const double zprev = BufZ[i-1];
         if(z>=InpEntryZ && zprev<InpEntryZ) BufArrowShort[i]=basis;
         if(z<=-InpEntryZ && zprev>-InpEntryZ) BufArrowLong[i]=basis;
        }

      if(InpDrawFutCandles && fi_now>=0)
        {
         double fo = iOpen(g_fut, Period(), fi_now);
         double fh = iHigh(g_fut, Period(), fi_now);
         double fl = iLow(g_fut, Period(), fi_now);
         double fc = iClose(g_fut, Period(), fi_now);
         if(i==rates_total-1)
           {
            RefreshRates();
            const double fb = MarketInfo(g_fut, MODE_BID);
            const double fa = MarketInfo(g_fut, MODE_ASK);
            if(fb>0 && fa>0)
              {
               fc = 0.5*(fb+fa);
               if(fc>fh) fh=fc;
               if(fc<fl) fl=fc;
              }
           }
         DrawFutCandle(sh, time[i], fo, fh, fl, fc, period_sec);
        }
     }

   const int last = rates_total-1;
   if(last>=0 && BufZ[last]!=EMPTY_VALUE)
     {
      RefreshRates();
      double spot_mid = close[last], fut_mid=0;
      const double sb=MarketInfo(Symbol(),MODE_BID), sa=MarketInfo(Symbol(),MODE_ASK);
      const double fb=MarketInfo(g_fut,MODE_BID), fa=MarketInfo(g_fut,MODE_ASK);
      if(sb>0&&sa>0) spot_mid=0.5*(sb+sa);
      if(fb>0&&fa>0) fut_mid=0.5*(fb+fa);
      else fut_mid=iClose(g_fut, Period(), 0);
      const double stdev0 = (InpEntryZ>0) ? (BufUpper[last]-BufMean[last])/InpEntryZ : 0;
      UpdatePanel(BufBasis[last], BufMean[last], stdev0, BufZ[last], spot_mid, fut_mid);
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
