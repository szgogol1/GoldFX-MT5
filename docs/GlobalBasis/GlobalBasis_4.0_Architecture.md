# GlobalBasis 4.0 — AI Strategy Lifecycle Manager

## 定位

**AI ≠ 交易执行器。**  
AI = 策略研究员 + 数据分析师 + 风险预警员。

| 角色 | 职责 | 可否改硬风控 |
|------|------|--------------|
| AI Analyst | 分析绩效/体制/执行，提出建议与新版本 | ❌ |
| Rule / Risk Engine | 强制 Hard Limits，可降仓/暂停（SEMI-AUTO） | 自身即限制 |
| Human | 批准版本升级、资金配置、权限档位 | ✅ 唯一可放宽授权的主体 |
| Execution Engine | 点差/延迟/流动性闸门 | ❌ |

## 三道闸门（必须全部 PASS）

```
AI Gate (值不值得) → Risk Gate (允许多少风险) → Execution Gate (能否成交) → EXECUTE
```

任一 FAIL → 不开新仓。Hard DD / Daily Loss / Emergency Stop **AI 无权绕过**。

## 权限档位

| 档位 | Phase | AI 可做 | AI 不可做 |
|------|-------|---------|-----------|
| MANUAL | — | 无 | 一切自动调整 |
| **ASSISTED** | **1（当前）** | 分析、建议、回测草稿、Shadow | 改 live 参数、加仓、改硬限 |
| SEMI-AUTO | 2 | 降仓、暂停、关新单 | 提高 MaxRisk/MaxPos/硬止损 |
| FULL AUTO | 3+ | 预设边界内调参 | 突破 Hard DD / Daily Loss / Emergency |

## 策略生命周期

```
RESEARCH → BACKTEST → PAPER → LIVE_SMALL → ACTIVE ⇄ REVIEW → OPTIMIZE → ACTIVE
                                              ↓
                                         WARNING → SUSPENDED → RETIRED
```

Shadow Mode：V2 仅记账对比 V1 实盘，**不发单**；连续优势后才进入人工批准升级。

## 模块映射

| 模块 | 路径 |
|------|------|
| 类型与枚举 | `Include/GlobalBasis/GB_Types.mqh` |
| 硬风控（AI 不可改） | `Include/GlobalBasis/GB_HardRisk.mqh` |
| 绩效快照 | `Include/GlobalBasis/GB_Performance.mqh` |
| 市场体制 | `Include/GlobalBasis/GB_Regime.mqh` |
| 执行质量 | `Include/GlobalBasis/GB_Execution.mqh` |
| 规则化 AI 分析师 | `Include/GlobalBasis/GB_AIAnalyst.mqh` |
| Shadow 账本 | `Include/GlobalBasis/GB_Shadow.mqh` |
| 人工批准闸 | `Include/GlobalBasis/GB_Approval.mqh` |
| 生命周期管理器 | `Include/GlobalBasis/GB_Lifecycle.mqh` |
| Demo EA | `Experts/GlobalBasis/GlobalBasis_Lifecycle.mq5` |

## Phase 1 行为（ASSISTED）

1. 每日/每 N 棒汇总 Performance / Risk / Execution / Strategy 切片  
2. 健康分 0–100 + 状态色（绿/黄/红）  
3. 异常时 **不改 live**，生成 `SGBRecommendation`（KEEP / REDUCE_RISK / SUSPEND / NO_TRADE / PROPOSE_V2）  
4. PROPOSE_V2 → 写入候选版本 + Shadow，面板显示 `[APPROVE] [REJECT]`  
5. 仅人工 APPROVE 后候选版本才可升为 LIVE  

## 明确不做（Phase 1）

- AI 自主加仓 / 提高风险上限  
- AI 修改 Daily Loss / Max Portfolio DD / Emergency Stop  
- 无审批的参数热切换  
- 把 LLM 直接接到 OrderSend  

（未来可用外部 sidecar 读同一 JSON 报告做自然语言解读，仍走 Approval 闸。）
