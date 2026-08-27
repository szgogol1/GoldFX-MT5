//+------------------------------------------------------------------+
//| GoldFX_BasisCompare.mq4 — 期现双色K线对比 + 价差柱状图（MT4）       |
//| 主图：现货/期货并排K线（不同颜色）；副图：价差柱状图+均值带           |
//| 默认：现货 XAUUSD.s  期货 GC                                        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property link      "https://github.com/szgogol1/GoldFX-MT5"
#property version   "1.20"
#property strict
#property indicator_separate_window
#property indicator_buffers 7
#property indicator_color1 C'40,160,120'   // 价差柱 高于均值
#property indicator_color2 C'200,80,70'    // 价差柱 低于均值
#property indicator_color3 Silver          // 均值
#property indicator_color4 Tomato          // 上带
#property indicator_color5 DodgerBlue      // 下带
#property indicator_color6 OrangeRed       // 空基差箭头
#property indicator_color7 Lime            // 多基差箭头
#property indicator_width1 3
#property indicator_width2 3
#property indicator_width3 1
#property indicator_width4 1
#property indicator_width5 1
#property indicator_width6 2
#property indicator_width7 2
#property indicator_level1 0
#property indicator_levelcolor DimGray
#property indicator_levelstyle STYLE_DOT

input string InpSpotSymbol     = "XAUUSD.s";  // 现货（建议挂此品种图表）
input string InpFutSymbol      = "GC";        // 期货
input int    InpLookback       = 60;          // 滚动窗口
input double InpEntryZ         = 2.0;         // 入场|Z|
input double InpExitZ          = 0.40;        // 出场|Z|
input int    InpSpreadMode     = 0;           // 0=F-S 1=比率 2=对数
input int    InpMinBars        = 120;
input int    InpMaxDrawBars    = 400;
input bool   InpDrawTwinK      = true;        // 主图并排双色K线
input color  InpSpotBull       = C'210,160,50';  // 现货阳线
input color  InpSpotBear       = C'140,90,40';   // 现货阴线
input color  InpFutBull        = C'40,140,160';  // 期货阳线
input color  InpFutBear        = C'50,80,140';   // 期货阴线
input int    InpCandleWidth    = 70;          // K线宽度%

#define OBJ_PREFIX "GFXBC4_"

double BufHistUp[];    // 价差柱（≥均值）
double BufHistDn[];    // 价差柱（<均值）
double BufMean[];
double BufUpper[];
double BufLower[];
double BufArrowShort[];
double BufArrowLong[];
double BufZ[];
double BufBasis[];

string g_spot = "";
string g_fut  = "";
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

string SpotSym()
  {
   if(StringLen(g_spot)>0) return g_spot;
   return Symbol();
  }

void DeleteChartObjects()
  {
   for(int i=ObjectsTotal()-1; i>=0; i--)
     {
      const string name = ObjectName(i);
      if(StringFind(name, OBJ_PREFIX)==0)
         ObjectDelete(name);
     }
  }

void DrawCandleHalf(const string tag, const int idx, const datetime t,
                    const double o, const double h, const double l, const double c,
                    const datetime t1, const datetime t2, const color col)
  {
   const string body = StringFormat("%s%s_b%d", OBJ_PREFIX, tag, idx);
   const string wick = StringFormat("%s%s_w%d", OBJ_PREFIX, tag, idx);
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

   const datetime tm = t1 + (t2-t1)/2;
   if(ObjectFind(wick)<0)
      ObjectCreate(wick, OBJ_TREND, 0, tm, h, tm, l);
   else
     {
      ObjectMove(wick, 0, tm, h);
      ObjectMove(wick, 1, tm, l);
     }
   ObjectSet(wick, OBJPROP_COLOR, col);
   ObjectSet(wick, OBJPROP_RAY, false);
   ObjectSet(wick, OBJPROP_WIDTH, 1);
   ObjectSet(wick, OBJPROP_BACK, true);
   ObjectSet(wick, OBJPROP_SELECTABLE, false);
  }

void DrawTwinCandles(const int idx, const datetime t,
                     const double so, const double sh, const double sl, const double sc,
                     const double fo, const double fh, const double fl, const double fc,
                     const int period_sec)
  {
   int half = period_sec * MathMax(40, MathMin(90, InpCandleWidth)) / 200;
   if(half<2) half=2;
   const int gap = MathMax(1, half/8);
   // 左：现货  右：期货
   const datetime s1 = t - half;
   const datetime s2 = t - gap;
   const datetime f1 = t + gap;
   const datetime f2 = t + half;
   const color scol = (sc>=so) ? InpSpotBull : InpSpotBear;
   const color fcol = (fc>=fo) ? InpFutBull : InpFutBear;
   DrawCandleHalf("S", idx, t, so, sh, sl, sc, s1, s2, scol);
   DrawCandleHalf("F", idx, t, fo, fh, fl, fc, f1, f2, fcol);
  }

