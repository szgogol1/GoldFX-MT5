//+------------------------------------------------------------------+
//| GB_Regime.mqh — 市场体制分析（基差 / funding / 波动）               |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_REGIME_MQH
#define GLOBALBASIS_REGIME_MQH

#include "GB_Types.mqh"

class CGBRegime
  {
private:
   SGBRegimeSnap m_snap;

public:
                     CGBRegime(void) { ZeroMemory(m_snap); m_snap.regime = GB_REG_UNKNOWN; }

   // 由外部喂入指标；本层不做交易决策
   void Update(const double vol_score, const double liq_score,
               const double funding_edge, const bool cost_dominates)
     {
      m_snap.volatility_score = vol_score;
      m_snap.liquidity_score  = liq_score;
      m_snap.funding_edge     = funding_edge;

      if(cost_dominates)
        {
         m_snap.regime = GB_REG_COST_DOMINANT;
         m_snap.note = "Gross edge consumed by costs";
        }
      else if(funding_edge < -20.0)
        {
         m_snap.regime = GB_REG_FUNDING_NEG;
         m_snap.note = "Funding advantage declined / negative";
        }
      else if(liq_score < 40.0)
        {
         m_snap.regime = GB_REG_LOW_LIQUIDITY;
         m_snap.note = "Liquidity deteriorated";
        }
      else if(vol_score > 80.0)
        {
         m_snap.regime = GB_REG_HIGH_VOL;
         m_snap.note = "Volatility regime elevated";
        }
      else
        {
         m_snap.regime = GB_REG_NORMAL;
         m_snap.note = "Normal regime";
        }
     }

   SGBRegimeSnap Snapshot(void) const { return m_snap; }

   int ScoreRegimeFit(void) const
     {
      switch(m_snap.regime)
        {
         case GB_REG_NORMAL:        return 92;
         case GB_REG_HIGH_VOL:      return 55;
         case GB_REG_LOW_LIQUIDITY: return 45;
         case GB_REG_FUNDING_NEG:   return 30;
         case GB_REG_COST_DOMINANT: return 15;
         default:                   return 50;
        }
     }
  };

#endif
//+------------------------------------------------------------------+
