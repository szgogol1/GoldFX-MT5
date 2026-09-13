# GoldFX BoxBreakout — 顺势小箱体突破（独立包）

与 `GoldFX_Intraday`（七条件）**完全分离**的独立 EA。

## 策略（仅顺势）

| 背景 | 入场 | 不做 |
|------|------|------|
| EMA50/200 + ADX/DI 多头（可选 H1） | 收盘上破箱上沿 | 下破不做空，箱作废重建 |
| 空头同理 | 收盘下破箱下沿 | 上破不做多 |

- 箱宽约 `0.35–1.20 ATR`
- SL：箱体对侧外沿 + ATR 缓冲
- TP：箱高 × 倍数，并保证最低 RR
- 入场后：保本 / ATR 追踪 / 部分平仓

## 本机安装（重要）

头文件已放在 **EA 同目录**。请复制**整个文件夹**，不要只拷一个 `.mq5`。

### 方式 A：一键脚本

1. 解压本包
2. 双击 `install_to_MT5.bat`
3. 粘贴 MT5 的 `MQL5` 路径（文件 → 打开数据文件夹 → `MQL5`）
4. MetaEditor 打开 `Experts\GoldFX_BoxBreakout\GoldFX_BoxBreakout.mq5`，按 **F7**

### 方式 B：手动复制（最稳）

把整个目录：

`Experts\GoldFX_BoxBreakout\`

复制到：

`你的MT5\MQL5\Experts\GoldFX_BoxBreakout\`

该目录内应同时有：

- `GoldFX_BoxBreakout.mq5`
- `Common.mqh`
- `BoxBreakoutStrategy.mqh`
- `PositionTrail.mqh`

若 MetaEditor 报 `Common.mqh not found`，就是少拷了同目录的 `.mqh` 文件。

## 目录

```
GoldFX_BoxBreakout/
  Experts/GoldFX_BoxBreakout/
    GoldFX_BoxBreakout.mq5
    Common.mqh
    BoxBreakoutStrategy.mqh
    PositionTrail.mqh
  Include/GoldFX_Box/     # 可选镜像
  Presets/
  install_to_MT5.bat
  install_to_MT5.ps1
  README.md
```
