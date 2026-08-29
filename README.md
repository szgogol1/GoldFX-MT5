# GoldFX Intraday v3 + GlobalBasis 4.0

## GlobalBasis 4.0 — AI 策略生命周期（ASSISTED）

**AI = 分析师，不是无限制交易员。** 详见 `docs/GlobalBasis/GlobalBasis_4.0_Architecture.md`。

| 组件 | 路径 |
|------|------|
| 生命周期总装 | `Include/GlobalBasis/GB_Lifecycle.mqh` |
| 硬风控（AI 不可放宽） | `Include/GlobalBasis/GB_HardRisk.mqh` |
| 规则化 AI 分析师 | `Include/GlobalBasis/GB_AIAnalyst.mqh` |
| Shadow / 人工批准 | `GB_Shadow.mqh` / `GB_Approval.mqh` |
| Demo 面板 EA | `Experts/GlobalBasis/GlobalBasis_Lifecycle.mq5` |

Phase 1：**ASSISTED** — AI 只产出 KEEP / REDUCE_RISK / SUSPEND / NO_TRADE / PROPOSE_V2；`PROPOSE_V2` 进 Shadow；**人工 APPROVE** 后才升版。Hard DD / Daily Loss / Emergency Stop 为强制闸门。

编译：`GlobalBasis_Lifecycle.mq5` → 挂图查看健康面板与 `[APPROVE][REJECT][IGNORE]`。

---

# GoldFX Intraday v3 — 七条件 + 组合基础设施

## Windows 安装

1. 克隆或解压仓库到本机，例如 `D:\GoldFX-MT5\`
2. 双击 `install_to_MT5.bat`（或 `install_to_MT5.ps1`），粘贴 MT5 的 `MQL5` 路径
3. MetaEditor 打开 `Experts\GoldFX_Intraday\GoldFX_Intraday.mq5`，按 **F7** 编译
4. 可选：双击 `open_MetaEditor.bat` 启动 MetaEditor

云端环境无法直接写入你电脑的 `D:` 盘，需本机完成上述步骤。

GitHub：https://github.com/szgogol1/GoldFX-MT5


参考 **SafeScalperPro / Prime** 的工程能力，在自有框架上实现：

- **七条件缺一不可**入场（EMA 趋势/强度/价格位置/突破/RSI/动量/H1 确认）
- **黄金现货–期货基差均值回归套利**（Z 分双边对冲）
- **无网格 · 无马丁 · 一次一笔/每品种一笔**
- **自适应风险引擎**（回撤降仓、ATR 反比、滚动胜率调整）
- **单图多品种**（最多 8，CSV 配置）+ **相关性保护**
- **Telegram** 推送与 `/status /stop /resume /risk`（原生 WebRequest，无 DLL）
- **Forge 仪表盘**（回测自动禁用）
- **峰值回撤持久化**、交易 CSV 日志、新闻/周五/时段过滤

> 非官方克隆。研究与模拟用途。实盘前请充分测试。

## 黄金期货 / 现货基差套利（`GoldFX_BasisArb`）

### 原理

\[
B_t = F_t - S_t,\quad
Z_t = \frac{B_t - \mu_B}{\sigma_B}
\]

- \(S\)：现货黄金（如 `XAUUSD`）  
- \(F\)：期货/远期类黄金（经纪商符号因平台而异，如 `XAUUSD.f`、`GOLDfut`、`XAUz`）  
- \(\mu_B,\sigma_B\)：近 `Lookback` 根 K 线滚动均值与标准差  

| 信号 | 条件 | 仓位 |
|------|------|------|
| 做空基差 | \(Z \ge EntryZ\)（基差过高 / Contango 极端） | **空期货 + 多现货** |
| 做多基差 | \(Z \le -EntryZ\)（基差过低 / Backwardation 极端） | **多期货 + 空现货** |
| 回归出场 | \(\|Z\| \le ExitZ\) | 双边平仓 |
| Z 止损 | 逆向 \(\|Z\| \ge StopZ\) 或超时 | 双边平仓 |

另需：现货–期货滚动相关 \(\ge MinCorr\)；名义价值自动对冲手数；点差/时段/日亏损闸门。

### 使用

1. 确认账户为**对冲模式**，且同时有现货 + 期货类黄金品种  
2. 编译 `Experts/GoldFX_BasisArb/GoldFX_BasisArb.mq5`  
3. 设置 `InpFutSymbol` 为你的期货代码（预设里的 `XAUUSD.f` 只是占位）  
4. 挂在现货图表上，加载 `GoldFX_BasisArb_M15.set` 或 `GoldFX_BasisArb_Conservative.set`  
5. 建议先 `InpSignalOnly=true` 观察 Z 分与相关，再实盘/模拟下单  

> MT5 策略测试器对**双品种对冲**支持有限；基差策略请以**模拟盘实盘环境**验证为主。

### 风险说明

- 这不是无风险套利：基差可因库存、利率、展期、流动性而**不回归**  
- 合约乘数/点值不同时务必开启 `InpAutoHedge` 并核对手数  
- 展期日、重大非农/CPI 前后基差噪声大，可用时段与周五截止规避  

## 七条件 v3.1（回调入场 · 防追涨）

1. EMA(89)/EMA(233) 方向  
2. EMA 间距 ≥ ATR × 最小倍数  
3. 收盘在双均线正确一侧  
4. **回踩快 EMA 后反弹**（默认）或突破确认  
5. RSI 健康区（多 45–58，空 42–55，避免超买追多）  
6. 3 根 K 线动量确认  
7. H1 EMA50/200 同向  
8. **ADX ≥ 22 且 DI 方向一致**  
9. **价格距快 EMA ≤ 1.3 ATR**（防过度延伸）

结构止损 + 最低盈亏比 1.8:1；TP 默认 2.8 ATR。

## 目录

```
Experts/GoldFX_Intraday/GoldFX_Intraday.mq5   # 日内七条件
Experts/GoldFX_BasisArb/GoldFX_BasisArb.mq5   # 现货-期货基差套利
Include/GoldFX/
  SevenConditionStrategy.mqh
  BasisArbitrage.mqh           # 基差 Z 分引擎
  PortfolioEngine.mqh / AdaptiveRisk.mqh / ...
