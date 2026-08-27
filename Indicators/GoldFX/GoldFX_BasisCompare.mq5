//+------------------------------------------------------------------+
//| GoldFX_BasisCompare.mq5 — 黄金期货/现货双K对比 + 基差/Z副图        |
//| 主图：期货K线叠加（ChartObjects）；副图：基差带与信号箭头           |
//| 仅可视化，不下单。配合 GoldFX_BasisArb EA 做提醒/交易。             |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.00"
#property description "现货图叠加期货K线；副图显示基差均值带与开平仓标记"
#property indicator_separate_window
#property indicator_buffers 8
#property indicator_plots   6

#property indicator_label1  "Basis"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

#property indicator_label2  "Mean"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_style2  STYLE_DOT
#property indicator_width2  1

#property indicator_label3  "Upper"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrTomato
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "Lower"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLimeGreen
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

#property indicator_label5  "EntryShort"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrOrangeRed
#property indicator_width5  2

#property indicator_label6  "EntryLong"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrLime
#property indicator_width6  2

input group "=== 品种 / 模型 ==="
input string InpFutSymbol   = "";           // 期货/远期（必填，如 XAUUSD.f）
input int    InpLookback    = 60;           // 滚动窗口
input double InpEntryZ      = 2.0;          // 入场 |Z|（带宽 = mean±EntryZ·σ）
input double InpExitZ       = 0.40;         // 出场 |Z|（标记用）
input int    InpSpreadMode  = 0;            // 0=F-S  1=F/S-1  2=ln(F/S)
input int    InpMinBars     = 120;          // 最少K线
input int    InpMaxDrawBars = 400;          // 最多绘制历史根数

input group "=== 主图期货K线 ==="
input bool   InpDrawFutCandles = true;      // 在主图叠加期货K线
input color  InpFutBull        = C'32,120,140';
input color  InpFutBear        = C'160,70,60';
input int    InpCandleWidth    = 60;        // 实体宽度占周期比例%(30-90)

#define OBJ_PREFIX "GFXBC_"

double BufBasis[];
double BufMean[];
double BufUpper[];
double BufLower[];
double BufArrowShort[];
double BufArrowLong[];
double BufZ[];
double BufExitMark[];

string g_fut = "";
int    g_lookback = 60;

//------------------------------------------------------------------
double RawSpread(const double fut, const double spot)
  {
   if(spot <= 0.0) return 0.0;
   if(InpSpreadMode == 1) return fut / spot - 1.0;
   if(InpSpreadMode == 2) return MathLog(fut / spot);
   return fut - spot;
  }

void DeleteFutObjects(void)
  {
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
     {
      const string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, OBJ_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

void DrawFutCandle(const int idx, const datetime t, const double o, const double h,
                   const double l, const double c, const int period_sec)
  {
   const string body = StringFormat("%sb%d", OBJ_PREFIX, idx);
   const string wick = StringFormat("%sw%d", OBJ_PREFIX, idx);
   const color col = (c >= o) ? InpFutBull : InpFutBear;
   const int half = MathMax(1, (int)(period_sec * MathMax(30, MathMin(90, InpCandleWidth)) / 200.0));
   const datetime t1 = t - half;
   const datetime t2 = t + half;
   double top = MathMax(o, c);
   double bot = MathMin(o, c);
   if(MathAbs(top - bot) < _Point) top = bot + _Point;

   if(ObjectFind(0, body) < 0)
      ObjectCreate(0, body, OBJ_RECTANGLE, 0, t1, top, t2, bot);
   else
     {
      ObjectSetInteger(0, body, OBJPROP_TIME, 0, t1);
      ObjectSetDouble(0, body, OBJPROP_PRICE, 0, top);
      ObjectSetInteger(0, body, OBJPROP_TIME, 1, t2);
      ObjectSetDouble(0, body, OBJPROP_PRICE, 1, bot);
     }
   ObjectSetInteger(0, body, OBJPROP_COLOR, col);
   ObjectSetInteger(0, body, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, body, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, body, OBJPROP_FILL, true);
   ObjectSetInteger(0, body, OBJPROP_BACK, true);
   ObjectSetInteger(0, body, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, body, OBJPROP_HIDDEN, true);

   if(ObjectFind(0, wick) < 0)
      ObjectCreate(0, wick, OBJ_TREND, 0, t, h, t, l);
   else
     {
      ObjectSetInteger(0, wick, OBJPROP_TIME, 0, t);
      ObjectSetDouble(0, wick, OBJPROP_PRICE, 0, h);
      ObjectSetInteger(0, wick, OBJPROP_TIME, 1, t);
      ObjectSetDouble(0, wick, OBJPROP_PRICE, 1, l);
     }
   ObjectSetInteger(0, wick, OBJPROP_COLOR, col);
   ObjectSetInteger(0, wick, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, wick, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, wick, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, wick, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, wick, OBJPROP_BACK, true);
   ObjectSetInteger(0, wick, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, wick, OBJPROP_HIDDEN, true);
  }

void UpdatePanel(const double basis, const double mean, const double stdev,
                 const double z, const double spot, const double fut)
  {
   const string n = OBJ_PREFIX "panel";
   string txt = StringFormat("GoldFX 期现对比\n现货 %s %.2f\n期货 %s %.2f\n基差 %.4f  均值 %.4f  σ %.4f\nZ=%.2f  Entry±%.1f  Exit±%.1f",
                             _Symbol, spot, g_fut, fut, basis, mean, stdev, z, InpEntryZ, InpExitZ);
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 8);
      ObjectSetInteger(0, n, OBJPROP_YDISTANCE, 20);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_COLOR, clrWhiteSmoke);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
   ObjectSetString(0, n, OBJPROP_TEXT, txt);
  }

