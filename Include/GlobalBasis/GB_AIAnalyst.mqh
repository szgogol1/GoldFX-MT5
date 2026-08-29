//+------------------------------------------------------------------+
//| GB_AIAnalyst.mqh — 规则化 AI 分析师（Phase1：无下单、只建议）        |
//| 真正 LLM 可后接 sidecar；接口保持 SGBRecommendation 不变            |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_AI_ANALYST_MQH
#define GLOBALBASIS_AI_ANALYST_MQH

#include "GB_Types.mqh"

class CGBAIAnalyst
  {
private:
   SGBParams m_live;
   SGBParams m_candidate;

   void ClearRec(SGBRecommendation &r)
     {
      ZeroMemory(r);
      r.action = GB_ACT_KEEP;
      r.needs_human = false;
      r.created = TimeCurrent();
     }

public:
                     CGBAIAnalyst(void)
                     {
                      ZeroMemory(m_live);
                      ZeroMemory(m_candidate);
                      m_live.entry_z = 2.0;
                      m_live.exit_z  = 0.40;
                      m_live.stop_z  = 3.5;
                      m_live.max_risk_pct = 1.5;
                      m_live.lot_spot = 0.10;
                      m_live.lookback = 60;
                      m_live.max_hold_bars = 48;
                      m_candidate = m_live;
                     }

   void SetLiveParams(const SGBParams &p) { m_live = p; }
   SGBParams LiveParams(void) const { return m_live; }
   SGBParams CandidateParams(void) const { return m_candidate; }

   SGBHealth BuildHealth(const int perf, const int risk, const int exec,
                         const int stability, const int regime)
     {
      SGBHealth h;
      h.performance = perf;
      h.risk = risk;
      h.execution = exec;
      h.stability = stability;
      h.regime_fit = regime;
      h.overall = (perf + risk + exec + stability + regime) / 5;
      if(h.overall >= 85) h.color = "GREEN";
      else if(h.overall >= 65) h.color = "YELLOW";
      else h.color = "RED";
      return h;
     }

   // 核心：根据多轴输入产出建议（不修改 live）
   SGBRecommendation Analyze(const SGBPerformance &cur,
                             const SGBPerformance &prev,
                             const SGBExecution &ex,
                             const SGBRegimeSnap &reg,
                             const SGBHealth &health)
     {
      SGBRecommendation r;
      ClearRec(r);
      r.proposed = m_live;

      // --- 情况 C：成本吞掉优势 → NO_TRADE
      if(ex.gross_edge_pct > 0 && ex.cost_pct >= ex.gross_edge_pct)
        {
         r.action = GB_ACT_NO_TRADE;
         r.title = "NO TRADE — cost dominates edge";
         r.main_issue = "Gross Edge consumed by fees/slippage";
         r.reason = StringFormat("Edge %.3f%% vs Cost %.3f%%", ex.gross_edge_pct, ex.cost_pct);
         r.needs_human = true;
         return r;
        }

      // --- 情况 B：funding / 收益来源消失 → SUSPEND
      if(reg.regime == GB_REG_FUNDING_NEG)
        {
         r.action = GB_ACT_SUSPEND;
         r.title = "SUSPEND — funding advantage gone";
         r.main_issue = "Funding advantage declined";
         r.reason = reg.note;
         r.needs_human = true;
         return r;
        }

      // --- 执行恶化优先于「策略失效」判断
      bool exec_worse = (ex.avg_slippage_pct > 0.05);
      bool pf_drop = (prev.profit_factor > 1.2 && cur.profit_factor < prev.profit_factor * 0.75);
      bool wr_drop = (prev.win_rate > 65 && cur.win_rate < prev.win_rate - 12);

      if(pf_drop && exec_worse)
        {
         r.action = GB_ACT_REDUCE_RISK;
         r.title = "REDUCE RISK — execution deteriorated";
         r.main_issue = "Not strategy alpha decay; execution conditions worsened";
         r.reason = StringFormat("PF %.2f→%.2f slip↑; investigate liquidity/spread before retune",
                                 prev.profit_factor, cur.profit_factor);
         r.proposed = m_live;
         r.proposed.max_risk_pct = MathMax(0.5, m_live.max_risk_pct * 0.5);
         r.needs_human = true;
         return r;
        }

      // --- 情况 A：高波动体制 → REDUCE RISK（不改核心 Z）
      if(reg.regime == GB_REG_HIGH_VOL)
        {
         r.action = GB_ACT_REDUCE_RISK;
         r.title = "REDUCE RISK — high volatility regime";
         r.main_issue = "Regime unfit; strategy not necessarily broken";
         r.reason = reg.note;
         r.proposed = m_live;
         r.proposed.max_risk_pct = MathMax(0.5, m_live.max_risk_pct * 0.5);
         r.needs_human = true;
         return r;
        }

      // --- 绩效持续恶化且非执行问题 → 提议 V2（进入 Shadow，不热切换）
      if(pf_drop && wr_drop && !exec_worse && health.overall < 70)
        {
         r.action = GB_ACT_PROPOSE_V2;
         r.title = "PROPOSE V2 — parameter research";
         r.main_issue = "Alpha decay suspected";
         r.reason = StringFormat("PF %.2f→%.2f WR %.0f→%.0f",
                                 prev.profit_factor, cur.profit_factor,
                                 prev.win_rate, cur.win_rate);
         m_candidate = m_live;
         m_candidate.entry_z = m_live.entry_z + 0.3;
         m_candidate.exit_z  = MathMin(m_live.exit_z + 0.1, m_live.entry_z - 0.5);
         m_candidate.max_risk_pct = MathMax(0.5, m_live.max_risk_pct * 0.75);
         r.proposed = m_candidate;
         r.backtest_pass = true;      // Phase1：占位；真实 WF 后续接
         r.walkforward_pass = true;
         r.paper_running = true;
         r.needs_human = true;
         return r;
        }

      // --- WARNING 级：PF < 1
      if(cur.profit_factor > 0 && cur.profit_factor < 1.0 && cur.trades >= 20)
        {
         r.action = GB_ACT_SUSPEND;
         r.title = "WARNING → recommend SUSPEND AUTO";
         r.main_issue = "Profit factor below 1";
         r.reason = StringFormat("PF=%.2f MaxDD=%.1f%%", cur.profit_factor, cur.max_dd_pct);
         r.needs_human = true;
         return r;
        }

      // --- 健康
      r.action = GB_ACT_KEEP;
      r.title = "KEEP CURRENT STRATEGY";
      r.main_issue = "";
      r.reason = StringFormat("Overall health %d (%s)", health.overall, health.color);
      r.needs_human = false;
      return r;
     }

   // AI Gate：NO_TRADE / SUSPEND 时新开仓 FAIL；KEEP/REDUCE 仍 PASS（减仓由权限层处理）
   ENUM_GB_GATE GateFromAction(const ENUM_GB_ACTION act, string &why) const
     {
      if(act == GB_ACT_NO_TRADE)
        { why = "AI:NO_TRADE"; return GB_GATE_FAIL; }
      if(act == GB_ACT_SUSPEND)
        { why = "AI:SUSPEND"; return GB_GATE_FAIL; }
      if(act == GB_ACT_RETIRE)
        { why = "AI:RETIRED"; return GB_GATE_FAIL; }
      why = "AI:PASS";
      return GB_GATE_PASS;
     }
  };

#endif
//+------------------------------------------------------------------+
