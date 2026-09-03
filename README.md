# GoldFX Intraday v3 — 七条件 + 组合基础设施 + 订单流

## Windows 安装

1. 克隆或解压仓库到本机，例如 `D:\GoldFX-MT5\`
2. 双击 `install_to_MT5.bat`（或 `install_to_MT5.ps1`），粘贴 MT5 的 `MQL5` 路径
3. MetaEditor 打开对应 EA，按 **F7** 编译：
   - `Experts\GoldFX_Intraday\GoldFX_Intraday.mq5`
   - `Experts\GoldFX_BasisArb\GoldFX_BasisArb.mq5`
   - `Experts\GoldFX_OrderFlow\GoldFX_OrderFlow.mq5`
4. 可选：双击 `open_MetaEditor.bat` 启动 MetaEditor

云端环境无法直接写入你电脑的 `D:` 盘，需本机完成上述步骤。

GitHub：https://github.com/szgogol1/GoldFX-MT5


参考 **SafeScalperPro / Prime** 的工程能力，在自有框架上实现：

- **七条件缺一不可**入场（EMA 趋势/强度/价格位置/突破/RSI/动量/H1 确认）
- **黄金现货–期货基差均值回归套利**（Z 分双边对冲）
- **日内订单流**（Tick Delta / CVD / VWAP·POC·VA + 可选 DOM）
- **无网格 · 无马丁 · 一次一笔/每品种一笔**
- **自适应风险引擎**（回撤降仓、ATR 反比、滚动胜率调整）
- **单图多品种**（最多 8，CSV 配置）+ **相关性保护**（七条件 EA）
- **Telegram** 推送与 `/status /stop /resume /risk`（原生 WebRequest，无 DLL）
- **Forge 仪表盘**（回测自动禁用）
- **峰值回撤持久化**、交易 CSV 日志、新闻/周五/时段过滤

> 非官方克隆。研究与模拟用途。实盘前请充分测试。

## 日内订单流（`GoldFX_OrderFlow`）

### 原理（零售 MT5 近似）

外汇/黄金零售盘通常没有真实 CME Footprint。本 EA 用可审计的近似：

| 组件 | 实现 |
|------|------|
| Tape | `CopyTicks` + Lee-Ready / `TICK_FLAG_BUY·SELL` 分类主动买/卖 |
| Delta / CVD | 每根 K 的 buy−sell；会话累计 CVD（换日重置） |
| 堆叠失衡 | 近 N 根同向 Delta + `\|Δ\|/Vol ≥ ImbalancePct` |
| 成交量分布 | 会话 VWAP、POC、VAH/VAL（价格桶） |
| 吸收 | 高量 + 窄幅后 Delta 翻转 → 禁止追价 |
| DOM（可选） | `MarketBookGet`；经纪商无深度或测试器中静默降级 |

### 入场（已收盘 K，缺一不可）

1. **位置**：收盘在会话 VWAP 正确一侧，或回踩 POC/VA 后收回  
2. **主动单边**：堆叠失衡达到阈值  
3. **CVD**：斜率同向，或允许背离反转  
4. **吸收过滤**：高点/低点吸收则否决追单  
5. **结构**：可选 H1 EMA + 日 VWAP 同向  
6. **闸门**：点差 / 新闻 / 时段 / 日交易上限（复用现有过滤器）

止损：摆动结构或 POC/VA 外侧 + ATR 封顶；止盈：ATR 或对侧 VA，最低 RR 可配。  
额外离场：反向堆叠失衡 / CVD 背离（可关）。

### 使用

1. 编译 `Experts/GoldFX_OrderFlow/GoldFX_OrderFlow.mq5`  
2. 挂 **XAUUSD M5**（外汇同理换品种）；Magic 默认 `20260903`，可与七条件并存  
3. 加载 `GoldFX_OrderFlow_XAUUSD_M5.set`，或先用 `GoldFX_OrderFlow_Conservative.set`（默认 `AllowTrade=false`）  
4. 策略测试器必须选 **Every tick based on real ticks**；DOM 在测试器通常不可用  

### 限制

- 这是零售报价流近似，不是交易所 Level 2 订单流  
- 点差大、Tick 稀疏的品种噪声更大  
- 务必先模拟观察 CVD/VWAP 画线是否合理，再开 `InpAllowTrade`

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
Experts/GoldFX_OrderFlow/GoldFX_OrderFlow.mq5 # 日内订单流
Include/GoldFX/
  SevenConditionStrategy.mqh
  OrderFlowTape.mqh / VolumeProfile.mqh / OrderFlowBook.mqh / OrderFlowStrategy.mqh
  BasisArbitrage.mqh
  PortfolioEngine.mqh / AdaptiveRisk.mqh / ...
Presets/
  GoldFX_XAUUSD_M5_SevenCond.set
  GoldFX_OrderFlow_XAUUSD_M5.set
  GoldFX_OrderFlow_Conservative.set
  GoldFX_BasisArb_M15.set
  ...
```

## 安装

1. 复制到 MT5 `MQL5/Experts` 与 `MQL5/Include/GoldFX`、`MQL5/Presets`  
2. MetaEditor **F7** 编译三个 EA  
3. 七条件：挂 **XAUUSD M5**（推荐伦敦–纽约）  
4. 订单流：挂 **XAUUSD M5**，真实 tick 回测  
5. 基差套利：挂现货图，填好期货品种名  
6. Telegram：工具 → 选项 → 专家 → 允许 `https://api.telegram.org`

## 推荐起步

| 步骤 | 预设 |
|------|------|
| 结构验证 | `Phase1_Structure.set`（可关交易） |
| 风险/SLTP | `Phase2_SL_TP_Risk.set` |
| 离场 | `Phase3_Exit_Management.set` |
| 时段 | `Phase4_Session_DayCap.set` |
| 黄金即用 | `GoldFX_XAUUSD_M5_SevenCond.set` |
| 多品种 | `GoldFX_Portfolio_Major.set`（`InpSymbols=XAUUSD,XAGUSD,...`） |
| 订单流 | `GoldFX_OrderFlow_XAUUSD_M5.set` |
| 订单流观察 | `GoldFX_OrderFlow_Conservative.set`（先关交易） |
| 基差套利 | `GoldFX_BasisArb_M15.set`（先改期货品种名） |
| 基差保守 | `GoldFX_BasisArb_Conservative.set` |

资金管理默认 **自适应 (MM_ADAPTIVE)**；亦可固定手数 / 风险% / 八档自动。

## 远程命令（Telegram）

`/status` `/stop` `/resume` `/pause SYMBOL` `/risk 0.5`

## 与营销版差异（刻意）

未实现其全部商业预设包与私有蒙特卡洛文件；核心是可审计的开源级骨架，便于你替换信号或风控层。

## 免责声明

交易有亏损风险。新闻日历依赖终端数据；部分经纪商/测试器可能无日历（过滤器会安全降级）。订单流为零售盘近似，务必先模拟。
