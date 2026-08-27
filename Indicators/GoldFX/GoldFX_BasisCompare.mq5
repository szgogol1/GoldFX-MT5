//+------------------------------------------------------------------+
//| GoldFX_BasisCompare.mq5 — 期现双色并排K线 + 价差柱状图              |
//| 默认：现货 XAUUSD.s  期货 GC                                        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.20"
#property description "主图并排双色K线；副图价差柱状图+均值带"
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   7

#property indicator_label1  "价差↑"
#property indicator_type1   DRAW_HISTOGRAM
#property indicator_color1  clrMediumSeaGreen
#property indicator_width1  3

#property indicator_label2  "价差↓"
#property indicator_type2   DRAW_HISTOGRAM
#property indicator_color2  clrTomato
#property indicator_width2  3

#property indicator_label3  "均值"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_DOT
#property indicator_width3  1

#property indicator_label4  "上带"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrTomato
#property indicator_style4  STYLE_DASH

#property indicator_label5  "下带"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrDodgerBlue
#property indicator_style5  STYLE_DASH

#property indicator_label6  "空基差"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrOrangeRed
#property indicator_width6  2

#property indicator_label7  "多基差"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrLime
#property indicator_width7  2

input group "=== 品种 / 模型 ==="
input string InpSpotSymbol  = "XAUUSD.s";  // 现货
input string InpFutSymbol   = "GC";        // 期货
input int    InpLookback    = 60;
input double InpEntryZ      = 2.0;
input double InpExitZ       = 0.40;
input int    InpSpreadMode  = 0;           // 0=F-S
input int    InpMinBars     = 120;
input int    InpMaxDrawBars = 400;

input group "=== 主图双色K线 ==="
input bool   InpDrawTwinK   = true;
input color  InpSpotBull    = C'210,160,50';
input color  InpSpotBear    = C'140,90,40';
input color  InpFutBull     = C'40,140,160';
input color  InpFutBear     = C'50,80,140';
input int    InpCandleWidth = 70;

#define OBJ_PREFIX "GFXBC_"

double BufHistUp[], BufHistDn[], BufMean[], BufUpper[], BufLower[];
double BufArrowShort[], BufArrowLong[], BufZ[];
string g_spot="", g_fut="";
int g_lookback=60;

double RawSpread(const double fut, const double spot)
  {
   if(spot<=0) return 0;
   if(InpSpreadMode==1) return fut/spot-1.0;
   if(InpSpreadMode==2) return MathLog(fut/spot);
   return fut-spot;
  }

void DeleteObjs()
  {
   int total=ObjectsTotal(0,0,-1);
   for(int i=total-1;i>=0;--i)
     {
      string n=ObjectName(0,i,0,-1);
      if(StringFind(n,OBJ_PREFIX)==0) ObjectDelete(0,n);
     }
  }

void DrawHalf(const string tag,const int idx,const datetime t1,const datetime t2,
              const double o,const double h,const double l,const double c,const color col)
  {
   string body=StringFormat("%s%s_b%d",OBJ_PREFIX,tag,idx);
   string wick=StringFormat("%s%s_w%d",OBJ_PREFIX,tag,idx);
   double top=MathMax(o,c), bot=MathMin(o,c);
   if(MathAbs(top-bot)<_Point) top=bot+_Point;
   if(ObjectFind(0,body)<0) ObjectCreate(0,body,OBJ_RECTANGLE,0,t1,top,t2,bot);
   else
     {
      ObjectSetInteger(0,body,OBJPROP_TIME,0,t1);
      ObjectSetDouble(0,body,OBJPROP_PRICE,0,top);
      ObjectSetInteger(0,body,OBJPROP_TIME,1,t2);
      ObjectSetDouble(0,body,OBJPROP_PRICE,1,bot);
     }
   ObjectSetInteger(0,body,OBJPROP_COLOR,col);
   ObjectSetInteger(0,body,OBJPROP_FILL,true);
   ObjectSetInteger(0,body,OBJPROP_BACK,true);
   ObjectSetInteger(0,body,OBJPROP_SELECTABLE,false);
   datetime tm=t1+(t2-t1)/2;
   if(ObjectFind(0,wick)<0) ObjectCreate(0,wick,OBJ_TREND,0,tm,h,tm,l);
   else
     {
      ObjectSetInteger(0,wick,OBJPROP_TIME,0,tm);
      ObjectSetDouble(0,wick,OBJPROP_PRICE,0,h);
      ObjectSetInteger(0,wick,OBJPROP_TIME,1,tm);
      ObjectSetDouble(0,wick,OBJPROP_PRICE,1,l);
     }
   ObjectSetInteger(0,wick,OBJPROP_COLOR,col);
   ObjectSetInteger(0,wick,OBJPROP_RAY_RIGHT,false);
   ObjectSetInteger(0,wick,OBJPROP_BACK,true);
   ObjectSetInteger(0,wick,OBJPROP_SELECTABLE,false);
  }

