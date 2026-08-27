//+------------------------------------------------------------------+
//| SevenConditionStrategy.mqh — 七条件 + 回调入场 + ADX + 结构止损     |
//| v3.1: 趋势回调优于突破追涨；ADX/延伸过滤；结构SL + 最低盈亏比       |
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
   int               m_ema_f_h, m_ema_s_h, m_atr_h, m_rsi_h, m_adx_h;
   int               m_htf_f_h, m_htf_s_h;
   int               m_ema_fast, m_ema_slow, m_atr_period, m_rsi_period, m_adx_period;
   double            m_min_gap_atr;
   int               m_break_bars;
   double            m_break_buf;
   double            m_rsi_l_lo, m_rsi_l_hi, m_rsi_s_lo, m_rsi_s_hi;
   bool              m_use_htf;
   int               m_htf_fast, m_htf_slow;
   double            m_sl_atr, m_tp_atr, m_sl_atr_max;
   double            m_min_adx, m_max_ext_atr, m_min_rr;
   bool              m_use_pullback;
   int               m_pullback_bars, m_swing_sl_bars;
   int               m_min_bars;
   datetime          m_last_bar;
   SSevenCondSnapshot m_last_snap;

   bool CopyBuf(const int h, const int buf, const int cnt, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(h, buf, 0, cnt, out) >= cnt);
     }

   // 回调：近 N 根回踩快EMA区域后，收盘重新站回趋势侧
   bool CheckPullbackLong(const double &close[], const double &open[],
                          const double &high[], const double &low[],
                          const double &ema_f[], const double &ema_s[],
                          const double atr_v) const
     {
      bool touched = false;
      const int last = MathMax(2, m_pullback_bars);
      for(int i=2; i<=last+1; ++i)
        {
         const double zone_top = ema_f[i] + atr_v * 0.25;
         const double zone_bot = MathMin(ema_f[i], ema_s[i]) - atr_v * 0.15;
         if(low[i] <= zone_top && low[i] >= zone_bot - atr_v * 0.5)
            touched = true;
        }
      const bool bounce = (close[1] > ema_f[1] && close[1] > open[1]);
      const bool hold   = (close[1] > ema_s[1]);
      return (touched && bounce && hold);
     }

   bool CheckPullbackShort(const double &close[], const double &open[],
                           const double &high[], const double &low[],
                           const double &ema_f[], const double &ema_s[],
                           const double atr_v) const
     {
      bool touched = false;
      const int last = MathMax(2, m_pullback_bars);
      for(int i=2; i<=last+1; ++i)
        {
         const double zone_bot = ema_f[i] - atr_v * 0.25;
         const double zone_top = MathMax(ema_f[i], ema_s[i]) + atr_v * 0.15;
         if(high[i] >= zone_bot && high[i] <= zone_top + atr_v * 0.5)
            touched = true;
        }
      const bool bounce = (close[1] < ema_f[1] && close[1] < open[1]);
      const bool hold   = (close[1] < ema_s[1]);
      return (touched && bounce && hold);
     }

   // 突破：收盘突破近 N 根高/低 + 缓冲，且前一根未过度延伸
   bool CheckBreakoutLong(const double &close[], const double &high[],
                          const double &low[], const double atr_v) const
     {
      double hh = high[2];
      for(int i=3; i<=m_break_bars+1; ++i)
         if(high[i] > hh) hh = high[i];
      return (close[1] > hh + atr_v * m_break_buf);
     }

   bool CheckBreakoutShort(const double &close[], const double &high[],
                           const double &low[], const double atr_v) const
     {
      double ll = low[2];
      for(int i=3; i<=m_break_bars+1; ++i)
         if(low[i] < ll) ll = low[i];
      return (close[1] < ll - atr_v * m_break_buf);
     }

   // 3 根中至少 2 根收盘沿趋势方向 + 当前棒实体同向
   bool CheckMomentumLong(const double &close[], const double &open[]) const
     {
      int up = 0;
      for(int i=1; i<=3; ++i)
         if(close[i] > close[i+1]) up++;
      return (up >= 2 && close[1] > open[1]);
     }

   bool CheckMomentumShort(const double &close[], const double &open[]) const
     {
      int down = 0;
      for(int i=1; i<=3; ++i)
         if(close[i] < close[i+1]) down++;
      return (down >= 2 && close[1] < open[1]);
     }

   // 结构止损：摆动高/低 + ATR 缓冲，并限制最大距离
   double CalcStopLong(const double entry, const double &low[], const double atr_v) const
     {
      double swing = low[1];
      for(int i=2; i<=m_swing_sl_bars+1; ++i)
         if(low[i] < swing) swing = low[i];
      double sl = swing - atr_v * 0.12;
      const double max_dist = atr_v * m_sl_atr_max;
      const double min_dist = atr_v * MathMax(0.5, m_sl_atr * 0.7);
      if(entry - sl > max_dist) sl = entry - max_dist;
      if(entry - sl < min_dist) sl = entry - min_dist;
      return NormalizePriceSym(sl, m_symbol);
     }

   double CalcStopShort(const double entry, const double &high[], const double atr_v) const
     {
      double swing = high[1];
      for(int i=2; i<=m_swing_sl_bars+1; ++i)
         if(high[i] > swing) swing = high[i];
      double sl = swing + atr_v * 0.12;
      const double max_dist = atr_v * m_sl_atr_max;
      const double min_dist = atr_v * MathMax(0.5, m_sl_atr * 0.7);
      if(sl - entry > max_dist) sl = entry + max_dist;
      if(sl - entry < min_dist) sl = entry + min_dist;
      return NormalizePriceSym(sl, m_symbol);
     }

   double CalcTakeProfitLong(const double entry, const double sl, const double atr_v) const
     {
      const double risk = entry - sl;
      double tp = entry + atr_v * m_tp_atr;
      if(risk > 0.0 && m_min_rr > 0.0)
        {
         const double rr_tp = entry + risk * m_min_rr;
         if(rr_tp > tp) tp = rr_tp;
        }
      return NormalizePriceSym(tp, m_symbol);
     }

   double CalcTakeProfitShort(const double entry, const double sl, const double atr_v) const
     {
      const double risk = sl - entry;
      double tp = entry - atr_v * m_tp_atr;
      if(risk > 0.0 && m_min_rr > 0.0)
        {
         const double rr_tp = entry - risk * m_min_rr;
         if(rr_tp < tp) tp = rr_tp;
        }
      return NormalizePriceSym(tp, m_symbol);
     }

