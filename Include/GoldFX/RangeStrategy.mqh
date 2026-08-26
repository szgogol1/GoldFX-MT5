//+------------------------------------------------------------------+
//| RangeStrategy.mqh — 选择性震荡：布林边缘 + RSI 极值质量评分         |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_RANGE_STRATEGY_MQH
#define GOLDFX_RANGE_STRATEGY_MQH

#include "Common.mqh"

class CRangeStrategy
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_bb_h;
   int               m_rsi_h;
   int               m_atr_h;
   int               m_rsi_period;
   int               m_atr_period;
   double            m_rsi_os;
   double            m_rsi_ob;
   double            m_sl_mult;
   double            m_tp_mult;
   datetime          m_last_signal_bar;

   bool CopyBuf(const int handle, const int buf, const int count, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(handle, buf, 0, count, out) >= count);
     }

public:
                     CRangeStrategy(void)
                       : m_symbol(_Symbol),
                         m_tf(PERIOD_CURRENT),
                         m_bb_h(INVALID_HANDLE),
                         m_rsi_h(INVALID_HANDLE),
                         m_atr_h(INVALID_HANDLE),
                         m_rsi_period(14),
                         m_atr_period(14),
                         m_rsi_os(30.0),
                         m_rsi_ob(70.0),
                         m_sl_mult(1.0),
                         m_tp_mult(1.2),
                         m_last_signal_bar(0)
                     {
                     }

                    ~CRangeStrategy(void) { Release(); }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf     = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      Release();
      m_rsi_period = MathMax(2, p.rsi_period);
      m_atr_period = MathMax(2, p.atr_period);
      m_rsi_os     = p.rsi_oversold;
      m_rsi_ob     = p.rsi_overbought;
      m_sl_mult    = MathMax(0.2, p.range_sl_atr_mult);
      m_tp_mult    = MathMax(0.2, p.range_tp_atr_mult);

      m_bb_h  = iBands(m_symbol, m_tf, 20, 0, 2.0, PRICE_CLOSE);
      m_rsi_h = iRSI(m_symbol, m_tf, m_rsi_period, PRICE_CLOSE);
      m_atr_h = iATR(m_symbol, m_tf, m_atr_period);

      if(m_bb_h == INVALID_HANDLE || m_rsi_h == INVALID_HANDLE || m_atr_h == INVALID_HANDLE)
        {
         Print("CRangeStrategy: 指标句柄失败");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_bb_h != INVALID_HANDLE)  { IndicatorRelease(m_bb_h);  m_bb_h = INVALID_HANDLE; }
      if(m_rsi_h != INVALID_HANDLE) { IndicatorRelease(m_rsi_h); m_rsi_h = INVALID_HANDLE; }
      if(m_atr_h != INVALID_HANDLE) { IndicatorRelease(m_atr_h); m_atr_h = INVALID_HANDLE; }
     }

   SSignalResult Evaluate(void)
     {
      SSignalResult r;
      InitSignal(r);
      r.symbol = m_symbol;

      datetime bar = iTime(m_symbol, m_tf, 0);
      if(bar == m_last_signal_bar)
         return r;

      double upper[], mid[], lower[], rsi[], atr[], close[];
      ArraySetAsSeries(close, true);
      if(!CopyBuf(m_bb_h, 1, 3, upper) ||
         !CopyBuf(m_bb_h, 0, 3, mid) ||
         !CopyBuf(m_bb_h, 2, 3, lower) ||
         !CopyBuf(m_rsi_h, 0, 4, rsi) ||
         !CopyBuf(m_atr_h, 0, 3, atr) ||
         CopyClose(m_symbol, m_tf, 0, 3, close) < 3)
         return r;

      const double atr_v = atr[1];
      if(atr_v <= 0.0)
         return r;

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return r;

      const bool buy_setup  = (close[1] <= lower[1] && rsi[1] <= m_rsi_os);
      const bool sell_setup = (close[1] >= upper[1] && rsi[1] >= m_rsi_ob);

      if(!buy_setup && !sell_setup)
        {
         r.reason = "等待震荡极值";
         return r;
        }

      int q = 40;
      const double band = upper[1] - lower[1];
      // 带宽适中更适合均值回归（过宽可能是趋势启动）
      const double bw = SafeDiv(band, mid[1], 0.0);
      if(bw > 0.0 && bw < 0.02) q += 15;
      else if(bw < 0.03)        q += 8;

      if(buy_setup)
        {
         if(rsi[1] < m_rsi_os - 5.0) q += 15;
         else if(rsi[1] <= m_rsi_os) q += 8;
         if(rsi[1] > rsi[2])         q += 10; // RSI 拐头
         if(close[1] < lower[1])     q += 5;  // 刺破更深
         r.signal = SIGNAL_BUY;
         r.entry  = tick.ask;
         r.sl     = NormalizePrice(r.entry - atr_v * m_sl_mult);
         const double mid_tp = mid[1];
         r.tp = (mid_tp > r.entry) ? NormalizePrice(mid_tp)
                                   : NormalizePrice(r.entry + atr_v * m_tp_mult);
         r.atr = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("震荡多 下轨+RSI=%.1f Q=%d", rsi[1], r.quality);
         m_last_signal_bar = bar;
        }
      else
        {
         if(rsi[1] > m_rsi_ob + 5.0) q += 15;
         else if(rsi[1] >= m_rsi_ob) q += 8;
         if(rsi[1] < rsi[2])         q += 10;
         if(close[1] > upper[1])     q += 5;
         r.signal = SIGNAL_SELL;
         r.entry  = tick.bid;
         r.sl     = NormalizePrice(r.entry + atr_v * m_sl_mult);
         const double mid_tp = mid[1];
         r.tp = (mid_tp < r.entry) ? NormalizePrice(mid_tp)
                                   : NormalizePrice(r.entry - atr_v * m_tp_mult);
         r.atr = atr_v;
         r.quality = MathMin(100, q);
         r.reason = StringFormat("震荡空 上轨+RSI=%.1f Q=%d", rsi[1], r.quality);
         m_last_signal_bar = bar;
        }
      return r;
     }
  };

#endif
//+------------------------------------------------------------------+
