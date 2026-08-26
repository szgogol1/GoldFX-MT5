//+------------------------------------------------------------------+
//| RangeStrategy.mqh — 震荡策略（布林带边缘 + RSI 极值均值回归）       |
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
      r.signal = SIGNAL_NONE;
      r.entry  = 0;
      r.sl     = 0;
      r.tp     = 0;
      r.reason = "";

      datetime bar = iTime(m_symbol, m_tf, 0);
      if(bar == m_last_signal_bar)
         return r;

      double upper[], mid[], lower[], rsi[], atr[], close[];
      ArraySetAsSeries(close, true);
      if(!CopyBuf(m_bb_h, 1, 3, upper) ||
         !CopyBuf(m_bb_h, 0, 3, mid) ||
         !CopyBuf(m_bb_h, 2, 3, lower) ||
         !CopyBuf(m_rsi_h, 0, 3, rsi) ||
         !CopyBuf(m_atr_h, 0, 3, atr) ||
         CopyClose(m_symbol, m_tf, 0, 3, close) < 3)
         return r;

      const double atr_v = atr[1];
      if(atr_v <= 0.0)
         return r;

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return r;

      // 收盘触及下轨且 RSI 超卖 → 做多回归中轨
      const bool buy_setup  = (close[1] <= lower[1] && rsi[1] <= m_rsi_os);
      const bool sell_setup = (close[1] >= upper[1] && rsi[1] >= m_rsi_ob);

      if(buy_setup)
        {
         r.signal = SIGNAL_BUY;
         r.entry  = tick.ask;
         r.sl     = NormalizePrice(r.entry - atr_v * m_sl_mult);
         // 目标优先中轨，否则 ATR 倍数
         const double mid_tp = mid[1];
         r.tp = (mid_tp > r.entry) ? NormalizePrice(mid_tp)
                                   : NormalizePrice(r.entry + atr_v * m_tp_mult);
         r.reason = StringFormat("震荡多: 触下轨 RSI=%.1f", rsi[1]);
         m_last_signal_bar = bar;
        }
      else if(sell_setup)
        {
         r.signal = SIGNAL_SELL;
         r.entry  = tick.bid;
         r.sl     = NormalizePrice(r.entry + atr_v * m_sl_mult);
         const double mid_tp = mid[1];
         r.tp = (mid_tp < r.entry) ? NormalizePrice(mid_tp)
                                   : NormalizePrice(r.entry - atr_v * m_tp_mult);
         r.reason = StringFormat("震荡空: 触上轨 RSI=%.1f", rsi[1]);
         m_last_signal_bar = bar;
        }
      return r;
     }
  };

#endif
//+------------------------------------------------------------------+
