//+------------------------------------------------------------------+
//| BoxBreakoutStrategy.mqh — with-trend small-box breakout          |
//+------------------------------------------------------------------+
#ifndef GOLDFX_BOX_BREAKOUT_STRATEGY_MQH
#define GOLDFX_BOX_BREAKOUT_STRATEGY_MQH

#include "Common.mqh"

class CBoxBreakoutStrategy
  {
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int m_ema_fast_h;
   int m_ema_slow_h;
   int m_htf_fast_h;
   int m_htf_slow_h;
   int m_atr_h;
   int m_adx_h;

   int    m_lookback;
   int    m_min_bars;
   double m_width_min_atr;
   double m_width_max_atr;
   double m_break_buf_atr;
   int    m_ema_fast;
   int    m_ema_slow;
   double m_min_adx;
   double m_sl_buf_atr;
   double m_tp_height_mult;
   double m_min_rr;
   bool   m_use_htf;
   int    m_htf_fast;
   int    m_htf_slow;
   int    m_atr_period;
   int    m_adx_period;
   int    m_touch_min;

   datetime m_last_signal_bar;
   bool     m_need_rebuild;
   double   m_fired_high;
   double   m_fired_low;
   string   m_status;

   bool CopyBuf(const int handle, const int buf, const int count, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(handle, buf, 0, count, out) >= count);
     }

   void ReleaseHandles(void)
     {
      if(m_ema_fast_h != INVALID_HANDLE) { IndicatorRelease(m_ema_fast_h); m_ema_fast_h = INVALID_HANDLE; }
      if(m_ema_slow_h != INVALID_HANDLE) { IndicatorRelease(m_ema_slow_h); m_ema_slow_h = INVALID_HANDLE; }
      if(m_htf_fast_h != INVALID_HANDLE) { IndicatorRelease(m_htf_fast_h); m_htf_fast_h = INVALID_HANDLE; }
      if(m_htf_slow_h != INVALID_HANDLE) { IndicatorRelease(m_htf_slow_h); m_htf_slow_h = INVALID_HANDLE; }
      if(m_atr_h != INVALID_HANDLE)      { IndicatorRelease(m_atr_h);      m_atr_h = INVALID_HANDLE; }
      if(m_adx_h != INVALID_HANDLE)      { IndicatorRelease(m_adx_h);      m_adx_h = INVALID_HANDLE; }
     }

   int TrendBias(const double &ema_f[], const double &ema_s[],
                 const double &plus_di[], const double &minus_di[],
                 const double adx_v) const
     {
      if(adx_v < m_min_adx)
         return 0;
      const bool bull = (ema_f[1] > ema_s[1] && plus_di[1] >= minus_di[1]);
      const bool bear = (ema_f[1] < ema_s[1] && minus_di[1] >= plus_di[1]);
      if(bull) return 1;
      if(bear) return -1;
      return 0;
     }

   bool HtfAgrees(const int bias)
     {
      if(!m_use_htf)
         return true;
      if(m_htf_fast_h == INVALID_HANDLE || m_htf_slow_h == INVALID_HANDLE)
         return false;
      double hf[], hs[];
      if(!CopyBuf(m_htf_fast_h, 0, 3, hf) || !CopyBuf(m_htf_slow_h, 0, 3, hs))
         return false;
      if(bias > 0) return (hf[1] > hs[1]);
      if(bias < 0) return (hf[1] < hs[1]);
      return false;
     }

   bool BuildBox(const double &high[], const double &low[], const double &close[],
                 const double atr_v, double &box_hi, double &box_lo, double &box_h,
                 int &inside_n, int &touch_up, int &touch_dn) const
     {
      box_hi = high[2];
      box_lo = low[2];
      const int last = m_lookback + 1;
      for(int i=3; i<=last; ++i)
        {
         if(high[i] > box_hi) box_hi = high[i];
         if(low[i]  < box_lo) box_lo = low[i];
        }
      box_h = box_hi - box_lo;
      if(box_h <= 0.0 || atr_v <= 0.0)
         return false;

      const double w = box_h / atr_v;
      if(w < m_width_min_atr || w > m_width_max_atr)
         return false;

      inside_n = 0;
      touch_up = 0;
      touch_dn = 0;
      const double edge = MathMax(atr_v * 0.08, box_h * 0.15);
      for(int i=2; i<=last; ++i)
        {
         if(close[i] <= box_hi && close[i] >= box_lo)
            inside_n++;
         if(high[i] >= box_hi - edge)
            touch_up++;
         if(low[i] <= box_lo + edge)
            touch_dn++;
        }
      if(inside_n < m_min_bars)
         return false;
      if(touch_up < m_touch_min || touch_dn < m_touch_min)
         return false;
      return true;
     }

   bool SameFiredBox(const double box_hi, const double box_lo, const double atr_v) const
     {
      if(!m_need_rebuild)
         return false;
      const double tol = atr_v * 0.15;
      return (MathAbs(box_hi - m_fired_high) <= tol &&
              MathAbs(box_lo - m_fired_low)  <= tol);
     }

   bool IsFreshBox(const double box_hi, const double box_lo, const double atr_v,
                   const double &close[]) const
     {
      if(!m_need_rebuild)
         return true;
      if(SameFiredBox(box_hi, box_lo, atr_v))
         return false;
      int ok = 0;
      for(int i=1; i<=m_min_bars; ++i)
         if(close[i] <= box_hi && close[i] >= box_lo)
            ok++;
      return (ok >= m_min_bars);
     }