void DrawTwin(const int idx,const datetime t,const int period_sec,
              const double so,const double sh,const double sl,const double sc,
              const double fo,const double fh,const double fl,const double fc)
  {
   int half=period_sec*MathMax(40,MathMin(90,InpCandleWidth))/200;
   if(half<2) half=2;
   int gap=MathMax(1,half/8);
   DrawHalf("S",idx,t-half,t-gap,so,sh,sl,sc,(sc>=so)?InpSpotBull:InpSpotBear);
   DrawHalf("F",idx,t+gap,t+half,fo,fh,fl,fc,(fc>=fo)?InpFutBull:InpFutBear);
  }

void UpdatePanel(const double basis,const double mean,const double stdev,
                 const double z,const double spot,const double fut)
  {
   string n=OBJ_PREFIX"panel";
   string txt=StringFormat("GoldFX 期现对比\n金=现货 %s  蓝绿=期货 %s\n现货 %.2f  期货 %.2f\n价差(柱) %.4f 均值 %.4f σ %.4f\nZ=%.2f ±Entry %.1f",
                           g_spot,g_fut,spot,fut,basis,mean,stdev,z,InpEntryZ);
   if(ObjectFind(0,n)<0)
     {
      ObjectCreate(0,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,n,OBJPROP_XDISTANCE,8);
      ObjectSetInteger(0,n,OBJPROP_YDISTANCE,18);
      ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
      ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhiteSmoke);
     }
   ObjectSetString(0,n,OBJPROP_TEXT,txt);
  }