void UpdatePanel(const double basis, const double mean, const double stdev,
                 const double z, const double spot, const double fut)
  {
   const string n = OBJ_PREFIX "panel";
   string txt = StringFormat(
      "GoldFX 期现对比\n金=现货 %s  蓝绿=期货 %s\n现货 %.2f  期货 %.2f\n价差(柱) %.4f  均值 %.4f  σ %.4f\nZ=%.2f  入场±%.1f  出场±%.1f",
      SpotSym(), g_fut, spot, fut, basis, mean, stdev, z, InpEntryZ, InpExitZ);
   if(ObjectFind(n)<0)
     {
      ObjectCreate(n, OBJ_LABEL, 0, 0, 0);
      ObjectSet(n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSet(n, OBJPROP_XDISTANCE, 8);
      ObjectSet(n, OBJPROP_YDISTANCE, 18);
      ObjectSet(n, OBJPROP_SELECTABLE, false);
     }
   ObjectSetText(n, txt, 9, "Consolas", WhiteSmoke);

   // 图例色块说明
   const string ls = OBJ_PREFIX "legS";
   const string lf = OBJ_PREFIX "legF";
   if(ObjectFind(ls)<0)
     {
      ObjectCreate(ls, OBJ_LABEL, 0, 0, 0);
      ObjectSet(ls, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSet(ls, OBJPROP_XDISTANCE, 120);
      ObjectSet(ls, OBJPROP_YDISTANCE, 18);
      ObjectSet(ls, OBJPROP_SELECTABLE, false);
     }
   ObjectSetText(ls, "■ 现货 "+SpotSym(), 9, "Arial", InpSpotBull);
   if(ObjectFind(lf)<0)
     {
      ObjectCreate(lf, OBJ_LABEL, 0, 0, 0);
      ObjectSet(lf, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
      ObjectSet(lf, OBJPROP_XDISTANCE, 120);
      ObjectSet(lf, OBJPROP_YDISTANCE, 34);
      ObjectSet(lf, OBJPROP_SELECTABLE, false);
     }
   ObjectSetText(lf, "■ 期货 "+g_fut, 9, "Arial", InpFutBull);
  }

bool ReadOHLC(const string sym, const datetime t, const bool use_tick,
              double &o, double &h, double &l, double &c)
  {
   const int sh = iBarShift(sym, Period(), t);
   if(sh<0) return false;
   o = iOpen(sym, Period(), sh);
   h = iHigh(sym, Period(), sh);
   l = iLow(sym, Period(), sh);
   c = iClose(sym, Period(), sh);
   if(use_tick)
     {
      RefreshRates();
      const double bid = MarketInfo(sym, MODE_BID);
      const double ask = MarketInfo(sym, MODE_ASK);
      if(bid>0 && ask>0)
        {
         c = 0.5*(bid+ask);
         if(c>h) h=c;
         if(c<l) l=c;
        }
     }
   return (c>0);
  }

//------------------------------------------------------------------
int OnInit()
  {
   g_spot = InpSpotSymbol;
   g_fut  = InpFutSymbol;
   StringTrimLeft(g_spot); StringTrimRight(g_spot);
   StringTrimLeft(g_fut);  StringTrimRight(g_fut);
   if(StringLen(g_fut)==0)
     {
      Print("请填写 InpFutSymbol（如 GC）");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(StringLen(g_spot)==0) g_spot = Symbol();

   if(!SymbolSelect(g_spot, true))
     {
      Print("无法选择现货 ", g_spot);
      return INIT_FAILED;
     }
   if(!SymbolSelect(g_fut, true))
     {
      Print("无法选择期货 ", g_fut);
      return INIT_FAILED;
     }
   if(g_spot==g_fut)
     {
      Print("现货与期货不能相同");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_lookback = MathMax(20, InpLookback);

   // 副图：价差柱状图（相对均值染色）+ 均值/上下带 + 箭头
   SetIndexBuffer(0, BufHistUp);     SetIndexStyle(0, DRAW_HISTOGRAM);
   SetIndexBuffer(1, BufHistDn);     SetIndexStyle(1, DRAW_HISTOGRAM);
   SetIndexBuffer(2, BufMean);       SetIndexStyle(2, DRAW_LINE, STYLE_DOT);
   SetIndexBuffer(3, BufUpper);      SetIndexStyle(3, DRAW_LINE, STYLE_DASH);
   SetIndexBuffer(4, BufLower);      SetIndexStyle(4, DRAW_LINE, STYLE_DASH);
   SetIndexBuffer(5, BufArrowShort); SetIndexStyle(5, DRAW_ARROW); SetIndexArrow(5, 234);
   SetIndexBuffer(6, BufArrowLong);  SetIndexStyle(6, DRAW_ARROW); SetIndexArrow(6, 233);

   SetIndexLabel(0, "价差↑");
   SetIndexLabel(1, "价差↓");
   SetIndexLabel(2, "均值");
   SetIndexLabel(3, "上带");
   SetIndexLabel(4, "下带");
   SetIndexLabel(5, "空基差");
   SetIndexLabel(6, "多基差");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(1, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);
   SetIndexEmptyValue(6, EMPTY_VALUE);

   ArrayResize(BufZ, 0);
   ArrayResize(BufBasis, 0);

   IndicatorShortName(StringFormat("价差柱 %s-%s", g_fut, SpotSym()));
   IndicatorDigits(4);
   // 主图改折线，避免与并排双色K重叠
   ChartSetInteger(0, CHART_MODE, CHART_LINE);
   ChartSetInteger(0, CHART_COLOR_CHART_LINE, C'60,60,60');
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteChartObjects();
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

   if(ArraySize(BufZ) < rates_total)
     {
      ArrayResize(BufZ, rates_total);
      ArrayResize(BufBasis, rates_total);
     }

   const int limit = MathMin(rates_total - g_lookback - 1, InpMaxDrawBars);
   int start_bar = rates_total - 1 - limit;
   if(start_bar < g_lookback) start_bar = g_lookback;
   if(prev_calculated > g_lookback + 2)
      start_bar = MathMax(g_lookback, rates_total - 4);

   const int period_sec = PeriodSec();
   const string spot = SpotSym();
   const int bars_s = iBars(spot, Period());
   const int bars_f = iBars(g_fut, Period());

   for(int i=start_bar; i<rates_total; i++)
     {
      const int sh = rates_total - 1 - i;
      BufHistUp[i] = EMPTY_VALUE;
      BufHistDn[i] = EMPTY_VALUE;
      BufArrowShort[i] = EMPTY_VALUE;
      BufArrowLong[i]  = EMPTY_VALUE;

      double sum=0, sum2=0;
      int cnt=0;
      bool ok=true;
      for(int k=1; k<=g_lookback; k++)
        {
         const int bi = i - k;
         if(bi < 0){ ok=false; break; }
         const int fs = iBarShift(spot, Period(), time[bi]);
         const int ff = iBarShift(g_fut, Period(), time[bi]);
         if(fs<0 || fs>=bars_s || ff<0 || ff>=bars_f){ ok=false; break; }
         const double sp = RawSpread(iClose(g_fut, Period(), ff), iClose(spot, Period(), fs));
         sum += sp; sum2 += sp*sp; cnt++;
        }
      if(!ok || cnt<g_lookback)
        {
         BufMean[i]=EMPTY_VALUE; BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE;
         BufZ[i]=EMPTY_VALUE; BufBasis[i]=EMPTY_VALUE;
         continue;
        }

      const double mean = sum/cnt;
      const double var  = MathMax(0.0, sum2/cnt - mean*mean);
      const double stdev = MathSqrt(var);

      const bool is_last = (i==rates_total-1);
      double so,sh_,sl,sc, fo,fh,fl,fc;
      if(!ReadOHLC(spot, time[i], is_last, so, sh_, sl, sc))
        {
         BufMean[i]=EMPTY_VALUE;
         continue;
        }
      if(!ReadOHLC(g_fut, time[i], is_last, fo, fh, fl, fc))
        {
         BufMean[i]=EMPTY_VALUE;
         continue;
        }

      const double basis = RawSpread(fc, sc);
      const double z = (stdev>1e-12) ? (basis-mean)/stdev : 0.0;

      BufBasis[i]=basis;
      BufMean[i]=mean;
      BufUpper[i]=mean+InpEntryZ*stdev;
      BufLower[i]=mean-InpEntryZ*stdev;
      BufZ[i]=z;

      // 柱状图：相对均值染色（高于均值绿柱，低于红柱）
      if(basis >= mean)
         BufHistUp[i] = basis;
      else
         BufHistDn[i] = basis;

      if(i>0 && BufZ[i-1]!=EMPTY_VALUE)
        {
         const double zprev = BufZ[i-1];
         if(z>=InpEntryZ && zprev<InpEntryZ) BufArrowShort[i]=basis;
         if(z<=-InpEntryZ && zprev>-InpEntryZ) BufArrowLong[i]=basis;
        }

      if(InpDrawTwinK)
         DrawTwinCandles(sh, time[i], so, sh_, sl, sc, fo, fh, fl, fc, period_sec);
     }

   const int last = rates_total-1;
   if(last>=0 && BufZ[last]!=EMPTY_VALUE)
     {
      RefreshRates();
      double sb=MarketInfo(spot,MODE_BID), sa=MarketInfo(spot,MODE_ASK);
      double fb=MarketInfo(g_fut,MODE_BID), fa=MarketInfo(g_fut,MODE_ASK);
      double sm = (sb>0&&sa>0)?0.5*(sb+sa):iClose(spot,Period(),0);
      double fm = (fb>0&&fa>0)?0.5*(fb+fa):iClose(g_fut,Period(),0);
      const double stdev0 = (InpEntryZ>0)?(BufUpper[last]-BufMean[last])/InpEntryZ:0;
      UpdatePanel(BufBasis[last], BufMean[last], stdev0, BufZ[last], sm, fm);
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