public:
                     CSevenConditionStrategy(void)
                       : m_symbol(_Symbol), m_tf(PERIOD_CURRENT),
                         m_ema_f_h(INVALID_HANDLE), m_ema_s_h(INVALID_HANDLE),
                         m_atr_h(INVALID_HANDLE), m_rsi_h(INVALID_HANDLE),
                         m_adx_h(INVALID_HANDLE),
                         m_htf_f_h(INVALID_HANDLE), m_htf_s_h(INVALID_HANDLE),
                         m_ema_fast(89), m_ema_slow(233), m_atr_period(14),
                         m_rsi_period(14), m_adx_period(14),
                         m_min_gap_atr(0.25), m_break_bars(12), m_break_buf(0.08),
                         m_rsi_l_lo(45), m_rsi_l_hi(58), m_rsi_s_lo(42), m_rsi_s_hi(55),
                         m_use_htf(true), m_htf_fast(50), m_htf_slow(200),
                         m_sl_atr(1.2), m_tp_atr(2.8), m_sl_atr_max(1.8),
                         m_min_adx(22.0), m_max_ext_atr(1.3), m_min_rr(1.8),
                         m_use_pullback(true), m_pullback_bars(4), m_swing_sl_bars(8),
                         m_min_bars(300), m_last_bar(0)
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
      m_adx_period = MathMax(2, p.adx_period);
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
      m_sl_atr_max = MathMax(m_sl_atr, p.sc_sl_atr_max);
      m_min_adx    = MathMax(10.0, p.sc_min_adx);
      m_max_ext_atr= MathMax(0.3, p.sc_max_ext_atr);
      m_min_rr     = MathMax(1.0, p.sc_min_rr);
      m_use_pullback = p.sc_use_pullback;
      m_pullback_bars = MathMax(2, p.sc_pullback_bars);
      m_swing_sl_bars = MathMax(3, p.sc_swing_sl_bars);
      m_min_bars   = MathMax(m_ema_slow + 20, p.min_bars_required);

      m_ema_f_h = iMA(m_symbol, m_tf, m_ema_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_ema_s_h = iMA(m_symbol, m_tf, m_ema_slow, 0, MODE_EMA, PRICE_CLOSE);
      m_atr_h   = iATR(m_symbol, m_tf, m_atr_period);
      m_rsi_h   = iRSI(m_symbol, m_tf, m_rsi_period, PRICE_CLOSE);
      m_adx_h   = iADX(m_symbol, m_tf, m_adx_period);
      if(m_use_htf)
        {
         m_htf_f_h = iMA(m_symbol, PERIOD_H1, m_htf_fast, 0, MODE_EMA, PRICE_CLOSE);
         m_htf_s_h = iMA(m_symbol, PERIOD_H1, m_htf_slow, 0, MODE_EMA, PRICE_CLOSE);
        }
      if(m_ema_f_h==INVALID_HANDLE || m_ema_s_h==INVALID_HANDLE ||
         m_atr_h==INVALID_HANDLE || m_rsi_h==INVALID_HANDLE || m_adx_h==INVALID_HANDLE)
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
      if(m_adx_h!=INVALID_HANDLE){ IndicatorRelease(m_adx_h); m_adx_h=INVALID_HANDLE; }
      if(m_htf_f_h!=INVALID_HANDLE){ IndicatorRelease(m_htf_f_h); m_htf_f_h=INVALID_HANDLE; }
      if(m_htf_s_h!=INVALID_HANDLE){ IndicatorRelease(m_htf_s_h); m_htf_s_h=INVALID_HANDLE; }
     }

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

      const int need = MathMax(m_break_bars + 5, m_swing_sl_bars + 5);
      double ema_f[], ema_s[], atr[], rsi[], adx[], plus_di[], minus_di[];
      double close[], open[], high[], low[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      if(!CopyBuf(m_ema_f_h, 0, need, ema_f) ||
         !CopyBuf(m_ema_s_h, 0, need, ema_s) ||
         !CopyBuf(m_atr_h, 0, 5, atr) ||
         !CopyBuf(m_rsi_h, 0, 5, rsi) ||
         !CopyBuf(m_adx_h, 0, 5, adx) ||
         !CopyBuf(m_adx_h, 1, 5, plus_di) ||
         !CopyBuf(m_adx_h, 2, 5, minus_di) ||
         CopyClose(m_symbol, m_tf, 0, need, close) < need ||
         CopyOpen(m_symbol, m_tf, 0, need, open) < need ||
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
      m_last_snap.adx = adx[1];
      m_last_snap.ema_gap_atr = SafeDiv(MathAbs(ema_f[1] - ema_s[1]), atr_v, 0.0);

      const bool bull_trend = (ema_f[1] > ema_s[1]);
      const bool bear_trend = (ema_f[1] < ema_s[1]);

      m_last_snap.ema_trend = (bull_trend || bear_trend);
      m_last_snap.ema_strength = (m_last_snap.ema_gap_atr >= m_min_gap_atr);

      ENUM_SIGNAL dir = SIGNAL_NONE;
      if(bull_trend) dir = SIGNAL_BUY;
      else if(bear_trend) dir = SIGNAL_SELL;

      if(dir == SIGNAL_BUY)
         m_last_snap.price_pos = (close[1] > ema_f[1] && close[1] > ema_s[1]);
      else if(dir == SIGNAL_SELL)
         m_last_snap.price_pos = (close[1] < ema_f[1] && close[1] < ema_s[1]);
      else
         m_last_snap.price_pos = false;

      // C4 入场触发：回调（默认）或突破
      if(dir == SIGNAL_BUY)
         m_last_snap.breakout = m_use_pullback
            ? CheckPullbackLong(close, open, high, low, ema_f, ema_s, atr_v)
            : CheckBreakoutLong(close, high, low, atr_v);
      else if(dir == SIGNAL_SELL)
         m_last_snap.breakout = m_use_pullback
            ? CheckPullbackShort(close, open, high, low, ema_f, ema_s, atr_v)
            : CheckBreakoutShort(close, high, low, atr_v);
      else
         m_last_snap.breakout = false;

      // C5 RSI：健康区（收紧，避免超买/超卖追单）
      if(dir == SIGNAL_BUY)
         m_last_snap.rsi_ok = (rsi[1] >= m_rsi_l_lo && rsi[1] <= m_rsi_l_hi);
      else if(dir == SIGNAL_SELL)
         m_last_snap.rsi_ok = (rsi[1] >= m_rsi_s_lo && rsi[1] <= m_rsi_s_hi);
      else
         m_last_snap.rsi_ok = false;

      // C6 动量：多棒确认
      if(dir == SIGNAL_BUY)
         m_last_snap.momentum = CheckMomentumLong(close, open);
      else if(dir == SIGNAL_SELL)
         m_last_snap.momentum = CheckMomentumShort(close, open);
      else
         m_last_snap.momentum = false;

      // C7 HTF
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

      // C8 ADX + DI 方向
      if(dir == SIGNAL_BUY)
         m_last_snap.adx_ok = (adx[1] >= m_min_adx && plus_di[1] > minus_di[1] && adx[1] >= adx[2]);
      else if(dir == SIGNAL_SELL)
         m_last_snap.adx_ok = (adx[1] >= m_min_adx && minus_di[1] > plus_di[1] && adx[1] >= adx[2]);
      else
         m_last_snap.adx_ok = false;

      // C9 延伸过滤：不在远离均线的极端位置开仓
      if(dir == SIGNAL_BUY)
        {
         m_last_snap.ext_atr = SafeDiv(close[1] - ema_f[1], atr_v, 99.0);
         m_last_snap.not_extended = (m_last_snap.ext_atr >= 0.0 && m_last_snap.ext_atr <= m_max_ext_atr);
        }
      else if(dir == SIGNAL_SELL)
        {
         m_last_snap.ext_atr = SafeDiv(ema_f[1] - close[1], atr_v, 99.0);
         m_last_snap.not_extended = (m_last_snap.ext_atr >= 0.0 && m_last_snap.ext_atr <= m_max_ext_atr);
        }
      else
        {
         m_last_snap.ext_atr = 0.0;
         m_last_snap.not_extended = false;
        }

      if(!m_last_snap.ema_trend)      { m_last_snap.fail_reason="C1 EMA趋势"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.ema_strength)   { m_last_snap.fail_reason="C2 趋势强度不足"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.price_pos)      { m_last_snap.fail_reason="C3 价格位置"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.breakout)       { m_last_snap.fail_reason=m_use_pullback?"C4 回调未确认":"C4 突破未确认"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.rsi_ok)         { m_last_snap.fail_reason="C5 RSI区间"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.momentum)       { m_last_snap.fail_reason="C6 动量"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.htf_ok)         { m_last_snap.fail_reason="C7 高周期EMA不一致"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.adx_ok)         { m_last_snap.fail_reason="C8 ADX/DI不足"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }
      if(!m_last_snap.not_extended)   { m_last_snap.fail_reason="C9 价格过度延伸"; r.reason=m_last_snap.fail_reason; r.seven=m_last_snap; return r; }

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
        {
         r.reason = "Tick失败";
         return r;
        }

      r.signal = dir;
      r.atr = atr_v;
      r.quality = 78;
      if(m_last_snap.ema_gap_atr >= m_min_gap_atr * 1.5) r.quality += 6;
      if(adx[1] >= m_min_adx + 5.0) r.quality += 8;
      if(m_last_snap.ext_atr <= m_max_ext_atr * 0.6) r.quality += 6;
      if(m_use_pullback) r.quality += 4;
      r.quality = MathMin(100, r.quality);

      if(dir == SIGNAL_BUY)
        {
         r.entry = tick.ask;
         r.sl = CalcStopLong(r.entry, low, atr_v);
         r.tp = CalcTakeProfitLong(r.entry, r.sl, atr_v);
         r.reason = StringFormat("回调多 ADX=%.1f ext=%.2f gapATR=%.2f RSI=%.1f",
                                 adx[1], m_last_snap.ext_atr, m_last_snap.ema_gap_atr, rsi[1]);
        }
      else
        {
         r.entry = tick.bid;
         r.sl = CalcStopShort(r.entry, high, atr_v);
         r.tp = CalcTakeProfitShort(r.entry, r.sl, atr_v);
         r.reason = StringFormat("回调空 ADX=%.1f ext=%.2f gapATR=%.2f RSI=%.1f",
                                 adx[1], m_last_snap.ext_atr, m_last_snap.ema_gap_atr, rsi[1]);
        }

      r.seven = m_last_snap;
      m_last_bar = bar;
      return r;
     }
  };

#endif
//+------------------------------------------------------------------+
