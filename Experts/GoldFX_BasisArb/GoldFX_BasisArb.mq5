//+------------------------------------------------------------------+
//| GoldFX_BasisArb.mq5 — 黄金期货/现货基差均值回归套利                  |
//| 逻辑：B=F-S → 滚动Z分；Z高则空基差(空期+多现)，Z低则多基差            |
//| 提醒：Alert / 推送 / Telegram；回归且达最小盈利后平仓                 |
//| 要求：经纪商同时提供现货与期货/远期类黄金品种；对冲账户推荐            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.10"
#property description "黄金现货-期货基差Z分均值回归套利（双边对冲+价差提醒）"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <GoldFX/BasisArbitrage.mqh>
#include <GoldFX/TelegramBridge.mqh>

input group "=== 品种 ==="
input string InpSpotSymbol     = "XAUUSD";     // 现货（或挂图品种）
input string InpFutSymbol      = "";           // 期货/远期，必填（如 XAUz, GOLD#, XAUUSD.f）
input ENUM_TIMEFRAMES InpTF    = PERIOD_M15;   // 统计周期

input group "=== 基差模型 ==="
input ENUM_BASIS_SPREAD_MODE InpSpreadMode = BASIS_DIFF; // DIFF推荐用于同报价货币
input int    InpLookback       = 60;           // 滚动窗口（根）
input double InpEntryZ         = 2.0;          // 入场 |Z|
input double InpExitZ          = 0.40;         // 出场 |Z|
input double InpStopZ          = 3.5;          // 逆向止损 |Z|
input double InpMinCorr        = 0.88;         // 最低现货-期货相关
input int    InpMinBars        = 120;
input int    InpMaxHoldBars    = 48;           // 超时平仓
input int    InpCooldownBars   = 4;
input double InpMinProfitMoney = 5.0;          // 回归平仓最小浮盈（账户货币）

input group "=== 仓位 / 风控 ==="
input double InpLotSpot        = 0.10;         // 现货基准手数
input bool   InpAutoHedge      = true;         // 按名义价值对冲期货手数
input double InpMaxDailyLossPct= 2.0;
input double InpMaxSpreadSpot  = 0.60;         // 现货最大点差（价格）
input double InpMaxSpreadFut   = 0.80;
input bool   InpAllowTrade     = true;
input bool   InpSignalOnly     = true;         // true=仅提醒不开仓（推荐先观察）
input int    InpMagic          = 20260827;
input int    InpSlippage       = 40;

input group "=== 提醒 ==="
input bool   InpUseAlert       = true;         // Alert 弹窗
input bool   InpUsePush        = true;         // MT5 手机推送
input bool   InpTelegramEnable = false;
input string InpTelegramToken  = "";
input string InpTelegramChatId = "";
input bool   InpShowPanel      = true;         // 图表面板

input group "=== 时段 ==="
input bool   InpUseSession     = true;
input int    InpSessStart      = 1;            // 避开日切换月高峰可自调
input int    InpSessEnd        = 22;
input bool   InpFridayCut      = true;
input int    InpFridayHour     = 18;

#define PANEL_PREFIX "GFXBA_"

//---
CBasisArbitrage g_engine;
CTrade          g_trade;
CPositionInfo   g_pos;
CTelegramBridge g_tg;
string          g_status = "";
datetime        g_day_stamp = 0;
double          g_day_start_eq = 0;
bool            g_paused = false;
int             g_last_alert_act = -1;
datetime        g_last_alert_bar = 0;

//------------------------------------------------------------------
bool InSession(void)
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(InpFridayCut && dt.day_of_week==5 && dt.hour>=InpFridayHour)
      return false;
   if(!InpUseSession) return true;
   if(InpSessStart < InpSessEnd)
      return (dt.hour >= InpSessStart && dt.hour < InpSessEnd);
   return (dt.hour >= InpSessStart || dt.hour < InpSessEnd);
  }

void RefreshDay(void)
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   datetime d = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));
   if(d != g_day_stamp)
     {
      g_day_stamp = d;
      g_day_start_eq = AccountInfoDouble(ACCOUNT_EQUITY);
      g_paused = false;
     }
   if(g_day_start_eq > 0 && InpMaxDailyLossPct > 0)
     {
      const double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      const double dd = 100.0 * (g_day_start_eq - eq) / g_day_start_eq;
      if(dd >= InpMaxDailyLossPct)
         g_paused = true;
     }
  }

int CountMagicPositions(const string sym)
  {
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic()!=InpMagic) continue;
      if(StringLen(sym)>0 && g_pos.Symbol()!=sym) continue;
      n++;
     }
   return n;
  }

