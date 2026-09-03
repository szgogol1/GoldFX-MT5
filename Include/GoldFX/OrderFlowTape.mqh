//+------------------------------------------------------------------+
//| OrderFlowTape.mqh — Tick 分类 / Bar Delta / CVD / 堆叠失衡         |
//| 零售盘近似订单流：Lee-Ready + TICK_FLAG；外汇常按 tick 计数        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_ORDER_FLOW_TAPE_MQH
#define GOLDFX_ORDER_FLOW_TAPE_MQH

#include "Common.mqh"

#define OF_MAX_BARS 256

struct SBarDelta
  {
   datetime bar_time;
   double   buy_vol;
   double   sell_vol;
   double   delta;      // buy - sell
   double   volume;     // buy + sell
   double   high;
   double   low;
   double   close;
   double   open;
  };

class COrderFlowTape
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   ulong             m_last_msc;
   int               m_last_dir;       // +1 buy / -1 sell（tick rule）
   double            m_cvd;
   datetime          m_cur_bar;
   SBarDelta         m_cur;
   SBarDelta         m_hist[OF_MAX_BARS];
   int               m_hist_count;     // 已封存根数
   int               m_hist_head;      // 环形写入位置（下一写入）
   bool              m_ready;
   string            m_err;

   double TickSize(void) const
     {
      double t = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      if(t <= 0.0) t = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      return (t > 0.0 ? t : _Point);
     }

   double TickWeight(const MqlTick &tk) const
     {
      if(tk.volume_real > 0.0) return (double)tk.volume_real;
      if(tk.volume > 0) return (double)tk.volume;
      return 1.0; // 外汇 CFD 常见：按 tick 计数
     }

   // Lee-Ready + 交易所买卖标志
   int Classify(const MqlTick &tk)
     {
      if((tk.flags & TICK_FLAG_BUY)  != 0 && (tk.flags & TICK_FLAG_SELL) == 0)
         return 1;
      if((tk.flags & TICK_FLAG_SELL) != 0 && (tk.flags & TICK_FLAG_BUY)  == 0)
         return -1;

      const double last = tk.last;
      const double bid  = tk.bid;
      const double ask  = tk.ask;
      if(last > 0.0 && bid > 0.0 && ask > 0.0)
        {
         if(last >= ask) return 1;
         if(last <= bid) return -1;
         const double mid = 0.5 * (bid + ask);
         if(last > mid) return 1;
         if(last < mid) return -1;
        }
      // 无 last：用 bid/ask 变动近似（ask 上抬偏买）
      if(m_last_dir != 0) return m_last_dir;
      return 1;
     }

   void ResetCur(const datetime bar)
     {
      ZeroMemory(m_cur);
      m_cur.bar_time = bar;
      m_cur.open = m_cur.high = m_cur.low = m_cur.close = 0.0;
     }

   void SealCur(void)
     {
      if(m_cur.bar_time == 0) return;
      m_hist[m_hist_head] = m_cur;
      m_hist_head = (m_hist_head + 1) % OF_MAX_BARS;
      if(m_hist_count < OF_MAX_BARS) m_hist_count++;
     }

   bool HistIndex(const int age, int &idx) const
     {
      // age=0 最近已封存棒；age=1 再前一根…
      if(age < 0 || age >= m_hist_count) return false;
      idx = (m_hist_head - 1 - age + OF_MAX_BARS * 2) % OF_MAX_BARS;
      return true;
     }

   void ApplyTick(const MqlTick &tk)
     {
      if(tk.time_msc <= (long)m_last_msc) return;
      // 无 last 的纯 bid/ask 更新：仍用于分类（外汇主流）
      const double px = (tk.last > 0.0 ? tk.last :
                         (tk.bid > 0.0 && tk.ask > 0.0 ? 0.5 * (tk.bid + tk.ask) : tk.bid));
      if(px <= 0.0) { m_last_msc = (ulong)tk.time_msc; return; }

      const datetime bar = iTime(m_symbol, m_tf, 0);
      if(bar == 0) return;
      if(m_cur_bar == 0)
        {
         m_cur_bar = bar;
         ResetCur(bar);
         m_cur.open = px;
         m_cur.high = px;
         m_cur.low  = px;
         m_cur.close= px;
        }
      else if(bar != m_cur_bar)
        {
         SealCur();
         m_cur_bar = bar;
         ResetCur(bar);
         m_cur.open = px;
         m_cur.high = px;
         m_cur.low  = px;
         m_cur.close= px;
        }

      const int dir = Classify(tk);
      m_last_dir = dir;
      const double w = TickWeight(tk);
      if(dir > 0) m_cur.buy_vol  += w;
      else        m_cur.sell_vol += w;
      m_cur.delta  = m_cur.buy_vol - m_cur.sell_vol;
      m_cur.volume = m_cur.buy_vol + m_cur.sell_vol;
      m_cvd += (dir > 0 ? w : -w);

      if(px > m_cur.high || m_cur.high <= 0.0) m_cur.high = px;
      if(px < m_cur.low  || m_cur.low  <= 0.0) m_cur.low  = px;
      m_cur.close = px;

      m_last_msc = (ulong)tk.time_msc;
      m_ready = true;
     }