public:
   CBoxBreakoutStrategy(void)
     : m_symbol(_Symbol),
       m_tf(PERIOD_CURRENT),
       m_ema_fast_h(INVALID_HANDLE),
       m_ema_slow_h(INVALID_HANDLE),
       m_htf_fast_h(INVALID_HANDLE),
       m_htf_slow_h(INVALID_HANDLE),
       m_atr_h(INVALID_HANDLE),
       m_adx_h(INVALID_HANDLE),
       m_lookback(8),
       m_min_bars(5),
       m_width_min_atr(0.35),
       m_width_max_atr(1.20),
       m_break_buf_atr(0.05),
       m_ema_fast(50),
       m_ema_slow(200),
       m_min_adx(20.0),
       m_sl_buf_atr(0.10),
       m_tp_height_mult(2.0),
       m_min_rr(1.5),
       m_use_htf(true),
       m_htf_fast(50),
       m_htf_slow(200),
       m_atr_period(14),
       m_adx_period(14),
       m_touch_min(1),
       m_last_signal_bar(0),
       m_need_rebuild(false),
       m_fired_high(0.0),
       m_fired_low(0.0),
       m_status("")
     {
     }

   ~CBoxBreakoutStrategy(void) { Release(); }

   string LastStatus(void) const { return m_status; }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SBoxParams &p)
     {
      m_symbol = symbol;
      m_tf = tf;
      return Configure(p);
     }

   bool Configure(const SBoxParams &p)
     {
      ReleaseHandles();
      m_lookback = MathMax(4, p.lookback);
      m_min_bars = MathMax(3, MathMin(m_lookback, p.min_bars));
      m_width_min_atr = MathMax(0.05, p.width_min_atr);
      m_width_max_atr = MathMax(m_width_min_atr + 0.05, p.width_max_atr);
      m_break_buf_atr = MathMax(0.0, p.break_buf_atr);
      m_ema_fast = MathMax(2, p.ema_fast);
      m_ema_slow = MathMax(m_ema_fast + 1, p.ema_slow);
      m_min_adx = MathMax(5.0, p.min_adx);
      m_sl_buf_atr = MathMax(0.0, p.sl_buf_atr);
      m_tp_height_mult = MathMax(0.5, p.tp_height_mult);
      m_min_rr = MathMax(1.0, p.min_rr);
      m_use_htf = p.use_htf;
      m_htf_fast = MathMax(2, p.htf_fast);
      m_htf_slow = MathMax(m_htf_fast + 1, p.htf_slow);
      m_atr_period = MathMax(2, p.atr_period);
      m_adx_period = MathMax(2, p.adx_period);
      m_touch_min = MathMax(1, p.touch_min);

      m_ema_fast_h = iMA(m_symbol, m_tf, m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_ema_slow_h = iMA(m_symbol, m_tf, m_ema_slow, 0, MODE_EMA, PRICE_CLOSE);
      m_atr_h = iATR(m_symbol, m_tf, m_atr_period);
      m_adx_h = iADX(m_symbol, m_tf, m_adx_period);
      if(m_use_htf)
        {
         m_htf_fast_h = iMA(m_symbol, PERIOD_H1, m_htf_fast, 0, MODE_EMA, PRICE_CLOSE);
         m_htf_slow_h = iMA(m_symbol, PERIOD_H1, m_htf_slow, 0, MODE_EMA, PRICE_CLOSE);
        }

      if(m_ema_fast_h == INVALID_HANDLE || m_ema_slow_h == INVALID_HANDLE ||
         m_atr_h == INVALID_HANDLE || m_adx_h == INVALID_HANDLE)
        {
         Print("CBoxBreakoutStrategy: indicator handle failed ", m_symbol);
         return false;
        }
      if(m_use_htf && (m_htf_fast_h == INVALID_HANDLE || m_htf_slow_h == INVALID_HANDLE))
        {
         Print("CBoxBreakoutStrategy: H1 handle failed ", m_symbol);
         return false;
        }
      return true;
     }

   void Release(void) { ReleaseHandles(); }

   SBoxSignal Evaluate(void)
     {
      SBoxSignal r;
      BoxSignalClear(r);
      r.symbol = m_symbol;
      m_status = "";

      const datetime bar = iTime(m_symbol, m_tf, 0);
      if(bar == 0 || bar == m_last_signal_bar)
         return r;

      const int need = m_lookback + 5;
      double ema_f[], ema_s[], atr[], adx[], plus_di[], minus_di[];
      double high[], low[], close[], open[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);

      if(!CopyBuf(m_ema_fast_h, 0, 5, ema_f) ||
         !CopyBuf(m_ema_slow_h, 0, 5, ema_s) ||
         !CopyBuf(m_atr_h, 0, 3, atr) ||
         !CopyBuf(m_adx_h, 0, 3, adx) ||
         !CopyBuf(m_adx_h, 1, 3, plus_di) ||
         !CopyBuf(m_adx_h, 2, 3, minus_di) ||
         CopyHigh(m_symbol, m_tf, 0, need, high) < need ||
         CopyLow(m_symbol, m_tf, 0, need, low) < need ||
         CopyClose(m_symbol, m_tf, 0, need, close) < need ||
         CopyOpen(m_symbol, m_tf, 0, need, open) < need)
        {
         m_status = "data not ready";
         r.reason = m_status;
         return r;
        }

      const double atr_v = atr[1];
      if(atr_v <= 0.0)
        {
         m_status = "ATR invalid";
         r.reason = m_status;
         return r;
        }

      const int bias = TrendBias(ema_f, ema_s, plus_di, minus_di, adx[1]);
      if(bias == 0)
        {
         m_status = "no with-trend bias";
         r.reason = m_status;
         return r;
        }
      if(!HtfAgrees(bias))
        {
         m_status = "H1 disagree";
         r.reason = m_status;
         return r;
        }

      double box_hi=0.0, box_lo=0.0, box_h=0.0;
      int inside_n=0, touch_up=0, touch_dn=0;
      if(!BuildBox(high, low, close, atr_v, box_hi, box_lo, box_h, inside_n, touch_up, touch_dn))
        {
         m_status = StringFormat("wait box bias=%s", bias>0 ? "long" : "short");
         r.reason = m_status;
         return r;
        }

      if(!IsFreshBox(box_hi, box_lo, atr_v, close))
        {
         m_status = "wait next consolidation box";
         r.reason = m_status;
         return r;
        }
      if(m_need_rebuild)
         m_need_rebuild = false;

      const double buf = atr_v * m_break_buf_atr;
      const bool break_up = (close[1] > box_hi + buf);
      const bool break_dn = (close[1] < box_lo - buf);

      if(bias > 0 && break_dn)
        {
         m_need_rebuild = true;
         m_fired_high = box_hi;
         m_fired_low = box_lo;
         m_status = "uptrend lower-break invalidate (no short)";
         r.reason = m_status;
         return r;
        }
      if(bias < 0 && break_up)
        {
         m_need_rebuild = true;
         m_fired_high = box_hi;
         m_fired_low = box_lo;
         m_status = "downtrend upper-break invalidate (no long)";
         r.reason = m_status;
         return r;
        }

      if(!break_up && !break_dn)
        {
         m_status = StringFormat("armed %.2f-%.2f %s", box_lo, box_hi, bias>0?"wait up":"wait dn");
         r.reason = m_status;
         return r;
        }

      if(bias > 0 && !(close[1] > open[1]))
        {
         m_status = "upper break but bearish candle";
         r.reason = m_status;
         return r;
        }
      if(bias < 0 && !(close[1] < open[1]))
        {
         m_status = "lower break but bullish candle";
         r.reason = m_status;
         return r;
        }

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return r;

      int q = 45;
      if(adx[1] >= m_min_adx + 5.0) q += 12;
      else if(adx[1] >= m_min_adx) q += 6;
      if(adx[1] > adx[2]) q += 8;
      const double w = box_h / atr_v;
      if(w >= 0.40 && w <= 0.90) q += 10;
      if(inside_n >= m_min_bars + 2) q += 5;
      if(touch_up >= 2 && touch_dn >= 2) q += 8;
      if(m_use_htf) q += 5;

      if(bias > 0 && break_up)
        {
         r.signal = BOX_SIGNAL_BUY;
         r.entry = tick.ask;
         r.sl = BoxNormPrice(box_lo - atr_v * m_sl_buf_atr, m_symbol);
         double risk = r.entry - r.sl;
         if(risk <= 0.0) risk = atr_v;
         double tp = r.entry + box_h * m_tp_height_mult;
         const double rr_tp = r.entry + risk * m_min_rr;
         if(tp < rr_tp) tp = rr_tp;
         r.tp = BoxNormPrice(tp, m_symbol);
         r.atr = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("with-trend upper-break h=%.2f ADX=%.1f Q=%d", box_h, adx[1], r.quality);
         m_status = r.reason;
         m_need_rebuild = true;
         m_fired_high = box_hi;
         m_fired_low = box_lo;
         m_last_signal_bar = bar;
        }
      else if(bias < 0 && break_dn)
        {
         r.signal = BOX_SIGNAL_SELL;
         r.entry = tick.bid;
         r.sl = BoxNormPrice(box_hi + atr_v * m_sl_buf_atr, m_symbol);
         double risk = r.sl - r.entry;
         if(risk <= 0.0) risk = atr_v;
         double tp = r.entry - box_h * m_tp_height_mult;
         const double rr_tp = r.entry - risk * m_min_rr;
         if(tp > rr_tp) tp = rr_tp;
         r.tp = BoxNormPrice(tp, m_symbol);
         r.atr = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("with-trend lower-break h=%.2f ADX=%.1f Q=%d", box_h, adx[1], r.quality);
         m_status = r.reason;
         m_need_rebuild = true;
         m_fired_high = box_hi;
         m_fired_low = box_lo;
         m_last_signal_bar = bar;
        }
      else
        {
         m_status = "bias/break mismatch";
         r.reason = m_status;
        }
      return r;
     }
  };

#endif
