//+------------------------------------------------------------------+
//| GB_Types.mqh — GlobalBasis 4.0 核心类型                            |
//| AI = 分析师；Hard Risk / Human Approval 为强制闸门                  |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_TYPES_MQH
#define GLOBALBASIS_TYPES_MQH

//--- 人工权限（Phase1 仅开放 ASSISTED）
enum ENUM_GB_AUTHORITY
  {
   GB_AUTH_MANUAL     = 0,
   GB_AUTH_ASSISTED   = 1,  // Phase 1
   GB_AUTH_SEMI_AUTO  = 2,  // Phase 2：可降仓/暂停
   GB_AUTH_FULL_AUTO  = 3   // Phase 3+：边界内调参
  };

//--- 策略生命周期
enum ENUM_GB_LIFECYCLE
  {
   GB_LC_RESEARCH    = 0,
   GB_LC_BACKTEST    = 1,
   GB_LC_PAPER       = 2,
   GB_LC_LIVE_SMALL  = 3,
   GB_LC_ACTIVE      = 4,
   GB_LC_REVIEW      = 5,
   GB_LC_OPTIMIZE    = 6,
   GB_LC_WARNING     = 7,
   GB_LC_SUSPENDED   = 8,
   GB_LC_RETIRED     = 9
  };

//--- AI 建议动作（不直接下单）
enum ENUM_GB_ACTION
  {
   GB_ACT_KEEP          = 0,
   GB_ACT_REDUCE_RISK   = 1,
   GB_ACT_SUSPEND       = 2,
   GB_ACT_NO_TRADE      = 3,
   GB_ACT_PROPOSE_V2    = 4,
   GB_ACT_RESUME        = 5,
   GB_ACT_RETIRE        = 6
  };

//--- 三道闸门结果
enum ENUM_GB_GATE
  {
   GB_GATE_FAIL = 0,
   GB_GATE_PASS = 1
  };

//--- 市场体制（基差/funding 视角）
enum ENUM_GB_REGIME
  {
   GB_REG_UNKNOWN      = 0,
   GB_REG_NORMAL       = 1,
   GB_REG_HIGH_VOL     = 2,
   GB_REG_LOW_LIQUIDITY= 3,
   GB_REG_FUNDING_NEG  = 4,  // 空永续不再占优
   GB_REG_COST_DOMINANT= 5   // 成本 > 毛优势
  };

//--- 策略身份
struct SGBStrategyId
  {
   string venue;       // Binance / IBKR / MT5
   string symbol;      // BTC / XAU / GC-XAU
   string name;        // BTC_Basis_V1
   int    version;     // 1,2,...
  };

//--- 可调参数（候选版本）；硬风控不在此结构
struct SGBParams
  {
   double entry_z;
   double exit_z;
   double stop_z;
   double max_risk_pct;     // 建议风险，仍受 Hard 上限钳制
   double lot_spot;
   int    lookback;
   int    max_hold_bars;
  };

//--- Hard Limits — AI 永远不能写入这些字段的放宽
struct SGBHardLimits
  {
   double max_portfolio_dd_pct;   // 如 5.0
   double max_daily_loss_pct;     // 如 2.0
   double max_position_notional;  // 0=不限
   int    max_positions;
   bool   emergency_stop;         // 人工/系统置位后全停
  };

//--- 绩效快照
struct SGBPerformance
  {
   int    trades;
   double win_rate;          // 0-100
   double gross_pl;
   double net_pl;
   double profit_factor;
   double max_dd_pct;
   double daily_dd_pct;
   double mae_pct;
   double mfe_pct;
   int    orphan_events;
   int    exec_failures;
  };

//--- 执行质量
struct SGBExecution
  {
   double avg_slippage_pct;
   double avg_latency_ms;
   double fees;
   double funding;           // 可正可负
   double avg_spread_pct;
   double gross_edge_pct;    // 毛优势
   double cost_pct;          // 成本合计
  };

//--- 体制快照
struct SGBRegimeSnap
  {
   ENUM_GB_REGIME regime;
   double volatility_score;  // 0-100
   double liquidity_score;
   double funding_edge;      // 相对历史，可为负
   string note;
  };

//--- 健康分
struct SGBHealth
  {
   int performance;   // 0-100
   int risk;
   int execution;
   int stability;
   int regime_fit;
   int overall;
   string color;      // GREEN / YELLOW / RED
  };

//--- AI 建议（只读输出）
struct SGBRecommendation
  {
   ENUM_GB_ACTION action;
   string         title;
   string         reason;
   string         main_issue;
   SGBParams      proposed;     // 仅当 PROPOSE_V2
   bool           backtest_pass;
   bool           walkforward_pass;
   bool           paper_running;
   bool           needs_human;  // ASSISTED 下几乎总是 true（除 KEEP 日志）
   datetime       created;
  };

//--- 闸门汇总
struct SGBGateResult
  {
   ENUM_GB_GATE ai_gate;
   ENUM_GB_GATE risk_gate;
   ENUM_GB_GATE exec_gate;
   string       ai_why;
   string       risk_why;
   string       exec_why;
   bool         can_execute;   // 三者皆 PASS
  };

string GB_LifecycleToString(const ENUM_GB_LIFECYCLE lc)
  {
   switch(lc)
     {
      case GB_LC_RESEARCH:   return "RESEARCH";
      case GB_LC_BACKTEST:   return "BACKTEST";
      case GB_LC_PAPER:      return "PAPER";
      case GB_LC_LIVE_SMALL: return "LIVE_SMALL";
      case GB_LC_ACTIVE:     return "ACTIVE";
      case GB_LC_REVIEW:     return "REVIEW";
      case GB_LC_OPTIMIZE:   return "OPTIMIZE";
      case GB_LC_WARNING:    return "WARNING";
      case GB_LC_SUSPENDED:  return "SUSPENDED";
      case GB_LC_RETIRED:    return "RETIRED";
     }
   return "?";
  }

string GB_ActionToString(const ENUM_GB_ACTION a)
  {
   switch(a)
     {
      case GB_ACT_KEEP:        return "KEEP";
      case GB_ACT_REDUCE_RISK: return "REDUCE_RISK";
      case GB_ACT_SUSPEND:     return "SUSPEND";
      case GB_ACT_NO_TRADE:    return "NO_TRADE";
      case GB_ACT_PROPOSE_V2:  return "PROPOSE_V2";
      case GB_ACT_RESUME:      return "RESUME";
      case GB_ACT_RETIRE:      return "RETIRE";
     }
   return "?";
  }

string GB_AuthToString(const ENUM_GB_AUTHORITY a)
  {
   switch(a)
     {
      case GB_AUTH_MANUAL:    return "MANUAL";
      case GB_AUTH_ASSISTED:  return "ASSISTED";
      case GB_AUTH_SEMI_AUTO: return "SEMI_AUTO";
      case GB_AUTH_FULL_AUTO: return "FULL_AUTO";
     }
   return "?";
  }

#endif
//+------------------------------------------------------------------+
