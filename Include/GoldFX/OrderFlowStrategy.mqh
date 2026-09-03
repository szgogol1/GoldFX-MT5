//+------------------------------------------------------------------+
//| OrderFlowStrategy.mqh — 位置+失衡+CVD+吸收+结构 → SSignalResult    |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_ORDER_FLOW_STRATEGY_MQH
#define GOLDFX_ORDER_FLOW_STRATEGY_MQH

#include "Common.mqh"
#include "OrderFlowTape.mqh"
#include "VolumeProfile.mqh"
#include "OrderFlowBook.mqh"

class COrderFlowStrategy
  {
private:
   string              m_symbol;
   ENUM_TIMEFRAMES     m_tf;
   COrderFlowTape     *m_tape;
   CVolumeProfile     *m_vp;
   COrderFlowBook     *m_book;
   int                 m_atr_h;
   int                 m_htf_ema_h;
   int                 m_stack_bars;
   int                 m_min_pos_delta;
   double              m_imbalance_pct;
   int                 m_cvd_slope_bars;
   bool                m_allow_div;
   bool                m_use_absorb;
   double              m_absorb_vol_mult;
   double              m_absorb_range_atr;
   bool                m_use_htf;
   int                 m_htf_ema;
   double              m_sl_atr, m_tp_atr, m_sl_atr_max, m_min_rr;
   int                 m_swing_sl_bars;
   int                 m_atr_period;
   int                 m_min_bars;
   datetime            m_last_eval_bar;
   SOrderFlowSnapshot  m_last_snap;

   bool CopyBuf(const int h, const int buf, const int cnt, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(h, buf, 0, cnt, out) >= cnt);
     }

   double CalcStopLong(const double entry, const double atr_v, const double &low[]) const
     {
      double swing = low[1];
      for(int i=2; i<=m_swing_sl_bars+1; ++i)
         if(low[i] < swing) swing = low[i];
      double sl = swing - atr_v * m_sl_atr * 0.35;
      if(m_vp != NULL && m_vp.Valid())
        {
         const double below_val = m_vp.Val() - atr_v * 0.15;
         if(below_val < entry) sl = MathMin(sl, below_val);
         const double below_poc = m_vp.Poc() - atr_v * 0.20;
         if(entry > m_vp.Poc()) sl = MathMin(sl, below_poc);
        }
      const double max_dist = atr_v * m_sl_atr_max;
      if(entry - sl > max_dist) sl = entry - max_dist;
      if(sl >= entry) sl = entry - atr_v * m_sl_atr;
      return NormalizePriceSym(sl, m_symbol);
     }

   double CalcStopShort(const double entry, const double atr_v, const double &high[]) const
     {
      double swing = high[1];
      for(int i=2; i<=m_swing_sl_bars+1; ++i)
         if(high[i] > swing) swing = high[i];
      double sl = swing + atr_v * m_sl_atr * 0.35;
      if(m_vp != NULL && m_vp.Valid())
        {
         const double above_vah = m_vp.Vah() + atr_v * 0.15;
         if(above_vah > entry) sl = MathMax(sl, above_vah);
         const double above_poc = m_vp.Poc() + atr_v * 0.20;
         if(entry < m_vp.Poc()) sl = MathMax(sl, above_poc);
        }
      const double max_dist = atr_v * m_sl_atr_max;
      if(sl - entry > max_dist) sl = entry + max_dist;
      if(sl <= entry) sl = entry + atr_v * m_sl_atr;
      return NormalizePriceSym(sl, m_symbol);
     }

   double CalcTpLong(const double entry, const double sl, const double atr_v) const
     {
      double tp = entry + atr_v * m_tp_atr;
      if(m_vp != NULL && m_vp.Valid() && m_vp.Vah() > entry)
         tp = MathMax(tp, m_vp.Vah());
      const double risk = entry - sl;
      if(risk > 0.0 && (tp - entry) < risk * m_min_rr)
         tp = entry + risk * m_min_rr;
      return NormalizePriceSym(tp, m_symbol);
     }

   double CalcTpShort(const double entry, const double sl, const double atr_v) const
     {
      double tp = entry - atr_v * m_tp_atr;
      if(m_vp != NULL && m_vp.Valid() && m_vp.Val() < entry)
         tp = MathMin(tp, m_vp.Val());
      const double risk = sl - entry;
      if(risk > 0.0 && (entry - tp) < risk * m_min_rr)
         tp = entry - risk * m_min_rr;
      return NormalizePriceSym(tp, m_symbol);
     }

   int ScoreLong(const SOrderFlowSnapshot &s, const bool div) const
     {
      int q = 50;
      if(s.pos_ok) q += 10;
      if(s.delta_ok) q += 12;
      if(s.cvd_ok) q += 10;
      if(s.absorb_ok) q += 6;
      if(s.structure_ok) q += 8;
      if(s.book_available && s.book_ok) q += 4;
      if(div) q += 5;
      if(s.imbalance_pct >= 50.0) q += 5;
      return MathMin(99, q);
     }

   int ScoreShort(const SOrderFlowSnapshot &s, const bool div) const
     {
      return ScoreLong(s, div);
     }

   void FillBaseSnap(SOrderFlowSnapshot &s, const SBarDelta &last) const
     {
      ZeroMemory(s);
      s.fail_reason = "";
      s.bar_delta = last.delta;
      s.bar_buy_vol = last.buy_vol;
      s.bar_sell_vol = last.sell_vol;
      s.bar_volume = last.volume;
      s.imbalance_pct = (m_tape != NULL ? m_tape.ImbalancePct(last) : 0.0);
      s.cvd = (m_tape != NULL ? m_tape.Cvd() : 0.0);
      s.cvd_slope = (m_tape != NULL ? m_tape.CvdSlope(m_cvd_slope_bars) : 0.0);
      if(m_vp != NULL && m_vp.Valid())
        {
         s.vwap = m_vp.Vwap();
         s.poc  = m_vp.Poc();
         s.vah  = m_vp.Vah();
         s.val  = m_vp.Val();
        }
      s.book_available = (m_book != NULL && m_book.Available());
      s.book_ok = true;
      s.pos_ok = s.delta_ok = s.cvd_ok = s.absorb_ok = s.structure_ok = false;
     }

