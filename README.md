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
- **无网格 · 无马丁 · 一次一笔/每品种一笔**
- **自适应风险引擎**（回撤降仓、ATR 反比、滚动胜率调整）
- **单图多品种**（最多 8，CSV 配置）+ **相关性保护**
- **Telegram** 推送与 `/status /stop /resume /risk`（原生 WebRequest，无 DLL）
- **Forge 仪表盘**（回测自动禁用）
- **峰值回撤持久化**、交易 CSV 日志、新闻/周五/时段过滤

> 非官方克隆。研究与模拟用途。实盘前请充分测试。

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
Experts/GoldFX_Intraday/GoldFX_Intraday.mq5
Include/GoldFX/
  SevenConditionStrategy.mqh   # 七条件引擎
  PortfolioEngine.mqh          # 多品种
  AdaptiveRisk.mqh             # 自适应风险
  SessionNewsFilter.mqh        # 时段/新闻/周五
  Persistence.mqh              # 跨重启状态
  TelegramBridge.mqh
  TradeJournal.mqh
  Dashboard.mqh
  RiskManager / PositionManager / TradeManager / ...
Presets/
  GoldFX_XAUUSD_M5_SevenCond.set
  GoldFX_Portfolio_Major.set
  Phase1_Structure.set … Phase4_Session_DayCap.set
```

## 安装

1. 复制到 MT5 `MQL5/Experts` 与 `MQL5/Include/GoldFX`、`MQL5/Presets`  
2. MetaEditor **F7** 编译  
3. 挂 **XAUUSD M5**（推荐伦敦–纽约）  
4. Telegram：工具 → 选项 → 专家 → 允许 `https://api.telegram.org`

## 推荐起步

| 步骤 | 预设 |
|------|------|
| 结构验证 | `Phase1_Structure.set`（可关交易） |
| 风险/SLTP | `Phase2_SL_TP_Risk.set` |
| 离场 | `Phase3_Exit_Management.set` |
| 时段 | `Phase4_Session_DayCap.set` |
| 黄金即用 | `GoldFX_XAUUSD_M5_SevenCond.set` |
| 多品种 | `GoldFX_Portfolio_Major.set`（`InpSymbols=XAUUSD,XAGUSD,...`） |

资金管理默认 **自适应 (MM_ADAPTIVE)**；亦可固定手数 / 风险% / 八档自动。

## 远程命令（Telegram）

`/status` `/stop` `/resume` `/pause SYMBOL` `/risk 0.5`

## 与营销版差异（刻意）

未实现其全部商业预设包与私有蒙特卡洛文件；核心是可审计的开源级骨架，便于你替换信号或风控层。

## 免责声明

交易有亏损风险。新闻日历依赖终端数据；部分经纪商/测试器可能无日历（过滤器会安全降级）。务必先模拟。
