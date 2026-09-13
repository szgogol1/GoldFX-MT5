//+------------------------------------------------------------------+
//| PortfolioEngine.mqh — 单图多品种（最多8）同步扫描与状态             |
//| 引擎：七条件 / 体制自动 / 趋势 / 震荡 / 顺势小箱体突破（互斥）      |
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
#include "BoxBreakoutStrategy.mqh"

#define GFX_MAX_SYMBOLS 8

class CPortfolioEngine
  {
private:
   string                   m_symbols[];
   CSevenConditionStrategy  m_seven[GFX_MAX_SYMBOLS];
   CRegimeDetector          m_regime[GFX_MAX_SYMBOLS];
   CTrendStrategy           m_trend[GFX_MAX_SYMBOLS];
   CRangeStrategy           m_range[GFX_MAX_SYMBOLS];
   CBoxBreakoutStrategy     m_box[GFX_MAX_SYMBOLS];
   datetime                 m_last_bar[GFX_MAX_SYMBOLS];
   ENUM_STRATEGY_ENGINE     m_engine;
   ENUM_TIMEFRAMES          m_tf;
   int                      m_count;
   SSevenCondSnapshot       m_dash_snap;
   string                   m_box_status;

   bool InitSymbolEngines(const int i, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      if(m_engine == STRAT_SEVEN_COND)
         return m_seven[i].Init(m_symbols[i], tf, p);

      if(m_engine == STRAT_TREND_ONLY)
         return m_trend[i].Init(m_symbols[i], tf, p);

      if(m_engine == STRAT_RANGE_ONLY)
         return m_range[i].Init(m_symbols[i], tf, p);

      if(m_engine == STRAT_BOX_BREAKOUT)
         return m_box[i].Init(m_symbols[i], tf, p);

      // STRAT_REGIME_AUTO（及未知回退）
      if(!m_regime[i].Init(m_symbols[i], tf, p)) return false;
      if(!m_trend[i].Init(m_symbols[i], tf, p))  return false;
      if(!m_range[i].Init(m_symbols[i], tf, p))  return false;
      return true;
     }

   bool ConfigureSymbolEngines(const int i, const SRuntimeParams &p)
     {
      if(m_engine == STRAT_SEVEN_COND)
         return m_seven[i].Configure(p);

      if(m_engine == STRAT_TREND_ONLY)
         return m_trend[i].Configure(p);

      if(m_engine == STRAT_RANGE_ONLY)
         return m_range[i].Configure(p);

      if(m_engine == STRAT_BOX_BREAKOUT)
         return m_box[i].Configure(p);

      if(!m_regime[i].Configure(p)) return false;
      if(!m_trend[i].Configure(p))  return false;
      if(!m_range[i].Configure(p))  return false;
      return true;
     }

public:
                     CPortfolioEngine(void): m_engine(STRAT_SEVEN_COND), m_tf(PERIOD_CURRENT), m_count(0), m_box_status("")
                     {
                      ZeroMemory(m_dash_snap);
                      ArrayResize(m_symbols, 0);
                     }

                    ~CPortfolioEngine(void) { Release(); }

   int Count(void) const { return m_count; }
   string SymbolAt(const int i) const { return (i>=0 && i<m_count)? m_symbols[i] : ""; }
   SSevenCondSnapshot DashSnapshot(void) const { return m_dash_snap; }
   string BoxStatus(void) const { return m_box_status; }
   ENUM_STRATEGY_ENGINE Engine(void) const { return m_engine; }

   bool Init(const string symbols_csv, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      Release();
      m_tf = tf;
      m_engine = p.strategy_engine;
      m_box_status = "";
      m_count = ParseSymbolsCSV(symbols_csv, m_symbols, _Symbol);
      for(int i=0;i<m_count;++i)
        {
         if(!SymbolSelect(m_symbols[i], true))
            Print("警告: 无法选择品种 ", m_symbols[i]);
         m_last_bar[i] = 0;
         if(!InitSymbolEngines(i, tf, p))
           {
            PrintFormat("GoldFX Portfolio: 引擎初始化失败 %s (%s)",
                        m_symbols[i], StratToString(m_engine));
            return false;
           }
        }
      return true;
     }

   bool Reconfigure(const SRuntimeParams &p)
     {
      // 策略引擎切换需重建（Init）；此处仅刷新同引擎参数
      if(p.strategy_engine != m_engine)
         return Init(p.symbols_csv, m_tf, p);

      for(int i=0;i<m_count;++i)
        {
         if(!ConfigureSymbolEngines(i, p))
            return false;
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
         m_box[i].Release();
        }
      m_count = 0;
      m_box_status = "";
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
            if(m_engine==STRAT_SEVEN_COND && m_symbols[i]==_Symbol)
               m_dash_snap = m_seven[i].LastSnapshot();
            if(m_engine==STRAT_BOX_BREAKOUT && m_symbols[i]==_Symbol)
               m_box_status = m_box[i].LastStatus();
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
         else if(m_engine == STRAT_TREND_ONLY)
           {
            sig = m_trend[i].Evaluate();
           }
         else if(m_engine == STRAT_RANGE_ONLY)
           {
            sig = m_range[i].Evaluate();
           }
         else if(m_engine == STRAT_BOX_BREAKOUT)
           {
            sig = m_box[i].Evaluate();
            if(m_symbols[i]==_Symbol)
               m_box_status = m_box[i].LastStatus();
           }
         else
           {
            // STRAT_REGIME_AUTO：体制自动；可用 run_mode 强制趋势/震荡
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
      if(m_engine == STRAT_SEVEN_COND)
        {
         for(int i=0;i<m_count;++i)
           {
            if(m_symbols[i] != _Symbol) continue;
            m_seven[i].Evaluate(false);
            m_dash_snap = m_seven[i].LastSnapshot();
            break;
           }
         return;
        }
      if(m_engine == STRAT_BOX_BREAKOUT)
        {
         for(int i=0;i<m_count;++i)
           {
            if(m_symbols[i] != _Symbol) continue;
            m_box_status = m_box[i].LastStatus();
            break;
           }
        }
     }
  };

#endif
//+------------------------------------------------------------------+
