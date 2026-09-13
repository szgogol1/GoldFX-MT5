# GoldFX BoxBreakout — 顺势小箱体突破（独立包）

与 `GoldFX_Intraday`（七条件）**完全分离**的独立 EA 安装包。

## 策略（仅顺势）

| 背景 | 入场 | 不做 |
|------|------|------|
| EMA50/200 + ADX/DI 多头（可选 H1） | 收盘上破箱上沿 | 下破不做空，箱作废重建 |
| 空头同理 | 收盘下破箱下沿 | 上破不做多 |

- 箱宽约 `0.35–1.20 ATR`，需上下沿触及  
- SL：箱体对侧外沿 + ATR 缓冲  
- TP：箱高 × 倍数，并保证最低 RR  
- 入场后：保本 / ATR 追踪 / 部分平仓  
- 破箱后等待**下一震荡箱**再建仓  

## 本机安装

### 方式 A：一键脚本

1. 解压本包到任意目录，例如 `D:\GoldFX_BoxBreakout\`
2. 双击 `install_to_MT5.bat`（或 `install_to_MT5.ps1`）
3. 粘贴 MT5 的 `MQL5` 路径（MT5：文件 → 打开数据文件夹 → 进入 `MQL5`）
4. MetaEditor 打开 `Experts\GoldFX_BoxBreakout\GoldFX_BoxBreakout.mq5`，按 **F7** 编译
5. 图表挂 EA，加载 `Presets\GoldFX_Box_XAUUSD_M5.set`

### 方式 B：手动复制

把本包内的：

- `Experts\GoldFX_BoxBreakout\` → MT5 `MQL5\Experts\`
- `Include\GoldFX_Box\` → MT5 `MQL5\Include\`
- `Presets\*.set` → MT5 `MQL5\Presets\`

然后 F7 编译。

## 目录

```
GoldFX_BoxBreakout/
  Experts/GoldFX_BoxBreakout/GoldFX_BoxBreakout.mq5
  Include/GoldFX_Box/
    Common.mqh
    BoxBreakoutStrategy.mqh
    PositionTrail.mqh
  Presets/GoldFX_Box_XAUUSD_M5.set
  install_to_MT5.bat
  install_to_MT5.ps1
  README.md
```

## 说明

- 不依赖、不修改 `GoldFX_Intraday` / 七条件 / 基差套利代码  
- 建议 XAUUSD M5，伦敦–纽约时段  
- 研究与模拟用途；实盘前请充分测试  