double FloatingProfitMagic(void)
  {
   double pnl = 0.0;
   for(int i=PositionsTotal()-1;i>=0;--i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic()!=InpMagic) continue;
      pnl += g_pos.Profit() + g_pos.Swap();
     }
   return pnl;
  }

bool CloseLeg(const string sym, const string cmt)
  {
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;--i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic()!=InpMagic) continue;
      if(g_pos.Symbol()!=sym) continue;
      g_trade.SetTypeFillingBySymbol(sym);
      if(!g_trade.PositionClose(g_pos.Ticket()))
        {
         PrintFormat("平仓失败 %s #%I64u %s", sym, g_pos.Ticket(), g_trade.ResultComment());
         ok=false;
        }
     }
   return ok;
  }

bool CloseAllLegs(const string why)
  {
   const string spot = g_engine.SpotSymbol();
   const string fut  = g_engine.FutSymbol();
   const double pnl  = FloatingProfitMagic();
   bool ok1 = CloseLeg(spot, why);
   bool ok2 = CloseLeg(fut, why);
   g_engine.NotifyClosed();
   g_status = why;
   Print("基差平仓: ", why);
   NotifySignal(3, StringFormat("【平仓】%s 盈=%.2f", why, pnl));
   return ok1 && ok2;
  }

void NotifySignal(const int act, const string msg)
  {
   const datetime bar = iTime(g_engine.SpotSymbol(), InpTF, 0);
   // 去抖：同一动作同一根K只推一次
   if(act == g_last_alert_act && bar == g_last_alert_bar)
      return;
   g_last_alert_act = act;
   g_last_alert_bar = bar;

   Print(msg);
   if(InpUseAlert)
      Alert(msg);
   if(InpUsePush)
      SendNotification(msg);
   if(g_tg.Enabled())
      g_tg.NotifyEvent(msg);
  }

bool OpenSpread(const ENUM_BASIS_SIDE side, const string why)
  {
   if(InpSignalOnly)
     {
      g_status = "信号:"+why;
      g_engine.SetOpenSide(side); // 虚拟持仓，便于后续平仓/待利提醒
      const int act = (side==BASIS_SHORT_SPREAD ? 1 : 2);
      const string tag = (side==BASIS_SHORT_SPREAD)
         ? "【开仓提醒】空基差(空期+多现) "
         : "【开仓提醒】多基差(多期+空现) ";
      NotifySignal(act, tag + why);
      return true;
     }

   // 已有仓则不开
   if(CountMagicPositions("") > 0)
     {
      g_status = "已有持仓，跳过开仓";
      return false;
     }

   double lot_s, lot_f;
   g_engine.LotsForSide(side, lot_s, lot_f);
   if(lot_s<=0 || lot_f<=0)
     {
      g_status = "手数无效";
      return false;
     }

   const string spot = g_engine.SpotSymbol();
   const string fut  = g_engine.FutSymbol();
   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);

   bool ok_s=false, ok_f=false;
   string cmt = "BasisZ";

   // SHORT_SPREAD: 空期 + 多现
   // LONG_SPREAD:  多期 + 空现
   g_trade.SetTypeFillingBySymbol(spot);
   g_trade.SetTypeFillingBySymbol(fut);

   if(side == BASIS_SHORT_SPREAD)
     {
      ok_f = g_trade.Sell(lot_f, fut, 0, 0, 0, cmt);
      if(ok_f) ok_s = g_trade.Buy(lot_s, spot, 0, 0, 0, cmt);
     }
   else if(side == BASIS_LONG_SPREAD)
     {
      ok_f = g_trade.Buy(lot_f, fut, 0, 0, 0, cmt);
      if(ok_f) ok_s = g_trade.Sell(lot_s, spot, 0, 0, 0, cmt);
     }

   if(!ok_f || !ok_s)
     {
      // 单腿失败则撤掉已开腿，避免裸敞口
      PrintFormat("开仓失败 fut=%d spot=%d — 回滚", (int)ok_f, (int)ok_s);
      CloseLeg(spot, "rollback");
      CloseLeg(fut, "rollback");
      g_status = "开仓失败已回滚";
      return false;
     }

   g_engine.SetOpenSide(side);
   g_status = why;
   PrintFormat("开仓成功 side=%d lot_s=%.2f lot_f=%.2f | %s", (int)side, lot_s, lot_f, why);
   const string tag = (side==BASIS_SHORT_SPREAD)
      ? "【开仓】空基差(空期+多现) "
      : "【开仓】多基差(多期+空现) ";
   NotifySignal(side==BASIS_SHORT_SPREAD ? 1 : 2, tag + why);
   return true;
  }