public:
                     COrderFlowTape(void)
                       : m_symbol(""), m_tf(PERIOD_CURRENT), m_last_msc(0),
                         m_last_dir(0), m_cvd(0), m_cur_bar(0),
                         m_hist_count(0), m_hist_head(0), m_ready(false), m_err("")
                     {
                      ZeroMemory(m_cur);
                     }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf)
     {
      m_symbol = symbol;
      m_tf = tf;
      m_last_msc = 0;
      m_last_dir = 0;
      m_cvd = 0;
      m_cur_bar = 0;
      m_hist_count = 0;
      m_hist_head = 0;
      m_ready = false;
      m_err = "";
      ZeroMemory(m_cur);
      // 预热：拉取近几分钟 tick
      MqlTick ticks[];
      const datetime to = TimeCurrent();
      const datetime from = to - 3600;
      const int n = CopyTicksRange(m_symbol, ticks, COPY_TICKS_ALL, from * 1000, to * 1000);
      if(n > 0)
        {
         for(int i=0;i<n;++i)
            ApplyTick(ticks[i]);
        }
      return true;
     }

   void ResetSessionCvd(void) { m_cvd = 0.0; }

   // 每个 OnTick 调用：增量拉取新 tick
   int ProcessNewTicks(void)
     {
      MqlTick ticks[];
      ulong from_msc = (m_last_msc > 0 ? m_last_msc + 1 : (ulong)(TimeCurrent() - 60) * 1000);
      const int n = CopyTicks(m_symbol, ticks, COPY_TICKS_ALL, from_msc, 100000);
      if(n <= 0)
        {
         // 退化：至少用当前报价推一次（保证当前棒存在）
         MqlTick tk;
         if(SymbolInfoTick(m_symbol, tk))
           {
            if((ulong)tk.time_msc > m_last_msc)
               ApplyTick(tk);
           }
         return 0;
        }
      for(int i=0;i<n;++i)
         ApplyTick(ticks[i]);
      return n;
     }

   bool Ready(void) const { return m_ready && m_hist_count >= 2; }
   string LastError(void) const { return m_err; }
   double Cvd(void) const { return m_cvd; }
   datetime CurrentBarTime(void) const { return m_cur_bar; }
   SBarDelta CurrentBar(void) const { return m_cur; }
   int HistCount(void) const { return m_hist_count; }

   bool GetHist(const int age, SBarDelta &out) const
     {
      int idx;
      if(!HistIndex(age, idx)) return false;
      out = m_hist[idx];
      return true;
     }

   // 最近已收盘棒（age=0）
   bool LastClosed(SBarDelta &out) const { return GetHist(0, out); }

   double ImbalancePct(const SBarDelta &b) const
     {
      if(b.volume <= 0.0) return 0.0;
      return 100.0 * MathAbs(b.delta) / b.volume;
     }

   // 近 stack 根已收盘：同向正 Delta 数量 & 最近一根是否达失衡阈值
   bool StackImbalanceLong(const int stack, const int min_pos, const double imb_pct) const
     {
      if(m_hist_count < stack) return false;
      int pos = 0;
      for(int a=0; a<stack; ++a)
        {
         SBarDelta b;
         if(!GetHist(a, b)) return false;
         if(b.delta > 0.0) pos++;
        }
      SBarDelta last;
      if(!GetHist(0, last)) return false;
      return (pos >= min_pos && ImbalancePct(last) >= imb_pct && last.delta > 0.0);
     }

   bool StackImbalanceShort(const int stack, const int min_pos, const double imb_pct) const
     {
      if(m_hist_count < stack) return false;
      int neg = 0;
      for(int a=0; a<stack; ++a)
        {
         SBarDelta b;
         if(!GetHist(a, b)) return false;
         if(b.delta < 0.0) neg++;
        }
      SBarDelta last;
      if(!GetHist(0, last)) return false;
      return (neg >= min_pos && ImbalancePct(last) >= imb_pct && last.delta < 0.0);
     }

   // CVD 斜率：当前 CVD - N 根前估算（用已封存棒 Delta 回溯）
   double CvdSlope(const int bars) const
     {
      if(bars <= 0 || m_hist_count < 1) return 0.0;
      double sum = 0.0;
      const int n = MathMin(bars, m_hist_count);
      for(int a=0; a<n; ++a)
        {
         SBarDelta b;
         if(!GetHist(a, b)) break;
         sum += b.delta;
        }
      return sum;
     }

   // 价格新低但 CVD 抬高（看涨背离）；需至少 look 根
   bool BullishDivergence(const int look) const
     {
      if(look < 3 || m_hist_count < look) return false;
      double price_low = 0, price_prev = 0;
      double cvd_at_low = 0, cvd_at_prev = 0;
      // 近似：用封存棒累计局部 CVD（从旧到新）
      double run = m_cvd;
      // 先把当前未封存棒去掉
      run -= m_cur.delta;
      double lows[], cvds[];
      ArrayResize(lows, look);
      ArrayResize(cvds, look);
      for(int a=0; a<look; ++a)
        {
         SBarDelta b;
         if(!GetHist(a, b)) return false;
         // 从近到远：回溯 run
         lows[a] = b.low;
         cvds[a] = run; // 该棒收盘时的 CVD 近似 = 当前(去未封) - sum(0..a-1)
         run -= b.delta;
        }
      // 最近 look/2 的最低价 vs 更早 look/2
      const int half = look / 2;
      int i_recent = 0, i_older = half;
      for(int i=1;i<half;++i) if(lows[i] < lows[i_recent]) i_recent = i;
      for(int i=half+1;i<look;++i) if(lows[i] < lows[i_older]) i_older = i;
      return (lows[i_recent] < lows[i_older] && cvds[i_recent] > cvds[i_older]);
     }

   bool BearishDivergence(const int look) const
     {
      if(look < 3 || m_hist_count < look) return false;
      double run = m_cvd - m_cur.delta;
      double highs[], cvds[];
      ArrayResize(highs, look);
      ArrayResize(cvds, look);
      for(int a=0; a<look; ++a)
        {
         SBarDelta b;
         if(!GetHist(a, b)) return false;
         highs[a] = b.high;
         cvds[a] = run;
         run -= b.delta;
        }
      const int half = look / 2;
      int i_recent = 0, i_older = half;
      for(int i=1;i<half;++i) if(highs[i] > highs[i_recent]) i_recent = i;
      for(int i=half+1;i<look;++i) if(highs[i] > highs[i_older]) i_older = i;
      return (highs[i_recent] > highs[i_older] && cvds[i_recent] < cvds[i_older]);
     }

   // 吸收：近 look 根中，高量但区间 < atr*mult，且最近 Delta 与此前主导方向相反
   bool AbsorptionAgainstLong(const int look, const double vol_mult, const double range_atr, const double atr_v) const
     {
      if(atr_v <= 0.0 || m_hist_count < look + 1) return false;
      double avg_vol = 0.0;
      for(int a=1; a<=look; ++a)
        {
         SBarDelta b; if(!GetHist(a, b)) return false;
         avg_vol += b.volume;
        }
      avg_vol /= (double)look;
      SBarDelta last; if(!GetHist(0, last)) return false;
      const double rng = last.high - last.low;
      const bool high_vol = (last.volume >= avg_vol * vol_mult);
      const bool tight = (rng <= atr_v * range_atr);
      // 上攻后卖方吸收：最近 Delta 转负
      return (high_vol && tight && last.delta < 0.0 && last.close >= last.open);
     }

   bool AbsorptionAgainstShort(const int look, const double vol_mult, const double range_atr, const double atr_v) const
     {
      if(atr_v <= 0.0 || m_hist_count < look + 1) return false;
      double avg_vol = 0.0;
      for(int a=1; a<=look; ++a)
        {
         SBarDelta b; if(!GetHist(a, b)) return false;
         avg_vol += b.volume;
        }
      avg_vol /= (double)look;
      SBarDelta last; if(!GetHist(0, last)) return false;
      const double rng = last.high - last.low;
      const bool high_vol = (last.volume >= avg_vol * vol_mult);
      const bool tight = (rng <= atr_v * range_atr);
      return (high_vol && tight && last.delta > 0.0 && last.close <= last.open);
     }
  };

#endif
//+------------------------------------------------------------------+
