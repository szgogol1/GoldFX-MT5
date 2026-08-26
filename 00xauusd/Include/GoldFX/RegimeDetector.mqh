//+------------------------------------------------------------------+
//| RegimeDetector.mqh — 趋势 / 震荡自动识别                           |
//| 融合：ADX 强度 + 布林带宽压缩 + 双均线斜率方向一致性                 |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_REGIME_DETECTOR_MQH
#define GOLDFX_REGIME_DETECTOR_MQH

#include "Common.mqh"

class CRegimeDetector
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_adx_handle;
   int               m_atr_handle;
   int               m_bb_handle;
   int               m_ma_fast_handle;
   int               m_ma_slow_handle;
   int               m_adx_period;
   int               m_atr_period;
   int               m_ma_fast;
   int               m_ma_slow;
   double            m_adx_trend;
   double            m_adx_range;
   double            m_bb_width_max;
   ENUM_MARKET_REGIME m_last_regime;
   double            m_last_adx;
   double            m_last_bb_width;
   datetime          m_last_bar;

   bool CopyBuf(const int handle, const int buf, const int count, double &out[])
     {
      ArraySetAsSeries(out, true);
      if(CopyBuffer(handle, buf, 0, count, out) < count)
         return false;
      return true;
     }

public:
                     CRegimeDetector(void)
                       : m_symbol(_Symbol),
                         m_tf(PERIOD_CURRENT),
                         m_adx_handle(INVALID_HANDLE),
                         m_atr_handle(INVALID_HANDLE),
                         m_bb_handle(INVALID_HANDLE),
                         m_ma_fast_handle(INVALID_HANDLE),
                         m_ma_slow_handle(INVALID_HANDLE),
                         m_adx_period(14),
                         m_atr_period(14),
                         m_ma_fast(20),
                         m_ma_slow(50),
                         m_adx_trend(25.0),
                         m_adx_range(20.0),
                         m_bb_width_max(0.015),
                         m_last_regime(REGIME_UNKNOWN),
                         m_last_adx(0.0),
                         m_last_bb_width(0.0),
                         m_last_bar(0)
                     {
                     }

                    ~CRegimeDetector(void) { Release(); }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf     = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      Release();
      m_adx_period   = MathMax(2, p.adx_period);
      m_atr_period   = MathMax(2, p.atr_period);
      m_ma_fast      = MathMax(2, p.ma_fast);
      m_ma_slow      = MathMax(m_ma_fast + 1, p.ma_slow);
      m_adx_trend    = p.adx_trend_threshold;
      m_adx_range    = p.adx_range_threshold;
      m_bb_width_max = p.bb_width_range_max;

      m_adx_handle = iADX(m_symbol, m_tf, m_adx_period);
      m_atr_handle = iATR(m_symbol, m_tf, m_atr_period);
      m_bb_handle  = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);
      m_ma_fast_handle = iMA(m_symbol, m_tf, m_ma_fast, 0, MODE_EMA, PRICE_CLOSE);
      m_ma_slow_handle = iMA(m_symbol, m_tf, m_ma_slow, 0, MODE_EMA, PRICE_CLOSE);

      if(m_adx_handle == INVALID_HANDLE || m_atr_handle == INVALID_HANDLE ||
         m_bb_handle == INVALID_HANDLE || m_ma_fast_handle == INVALID_HANDLE ||
         m_ma_slow_handle == INVALID_HANDLE)
        {
         Print("CRegimeDetector: 指标句柄创建失败");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_adx_handle != INVALID_HANDLE) { IndicatorRelease(m_adx_handle); m_adx_handle = INVALID_HANDLE; }
      if(m_atr_handle != INVALID_HANDLE) { IndicatorRelease(m_atr_handle); m_atr_handle = INVALID_HANDLE; }
      if(m_bb_handle  != INVALID_HANDLE) { IndicatorRelease(m_bb_handle);  m_bb_handle  = INVALID_HANDLE; }
      if(m_ma_fast_handle != INVALID_HANDLE) { IndicatorRelease(m_ma_fast_handle); m_ma_fast_handle = INVALID_HANDLE; }
      if(m_ma_slow_handle != INVALID_HANDLE) { IndicatorRelease(m_ma_slow_handle); m_ma_slow_handle = INVALID_HANDLE; }
     }

   ENUM_MARKET_REGIME LastRegime(void) const { return m_last_regime; }
   double             LastADX(void) const { return m_last_adx; }
   double             LastBBWidth(void) const { return m_last_bb_width; }

   // 每根新 K 线评估一次，避免 Tick 抖动
   ENUM_MARKET_REGIME Evaluate(const bool force = false)
     {
      datetime bar = iTime(m_symbol, m_tf, 0);
      if(!force && bar == m_last_bar && m_last_regime != REGIME_UNKNOWN)
         return m_last_regime;
      m_last_bar = bar;

      double adx[], plus_di[], minus_di[], upper[], middle[], lower[], ma_f[], ma_s[];
      if(!CopyBuf(m_adx_handle, 0, 3, adx) ||
         !CopyBuf(m_adx_handle, 1, 3, plus_di) ||
         !CopyBuf(m_adx_handle, 2, 3, minus_di) ||
         !CopyBuf(m_bb_handle, 1, 3, upper) ||
         !CopyBuf(m_bb_handle, 0, 3, middle) ||
         !CopyBuf(m_bb_handle, 2, 3, lower) ||
         !CopyBuf(m_ma_fast_handle, 0, 5, ma_f) ||
         !CopyBuf(m_ma_slow_handle, 0, 5, ma_s))
        {
         m_last_regime = REGIME_UNKNOWN;
         return m_last_regime;
        }

      m_last_adx = adx[1]; // 用已收盘 K 线
      const double mid = middle[1];
      m_last_bb_width = SafeDiv(upper[1] - lower[1], mid, 0.0);

      // 均线斜率：快慢线同向且分离 → 趋势倾向
      const double fast_slope = ma_f[1] - ma_f[3];
      const double slow_slope = ma_s[1] - ma_s[3];
      const bool   slope_aligned =
         (fast_slope > 0.0 && slow_slope > 0.0) ||
         (fast_slope < 0.0 && slow_slope < 0.0);
      const double sep = SafeDiv(MathAbs(ma_f[1] - ma_s[1]), mid, 0.0);
      const bool   separated = (sep > m_bb_width_max * 0.35);

      int score_trend = 0;
      int score_range = 0;

      if(m_last_adx >= m_adx_trend)          score_trend += 2;
      else if(m_last_adx <= m_adx_range)     score_range += 2;
      else if(m_last_adx > (m_adx_trend + m_adx_range) * 0.5) score_trend += 1;
      else                                  score_range += 1;

      if(m_last_bb_width <= m_bb_width_max)  score_range += 2;
      else                                  score_trend += 1;

      if(slope_aligned && separated)        score_trend += 2;
      else if(!slope_aligned)               score_range += 1;

      // DI 交叉幅度小 → 震荡
      const double di_gap = MathAbs(plus_di[1] - minus_di[1]);
      if(di_gap < 5.0)                      score_range += 1;
      else if(di_gap > 12.0)                score_trend += 1;

      if(score_trend > score_range)
         m_last_regime = REGIME_TREND;
      else if(score_range > score_trend)
         m_last_regime = REGIME_RANGE;
      else
         m_last_regime = (m_last_adx >= m_adx_trend) ? REGIME_TREND : REGIME_RANGE;

      return m_last_regime;
     }

   string Diagnostics(void) const
     {
      return StringFormat("ADX=%.1f BBW=%.4f 状态=%s",
                         m_last_adx, m_last_bb_width, RegimeToString(m_last_regime));
     }
  };

#endif
//+------------------------------------------------------------------+