public:
                     COrderFlowStrategy(void)
                       : m_symbol(""), m_tf(PERIOD_CURRENT),
                         m_tape(NULL), m_vp(NULL), m_book(NULL),
                         m_atr_h(INVALID_HANDLE), m_htf_ema_h(INVALID_HANDLE),
                         m_stack_bars(3), m_min_pos_delta(2), m_imbalance_pct(35.0),
                         m_cvd_slope_bars(5), m_allow_div(true), m_use_absorb(true),
                         m_absorb_vol_mult(1.8), m_absorb_range_atr(0.45),
                         m_use_htf(true), m_htf_ema(50),
                         m_sl_atr(1.0), m_tp_atr(2.0), m_sl_atr_max(1.8), m_min_rr(1.5),
                         m_swing_sl_bars(8), m_atr_period(14), m_min_bars(100),
                         m_last_eval_bar(0)
                     {
                      ZeroMemory(m_last_snap);
                     }

                    ~COrderFlowStrategy(void) { Release(); }

   SOrderFlowSnapshot LastSnapshot(void) const { return m_last_snap; }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf,
             COrderFlowTape *tape, CVolumeProfile *vp, COrderFlowBook *book,
             const SRuntimeParams &p)
     {
      Release();
      m_symbol = symbol;
      m_tf = tf;
      m_tape = tape;
      m_vp = vp;
      m_book = book;
      if(!Configure(p)) return false;

      m_atr_h = iATR(m_symbol, m_tf, m_atr_period);
      if(m_atr_h == INVALID_HANDLE) return false;
      if(m_use_htf)
        {
         m_htf_ema_h = iMA(m_symbol, PERIOD_H1, m_htf_ema, 0, MODE_EMA, PRICE_CLOSE);
         if(m_htf_ema_h == INVALID_HANDLE) return false;
        }
      return true;
     }

   bool Configure(const SRuntimeParams &p)
     {
      m_stack_bars = MathMax(2, p.of_stack_bars);
      m_min_pos_delta = MathMax(1, p.of_min_pos_delta);
      m_imbalance_pct = MathMax(10.0, p.of_imbalance_pct);
      m_cvd_slope_bars = MathMax(2, p.of_cvd_slope_bars);
      m_allow_div = p.of_allow_divergence;
      m_use_absorb = p.of_use_absorption;
      m_absorb_vol_mult = MathMax(1.1, p.of_absorb_vol_mult);
      m_absorb_range_atr = MathMax(0.1, p.of_absorb_range_atr);
      m_use_htf = p.of_use_htf;
      m_htf_ema = MathMax(5, p.of_htf_ema);
      m_sl_atr = p.of_sl_atr;
      m_tp_atr = p.of_tp_atr;
      m_sl_atr_max = p.of_sl_atr_max;
      m_min_rr = p.of_min_rr;
      m_swing_sl_bars = MathMax(3, p.of_swing_sl_bars);
      m_atr_period = MathMax(5, p.atr_period);
      m_min_bars = MathMax(50, p.min_bars_required);
      return true;
     }

   void Release(void)
     {
      if(m_atr_h != INVALID_HANDLE) { IndicatorRelease(m_atr_h); m_atr_h = INVALID_HANDLE; }
      if(m_htf_ema_h != INVALID_HANDLE) { IndicatorRelease(m_htf_ema_h); m_htf_ema_h = INVALID_HANDLE; }
     }

   bool BarsReady(string &why) const
     {
      why = "";
      if(Bars(m_symbol, m_tf) < m_min_bars)
        { why = "K线不足"; return false; }
      if(m_tape == NULL || !m_tape.Ready())
        { why = "Tape未就绪"; return false; }
      if(m_vp == NULL || !m_vp.Valid())
        { why = "成交量分布未就绪"; return false; }
      return true;
     }

   // new_bar_only：仅在新收盘棒上产生信号；false 只刷新快照
   SSignalResult Evaluate(const bool new_bar_only = true)
     {
      SSignalResult sig;
      InitSignal(sig);
      sig.symbol = m_symbol;
      sig.engine_tag = "OF";

      SOrderFlowSnapshot snap;
      ZeroMemory(snap);
      snap.fail_reason = "";

      string why;
      if(!BarsReady(why))
        {
         snap.fail_reason = why;
         m_last_snap = snap;
         sig.oflow = snap;
         sig.reason = why;
         return sig;
        }

      SBarDelta last;
      if(!m_tape.LastClosed(last))
        {
         snap.fail_reason = "无已收盘Delta棒";
         m_last_snap = snap;
         sig.oflow = snap;
         return sig;
        }

      FillBaseSnap(snap, last);

      double atr_early[];
      double atr_v = 0.0;
      if(CopyBuf(m_atr_h, 0, 5, atr_early) && atr_early[1] > 0.0)
         atr_v = atr_early[1];

      // 新棒门闩：用已收盘棒时间（仍刷新快照供仪表盘）
      if(new_bar_only)
        {
         if(last.bar_time == 0 || last.bar_time == m_last_eval_bar)
           {
            // 轻量刷新位置/CVD 诊断
            if(m_vp != NULL && m_vp.Valid() && atr_v > 0.0)
              {
               double c[];
               ArraySetAsSeries(c, true);
               if(CopyClose(m_symbol, m_tf, 0, 3, c) >= 3)
                 {
                  snap.pos_ok = m_vp.PositionLong(c[1], atr_v) || m_vp.PositionShort(c[1], atr_v);
                 }
              }
            snap.delta_ok = m_tape.StackImbalanceLong(m_stack_bars, m_min_pos_delta, m_imbalance_pct) ||
                            m_tape.StackImbalanceShort(m_stack_bars, m_min_pos_delta, m_imbalance_pct);
            snap.cvd_ok = (snap.cvd_slope != 0.0);
            snap.absorb_ok = true;
            snap.structure_ok = true;
            snap.fail_reason = "等待新收盘K";
            m_last_snap = snap;
            sig.oflow = snap;
            sig.reason = snap.fail_reason;
            return sig;
           }
        }

      double atr[];
      if(!CopyBuf(m_atr_h, 0, 5, atr) || atr[1] <= 0.0)
        {
         snap.fail_reason = "ATR无效";
         m_last_snap = snap; sig.oflow = snap; return sig;
        }
      atr_v = atr[1];

      double close[], open[], high[], low[];
      ArraySetAsSeries(close, true);
      ArraySetAsSeries(open, true);
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);
      if(CopyClose(m_symbol, m_tf, 0, m_swing_sl_bars+5, close) < m_swing_sl_bars+5 ||
         CopyOpen(m_symbol, m_tf, 0, 5, open) < 5 ||
         CopyHigh(m_symbol, m_tf, 0, m_swing_sl_bars+5, high) < m_swing_sl_bars+5 ||
         CopyLow(m_symbol, m_tf, 0, m_swing_sl_bars+5, low) < m_swing_sl_bars+5)
        {
         snap.fail_reason = "行情复制失败";
         m_last_snap = snap; sig.oflow = snap; return sig;
        }

      const double px = close[1];
      snap.pos_ok = m_vp.PositionLong(px, atr_v) || m_vp.PositionShort(px, atr_v);

      const bool stack_long  = m_tape.StackImbalanceLong(m_stack_bars, m_min_pos_delta, m_imbalance_pct);
      const bool stack_short = m_tape.StackImbalanceShort(m_stack_bars, m_min_pos_delta, m_imbalance_pct);
      snap.delta_ok = (stack_long || stack_short);

      const double slope = snap.cvd_slope;
      const bool div_bull = (m_allow_div && m_tape.BullishDivergence(MathMax(6, m_cvd_slope_bars+1)));
      const bool div_bear = (m_allow_div && m_tape.BearishDivergence(MathMax(6, m_cvd_slope_bars+1)));
      snap.cvd_ok = (slope > 0.0 || slope < 0.0 || div_bull || div_bear);

      bool absorb_block_long = false;
      bool absorb_block_short = false;
      if(m_use_absorb)
        {
         absorb_block_long  = m_tape.AbsorptionAgainstLong(4, m_absorb_vol_mult, m_absorb_range_atr, atr_v);
         absorb_block_short = m_tape.AbsorptionAgainstShort(4, m_absorb_vol_mult, m_absorb_range_atr, atr_v);
        }
      snap.absorb_ok = !(absorb_block_long && absorb_block_short);

      // H1 结构
      bool htf_long = true, htf_short = true;
      if(m_use_htf && m_htf_ema_h != INVALID_HANDLE)
        {
         double ema[];
         if(CopyBuf(m_htf_ema_h, 0, 3, ema))
           {
            double h1c[];
            ArraySetAsSeries(h1c, true);
            if(CopyClose(m_symbol, PERIOD_H1, 0, 3, h1c) >= 3)
              {
               htf_long  = (h1c[1] >= ema[1]);
               htf_short = (h1c[1] <= ema[1]);
              }
           }
         // 亦可结合会话 VWAP：H1 收盘相对日 VWAP
         if(m_vp.Valid())
           {
            double h1c2[];
            ArraySetAsSeries(h1c2, true);
            if(CopyClose(m_symbol, PERIOD_H1, 0, 2, h1c2) >= 2)
              {
               if(h1c2[1] < m_vp.Vwap()) htf_long = false;
               if(h1c2[1] > m_vp.Vwap()) htf_short = false;
              }
           }
        }
      snap.structure_ok = (htf_long || htf_short);

      if(m_book != NULL)
        {
         snap.book_available = m_book.Available();
         snap.book_ok = true; // 具体方向再判
        }

      // ---- 做多路径 ----
      bool long_ok = true;
      string long_fail = "";
      const bool pos_long = m_vp.PositionLong(px, atr_v);
      if(!pos_long) { long_ok = false; long_fail = "位置偏空/真空"; }
      if(long_ok && !stack_long) { long_ok = false; long_fail = "买盘失衡不足"; }
      const bool cvd_long = (slope > 0.0) || div_bull;
      if(long_ok && !cvd_long) { long_ok = false; long_fail = "CVD未确认多"; }
      if(long_ok && absorb_block_long) { long_ok = false; long_fail = "高点卖方吸收"; }
      if(long_ok && m_use_htf && !htf_long) { long_ok = false; long_fail = "H1结构偏空"; }
      bool book_long = true;
      if(m_book != NULL && m_book.Available())
        {
         book_long = m_book.SupportsLong();
         if(long_ok && !book_long) { long_ok = false; long_fail = "DOM近端卖压"; }
        }

      // ---- 做空路径 ----
      bool short_ok = true;
      string short_fail = "";
      const bool pos_short = m_vp.PositionShort(px, atr_v);
      if(!pos_short) { short_ok = false; short_fail = "位置偏多/真空"; }
      if(short_ok && !stack_short) { short_ok = false; short_fail = "卖盘失衡不足"; }
      const bool cvd_short = (slope < 0.0) || div_bear;
      if(short_ok && !cvd_short) { short_ok = false; short_fail = "CVD未确认空"; }
      if(short_ok && absorb_block_short) { short_ok = false; short_fail = "低点买方吸收"; }
      if(short_ok && m_use_htf && !htf_short) { short_ok = false; short_fail = "H1结构偏多"; }
      bool book_short = true;
      if(m_book != NULL && m_book.Available())
        {
         book_short = m_book.SupportsShort();
         if(short_ok && !book_short) { short_ok = false; short_fail = "DOM近端买撑"; }
        }

      // 刷新诊断 flags（按更接近触发的一侧）
      if(long_ok || (!short_ok && stack_long))
        {
         snap.pos_ok = pos_long;
         snap.delta_ok = stack_long;
         snap.cvd_ok = cvd_long;
         snap.absorb_ok = !absorb_block_long;
         snap.structure_ok = (!m_use_htf || htf_long);
         snap.book_ok = book_long;
        }
      else
        {
         snap.pos_ok = pos_short;
         snap.delta_ok = stack_short;
         snap.cvd_ok = cvd_short;
         snap.absorb_ok = !absorb_block_short;
         snap.structure_ok = (!m_use_htf || htf_short);
         snap.book_ok = book_short;
        }

      if(new_bar_only)
         m_last_eval_bar = last.bar_time;

      if(long_ok && !short_ok)
        {
         const double entry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         const double sl = CalcStopLong(entry, atr_v, low);
         const double tp = CalcTpLong(entry, sl, atr_v);
         if(entry - sl <= 0.0)
           {
            snap.fail_reason = "多SL无效";
            m_last_snap = snap; sig.oflow = snap; return sig;
           }
         sig.signal = SIGNAL_BUY;
         sig.entry = entry;
         sig.sl = sl;
         sig.tp = tp;
         sig.atr = atr_v;
         sig.quality = ScoreLong(snap, div_bull);
         sig.reason = StringFormat("OF|BUY Δ=%.0f Imb=%.0f CVD_slope=%.0f", last.delta, snap.imbalance_pct, slope);
         snap.fail_reason = "";
         m_last_snap = snap;
         sig.oflow = snap;
         return sig;
        }

      if(short_ok && !long_ok)
        {
         const double entry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
         const double sl = CalcStopShort(entry, atr_v, high);
         const double tp = CalcTpShort(entry, sl, atr_v);
         if(sl - entry <= 0.0)
           {
            snap.fail_reason = "空SL无效";
            m_last_snap = snap; sig.oflow = snap; return sig;
           }
         sig.signal = SIGNAL_SELL;
         sig.entry = entry;
         sig.sl = sl;
         sig.tp = tp;
         sig.atr = atr_v;
         sig.quality = ScoreShort(snap, div_bear);
         sig.reason = StringFormat("OF|SELL Δ=%.0f Imb=%.0f CVD_slope=%.0f", last.delta, snap.imbalance_pct, slope);
         snap.fail_reason = "";
         m_last_snap = snap;
         sig.oflow = snap;
         return sig;
        }

      // 双侧或均否
      if(long_ok && short_ok)
         snap.fail_reason = "多空冲突跳过";
      else if(!long_ok && !short_ok)
         snap.fail_reason = (StringLen(long_fail) ? long_fail : short_fail);
      else
         snap.fail_reason = "条件未齐";

      m_last_snap = snap;
      sig.oflow = snap;
      sig.reason = snap.fail_reason;
      return sig;
     }

   // 持仓离场：反向堆叠失衡 / CVD 背离（由 EA 开关分别启用）
   bool ShouldExitLong(const bool use_delta_flip, const bool use_cvd_div, string &why) const
     {
      why = "";
      if(m_tape == NULL || !m_tape.Ready()) return false;
      if(use_delta_flip &&
         m_tape.StackImbalanceShort(m_stack_bars, m_min_pos_delta, m_imbalance_pct))
        { why = "OF反向卖盘失衡"; return true; }
      if(use_cvd_div &&
         m_tape.BearishDivergence(MathMax(6, m_cvd_slope_bars+1)))
        { why = "OF看跌CVD背离"; return true; }
      return false;
     }

   bool ShouldExitShort(const bool use_delta_flip, const bool use_cvd_div, string &why) const
     {
      why = "";
      if(m_tape == NULL || !m_tape.Ready()) return false;
      if(use_delta_flip &&
         m_tape.StackImbalanceLong(m_stack_bars, m_min_pos_delta, m_imbalance_pct))
        { why = "OF反向买盘失衡"; return true; }
      if(use_cvd_div &&
         m_tape.BullishDivergence(MathMax(6, m_cvd_slope_bars+1)))
        { why = "OF看涨CVD背离"; return true; }
      return false;
     }
  };

#endif
//+------------------------------------------------------------------+
