# GoldFX Intraday — MQL5 黄金/外汇日内交易框架

面向 **XAUUSD / 主要外汇对** 的日内 EA 初步框架：自动识别趋势与震荡，按体制切换策略，并提供 **EA 属性面板 + 图表热调参面板**。

> 本仓库是策略骨架与工程结构，默认参数仅供研究/模拟盘起步，不构成实盘建议。请务必先在 Strategy Tester 与模拟账户验证。

## 功能概览

| 模块 | 说明 |
|------|------|
| 体制识别 | ADX 强度 + 布林带宽 + 双 EMA 斜率一致性评分 → `趋势` / `震荡` |
| 趋势策略 | EMA 快慢线金叉/死叉，ADX 过滤，ATR 倍数止损止盈 |
| 震荡策略 | 收盘触布林上下轨 + RSI 极值，目标中轨均值回归 |
| 运行模式 | `自动` / `强制趋势` / `强制震荡` / `仅观察` |
| 风控 | 固定手数或按净值风险%、日内亏损上限、最大持仓数、交易时段 |
| 参数面板 | 图表左上角：模式切换、ADX/风险/手数/ATR倍数/RSI、应用、刷新、一键平仓 |

## 目录结构

```
Experts/GoldFX_Intraday/GoldFX_Intraday.mq5   # 主 EA
Include/GoldFX/
  Common.mqh           # 枚举、运行时参数结构
  RegimeDetector.mqh   # 趋势/震荡识别
  TrendStrategy.mqh    # 趋势策略
  RangeStrategy.mqh    # 震荡策略
  RiskManager.mqh      # 仓位与日内风控
  TradeManager.mqh     # 开平仓封装
  ParamPanel.mqh       # 图表 GUI 面板
Presets/GoldFX_Intraday_XAUUSD_M15.set       # XAUUSD M15 参考预设
```

## 安装到 MetaTrader 5

1. 打开 MT5 → **文件 → 打开数据文件夹**
2. 将本仓库内容映射到 `MQL5/` 下：
   - `Experts/GoldFX_Intraday/` → `MQL5/Experts/GoldFX_Intraday/`
   - `Include/GoldFX/` → `MQL5/Include/GoldFX/`
   - `Presets/` → `MQL5/Presets/`（可选）
3. 在 MetaEditor 中打开 `GoldFX_Intraday.mq5`，按 **F7** 编译（应无错误）
4. 导航器中把 EA 拖到 **XAUUSD M15**（或目标品种周期）图表
5. 勾选 **允许算法交易**，按需加载 `.set` 预设

也可把整个仓库放在任意位置，用符号链接/复制同步到数据目录。

## 使用方式

### EA 属性面板（启动前）

挂载时配置：运行模式、体制阈值、趋势/震荡参数、手数与日内亏损、交易时段等。

### 图表参数面板（运行中）

- **自动 / 趋势 / 震荡 / 观察**：即时切换策略路由，不必重启 EA  
- 修改编辑框后点 **应用参数**：重建指标并强制重识别  
- **刷新识别**：按当前参数重算体制  
- **全部平仓**：平掉本 EA Magic 在当前品种上的持仓  

图表左上角 Comment 与面板状态行会显示：`ADX`、布林带宽、识别结果、生效体制、当日盈亏%。

## 推荐起步流程

1. 品种：`XAUUSD`（或经纪商黄金符号），周期：`M15` / `M5`  
2. 先用 `仅观察` 或关闭 `InpAllowTrade`，核对识别与信号日志  
3. Strategy Tester：`每个报价` 或 `1 分钟 OHLC`，点差按实盘设置  
4. 模拟盘小手数跑通时段过滤、滑点与填充模式后再考虑实盘  

## 扩展建议（下一步）

- 在 `TrendStrategy` / `RangeStrategy` 中替换为你的信号逻辑，保持 `SSignalResult` 接口  
- 增加伦敦/纽约子时段、新闻过滤、移动止损、部分平仓  
- `OnTradeTransaction` 中落库成交与绩效统计  
- 多周期确认（例如 M15 信号 + H1 体制）  

## 风险声明

量化交易存在本金损失风险。本框架为教学与研发起点，历史回测不能代表未来表现。使用前请独立验证并遵守当地监管要求。
