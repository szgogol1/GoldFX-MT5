//+------------------------------------------------------------------+
//| GB_Lifecycle.mqh — 策略生命周期管理器（总装）                       |
//| Phase1 权限 = ASSISTED：AI 只分析建议，人工批准后才升版             |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_LIFECYCLE_MQH
#define GLOBALBASIS_LIFECYCLE_MQH

#include "GB_Types.mqh"
#include "GB_HardRisk.mqh"
#include "GB_Performance.mqh"
#include "GB_Execution.mqh"
#include "GB_Regime.mqh"
#include "GB_AIAnalyst.mqh"
#include "GB_Shadow.mqh"
#include "GB_Approval.mqh"

class CGBLifecycle
  {
private:
   ENUM_GB_AUTHORITY   m_auth;
   ENUM_GB_LIFECYCLE   m_lc;
   SGBStrategyId       m_id;
   CGBHardRisk         m_hard;
   CGBPerformance      m_perf;
   CGBExecution        m_exec;
   CGBRegime           m_regime;
   CGBAIAnalyst        m_ai;
   CGBShadow           m_shadow;
   CGBApproval         m_appr;
   SGBRecommendation   m_last_rec;
   SGBHealth           m_health;
   SGBGateResult       m_gates;
   datetime            m_last_review;
   int                 m_review_hours;

   int StabilityScore(void) const
     {
      // 简单：执行失败与 orphan 惩罚
      SGBPerformance p = m_perf.Current();
      int s = 90;
      s -= p.exec_failures * 5;
      s -= p.orphan_events * 10;
      if(m_lc == GB_LC_WARNING) s -= 15;
      if(m_lc == GB_LC_SUSPENDED) s -= 30;
      if(s < 0) s = 0;
      return s;
     }

public:
                     CGBLifecycle(void)
                       : m_auth(GB_AUTH_ASSISTED),
                         m_lc(GB_LC_ACTIVE),
                         m_last_review(0),
                         m_review_hours(24)
                     {
                      ZeroMemory(m_id);
                      ZeroMemory(m_last_rec);
                      ZeroMemory(m_health);
                      ZeroMemory(m_gates);
                     }

   void Init(const SGBStrategyId &id, const SGBHardLimits &hard,
             const SGBParams &params, const ENUM_GB_AUTHORITY auth=GB_AUTH_ASSISTED)
     {
      m_id = id;
      m_hard.Configure(hard);
      m_ai.SetLiveParams(params);
      // Phase1 强制 ASSISTED（拒绝静默升到 FULL）
      if(auth == GB_AUTH_FULL_AUTO || auth == GB_AUTH_SEMI_AUTO)
         m_auth = GB_AUTH_ASSISTED;
      else
         m_auth = auth;
      m_lc = GB_LC_ACTIVE;
     }

   ENUM_GB_AUTHORITY Authority(void) const { return m_auth; }
   ENUM_GB_LIFECYCLE Lifecycle(void) const { return m_lc; }
   SGBHealth Health(void) const { return m_health; }
   SGBRecommendation LastRecommendation(void) const { return m_last_rec; }
   SGBGateResult Gates(void) const { return m_gates; }
   CGBApproval *Approval(void) { return &m_appr; }
   CGBShadow *Shadow(void) { return &m_shadow; }
   CGBHardRisk *HardRisk(void) { return &m_hard; }
   CGBPerformance *Perf(void) { return &m_perf; }
   CGBExecution *Exec(void) { return &m_exec; }
   CGBAIAnalyst *AI(void) { return &m_ai; }
   SGBStrategyId Id(void) const { return m_id; }

   // 喂入体制与成本
   void UpdateMarket(const double vol, const double liq, const double funding_edge,
                     const double gross_edge, const double cost)
     {
      bool cost_dom = (gross_edge > 0 && cost >= gross_edge);
      m_regime.Update(vol, liq, funding_edge, cost_dom);
      m_exec.SetEdgeCost(gross_edge, cost);
     }

   // 定期策略复盘（默认 24h）；生成建议 + 可选 Shadow
   void RunReview(const bool force=false)
     {
      if(!force && m_last_review > 0)
        {
         if(TimeCurrent() - m_last_review < m_review_hours * 3600)
            return;
        }
      m_last_review = TimeCurrent();

      m_health = m_ai.BuildHealth(
         m_perf.ScorePerformance(),
         m_perf.ScoreRisk(),
         m_exec.ScoreExecution(),
         StabilityScore(),
         m_regime.ScoreRegimeFit());

      m_last_rec = m_ai.Analyze(
         m_perf.Current(),
         m_perf.Previous(),
         m_exec.Snapshot(),
         m_regime.Snapshot(),
         m_health);

      // 生命周期推进（不自动改参数）
      if(m_last_rec.action == GB_ACT_SUSPEND || m_last_rec.action == GB_ACT_NO_TRADE)
         m_lc = GB_LC_WARNING;
      else if(m_last_rec.action == GB_ACT_PROPOSE_V2)
         m_lc = GB_LC_REVIEW;
      else if(m_health.overall >= 85 && m_lc == GB_LC_WARNING)
         m_lc = GB_LC_ACTIVE;

      // ASSISTED：需要人批的动作进入队列
      if(m_auth == GB_AUTH_ASSISTED && m_last_rec.needs_human)
         m_appr.Submit(m_last_rec);

      // PROPOSE_V2 → 启动 Shadow（仍不交易）
      if(m_last_rec.action == GB_ACT_PROPOSE_V2 && !m_shadow.Active())
        {
         string lab = StringFormat("%s_V%d", m_id.name, m_id.version + 1);
         m_shadow.Start(lab, m_last_rec.proposed, m_perf.Current().net_pl);
         m_lc = GB_LC_OPTIMIZE;
        }

      // 滚动窗口：复盘后把当前快照为 prev
      m_perf.SnapshotAsPrevious();
     }

   // 处理人工批准（在 OnChartEvent 后调用）
   void ProcessApprovals(void)
     {
      SGBRecommendation approved;
      if(!m_appr.ConsumeApproved(approved))
         return;

      if(approved.action == GB_ACT_PROPOSE_V2)
        {
         // 人工批准后才把候选升为 live
         m_ai.SetLiveParams(approved.proposed);
         m_id.version++;
         m_shadow.Stop();
         m_lc = GB_LC_ACTIVE;
         PrintFormat("GlobalBasis: Human APPROVED %s V%d", m_id.name, m_id.version);
        }
      else if(approved.action == GB_ACT_SUSPEND || approved.action == GB_ACT_NO_TRADE)
        {
         m_lc = GB_LC_SUSPENDED;
         Print("GlobalBasis: Human APPROVED suspend");
        }
      else if(approved.action == GB_ACT_REDUCE_RISK)
        {
         // 仅收紧风险参数；Hard 仍钳制
         SGBParams p = m_ai.LiveParams();
         p.max_risk_pct = m_hard.ClampRiskPct(approved.proposed.max_risk_pct);
         m_ai.SetLiveParams(p);
         // Hard 侧也允许收紧日亏（不可放宽）
         m_hard.TightenDailyLoss(MathMin(m_hard.Limits().max_daily_loss_pct,
                                         p.max_risk_pct + 0.5));
         m_lc = GB_LC_ACTIVE;
         Print("GlobalBasis: Human APPROVED risk reduction");
        }
      else if(approved.action == GB_ACT_RESUME)
        {
         m_lc = GB_LC_ACTIVE;
         m_hard.ResetTrip();
        }
     }

   // SEMI-AUTO 才允许自动降仓/暂停；Phase1 ASSISTED 不会走这里自动改
   void ApplySemiAutoIfAllowed(void)
     {
      if(m_auth != GB_AUTH_SEMI_AUTO && m_auth != GB_AUTH_FULL_AUTO)
         return;
      if(m_last_rec.action == GB_ACT_SUSPEND || m_last_rec.action == GB_ACT_NO_TRADE)
         m_lc = GB_LC_SUSPENDED;
      if(m_last_rec.action == GB_ACT_REDUCE_RISK)
        {
         SGBParams p = m_ai.LiveParams();
         p.max_risk_pct = m_hard.ClampRiskPct(m_last_rec.proposed.max_risk_pct);
         m_ai.SetLiveParams(p);
        }
     }

   // 三道闸门：开新仓前必须调用
   bool CanOpenNewTrade(const double equity, const int open_pos,
                        const double proposed_notional, string &why)
     {
      ZeroMemory(m_gates);

      // 生命周期：SUSPENDED / RETIRED 直接拒
      if(m_lc == GB_LC_SUSPENDED || m_lc == GB_LC_RETIRED || m_lc == GB_LC_RESEARCH)
        {
         why = "Lifecycle blocks: " + GB_LifecycleToString(m_lc);
         m_gates.can_execute = false;
         return false;
        }

      m_gates.ai_gate = m_ai.GateFromAction(m_last_rec.action, m_gates.ai_why);
      m_gates.risk_gate = m_hard.Evaluate(equity, open_pos, proposed_notional, m_gates.risk_why);
      m_gates.exec_gate = m_exec.Evaluate(m_gates.exec_why);

      m_gates.can_execute =
         (m_gates.ai_gate == GB_GATE_PASS &&
          m_gates.risk_gate == GB_GATE_PASS &&
          m_gates.exec_gate == GB_GATE_PASS);

      if(!m_gates.can_execute)
        {
         why = StringFormat("Gates AI=%s Risk=%s Exec=%s",
                            m_gates.ai_why, m_gates.risk_why, m_gates.exec_why);
         return false;
        }
      why = "ALL_PASS";
      return true;
     }

   string HealthReport(void) const
     {
      return StringFormat(
         "=== AI STRATEGY HEALTH ===\n%s / %s  V%d\nStatus %s  Health %d (%s)\n"
         "Perf %d  Risk %d  Exec %d  Stab %d  Regime %d\n"
         "Auth %s  Action %s\n%s",
         m_id.venue, m_id.symbol, m_id.version,
         GB_LifecycleToString(m_lc), m_health.overall, m_health.color,
         m_health.performance, m_health.risk, m_health.execution,
         m_health.stability, m_health.regime_fit,
         GB_AuthToString(m_auth), GB_ActionToString(m_last_rec.action),
         m_last_rec.title);
     }
  };

#endif
//+------------------------------------------------------------------+
