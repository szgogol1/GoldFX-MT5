//+------------------------------------------------------------------+
//| PortfolioEngine.mqh — 单图多品种（最多8）同步扫描与状态             |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_PORTFOLIO_ENGINE_MQH
#define GOLDFX_PORTFOLIO_ENGINE_MQH

#include "Common.mqh"
#include "SevenConditionStrategy.mqh"
#include "RegimeDetector.mqh"
#include "TrendStrategy.mqh"
#include "RangeStrategy.mqh"

#define GFX_MAX_SYMBOLS 8

class CPortfolioEngine
  {
private:
   string                   m_symbols[];
   CSevenConditionStrategy  m_seven[GFX_MAX_SYMBOLS];
   CRegimeDetector          m_regime[GFX_MAX_SYMBOLS];
   CTrendStrategy           m_trend[GFX_MAX_SYMBOLS];
   CRangeStrategy           m_range[GFX_MAX_SYMBOLS];
   datetime                 m_last_bar[GFX_MAX_SYMBOLS];
   ENUM_STRATEGY_ENGINE     m_engine;
   ENUM_TIMEFRAMES          m_tf;
   int                      m_count;
   SSevenCondSnapshot       m_dash_snap; // 图表品种快照

public:
                     CPortfolioEngine(void): m_engine(STRAT_SEVEN_COND), m_tf(PERIOD_CURRENT), m_count(0)
                     {
                      ZeroMemory(m_dash_snap);
                      ArrayResize(m_symbols, 0);
                     }

                    ~CPortfolioEngine(void) { Release(); }

   int Count(void) const { return m_count; }
   string SymbolAt(const int i) const { return (i>=0 && i<m_count)? m_symbols[i] : ""; }
   SSevenCondSnapshot DashSnapshot(void) const { return m_dash_snap; }

   bool Init(const string symbols_csv, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      Release();
      m_tf = tf;
      m_engine = p.strategy_engine;
      m_count = ParseSymbolsCSV(symbols_csv, m_symbols, _Symbol);
      for(int i=0;i<m_count;++i)
        {
         if(!SymbolSelect(m_symbols[i], true))
            Print("警告: 无法选择品种 ", m_symbols[i]);
         m_last_bar[i] = 0;
         if(m_engine == STRAT_SEVEN_COND)
           {
            if(!m_seven[i].Init(m_symbols[i], tf, p)) return false;
           }
         else
           {
            if(!m_regime[i].Init(m_symbols[i], tf, p)) return false;
            if(!m_trend[i].Init(m_symbols[i], tf, p)) return false;
            if(!m_range[i].Init(m_symbols[i], tf, p)) return false;
           }
        }
      return true;
     }

   bool Reconfigure(const SRuntimeParams &p)
     {
      m_engine = p.strategy_engine;
      for(int i=0;i<m_count;++i)
        {
         if(m_engine == STRAT_SEVEN_COND)
           {
            if(!m_seven[i].Configure(p)) return false;
           }
         else
           {
            if(!m_regime[i].Configure(p)) return false;
            if(!m_trend[i].Configure(p)) return false;
            if(!m_range[i].Configure(p)) return false;
           }
        }
      return true;
     }

   void Release(void)
     {
      for(int i=0;i<m_count;++i)
        {
         m_seven[i].Release();
         m_regime[i].Release();
         m_trend[i].Release();
         m_range[i].Release();
        }
      m_count = 0;
     }

   // 扫描全部品种；out_signals 装入有效信号（可能0）
   int ScanNewBars(SSignalResult &out_signals[], const ENUM_RUN_MODE run_mode)
     {
      ArrayResize(out_signals, 0);
      if(run_mode == MODE_FLAT)
         return 0;

      for(int i=0;i<m_count;++i)
        {
         const datetime bar = iTime(m_symbols[i], m_tf, 0);
         const bool is_new = (bar != 0 && bar != m_last_bar[i]);
         if(!is_new)
           {
            // 仍刷新图表品种七条件快照供仪表盘
            if(m_engine==STRAT_SEVEN_COND && m_symbols[i]==_Symbol)
               m_dash_snap = m_seven[i].LastSnapshot();
            continue;
           }
         m_last_bar[i] = bar;

         SSignalResult sig;
         InitSignal(sig);

         if(m_engine == STRAT_SEVEN_COND)
           {
            string why;
            if(!m_seven[i].BarsReady(why))
               continue;
            sig = m_seven[i].Evaluate(true);
            if(m_symbols[i]==_Symbol)
               m_dash_snap = m_seven[i].LastSnapshot();
           }
         else
           {
            ENUM_MARKET_REGIME reg = m_regime[i].Evaluate(true);
            if(run_mode == MODE_TREND) reg = REGIME_TREND;
            if(run_mode == MODE_RANGE) reg = REGIME_RANGE;
            if(reg == REGIME_TREND) sig = m_trend[i].Evaluate();
            else if(reg == REGIME_RANGE) sig = m_range[i].Evaluate();
            sig.symbol = m_symbols[i];
           }

         if(sig.signal == SIGNAL_NONE)
            continue;
         if(StringLen(sig.symbol)==0)
            sig.symbol = m_symbols[i];

         const int n = ArraySize(out_signals);
         ArrayResize(out_signals, n+1);
         out_signals[n] = sig;
        }
      return ArraySize(out_signals);
     }

   // 强制刷新图表品种快照（非新K也可）
   void RefreshDashSnapshot(void)
     {
      if(m_engine != STRAT_SEVEN_COND) return;
      for(int i=0;i<m_count;++i)
        {
         if(m_symbols[i] != _Symbol) continue;
         m_seven[i].Evaluate(false);
         m_dash_snap = m_seven[i].LastSnapshot();
         break;
        }
     }
  };

#endif
//+------------------------------------------------------------------+
