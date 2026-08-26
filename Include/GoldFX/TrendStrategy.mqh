//+------------------------------------------------------------------+
//| TrendStrategy.mqh — 选择性趋势：EMA交叉 + ADX/DI/斜率质量评分       |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TREND_STRATEGY_MQH
#define GOLDFX_TREND_STRATEGY_MQH

#include "Common.mqh"

class CTrendStrategy
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_ma_fast_h;
   int               m_ma_slow_h;
   int               m_atr_h;
   int               m_adx_h;
   int               m_ma_fast;
   int               m_ma_slow;
   int               m_atr_period;
   int               m_adx_period;
   double            m_adx_min;
   double            m_sl_mult;
   double            m_tp_mult;
   datetime          m_last_signal_bar;

   bool CopyBuf(const int handle, const int buf, const int count, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(handle, buf, 0, count, out) >= count);
     }

public:
                     CTrendStrategy(void)
                       : m_symbol(_Symbol),
                         m_tf(PERIOD_CURRENT),
                         m_ma_fast_h(INVALID_HANDLE),
                         m_ma_slow_h(INVALID_HANDLE),
                         m_atr_h(INVALID_HANDLE),
                         m_adx_h(INVALID_HANDLE),
                         m_ma_fast(20),
                         m_ma_slow(50),
                         m_atr_period(14),
                         m_adx_period(14),
                         m_adx_min(25.0),
                         m_sl_mult(1.5),
                         m_tp_mult(2.5),
                         m_last_signal_bar(0)
                     {
                     }

                    ~CTrendStrategy(void) { Release(); }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf     = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      Release();
      m_ma_fast    = MathMax(2, p.ma_fast);
      m_ma_slow    = MathMax(m_ma_fast + 1, p.ma_slow);
      m_atr_period = MathMax(2, p.atr_period);
      m_adx_period = MathMax(2, p.adx_period);
      m_adx_min    = p.adx_trend_threshold;
      m_sl_mult    = MathMax(0.2, p.trend_sl_atr_mult);
      m_tp_mult    = MathMax(0.2, p.trend_tp_atr_mult);

      m_ma_fast_h = iMA(m_symbol, m_tf, m_ma_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_ma_slow_h = iMA(m_symbol, m_tf, m_ma_slow, 0, MODE_EMA, PRICE_CLOSE);
      m_atr_h     = iATR(m_symbol, m_tf, m_atr_period);
      m_adx_h     = iADX(m_symbol, m_tf, m_adx_period);

      if(m_ma_fast_h == INVALID_HANDLE || m_ma_slow_h == INVALID_HANDLE ||
         m_atr_h == INVALID_HANDLE || m_adx_h == INVALID_HANDLE)
        {
         Print("CTrendStrategy: 指标句柄失败");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_ma_fast_h != INVALID_HANDLE) { IndicatorRelease(m_ma_fast_h); m_ma_fast_h = INVALID_HANDLE; }
      if(m_ma_slow_h != INVALID_HANDLE) { IndicatorRelease(m_ma_slow_h); m_ma_slow_h = INVALID_HANDLE; }
      if(m_atr_h != INVALID_HANDLE)     { IndicatorRelease(m_atr_h);     m_atr_h = INVALID_HANDLE; }
      if(m_adx_h != INVALID_HANDLE)     { IndicatorRelease(m_adx_h);     m_adx_h = INVALID_HANDLE; }
     }

   SSignalResult Evaluate(void)
     {
      SSignalResult r;
      InitSignal(r);
      r.symbol = m_symbol;

      datetime bar = iTime(m_symbol, m_tf, 0);
      if(bar == m_last_signal_bar)
         return r;

      double ma_f[], ma_s[], atr[], adx[], plus_di[], minus_di[];
      if(!CopyBuf(m_ma_fast_h, 0, 5, ma_f) ||
         !CopyBuf(m_ma_slow_h, 0, 5, ma_s) ||
         !CopyBuf(m_atr_h, 0, 3, atr) ||
         !CopyBuf(m_adx_h, 0, 3, adx) ||
         !CopyBuf(m_adx_h, 1, 3, plus_di) ||
         !CopyBuf(m_adx_h, 2, 3, minus_di))
         return r;

      const bool cross_up   = (ma_f[2] <= ma_s[2] && ma_f[1] > ma_s[1]);
      const bool cross_down = (ma_f[2] >= ma_s[2] && ma_f[1] < ma_s[1]);

      if(!cross_up && !cross_down)
        {
         r.reason = "等待趋势交叉";
         return r;
        }
      if(adx[1] < m_adx_min)
        {
         r.reason = "ADX不足，跳过低质量趋势";
         return r;
        }

      const double atr_v = atr[1];
      if(atr_v <= 0.0)
         return r;

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return r;

      // 质量评分：ADX 强度、DI 方向一致、均线分离、交叉后动量
      int q = 40;
      if(adx[1] >= m_adx_min + 5.0)  q += 15;
      else if(adx[1] >= m_adx_min)   q += 8;
      if(adx[1] > adx[2])            q += 10; // ADX 上升

      const double sep = MathAbs(ma_f[1] - ma_s[1]);
      if(sep > atr_v * 0.3)          q += 10;
      if(sep > atr_v * 0.6)          q += 5;

      if(cross_up)
        {
         if(plus_di[1] > minus_di[1]) q += 15;
         if(ma_f[1] > ma_f[2])        q += 5;
         r.signal = SIGNAL_BUY;
         r.entry  = tick.ask;
         r.sl     = NormalizePrice(r.entry - atr_v * m_sl_mult);
         r.tp     = NormalizePrice(r.entry + atr_v * m_tp_mult);
         r.atr    = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("趋势多 EMA交叉 ADX=%.1f Q=%d", adx[1], r.quality);
         m_last_signal_bar = bar;
        }
      else if(cross_down)
        {
         if(minus_di[1] > plus_di[1]) q += 15;
         if(ma_f[1] < ma_f[2])        q += 5;
         r.signal = SIGNAL_SELL;
         r.entry  = tick.bid;
         r.sl     = NormalizePrice(r.entry + atr_v * m_sl_mult);
         r.tp     = NormalizePrice(r.entry - atr_v * m_tp_mult);
         r.atr    = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("趋势空 EMA交叉 ADX=%.1f Q=%d", adx[1], r.quality);
         m_last_signal_bar = bar;
        }
      return r;
     }
  };

#endif
//+------------------------------------------------------------------+