//------------------------------------------------------------------
int OnInit()
  {
   g_fut = InpFutSymbol;
   StringTrimLeft(g_fut); StringTrimRight(g_fut);
   if(StringLen(g_fut) == 0)
     {
      Print("GoldFX_BasisCompare: 请填写 InpFutSymbol");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(g_fut == _Symbol)
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

   SetIndexBuffer(0, BufBasis, INDICATOR_DATA);
   SetIndexBuffer(1, BufMean, INDICATOR_DATA);
   SetIndexBuffer(2, BufUpper, INDICATOR_DATA);
   SetIndexBuffer(3, BufLower, INDICATOR_DATA);
   SetIndexBuffer(4, BufArrowShort, INDICATOR_DATA);
   SetIndexBuffer(5, BufArrowLong, INDICATOR_DATA);
   SetIndexBuffer(6, BufZ, INDICATOR_DATA);
   SetIndexBuffer(7, BufExitMark, INDICATOR_CALCULATIONS);

   PlotIndexSetInteger(4, PLOT_ARROW, 234); // 向下箭头 — 空基差
   PlotIndexSetInteger(5, PLOT_ARROW, 233); // 向上箭头 — 多基差
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetDouble(5, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArraySetAsSeries(BufBasis, true);
   ArraySetAsSeries(BufMean, true);
   ArraySetAsSeries(BufUpper, true);
   ArraySetAsSeries(BufLower, true);
   ArraySetAsSeries(BufArrowShort, true);
   ArraySetAsSeries(BufArrowLong, true);
   ArraySetAsSeries(BufZ, true);
   ArraySetAsSeries(BufExitMark, true);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("GoldFX Basis %s vs %s", _Symbol, g_fut));
   IndicatorSetInteger(INDICATOR_DIGITS, 4);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteFutObjects();
   ObjectDelete(0, OBJ_PREFIX "panel");
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
   if(rates_total < InpMinBars || rates_total < g_lookback + 5)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   MqlRates fut_rates[];
   ArraySetAsSeries(fut_rates, true);
   const int need = MathMin(rates_total, InpMaxDrawBars + g_lookback + 10);
   const int copied = CopyRates(g_fut, _Period, 0, need, fut_rates);
   if(copied < g_lookback + 5)
      return 0;

   const int limit = MathMin(rates_total - g_lookback - 1, InpMaxDrawBars);
   const int period_sec = PeriodSeconds(_Period);

   // 从旧到新填缓冲；series 下标 0 = 最新
   int start = limit;
   if(prev_calculated > g_lookback + 2)
      start = MathMin(limit, 3); // 增量：刷新最近几根

   for(int i = start; i >= 0; --i)
     {
      BufArrowShort[i] = EMPTY_VALUE;
      BufArrowLong[i]  = EMPTY_VALUE;
      BufExitMark[i]   = EMPTY_VALUE;

      // 滚动窗口：用已收盘棒 i+1 .. i+lookback（对当前形成棒 i=0 用 1..lookback）
      double sum = 0, sum2 = 0;
      int    cnt = 0;
      bool   ok  = true;
      for(int k = 1; k <= g_lookback; ++k)
        {
         const int si = i + k;
         if(si >= rates_total) { ok = false; break; }
         const int fi = iBarShift(g_fut, _Period, time[si], false);
         if(fi < 0 || fi >= copied) { ok = false; break; }
         const double sp = RawSpread(fut_rates[fi].close, close[si]);
         sum += sp;
         sum2 += sp * sp;
         cnt++;
        }
      if(!ok || cnt < g_lookback)
        {
         BufBasis[i] = EMPTY_VALUE;
         BufMean[i]  = EMPTY_VALUE;
         BufUpper[i] = EMPTY_VALUE;
         BufLower[i] = EMPTY_VALUE;
         BufZ[i]     = EMPTY_VALUE;
         continue;
        }

      const double mean = sum / cnt;
      const double var  = MathMax(0.0, sum2 / cnt - mean * mean);
      const double stdev = MathSqrt(var);

      int fi_now = iBarShift(g_fut, _Period, time[i], false);
      if(fi_now < 0 || fi_now >= copied)
        {
         BufBasis[i] = EMPTY_VALUE;
         continue;
        }

      double fut_c = fut_rates[fi_now].close;
      double spot_c = close[i];
      // 当前形成棒：用最新 mid 刷新
      if(i == 0)
        {
         MqlTick ts, tf;
         if(SymbolInfoTick(_Symbol, ts) && SymbolInfoTick(g_fut, tf))
           {
            spot_c = 0.5 * (ts.bid + ts.ask);
            fut_c  = 0.5 * (tf.bid + tf.ask);
           }
        }

      const double basis = RawSpread(fut_c, spot_c);
      const double z = (stdev > 1e-12) ? (basis - mean) / stdev : 0.0;

      BufBasis[i] = basis;
      BufMean[i]  = mean;
      BufUpper[i] = mean + InpEntryZ * stdev;
      BufLower[i] = mean - InpEntryZ * stdev;
      BufZ[i]     = z;

      // 信号：相对前一根 Z 穿越入场带
      if(i + 1 < rates_total && BufZ[i + 1] != EMPTY_VALUE)
        {
         const double zprev = BufZ[i + 1];
         if(z >= InpEntryZ && zprev < InpEntryZ)
            BufArrowShort[i] = basis;
         if(z <= -InpEntryZ && zprev > -InpEntryZ)
            BufArrowLong[i] = basis;
         if(MathAbs(z) <= InpExitZ && MathAbs(zprev) > InpExitZ)
            BufExitMark[i] = basis;
        }

      if(InpDrawFutCandles && fi_now >= 0 && fi_now < copied)
        {
         const MqlRates fr = fut_rates[fi_now];
         double fo = fr.open, fh = fr.high, fl = fr.low, fc = fr.close;
         if(i == 0)
           {
            MqlTick tf;
            if(SymbolInfoTick(g_fut, tf))
              {
               fc = 0.5 * (tf.bid + tf.ask);
               if(fc > fh) fh = fc;
               if(fc < fl) fl = fc;
              }
           }
         DrawFutCandle(i, time[i], fo, fh, fl, fc, period_sec);
        }
     }

   // 实时面板
   if(BufZ[0] != EMPTY_VALUE)
     {
      double spot_mid = close[0], fut_mid = 0;
      MqlTick ts, tf;
      if(SymbolInfoTick(_Symbol, ts)) spot_mid = 0.5 * (ts.bid + ts.ask);
      if(SymbolInfoTick(g_fut, tf))   fut_mid  = 0.5 * (tf.bid + tf.ask);
      else
        {
         const int fi0 = iBarShift(g_fut, _Period, time[0], false);
         if(fi0 >= 0 && fi0 < copied) fut_mid = fut_rates[fi0].close;
        }
      UpdatePanel(BufBasis[0], BufMean[0],
                  (InpEntryZ > 0 ? (BufUpper[0] - BufMean[0]) / InpEntryZ : 0),
                  BufZ[0], spot_mid, fut_mid);
     }

   return rates_total;
  }
//+------------------------------------------------------------------+
