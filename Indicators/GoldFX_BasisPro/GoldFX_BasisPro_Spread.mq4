//+------------------------------------------------------------------+
//|                              GoldFX_BasisPro_Spread.mq4          |
//|     黄金期现基差副图 — 彩色柱状图 + Z 分策略档位线（均值回归套利）   |
//|  用法：与 GoldFX_BasisPro_Overlay 同挂现货图；参数与 EA 逻辑对齐   |
//+------------------------------------------------------------------+
#property copyright   "GoldFX Intraday Framework"
#property link        "https://github.com/szgogol1/GoldFX-MT5"
#property version     "1.00"
#property strict
#property indicator_separate_window
#property indicator_buffers 9

// 柱颜色: 0出场 1观望 2空基差 3多基差 4空止损 5多止损
#property indicator_color1  C'255,200,0'     // 出场区
#property indicator_color2  C'128,128,128'   // 观望
#property indicator_color3  C'255,60,60'     // 空基差
#property indicator_color4  C'50,205,50'     // 多基差
#property indicator_color5  C'139,0,0'       // 空止损
#property indicator_color6  C'0,100,0'       // 多止损
#property indicator_color7  clrSilver         // μ
#property indicator_color8  clrRed            // 空入场
#property indicator_color9  clrLime            // 多入场

#property description "基差=期货-现货 | 柱色=策略档位 | 线=μ/Z阈值"

//--- 品种
input string InpSpotSymbol     = "";             // 现货(空=图表品种)
input string InpFutSymbol      = "GC";           // 期货品种

//--- 统计（与 GoldFX_BasisArb 默认一致）
input int    InpLookback       = 60;             // 滚动窗口
input int    InpMinBars        = 30;             // 最少 K 线
input double InpEntryZ         = 2.0;            // 入场 |Z|
input double InpExitZ          = 0.40;           // 出场 |Z|
input double InpStopZ          = 3.5;            // 止损 |Z|

//--- 显示
input bool   InpShowLevels     = true;           // 显示策略档位线
input bool   InpShowLegend     = true;           // 显示图例标签
input int    InpHistWidth      = 3;              // 柱宽

//--- 缓冲
double g_spread[];
double g_color[];
double g_mean[];
double g_entShort[];
double g_entLong[];
double g_exitUp[];
double g_exitDn[];
double g_stopUp[];
double g_stopDn[];

string   g_spotSym;
string   g_legendName = "GFBasisPro_Spread_Legend";
datetime g_lastLegUpd = 0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_spotSym = InpSpotSymbol;
   StringTrimLeft(g_spotSym);
   StringTrimRight(g_spotSym);
   if(StringLen(g_spotSym) == 0)
      g_spotSym = Symbol();

   if(StringLen(InpFutSymbol) == 0)
     {
      Alert("GoldFX_BasisPro_Spread: 请设置 InpFutSymbol");
      return(INIT_PARAMETERS_INCORRECT);
     }
   if(g_spotSym == InpFutSymbol)
     {
      Alert("GoldFX_BasisPro_Spread: 现货与期货不能相同");
      return(INIT_PARAMETERS_INCORRECT);
     }

   IndicatorShortName("GFBasisPro Spread [" + InpFutSymbol + "-" + g_spotSym + "]");

   SetIndexBuffer(0, g_spread);
   SetIndexBuffer(1, g_color);
   SetIndexBuffer(2, g_mean);
   SetIndexBuffer(3, g_entShort);
   SetIndexBuffer(4, g_entLong);
   SetIndexBuffer(5, g_exitUp);
   SetIndexBuffer(6, g_exitDn);
   SetIndexBuffer(7, g_stopUp);
   SetIndexBuffer(8, g_stopDn);

   SetIndexStyle(0, DRAW_COLOR_HISTOGRAM, STYLE_SOLID, InpHistWidth);
   SetIndexStyle(1, DRAW_NONE);
   SetIndexStyle(2, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_SOLID, 1);
   SetIndexStyle(3, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DOT,  1);
   SetIndexStyle(4, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DOT,  1);
   SetIndexStyle(5, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DASH, 1);
   SetIndexStyle(6, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DASH, 1);
   SetIndexStyle(7, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DASHDOT, 1);
   SetIndexStyle(8, InpShowLevels ? DRAW_LINE : DRAW_NONE, STYLE_DASHDOT, 1);

   SetIndexLabel(0, "Basis F-S");
   SetIndexLabel(2, "Mean u");
   SetIndexLabel(3, "Short Entry");
   SetIndexLabel(4, "Long Entry");
   SetIndexLabel(5, "Exit +");
   SetIndexLabel(6, "Exit -");
   SetIndexLabel(7, "Stop +");
   SetIndexLabel(8, "Stop -");

   SetIndexEmptyValue(0, EMPTY_VALUE);

   ArraySetAsSeries(g_spread,   true);
   ArraySetAsSeries(g_color,    true);
   ArraySetAsSeries(g_mean,     true);
   ArraySetAsSeries(g_entShort, true);
   ArraySetAsSeries(g_entLong,  true);
   ArraySetAsSeries(g_exitUp,   true);
   ArraySetAsSeries(g_exitDn,   true);
   ArraySetAsSeries(g_stopUp,   true);
   ArraySetAsSeries(g_stopDn,   true);

   IndicatorDigits(2);

   if(InpShowLegend)
      CreateLegend();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectDelete(0, g_legendName);
  }