void SyncOpenSideFromPositions(void)
  {
   // 仅提醒模式用引擎内虚拟持仓，不被空仓覆盖
   if(InpSignalOnly && CountMagicPositions("")==0)
      return;

   const string spot = g_engine.SpotSymbol();
   const string fut  = g_engine.FutSymbol();
   int spot_buy=0, spot_sell=0, fut_buy=0, fut_sell=0;
   for(int i=PositionsTotal()-1;i>=0;--i)
     {
      if(!g_pos.SelectByIndex(i)) continue;
      if(g_pos.Magic()!=InpMagic) continue;
      if(g_pos.Symbol()==spot)
        {
         if(g_pos.PositionType()==POSITION_TYPE_BUY) spot_buy++;
         else spot_sell++;
        }
      else if(g_pos.Symbol()==fut)
        {
         if(g_pos.PositionType()==POSITION_TYPE_BUY) fut_buy++;
         else fut_sell++;
        }
     }
   if(spot_buy>0 && fut_sell>0) g_engine.SetOpenSide(BASIS_SHORT_SPREAD);
   else if(spot_sell>0 && fut_buy>0) g_engine.SetOpenSide(BASIS_LONG_SPREAD);
   else if(CountMagicPositions("")==0) g_engine.NotifyClosed();
  }

void PanelSet(const string name, const int y, const string text, const color clr)
  {
   const string n = PANEL_PREFIX + name;
   if(ObjectFind(0, n) < 0)
     {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_XDISTANCE, 8);
      ObjectSetString(0, n, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(0, n, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
     }
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetString(0, n, OBJPROP_TEXT, text);
  }

void DestroyPanel(void)
  {
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
     {
      const string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, PANEL_PREFIX) == 0)
         ObjectDelete(0, name);
     }
  }

void RenderPanel(void)
  {
   const SBasisSnapshot s = g_engine.Snapshot();
   string side = "FLAT";
   if(g_engine.OpenSide()==BASIS_SHORT_SPREAD) side="空基差(空期+多现)";
   else if(g_engine.OpenSide()==BASIS_LONG_SPREAD) side="多基差(多期+空现)";
   const double pnl = FloatingProfitMagic();
   const string mode = InpSignalOnly ? "仅提醒" : "实盘对冲";

   Comment(""); // 改用面板，清空旧 Comment

   if(!InpShowPanel)
     {
      Comment(
         "GoldFX 基差套利 v1.1 [", mode, "]\n",
         "现货 ", g_engine.SpotSymbol(), " = ", DoubleToString(s.spot_mid, 2),
         " | 期货 ", g_engine.FutSymbol(), " = ", DoubleToString(s.fut_mid, 2), "\n",
         "基差 ", DoubleToString(s.spread, 4),
         " 均值 ", DoubleToString(s.mean, 4),
         " σ ", DoubleToString(s.stdev, 4), "\n",
         "Z=", DoubleToString(s.zscore, 2),
         " Corr=", DoubleToString(s.corr, 2),
         " Hedge=", DoubleToString(s.hedge_ratio, 3), "\n",
         "持仓: ", side, " 浮盈=", DoubleToString(pnl, 2),
         (g_paused?" | 日亏损暂停":""), "\n",
         g_status
      );
      return;
     }

   color zcol = clrSilver;
   if(s.zscore >= InpEntryZ) zcol = clrOrangeRed;
   else if(s.zscore <= -InpEntryZ) zcol = clrLime;
   else if(MathAbs(s.zscore) <= InpExitZ) zcol = clrGold;

   PanelSet("t0", 18, "GoldFX 基差套利 v1.1  [" + mode + "]", clrAqua);
   PanelSet("t1", 34, StringFormat("现货 %s = %.2f   期货 %s = %.2f",
            g_engine.SpotSymbol(), s.spot_mid, g_engine.FutSymbol(), s.fut_mid), clrWhiteSmoke);
   PanelSet("t2", 50, StringFormat("基差 %.4f  均值 %.4f  σ %.4f",
            s.spread, s.mean, s.stdev), clrDodgerBlue);
   PanelSet("t3", 66, StringFormat("Z=%.2f  Corr=%.2f  Hedge=%.3f  浮盈=%.2f",
            s.zscore, s.corr, s.hedge_ratio, pnl), zcol);
   PanelSet("t4", 82, StringFormat("持仓: %s%s", side, g_paused?" | 日亏损暂停":""), clrSilver);
   PanelSet("t5", 98, g_status, clrKhaki);
  }

