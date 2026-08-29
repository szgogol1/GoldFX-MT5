//+------------------------------------------------------------------+
//| GB_HardRisk.mqh — 硬风控闸门（AI 无权放宽）                         |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_HARD_RISK_MQH
#define GLOBALBASIS_HARD_RISK_MQH

#include "GB_Types.mqh"

class CGBHardRisk
  {
private:
   SGBHardLimits m_lim;
   double        m_day_start_eq;
   double        m_peak_eq;
   datetime      m_day_stamp;
   bool          m_tripped;

   datetime DayStamp(void) const
     {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
     }

public:
                     CGBHardRisk(void)
                       : m_day_start_eq(0), m_peak_eq(0), m_day_stamp(0), m_tripped(false)
                     {
                      m_lim.max_portfolio_dd_pct  = 5.0;
                      m_lim.max_daily_loss_pct    = 2.0;
                      m_lim.max_position_notional = 0;
                      m_lim.max_positions         = 2;
                      m_lim.emergency_stop        = false;
                     }

   // 仅允许人类/配置初始化时设置；运行中 AI 不得调用放宽接口
   void Configure(const SGBHardLimits &lim)
     {
      m_lim = lim;
      // 防呆：不允许配置成「无限制」绕过（0 表示该项关闭，除 emergency）
      if(m_lim.max_portfolio_dd_pct < 0.5) m_lim.max_portfolio_dd_pct = 0.5;
      if(m_lim.max_daily_loss_pct   < 0.2) m_lim.max_daily_loss_pct   = 0.2;
     }

   SGBHardLimits Limits(void) const { return m_lim; }

   // AI / SEMI 只允许收紧，不允许放宽
   bool TightenDailyLoss(const double pct)
     {
      if(pct <= 0) return false;
      if(pct >= m_lim.max_daily_loss_pct) return false; // 拒绝放宽或不变大
      m_lim.max_daily_loss_pct = pct;
      return true;
     }

   bool TightenPortfolioDD(const double pct)
     {
      if(pct <= 0) return false;
      if(pct >= m_lim.max_portfolio_dd_pct) return false;
      m_lim.max_portfolio_dd_pct = pct;
      return true;
     }

   void SetEmergencyStop(const bool on) { m_lim.emergency_stop = on; m_tripped = on; }

   void RefreshEquityBaselines(const double equity)
     {
      datetime d = DayStamp();
      if(d != m_day_stamp)
        {
         m_day_stamp = d;
         m_day_start_eq = equity;
        }
      if(equity > m_peak_eq)
         m_peak_eq = equity;
      if(m_day_start_eq <= 0) m_day_start_eq = equity;
      if(m_peak_eq <= 0) m_peak_eq = equity;
     }

   // Risk Gate：是否允许新开仓 / 继续加仓
   ENUM_GB_GATE Evaluate(const double equity, const int open_positions,
                         const double proposed_notional, string &why)
     {
      RefreshEquityBaselines(equity);

      if(m_lim.emergency_stop || m_tripped)
        {
         why = "EMERGENCY_STOP";
         return GB_GATE_FAIL;
        }

      if(m_lim.max_positions > 0 && open_positions >= m_lim.max_positions)
        {
         why = StringFormat("MaxPositions %d", m_lim.max_positions);
         return GB_GATE_FAIL;
        }

      if(m_lim.max_position_notional > 0 && proposed_notional > m_lim.max_position_notional)
        {
         why = "MaxNotional";
         return GB_GATE_FAIL;
        }

      if(m_peak_eq > 0)
        {
         double dd = 100.0 * (m_peak_eq - equity) / m_peak_eq;
         if(dd >= m_lim.max_portfolio_dd_pct)
           {
            why = StringFormat("HardDD %.2f%%>=%.2f%%", dd, m_lim.max_portfolio_dd_pct);
            m_tripped = true;
            return GB_GATE_FAIL;
           }
        }

      if(m_day_start_eq > 0)
        {
         double dloss = 100.0 * (m_day_start_eq - equity) / m_day_start_eq;
         if(dloss >= m_lim.max_daily_loss_pct)
           {
            why = StringFormat("DailyLoss %.2f%%>=%.2f%%", dloss, m_lim.max_daily_loss_pct);
            return GB_GATE_FAIL;
           }
        }

      why = "OK";
      return GB_GATE_PASS;
     }

   // 钳制 AI 建议风险：永远不超过 hard
   double ClampRiskPct(const double suggested) const
     {
      // 建议风险相对日亏上限的软比例，绝不突破 hard daily
      double cap = m_lim.max_daily_loss_pct;
      if(suggested <= 0) return MathMin(0.5, cap);
      return MathMin(suggested, cap);
     }

   bool Tripped(void) const { return m_tripped; }
   void ResetTrip(void) { m_tripped = false; } // 仅人工恢复
  };

#endif
//+------------------------------------------------------------------+