//+------------------------------------------------------------------+
void CreateLegend()
  {
   if(ObjectFind(0, g_legendName) < 0)
      ObjectCreate(0, g_legendName, OBJ_LABEL, 1, 0, 0);

   ObjectSetInteger(0, g_legendName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, g_legendName, OBJPROP_XDISTANCE, 8);
   ObjectSetInteger(0, g_legendName, OBJPROP_YDISTANCE, 8);
   ObjectSetInteger(0, g_legendName, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, g_legendName, OBJPROP_FONTSIZE, 8);
   ObjectSetString(0, g_legendName, OBJPROP_FONT, "Consolas");
   UpdateLegendText(0, 0, 0, 0);
  }

//+------------------------------------------------------------------+
void UpdateLegendText(const double basis, const double mean,
                      const double stdev, const double z)
  {
   string side = "观望";
   if(z >= InpEntryZ)       side = "-> 空基差(空期+多现)";
   else if(z <= -InpEntryZ) side = "-> 多基差(多期+空现)";
   else if(MathAbs(z) <= InpExitZ) side = "-> 回归/出场区";

   ObjectSetString(0, g_legendName, OBJPROP_TEXT,
      "基差=" + DoubleToString(basis, 2)
      + "  u=" + DoubleToString(mean, 2)
      + "  s=" + DoubleToString(stdev, 2)
      + "  Z=" + DoubleToString(z, 2) + "\n"
      + side + "\n"
      "黄=出场 灰=观望 红=空基差 绿=多基差 深红/深绿=止损");
  }

//+------------------------------------------------------------------+
bool CalcRolling(const int shift, double &mean, double &stdev, double &spread)
  {
   const int lb = MathMax(5, InpLookback);
   double sum = 0, sum2 = 0;
   int cnt = 0;

   for(int j = 0; j < lb; j++)
     {
      const int idx = shift + j;
      double cs = iClose(g_spotSym, Period(), idx);
      double cf = iClose(InpFutSymbol, Period(), idx);
      if(cs <= 0 || cf <= 0)
         continue;
      const double sp = cf - cs;
      sum  += sp;
      sum2 += sp * sp;
      cnt++;
     }

   if(cnt < MathMin(InpMinBars, lb))
      return(false);

   mean = sum / cnt;
   const double var = MathMax(0.0, sum2 / cnt - mean * mean);
   stdev = MathSqrt(var);

   double cs0 = iClose(g_spotSym, Period(), shift);
   double cf0 = iClose(InpFutSymbol, Period(), shift);
   if(cs0 <= 0 || cf0 <= 0)
      return(false);
   spread = cf0 - cs0;
   return(true);
  }

//+------------------------------------------------------------------+
int ZoneColor(const double z)
  {
   if(z >= InpStopZ)  return(4);
   if(z <= -InpStopZ) return(5);
   if(z >= InpEntryZ) return(2);
   if(z <= -InpEntryZ) return(3);
   if(MathAbs(z) <= InpExitZ) return(0);
   return(1);
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
   if(rates_total < InpMinBars + 2)
      return(0);

   int start = prev_calculated - 1;
   if(start < 0) start = 0;
   if(start > rates_total - 2) start = rates_total - 2;

   for(int i = start; i >= 0; i--)
     {
      double mean, stdev, basis;
      if(!CalcRolling(i, mean, stdev, basis))
        {
         g_spread[i]   = EMPTY_VALUE;
         g_mean[i]     = EMPTY_VALUE;
         g_entShort[i] = EMPTY_VALUE;
         g_entLong[i]  = EMPTY_VALUE;
         g_exitUp[i]   = EMPTY_VALUE;
         g_exitDn[i]   = EMPTY_VALUE;
         g_stopUp[i]   = EMPTY_VALUE;
         g_stopDn[i]   = EMPTY_VALUE;
         continue;
        }

      const double sd = (stdev > 1e-12) ? stdev : 0.0;
      const double z  = (sd > 0) ? (basis - mean) / sd : 0.0;

      g_spread[i] = basis;
      g_color[i]  = ZoneColor(z);

      g_mean[i]     = mean;
      g_entShort[i] = mean + InpEntryZ * sd;
      g_entLong[i]  = mean - InpEntryZ * sd;
      g_exitUp[i]   = mean + InpExitZ * sd;
      g_exitDn[i]   = mean - InpExitZ * sd;
      g_stopUp[i]   = mean + InpStopZ * sd;
      g_stopDn[i]   = mean - InpStopZ * sd;
     }

   if(InpShowLegend && time[0] != g_lastLegUpd)
     {
      g_lastLegUpd = time[0];
      double mean, stdev, basis;
      if(CalcRolling(0, mean, stdev, basis))
        {
         const double z = (stdev > 1e-12) ? (basis - mean) / stdev : 0.0;
         UpdateLegendText(basis, mean, stdev, z);
        }
     }

   return(rates_total);
  }
//+------------------------------------------------------------------+
