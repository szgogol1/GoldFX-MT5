# GoldFX MT4 — 期现双K对比与价差提醒

一键安装到本机 MetaTrader 4。

## 安装

1. 双击仓库根目录 `install_to_MT4.bat`（或 `install_to_MT4.ps1`）
2. 粘贴 MT4 的 **MQL4** 路径  
   （MT4：文件 → 打开数据文件夹 → 进入 `MQL4`）
3. MetaEditor（F4）编译：
   - `Experts\GoldFX_BasisArb.mq4`
   - `Indicators\GoldFX_BasisCompare.mq4`
4. 打开 **XAUUSD.s** 图表（M15 推荐），加载指标 + EA
5. 默认品种：现货 `XAUUSD.s`、期货 `GC`（可按经纪商修改）
6. 默认 **手动观察**（只提醒）；右上角按钮切换为 **自动交易**

Telegram（可选）：工具 → 选项 → 专家顾问 → 允许 WebRequest：`https://api.telegram.org`

## 图表说明

| 区域 | 内容 |
|------|------|
| 主图 | 现货/期货 **并排双色 K 线**（金=现货，蓝绿=期货） |
| 副图 | **价差柱状图**（高于均值绿柱、低于红柱）+ 均值/入场带 |

## 手 / 自动

- **手动观察**：只 Alert/推送/Telegram，不下单 — 先确认信号
- **自动交易**：按 Z 分双边对冲开平仓
- 图上右上角 **「模式: 手动观察 / 自动交易」** 一键切换

## 信号

| 条件 | 动作 |
|------|------|
| Z ≥ EntryZ | 提醒/开仓：空基差（空 GC + 多 XAUUSD.s） |
| Z ≤ -EntryZ | 提醒/开仓：多基差（多 GC + 空 XAUUSD.s） |
| \|Z\| ≤ ExitZ 且浮盈 ≥ MinProfit | 平仓提醒/平仓 |
| StopZ / 超时 | 止损或超时平仓 |
