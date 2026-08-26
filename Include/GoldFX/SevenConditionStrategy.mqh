//+------------------------------------------------------------------+
//| SevenConditionStrategy.mqh — 七条件缺一不可入场引擎                 |
//| 1 EMA趋势 2 间距强度 3 价格位置 4 突破 5 RSI 6 动量 7 HTF可选       |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_SEVEN_CONDITION_MQH
#define GOLDFX_SEVEN_CONDITION_MQH

#include "Common.mqh"

class CSevenConditionStrategy
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_ema_f_h, m_ema_s_h, m_atr_h, m_rsi_h;
   int               m_htf_f_h, m_htf_s_h;
   int               m_ema_fast, m_ema_slow, m_atr_period, m_rsi_period;
   double            m_min_gap_atr;
   int               m_break_bars;
   double            m_break_buf;
   double            m_rsi_l_lo, m_rsi_l_hi, m_rsi_s_lo, m_rsi_s_hi;
   bool              m_use_htf;
   int               m_htf_fast, m_htf_slow;
   double            m_sl_atr, m_tp_atr;
   int               m_min_bars;
   datetime          m_last_bar;
   SSevenCondSnapshot m_last_snap;

   bool CopyBuf(const int h, const int buf, const int cnt, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(h, buf, 0, cnt, out) >= cnt);
     }