Presets/
  GoldFX_XAUUSD_M5_SevenCond.set
  GoldFX_BasisArb_M15.set
  GoldFX_BasisArb_Conservative.set
  ...
```

## 安装

1. 复制到 MT5 `MQL5/Experts` 与 `MQL5/Include/GoldFX`、`MQL5/Presets`  
2. MetaEditor **F7** 编译两个 EA  
3. 日内策略：挂 **XAUUSD M5**（推荐伦敦–纽约）  
4. 基差套利：挂现货图，填好期货品种名  
5. Telegram：工具 → 选项 → 专家 → 允许 `https://api.telegram.org`

## 推荐起步

| 步骤 | 预设 |
|------|------|
| 结构验证 | `Phase1_Structure.set`（可关交易） |
| 风险/SLTP | `Phase2_SL_TP_Risk.set` |
| 离场 | `Phase3_Exit_Management.set` |
| 时段 | `Phase4_Session_DayCap.set` |
| 黄金即用 | `GoldFX_XAUUSD_M5_SevenCond.set` |
| 多品种 | `GoldFX_Portfolio_Major.set`（`InpSymbols=XAUUSD,XAGUSD,...`） |
| 基差套利 | `GoldFX_BasisArb_M15.set`（先改期货品种名） |
| 基差保守 | `GoldFX_BasisArb_Conservative.set` |

资金管理默认 **自适应 (MM_ADAPTIVE)**；亦可固定手数 / 风险% / 八档自动。

## 远程命令（Telegram）

`/status` `/stop` `/resume` `/pause SYMBOL` `/risk 0.5`

## 与营销版差异（刻意）

未实现其全部商业预设包与私有蒙特卡洛文件；核心是可审计的开源级骨架，便于你替换信号或风控层。

## 免责声明

交易有亏损风险。新闻日历依赖终端数据；部分经纪商/测试器可能无日历（过滤器会安全降级）。务必先模拟。