//------------------------------------------------------------------
int OnInit()
  {
   string spot = InpSpotSymbol;
   StringTrimLeft(spot); StringTrimRight(spot);
   if(StringLen(spot)==0) spot = _Symbol;

   string fut = InpFutSymbol;
   StringTrimLeft(fut); StringTrimRight(fut);
   if(StringLen(fut)==0)
     {
      Print("请填写 InpFutSymbol（期货/远期黄金品种）");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(spot == fut)
     {
      Print("现货与期货品种不能相同");
      return INIT_PARAMETERS_INCORRECT;
     }

   SBasisParams p;
   ZeroMemory(p);
   p.spot_symbol = spot;
   p.fut_symbol  = fut;
   p.tf = InpTF;
   p.spread_mode = InpSpreadMode;
   p.lookback = InpLookback;
   p.entry_z = InpEntryZ;
   p.exit_z = InpExitZ;
   p.stop_z = InpStopZ;
   p.min_corr = InpMinCorr;
   p.min_bars = InpMinBars;
   p.max_hold_bars = InpMaxHoldBars;
   p.lot_spot = InpLotSpot;
   p.auto_hedge = InpAutoHedge;
   p.max_spread_spot = InpMaxSpreadSpot;
   p.max_spread_fut = InpMaxSpreadFut;
   p.trade_both_legs = !InpSignalOnly;
   p.magic = InpMagic;
   p.slippage = InpSlippage;
   p.cooldown_bars = InpCooldownBars;
   p.min_profit_money = InpMinProfitMoney;

   if(!g_engine.Init(p))
      return INIT_FAILED;

   g_tg.ConfigureDirect(InpTelegramEnable, InpTelegramToken, InpTelegramChatId);

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   RefreshDay();
   SyncOpenSideFromPositions();
   g_status = "基差引擎就绪 — 等待Z分触发";
   g_last_alert_act = -1;
   g_last_alert_bar = 0;
   PrintFormat("BasisArb spot=%s fut=%s TF=%d entryZ=%.1f exitZ=%.1f minProfit=%.2f signalOnly=%d",
               spot, fut, (int)InpTF, InpEntryZ, InpExitZ, InpMinProfitMoney, (int)InpSignalOnly);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   Comment("");
   DestroyPanel();
  }

void OnTick()
  {
   RefreshDay();
   const bool newbar = g_engine.Update(true);
   SyncOpenSideFromPositions();

   const double pnl_real = FloatingProfitMagic();
   double pnl = pnl_real;
   // 仅提醒且无实仓：Z 回归即视为满足最小盈利门槛（无真实浮盈可计）
   if(InpSignalOnly && CountMagicPositions("")==0 && g_engine.OpenSide()!=BASIS_FLAT)
      pnl = MathMax(pnl_real, InpMinProfitMoney);

   if(!InpAllowTrade || g_paused)
     {
      g_status = g_paused ? "日亏损达限，暂停" : "交易关闭";
      RenderPanel();
      return;
     }
   if(!InSession())
     {
      g_status = "非交易时段";
      // 时段外仅允许平仓逻辑在新棒执行
     }

   string why;
   const int act = g_engine.Decide(why, pnl);

   // 平仓不受时段限制
   if(act==3 || act==4)
     {
      if(InpSignalOnly)
        {
         g_status = why;
         const string tag = (act==4) ? "【止损/超时提醒】" : "【平仓提醒】";
         NotifySignal(act, tag + why + StringFormat(" 浮盈=%.2f", pnl));
         if(CountMagicPositions("") > 0)
            CloseAllLegs(why);
         else
            g_engine.NotifyClosed(); // 清除虚拟持仓
         RenderPanel();
         return;
        }
      CloseAllLegs(why);
      RenderPanel();
      return;
     }

   if(!InSession())
     {
      g_status = why;
      RenderPanel();
      return;
     }

   // 仅在新棒开仓，避免 tick 噪声重复触发
   if(newbar && act==1)
      OpenSpread(BASIS_SHORT_SPREAD, why);
   else if(newbar && act==2)
      OpenSpread(BASIS_LONG_SPREAD, why);
   else
      g_status = why;

   // 信号模式：持仓回归待利时也可在新棒提醒一次「待利」
   if(InpSignalOnly && newbar && g_engine.OpenSide()!=BASIS_FLAT &&
      StringFind(why, "回归待利") == 0)
      NotifySignal(10, "【待平仓】" + why);

   RenderPanel();
  }
//+------------------------------------------------------------------+
