//+------------------------------------------------------------------+
//|                              GoldFX_BasisPro_Overlay.mq4         |
//|              黄金期现货 K 线叠加 — 主图期货蜡烛 + 现货原生 K 线    |
//|  用法：挂在现货图表(XAUUSD.s)，设置期货品种(GC)；配合 Spread 指标   |
//+------------------------------------------------------------------+
#property copyright   "GoldFX Intraday Framework"
#property link        "https://github.com/szgogol1/GoldFX-MT5"
#property version     "1.00"
#property strict
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_color1  C'30,144,255'    // 期货阳线
#property indicator_color2  C'255,99,71'     // 期货阴线
#property indicator_color3  C'0,191,255'     // 期货收盘线
#property indicator_color4  C'255,215,0'     // 现货收盘线

#property description "主图叠加期货 K 线（蓝=阳, 橙红=阴）"
#property description "现货为图表原生 K 线；请同时加载 GoldFX_BasisPro_Spread"

//--- 输入
input string InpFutSymbol      = "GC";           // 期货品种
input bool   InpShowFutCandles = true;           // 显示期货 K 线
input bool   InpShowFutClose   = true;           // 显示期货收盘价线
input bool   InpShowSpotClose  = true;           // 显示现货收盘价线(对照)
input int    InpFutCandleWidth= 2;               // 期货蜡烛线宽
input int    InpLabelCorner    = 1;              // 标签角落 0-3
input int    InpLabelX         = 10;
input int    InpLabelY         = 22;

//--- 缓冲: 0-4 蜡烛, 5 现货收盘线
double g_futOpen[];
double g_futHigh[];
double g_futLow[];
double g_futClose[];
double g_futColor[];
double g_spotClose[];

string   g_labelName = "GFBasisPro_Overlay_Lbl";

//+------------------------------------------------------------------+
int OnInit()
  {
   if(StringLen(InpFutSymbol) == 0)
     {
      Alert("GoldFX_BasisPro_Overlay: 请设置期货品种 InpFutSymbol");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(InpFutSymbol == Symbol())
     {
      Alert("GoldFX_BasisPro_Overlay: 期货品种不能与图表品种相同");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName("GFBasisPro Overlay [" + InpFutSymbol + "]");

   SetIndexBuffer(0, g_futOpen);
   SetIndexBuffer(1, g_futHigh);
   SetIndexBuffer(2, g_futLow);
   SetIndexBuffer(3, g_futClose);
   SetIndexBuffer(4, g_futColor);
   SetIndexBuffer(5, g_spotClose);

   SetIndexStyle(0, InpShowFutCandles ? DRAW_COLOR_CANDLES : DRAW_NONE, STYLE_SOLID, InpFutCandleWidth);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, DRAW_NONE);
   SetIndexStyle(3, DRAW_NONE);
   SetIndexStyle(4, DRAW_NONE);
   SetIndexStyle(5, InpShowSpotClose ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1);

   SetIndexLabel(0, "Fut OHLC");
   SetIndexLabel(5, "Spot Close");

   SetIndexEmptyValue(0, EMPTY_VALUE);
   SetIndexEmptyValue(5, EMPTY_VALUE);

   ArraySetAsSeries(g_futOpen,   true);
   ArraySetAsSeries(g_futHigh,   true);
   ArraySetAsSeries(g_futLow,    true);
   ArraySetAsSeries(g_futClose,  true);
   ArraySetAsSeries(g_futColor,  true);
   ArraySetAsSeries(g_spotClose, true);

   IndicatorDigits(Digits);
   CreateLegend();
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, g_labelName);
   Comment("");
  }

//+------------------------------------------------------------------+
void CreateLegend()
  {
   if(ObjectFind(0, g_labelName) < 0)
      ObjectCreate(0, g_labelName, OBJ_LABEL, 0, 0, 0);

   ObjectSetInteger(0, g_labelName, OBJPROP_CORNER, InpLabelCorner);
   ObjectSetInteger(0, g_labelName, OBJPROP_XDISTANCE, InpLabelX);
   ObjectSetInteger(0, g_labelName, OBJPROP_YDISTANCE, InpLabelY);
   ObjectSetInteger(0, g_labelName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_labelName, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, g_labelName, OBJPROP_FONT, "Consolas");
   ObjectSetString(0, g_labelName, OBJPROP_TEXT,
                   "■ 现货 " + Symbol() + " (原生K线+金线)\n"
                   + "■ 期货 " + InpFutSymbol + " (叠加蜡烛)\n"
                   + "蓝阳/橙阴 | 青虚线=期货收盘");
  }

//+------------------------------------------------------------------+
bool FutBar(const int shift, double &o, double &h, double &l, double &c)
  {
   o = iOpen(InpFutSymbol, Period(), shift);
   h = iHigh(InpFutSymbol, Period(), shift);
   l = iLow(InpFutSymbol, Period(), shift);
   c = iClose(InpFutSymbol, Period(), shift);
   if(o <= 0 || h <= 0 || l <= 0 || c <= 0)
      return(false);
   return(true);
  }

//+------------------------------------------------------------------+
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
   if(rates_total < 2)
      return(0);

   int start = prev_calculated - 1;
   if(start < 0) start = 0;
   if(start > rates_total - 2) start = rates_total - 2;

   // 期货收盘线复用 g_futClose；单独线用 Objects 太耗 — 用 buffer3 已是 close
   // 额外画期货收盘线：复制到 Comment 实时显示
   double ms0 = 0, mf0 = 0;

   for(int i = start; i >= 0; i--)
     {
      g_spotClose[i] = close[i];

      double fo, fh, fl, fc;
      if(FutBar(i, fo, fh, fl, fc))
        {
         g_futOpen[i]  = fo;
         g_futHigh[i]  = fh;
         g_futLow[i]   = fl;
         g_futClose[i] = fc;
         g_futColor[i] = (fc >= fo) ? 0 : 1;
         if(i == 0) { ms0 = close[i]; mf0 = fc; }
        }
      else
        {
         g_futOpen[i]  = EMPTY_VALUE;
         g_futHigh[i]  = EMPTY_VALUE;
         g_futLow[i]   = EMPTY_VALUE;
         g_futClose[i] = EMPTY_VALUE;
         g_futColor[i] = 0;
        }
     }

   if(ms0 > 0 && mf0 > 0)
      Comment("现货 ", DoubleToString(ms0, Digits),
              "  |  期货 ", DoubleToString(mf0, Digits),
              "  |  基差 ", DoubleToString(mf0 - ms0, Digits));

   return(rates_total);
  }
//+------------------------------------------------------------------+
