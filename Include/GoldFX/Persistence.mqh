//+------------------------------------------------------------------+
//| Persistence.mqh — 峰值回撤 / 滚动胜率 / 暂停状态跨重启持久化        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_PERSISTENCE_MQH
#define GOLDFX_PERSISTENCE_MQH

#include "Common.mqh"

#define GFX_GV_PEAK      "GFX_PEAK_EQ_"
#define GFX_GV_PAUSE     "GFX_PAUSED_"
#define GFX_GV_WINS      "GFX_ROLL_W_"
#define GFX_GV_TRADES    "GFX_ROLL_N_"
#define GFX_GV_ADAPT     "GFX_ADAPT_M_"

class CPersistence
  {
private:
   string            m_key;

   string K(const string prefix) const { return prefix + m_key; }

public:
                     CPersistence(void): m_key("default") {}

   void Init(const int magic)
     {
      m_key = IntegerToString(magic);
     }

   double LoadPeakEquity(const double fallback)
     {
      const string name = K(GFX_GV_PEAK);
      if(!GlobalVariableCheck(name))
        {
         GlobalVariableSet(name, fallback);
         return fallback;
        }
      return GlobalVariableGet(name);
     }

   void SavePeakEquity(const double peak)
     {
      GlobalVariableSet(K(GFX_GV_PEAK), peak);
     }

   bool LoadPaused(void)
     {
      const string name = K(GFX_GV_PAUSE);
      if(!GlobalVariableCheck(name))
         return false;
      return (GlobalVariableGet(name) > 0.5);
     }

   void SavePaused(const bool paused)
     {
      GlobalVariableSet(K(GFX_GV_PAUSE), paused ? 1.0 : 0.0);
     }

   void LoadRollStats(int &wins, int &trades)
     {
      wins = 0; trades = 0;
      if(GlobalVariableCheck(K(GFX_GV_WINS)))
         wins = (int)GlobalVariableGet(K(GFX_GV_WINS));
      if(GlobalVariableCheck(K(GFX_GV_TRADES)))
         trades = (int)GlobalVariableGet(K(GFX_GV_TRADES));
     }

   void SaveRollStats(const int wins, const int trades)
     {
      GlobalVariableSet(K(GFX_GV_WINS), wins);
      GlobalVariableSet(K(GFX_GV_TRADES), trades);
     }

   double LoadAdaptMult(const double fallback=1.0)
     {
      const string name = K(GFX_GV_ADAPT);
      if(!GlobalVariableCheck(name))
         return fallback;
      return GlobalVariableGet(name);
     }

   void SaveAdaptMult(const double m)
     {
      GlobalVariableSet(K(GFX_GV_ADAPT), m);
     }
  };

#endif
//+------------------------------------------------------------------+