int OnInit()
  {
   g_spot=InpSpotSymbol; g_fut=InpFutSymbol;
   StringTrimLeft(g_spot); StringTrimRight(g_spot);
   StringTrimLeft(g_fut); StringTrimRight(g_fut);
   if(StringLen(g_spot)==0) g_spot=_Symbol;
   if(StringLen(g_fut)==0){ Print("请填写期货代码 GC"); return INIT_PARAMETERS_INCORRECT; }
   if(g_spot==g_fut) return INIT_PARAMETERS_INCORRECT;
   if(!SymbolSelect(g_spot,true)||!SymbolSelect(g_fut,true)) return INIT_FAILED;
   g_lookback=MathMax(20,InpLookback);

   SetIndexBuffer(0,BufHistUp,INDICATOR_DATA);
   SetIndexBuffer(1,BufHistDn,INDICATOR_DATA);
   SetIndexBuffer(2,BufMean,INDICATOR_DATA);
   SetIndexBuffer(3,BufUpper,INDICATOR_DATA);
   SetIndexBuffer(4,BufLower,INDICATOR_DATA);
   SetIndexBuffer(5,BufArrowShort,INDICATOR_DATA);
   SetIndexBuffer(6,BufArrowLong,INDICATOR_DATA);
   SetIndexBuffer(7,BufZ,INDICATOR_DATA);
   PlotIndexSetInteger(5,PLOT_ARROW,234);
   PlotIndexSetInteger(6,PLOT_ARROW,233);
   PlotIndexSetDouble(0,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(1,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(5,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetDouble(6,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   ArraySetAsSeries(BufHistUp,true); ArraySetAsSeries(BufHistDn,true);
   ArraySetAsSeries(BufMean,true); ArraySetAsSeries(BufUpper,true); ArraySetAsSeries(BufLower,true);
   ArraySetAsSeries(BufArrowShort,true); ArraySetAsSeries(BufArrowLong,true); ArraySetAsSeries(BufZ,true);
   IndicatorSetString(INDICATOR_SHORTNAME,StringFormat("价差柱 %s-%s",g_fut,g_spot));
   IndicatorSetInteger(INDICATOR_DIGITS,4);
   ChartSetInteger(0,CHART_MODE,CHART_LINE);
   ChartSetInteger(0,CHART_COLOR_CHART_LINE,C'60,60,60');
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason){ DeleteObjs(); }

int OnCalculate(const int rates_total,const int prev_calculated,
                const datetime &time[],const double &open[],const double &high[],
                const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
  {
   if(rates_total<InpMinBars||rates_total<g_lookback+5) return 0;
   ArraySetAsSeries(time,true); ArraySetAsSeries(close,true);
   int limit=MathMin(rates_total-g_lookback-1,InpMaxDrawBars);
   int start=limit;
   if(prev_calculated>g_lookback+2) start=MathMin(limit,3);
   int period_sec=(int)PeriodSeconds(_Period);

   for(int i=start;i>=0;--i)
     {
      BufHistUp[i]=EMPTY_VALUE; BufHistDn[i]=EMPTY_VALUE;
      BufArrowShort[i]=EMPTY_VALUE; BufArrowLong[i]=EMPTY_VALUE;
      double sum=0,sum2=0; int cnt=0; bool ok=true;
      for(int k=1;k<=g_lookback;++k)
        {
         int si=i+k; if(si>=rates_total){ok=false;break;}
         int fs=iBarShift(g_spot,_Period,time[si],false);
         int ff=iBarShift(g_fut,_Period,time[si],false);
         if(fs<0||ff<0){ok=false;break;}
         double sp=RawSpread(iClose(g_fut,_Period,ff),iClose(g_spot,_Period,fs));
         sum+=sp; sum2+=sp*sp; cnt++;
        }
      if(!ok||cnt<g_lookback)
        { BufMean[i]=EMPTY_VALUE; BufUpper[i]=EMPTY_VALUE; BufLower[i]=EMPTY_VALUE; BufZ[i]=EMPTY_VALUE; continue; }
      double mean=sum/cnt, stdev=MathSqrt(MathMax(0.0,sum2/cnt-mean*mean));
      int fs0=iBarShift(g_spot,_Period,time[i],false);
      int ff0=iBarShift(g_fut,_Period,time[i],false);
      if(fs0<0||ff0<0){ BufMean[i]=EMPTY_VALUE; continue; }
      double so=iOpen(g_spot,_Period,fs0), sh=iHigh(g_spot,_Period,fs0), sl=iLow(g_spot,_Period,fs0), sc=iClose(g_spot,_Period,fs0);
      double fo=iOpen(g_fut,_Period,ff0), fh=iHigh(g_fut,_Period,ff0), fl=iLow(g_fut,_Period,ff0), fc=iClose(g_fut,_Period,ff0);
      if(i==0)
        {
         MqlTick ts,tf;
         if(SymbolInfoTick(g_spot,ts)){ sc=0.5*(ts.bid+ts.ask); if(sc>sh)sh=sc; if(sc<sl)sl=sc; }
         if(SymbolInfoTick(g_fut,tf)){ fc=0.5*(tf.bid+tf.ask); if(fc>fh)fh=fc; if(fc<fl)fl=fc; }
        }
      double basis=RawSpread(fc,sc);
      double z=(stdev>1e-12)?(basis-mean)/stdev:0;
      BufMean[i]=mean; BufUpper[i]=mean+InpEntryZ*stdev; BufLower[i]=mean-InpEntryZ*stdev; BufZ[i]=z;
      if(basis>=mean) BufHistUp[i]=basis; else BufHistDn[i]=basis;
      if(i+1<rates_total && BufZ[i+1]!=EMPTY_VALUE)
        {
         double zp=BufZ[i+1];
         if(z>=InpEntryZ && zp<InpEntryZ) BufArrowShort[i]=basis;
         if(z<=-InpEntryZ && zp>-InpEntryZ) BufArrowLong[i]=basis;
        }
      if(InpDrawTwinK) DrawTwin(i,time[i],period_sec,so,sh,sl,sc,fo,fh,fl,fc);
     }
   if(BufZ[0]!=EMPTY_VALUE)
     {
      MqlTick ts,tf; double sm=0,fm=0;
      if(SymbolInfoTick(g_spot,ts)) sm=0.5*(ts.bid+ts.ask);
      if(SymbolInfoTick(g_fut,tf)) fm=0.5*(tf.bid+tf.ask);
      double stdev0=(InpEntryZ>0)?(BufUpper[0]-BufMean[0])/InpEntryZ:0;
      double basis0=(BufHistUp[0]!=EMPTY_VALUE)?BufHistUp[0]:BufHistDn[0];
      UpdatePanel(basis0,BufMean[0],stdev0,BufZ[0],sm,fm);
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
