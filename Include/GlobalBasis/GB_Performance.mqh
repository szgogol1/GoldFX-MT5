//+------------------------------------------------------------------+
//| GB_Performance.mqh — 绩效累计与健康分（Performance 轴）             |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_PERFORMANCE_MQH
#define GLOBALBASIS_PERFORMANCE_MQH

#include "GB_Types.mqh"

class CGBPerformance
  {
private:
   SGBPerformance m_cur;
   SGBPerformance m_prev_window; // 上一窗口对照
   int            m_wins;
   double         m_gross_win;
   double         m_gross_loss;

public:
                     CGBPerformance(void) { Reset(); }

   void Reset(void)
     {
      ZeroMemory(m_cur);
      ZeroMemory(m_prev_window);
      m_wins = 0;
      m_gross_win = 0;
      m_gross_loss = 0;
     }

   // 仅清空当前窗，保留 Previous（用于滚动对比）
   void ResetCurrent(void)
     {
      ZeroMemory(m_cur);
      m_wins = 0;
      m_gross_win = 0;
      m_gross_loss = 0;
     }

   void SnapshotAsPrevious(void) { m_prev_window = m_cur; }

   void RecordTrade(const double net_pl, const double mae_pct, const double mfe_pct)
     {
      m_cur.trades++;
      m_cur.net_pl += net_pl;
      if(net_pl >= 0)
        {
         m_wins++;
         m_gross_win += net_pl;
         m_cur.gross_pl += net_pl;
        }
      else
        {
         m_gross_loss += MathAbs(net_pl);
         m_cur.gross_pl += net_pl;
        }
      m_cur.win_rate = (m_cur.trades > 0) ? (100.0 * m_wins / m_cur.trades) : 0;
      m_cur.profit_factor = (m_gross_loss > 1e-9) ? (m_gross_win / m_gross_loss) : (m_gross_win > 0 ? 99.0 : 0);
      if(mae_pct > m_cur.mae_pct) m_cur.mae_pct = mae_pct;
      if(mfe_pct > m_cur.mfe_pct) m_cur.mfe_pct = mfe_pct;
     }

   void SetRiskMetrics(const double max_dd, const double daily_dd)
     {
      m_cur.max_dd_pct = max_dd;
      m_cur.daily_dd_pct = daily_dd;
     }

   void IncOrphan(void) { m_cur.orphan_events++; }
   void IncExecFail(void) { m_cur.exec_failures++; }

   SGBPerformance Current(void) const { return m_cur; }
   SGBPerformance Previous(void) const { return m_prev_window; }

   // 简单健康分
   int ScorePerformance(void) const
     {
      double pf = m_cur.profit_factor;
      double wr = m_cur.win_rate;
      int s = 50;
      if(pf >= 1.8) s += 25;
      else if(pf >= 1.4) s += 15;
      else if(pf >= 1.1) s += 5;
      else if(pf < 1.0) s -= 25;
      if(wr >= 75) s += 15;
      else if(wr >= 60) s += 8;
      else if(wr < 50) s -= 15;
      if(m_cur.trades < 10) s = (int)(s * 0.8); // 样本不足降权
      if(s < 0) s = 0;
      if(s > 100) s = 100;
      return s;
     }

   int ScoreRisk(void) const
     {
      int s = 100;
      if(m_cur.max_dd_pct > 5) s -= 40;
      else if(m_cur.max_dd_pct > 3) s -= 20;
      else if(m_cur.max_dd_pct > 2) s -= 10;
      if(m_cur.daily_dd_pct > 2) s -= 20;
      else if(m_cur.daily_dd_pct > 1) s -= 8;
      if(m_cur.orphan_events > 0) s -= 15 * m_cur.orphan_events;
      if(s < 0) s = 0;
      return s;
     }

   bool PfDeteriorating(const double ratio_threshold=0.75) const
     {
      if(m_prev_window.profit_factor < 1e-6) return false;
      return (m_cur.profit_factor < m_prev_window.profit_factor * ratio_threshold);
     }
  };

#endif
//+------------------------------------------------------------------+