public:
                     CSevenConditionStrategy(void)
                       : m_symbol(_Symbol), m_tf(PERIOD_CURRENT),
                         m_ema_f_h(INVALID_HANDLE), m_ema_s_h(INVALID_HANDLE),
                         m_atr_h(INVALID_HANDLE), m_rsi_h(INVALID_HANDLE),
                         m_htf_f_h(INVALID_HANDLE), m_htf_s_h(INVALID_HANDLE),
                         m_ema_fast(150), m_ema_slow(510), m_atr_period(14), m_rsi_period(14),
                         m_min_gap_atr(0.35), m_break_bars(20), m_break_buf(0.1),
                         m_rsi_l_lo(40), m_rsi_l_hi(65), m_rsi_s_lo(35), m_rsi_s_hi(60),
                         m_use_htf(true), m_htf_fast(50), m_htf_slow(200),
                         m_sl_atr(1.5), m_tp_atr(2.0), m_min_bars(520), m_last_bar(0)
                     {
                      ZeroMemory(m_last_snap);
                     }

                    ~CSevenConditionStrategy(void) { Release(); }

   SSevenCondSnapshot LastSnapshot(void) const { return m_last_snap; }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      Release();
      m_ema_fast   = MathMax(2, p.sc_ema_fast);
      m_ema_slow   = MathMax(m_ema_fast+1, p.sc_ema_slow);
      m_atr_period = MathMax(2, p.atr_period);
      m_rsi_period = MathMax(2, p.rsi_period);
      m_min_gap_atr= MathMax(0.05, p.sc_min_gap_atr);
      m_break_bars = MathMax(3, p.sc_breakout_bars);
      m_break_buf  = MathMax(0.0, p.sc_breakout_atr_buf);
      m_rsi_l_lo   = p.sc_rsi_long_lo;
      m_rsi_l_hi   = p.sc_rsi_long_hi;
      m_rsi_s_lo   = p.sc_rsi_short_lo;
      m_rsi_s_hi   = p.sc_rsi_short_hi;
      m_use_htf    = p.sc_use_htf;
      m_htf_fast   = MathMax(2, p.sc_htf_fast);
      m_htf_slow   = MathMax(m_htf_fast+1, p.sc_htf_slow);
      m_sl_atr     = MathMax(0.2, p.sc_sl_atr);
      m_tp_atr     = MathMax(0.2, p.sc_tp_atr);
      m_min_bars   = MathMax(m_ema_slow + 20, p.min_bars_required);

      m_ema_f_h = iMA(m_symbol, m_tf, m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_ema_s_h = iMA(m_symbol, m_tf, m_ema_slow, 0, MODE_EMA, PRICE_CLOSE);
      m_atr_h   = iATR(m_symbol, m_tf, m_atr_period);
      m_rsi_h   = iRSI(m_symbol, m_tf, m_rsi_period, PRICE_CLOSE);
      if(m_use_htf)
        {
         m_htf_f_h = iMA(m_symbol, PERIOD_H1, m_htf_fast, 0, MODE_EMA, PRICE_CLOSE);
         m_htf_s_h = iMA(m_symbol, PERIOD_H1, m_htf_slow, 0, MODE_EMA, PRICE_CLOSE);
        }
      if(m_ema_f_h==INVALID_HANDLE || m_ema_s_h==INVALID_HANDLE ||
         m_atr_h==INVALID_HANDLE || m_rsi_h==INVALID_HANDLE)
        {
         Print("CSevenConditionStrategy: 指标失败 ", m_symbol);
         return false;
        }
      if(m_use_htf && (m_htf_f_h==INVALID_HANDLE || m_htf_s_h==INVALID_HANDLE))
        {
         Print("CSevenConditionStrategy: HTF 指标失败 ", m_symbol);
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_ema_f_h!=INVALID_HANDLE){ IndicatorRelease(m_ema_f_h); m_ema_f_h=INVALID_HANDLE; }
      if(m_ema_s_h!=INVALID_HANDLE){ IndicatorRelease(m_ema_s_h); m_ema_s_h=INVALID_HANDLE; }
      if(m_atr_h!=INVALID_HANDLE){ IndicatorRelease(m_atr_h); m_atr_h=INVALID_HANDLE; }
      if(m_rsi_h!=INVALID_HANDLE){ IndicatorRelease(m_rsi_h); m_rsi_h=INVALID_HANDLE; }
      if(m_htf_f_h!=INVALID_HANDLE){ IndicatorRelease(m_htf_f_h); m_htf_f_h=INVALID_HANDLE; }
      if(m_htf_s_h!=INVALID_HANDLE){ IndicatorRelease(m_htf_s_h); m_htf_s_h=INVALID_HANDLE; }
     }

   // 最小 K 线保护（OnTick 也应先检查）
   bool BarsReady(string &why) const
     {
      const int bars = Bars(m_symbol, m_tf);
      if(bars < m_min_bars)
        {
         why = StringFormat("%s K线不足 %d<%d", m_symbol, bars, m_min_bars);
         return false;
        }
      why = "";
      return true;
     }

   SSignalResult Evaluate(const bool new_bar_only = true)
     {
      SSignalResult r;
      InitSignal(r);
      r.symbol = m_symbol;
      ZeroMemory(m_last_snap);
      m_last_snap.fail_reason = "";

      string why;
      if(!BarsReady(why))
        {
         r.reason = why;
         m_last_snap.fail_reason = why;
         return r;
        }

      datetime bar = iTime(m_symbol, m_tf, 0);
      if(new_bar_only && bar == m_last_bar)
         return r;

      const int need = MathMax(m_break_bars + 5, 5);
      double ema_f[], ema_s[], atr[], rsi[], close[], high[], low[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      if(!CopyBuf(m_ema_f_h, 0, need, ema_f) ||
         !CopyBuf(m_ema_s_h, 0, need, ema_s) ||
         !CopyBuf(m_atr_h, 0, 5, atr) ||
         !CopyBuf(m_rsi_h, 0, 5, rsi) ||
         CopyClose(m_symbol, m_tf, 0, need, close) < need ||
         CopyHigh(m_symbol, m_tf, 0, need, high) < need ||
         CopyLow(m_symbol, m_tf, 0, need, low) < need)
        {
         r.reason = "指标复制失败";
         return r;
        }

      const double atr_v = atr[1];
      if(atr_v <= 0.0)
        {
         r.reason = "ATR无效";
         return r;
        }

      m_last_snap.ema_fast = ema_f[1];
      m_last_snap.ema_slow = ema_s[1];
      m_last_snap.rsi = rsi[1];
      m_last_snap.atr = atr_v;
      m_last_snap.ema_gap_atr = SafeDiv(MathAbs(ema_f[1] - ema_s[1]), atr_v, 0.0);

      // 方向候选：由 EMA 趋势决定
      const bool bull_trend = (ema_f[1] > ema_s[1]);
      const bool bear_trend = (ema_f[1] < ema_s[1]);

      // Cond1 EMA 趋势
      m_last_snap.ema_trend = (bull_trend || bear_trend);
      // Cond2 强度
      m_last_snap.ema_strength = (m_last_snap.ema_gap_atr >= m_min_gap_atr);

      ENUM_SIGNAL dir = SIGNAL_NONE;
      if(bull_trend) dir = SIGNAL_BUY;
      else if(bear_trend) dir = SIGNAL_SELL;

      // Cond3 价格位置
      if(dir == SIGNAL_BUY)
         m_last_snap.price_pos = (close[1] > ema_f[1] && close[1] > ema_s[1]);
      else if(dir == SIGNAL_SELL)
         m_last_snap.price_pos = (close[1] < ema_f[1] && close[1] < ema_s[1]);
      else
         m_last_snap.price_pos = false;

      // Cond4 突破：收盘突破近 N 根高/低 + ATR 缓冲（不含当前形成棒，用 [2..N+1]）
      double hh = high[2], ll = low[2];
      for(int i=3; i<=m_break_bars+1; ++i)
        {
         if(high[i] > hh) hh = high[i];
         if(low[i] < ll)  ll = low[i];
        }
      if(dir == SIGNAL_BUY)
         m_last_snap.breakout = (close[1] > hh + atr_v * m_break_buf);
      else if(dir == SIGNAL_SELL)
         m_last_snap.breakout = (close[1] < ll - atr_v * m_break_buf);
      else
         m_last_snap.breakout = false;

      // Cond5 RSI 健康区
      if(dir == SIGNAL_BUY)
         m_last_snap.rsi_ok = (rsi[1] >= m_rsi_l_lo && rsi[1] <= m_rsi_l_hi);
      else if(dir == SIGNAL_SELL)
         m_last_snap.rsi_ok = (rsi[1] >= m_rsi_s_lo && rsi[1] <= m_rsi_s_hi);
      else
         m_last_snap.rsi_ok = false;

      // Cond6 动量
      if(dir == SIGNAL_BUY)
         m_last_snap.momentum = (close[1] > close[2]);
      else if(dir == SIGNAL_SELL)
         m_last_snap.momentum = (close[1] < close[2]);
      else
         m_last_snap.momentum = false;

      // Cond7 HTF
      m_last_snap.htf_ok = true;
      if(m_use_htf)
        {
         double hf[], hs[];
         if(!CopyBuf(m_htf_f_h, 0, 3, hf) || !CopyBuf(m_htf_s_h, 0, 3, hs))
            m_last_snap.htf_ok = false;
         else if(dir == SIGNAL_BUY)
            m_last_snap.htf_ok = (hf[1] > hs[1]);
         else if(dir == SIGNAL_SELL)
            m_last_snap.htf_ok = (hf[1] < hs[1]);
        }

      // 缺一不可
      if(!m_last_snap.ema_trend)      { m_last_snap.fail_reason="C1 EMA趋势"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.ema_strength)   { m_last_snap.fail_reason="C2 趋势强度不足"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.price_pos)      { m_last_snap.fail_reason="C3 价格位置"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.breakout)       { m_last_snap.fail_reason="C4 突破未确认"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.rsi_ok)         { m_last_snap.fail_reason="C5 RSI区间"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.momentum)       { m_last_snap.fail_reason="C6 动量"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.htf_ok)         { m_last_snap.fail_reason="C7 高周期EMA不一致"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
        {
         r.reason = "Tick失败";
         return r;
        }

      r.signal = dir;
      r.atr = atr_v;
      r.quality = 85;
      // 间距越大、突破越干净 → 质量加分
      if(m_last_snap.ema_gap_atr >= m_min_gap_atr * 1.5) r.quality += 8;
      if(m_last_snap.ema_gap_atr >= m_min_gap_atr * 2.0) r.quality += 5;
      r.quality = MathMin(100, r.quality);

      if(dir == SIGNAL_BUY)
        {
         r.entry = tick.ask;
         r.sl = NormalizePriceSym(r.entry - atr_v * m_sl_atr, m_symbol);
         r.tp = NormalizePriceSym(r.entry + atr_v * m_tp_atr, m_symbol);
         r.reason = StringFormat("七条件多 gapATR=%.2f RSI=%.1f", m_last_snap.ema_gap_atr, rsi[1]);
        }
      else
        {
         r.entry = tick.bid;
         r.sl = NormalizePriceSym(r.entry + atr_v * m_sl_atr, m_symbol);
         r.tp = NormalizePriceSym(r.entry - atr_v * m_tp_atr, m_symbol);
         r.reason = StringFormat("七条件空 gapATR=%.2f RSI=%.1f", m_last_snap.ema_gap_atr, rsi[1]);
        }

      r.seven = m_last_snap;
      m_last_bar = bar;
      return r;
     }
  };

#endif
//+------------------------------------------------------------------+
