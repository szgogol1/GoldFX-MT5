//+------------------------------------------------------------------+
//| GB_Shadow.mqh — Shadow Mode 账本（候选版本只记账不下单）            |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_SHADOW_MQH
#define GLOBALBASIS_SHADOW_MQH

#include "GB_Types.mqh"

class CGBShadow
  {
private:
   bool     m_active;
   string   m_label;
   SGBParams m_params;
   double   m_shadow_pl;
   double   m_live_pl_baseline;
   int      m_signals;
   int      m_hypothetical_trades;

public:
                     CGBShadow(void)
                       : m_active(false), m_shadow_pl(0), m_live_pl_baseline(0),
                         m_signals(0), m_hypothetical_trades(0)
                     {
                      ZeroMemory(m_params);
                     }

   bool Active(void) const { return m_active; }
   SGBParams Params(void) const { return m_params; }
   double ShadowPL(void) const { return m_shadow_pl; }
   int    Signals(void) const { return m_signals; }

   void Start(const string label, const SGBParams &p, const double live_pl_now)
     {
      m_active = true;
      m_label = label;
      m_params = p;
      m_shadow_pl = 0;
      m_live_pl_baseline = live_pl_now;
      m_signals = 0;
      m_hypothetical_trades = 0;
     }

   void Stop(void) { m_active = false; }

   // 假设成交：由上层在信号触发时调用（不发真实订单）
   void OnHypotheticalFill(const double net_pl)
     {
      if(!m_active) return;
      m_shadow_pl += net_pl;
      m_hypothetical_trades++;
      m_signals++;
     }

   void OnSignalOnly(void)
     {
      if(!m_active) return;
      m_signals++;
     }

   // Shadow 相对 Live 增量优势
   double AdvantageVsLive(const double live_pl_now) const
     {
      if(!m_active) return 0;
      double live_delta = live_pl_now - m_live_pl_baseline;
      return m_shadow_pl - live_delta;
     }

   bool ClearlyBetter(const double live_pl_now, const double min_edge=50.0, const int min_trades=15) const
     {
      if(!m_active || m_hypothetical_trades < min_trades) return false;
      return (AdvantageVsLive(live_pl_now) >= min_edge);
     }

   string Label(void) const { return m_label; }
   int HypotheticalTrades(void) const { return m_hypothetical_trades; }
  };

#endif
//+------------------------------------------------------------------+
