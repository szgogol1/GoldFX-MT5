# GoldFX MT4 — 期现双K对比与价差提醒

一键安装到本机 MetaTrader 4。

## 安装

1. 双击仓库根目录 `install_to_MT4.bat`（或 `install_to_MT4.ps1`）
2. 粘贴 MT4 的 **MQL4** 路径  
   （MT4：文件 → 打开数据文件夹 → 进入 `MQL4`）
3. MetaEditor（F4）编译：
   - `Experts\GoldFX_BasisArb.mq4`
   - `Indicators\GoldFX_BasisCompare.mq4`
4. 在现货图（如 XAUUSD M15）先加载指标，再挂 EA
5. 设置 `InpFutSymbol` 为你经纪商的黄金期货/远期代码
6. 推荐先保持 `InpSignalOnly=true` 只收提醒

Telegram（可选）：工具 → 选项 → 专家顾问 → 允许 WebRequest：`https://api.telegram.org`

## 目录

```
MT4/
  Experts/GoldFX_BasisArb.mq4          # 基差提醒 / 双边对冲 EA
  Indicators/GoldFX_BasisCompare.mq4   # 期货K叠加 + 基差副图
  Include/GoldFX/BasisArbitrage.mqh
  Include/GoldFX/TelegramBridge.mqh
  Presets/*.set
```

## 信号

| 条件 | 动作 |
|------|------|
| Z ≥ EntryZ | 提醒空基差（空期+多现） |
| Z ≤ -EntryZ | 提醒多基差（多期+空现） |
| \|Z\| ≤ ExitZ 且浮盈 ≥ MinProfit | 提醒平仓 |
| Z 逆向达 StopZ / 超时 | 止损或超时平仓 |

与 MT5 版逻辑一致；MT4 使用订单系统（OrderSend）下单。
