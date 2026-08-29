//+------------------------------------------------------------------+
//| GB_Execution.mqh — 执行质量闸门                                    |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_EXECUTION_MQH
#define GLOBALBASIS_EXECUTION_MQH

#include "GB_Types.mqh"

class CGBExecution
  {
private:
   SGBExecution m_ex;
   double       m_max_slippage_pct;
   double       m_max_latency_ms;
   double       m_max_spread_pct;

public:
                     CGBExecution(void)
                       : m_max_slippage_pct(0.10),
                         m_max_latency_ms(500),
                         m_max_spread_pct(0.08)
                     {
                      ZeroMemory(m_ex);
                     }

   void ConfigureGates(const double max_slip, const double max_lat, const double max_spread)
     {
      m_max_slippage_pct = max_slip;
      m_max_latency_ms   = max_lat;
      m_max_spread_pct   = max_spread;
     }

   void Update(const SGBExecution &ex) { m_ex = ex; }

   void RecordFill(const double slip_pct, const double latency_ms, const double fee, const double funding)
     {
      // 指数平滑
      const double a = 0.2;
      m_ex.avg_slippage_pct = (1-a)*m_ex.avg_slippage_pct + a*slip_pct;
      m_ex.avg_latency_ms   = (1-a)*m_ex.avg_latency_ms   + a*latency_ms;
      m_ex.fees    += fee;
      m_ex.funding += funding;
     }

   void SetEdgeCost(const double gross_edge, const double cost)
     {
      m_ex.gross_edge_pct = gross_edge;
      m_ex.cost_pct = cost;
     }

   SGBExecution Snapshot(void) const { return m_ex; }

   int ScoreExecution(void) const
     {
      int s = 100;
      if(m_ex.avg_slippage_pct > m_max_slippage_pct) s -= 30;
      else if(m_ex.avg_slippage_pct > m_max_slippage_pct * 0.5) s -= 10;
      if(m_ex.avg_latency_ms > m_max_latency_ms) s -= 20;
      if(m_ex.cost_pct > m_ex.gross_edge_pct && m_ex.gross_edge_pct > 0) s -= 40;
      if(s < 0) s = 0;
      return s;
     }

   // Execution Gate
   ENUM_GB_GATE Evaluate(string &why) const
     {
      if(m_ex.gross_edge_pct > 0 && m_ex.cost_pct >= m_ex.gross_edge_pct)
        {
         why = StringFormat("Cost %.3f%% >= Edge %.3f%%", m_ex.cost_pct, m_ex.gross_edge_pct);
         return GB_GATE_FAIL;
        }
      if(m_ex.avg_slippage_pct > m_max_slippage_pct)
        {
         why = StringFormat("Slippage %.3f%%", m_ex.avg_slippage_pct);
         return GB_GATE_FAIL;
        }
      if(m_ex.avg_spread_pct > m_max_spread_pct && m_max_spread_pct > 0)
        {
         why = StringFormat("Spread %.3f%%", m_ex.avg_spread_pct);
         return GB_GATE_FAIL;
        }
      if(m_ex.avg_latency_ms > m_max_latency_ms)
        {
         why = StringFormat("Latency %.0fms", m_ex.avg_latency_ms);
         return GB_GATE_FAIL;
        }
      why = "OK";
      return GB_GATE_PASS;
     }
  };

#endif
//+------------------------------------------------------------------+
