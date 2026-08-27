//+------------------------------------------------------------------+
//| GoldFX_BasisArb.mq5 — 黄金期货/现货基差均值回归套利                  |
//| 逻辑：B=F-S → 滚动Z分；Z高则空基差(空期+多现)，Z低则多基差            |
//| 要求：经纪商同时提供现货与期货/远期类黄金品种；对冲账户推荐            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.00"
#property description "黄金现货-期货基差Z分均值回归套利（双边对冲）"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <GoldFX/BasisArbitrage.mqh>

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

input group "=== 仓位 / 风控 ==="
input double InpLotSpot        = 0.10;         // 现货基准手数
input bool   InpAutoHedge      = true;         // 按名义价值对冲期货手数
input double InpMaxDailyLossPct= 2.0;
input double InpMaxSpreadSpot  = 0.60;         // 现货最大点差（价格）
input double InpMaxSpreadFut   = 0.80;
input bool   InpAllowTrade     = true;
input bool   InpSignalOnly     = false;        // true=仅提示不开仓
input int    InpMagic          = 20260827;
input int    InpSlippage       = 40;

input group "=== 时段 ==="
input bool   InpUseSession     = true;
input int    InpSessStart      = 1;            // 避开日切换月高峰可自调
input int    InpSessEnd        = 22;
input bool   InpFridayCut      = true;
input int    InpFridayHour     = 18;

//---
CBasisArbitrage g_engine;
CTrade          g_trade;
CPositionInfo   g_pos;
string          g_status = "";
datetime        g_day_stamp = 0;
double          g_day_start_eq = 0;
bool            g_paused = false;

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
   bool ok1 = CloseLeg(spot, why);
   bool ok2 = CloseLeg(fut, why);
   g_engine.NotifyClosed();
   g_status = why;
   Print("基差平仓: ", why);
   return ok1 && ok2;
  }

bool OpenSpread(const ENUM_BASIS_SIDE side, const string why)
  {
   if(InpSignalOnly)
     {
      g_status = "信号:"+why;
      Print(g_status);
      return false;
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
   return true;
  }

void SyncOpenSideFromPositions(void)
  {
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

void RenderComment(void)
  {
   const SBasisSnapshot s = g_engine.Snapshot();
   string side = "FLAT";
   if(g_engine.OpenSide()==BASIS_SHORT_SPREAD) side="空基差(空期+多现)";
   else if(g_engine.OpenSide()==BASIS_LONG_SPREAD) side="多基差(多期+空现)";
   Comment(
      "GoldFX 基差套利 v1\n",
      "现货 ", g_engine.SpotSymbol(), " = ", DoubleToString(s.spot_mid, 2),
      " | 期货 ", g_engine.FutSymbol(), " = ", DoubleToString(s.fut_mid, 2), "\n",
      "基差 ", DoubleToString(s.spread, 4),
      " 均值 ", DoubleToString(s.mean, 4),
      " σ ", DoubleToString(s.stdev, 4), "\n",
      "Z=", DoubleToString(s.zscore, 2),
      " Corr=", DoubleToString(s.corr, 2),
      " Hedge=", DoubleToString(s.hedge_ratio, 3), "\n",
      "持仓: ", side, (g_paused?" | 日亏损暂停":""), "\n",
      g_status
   );
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

   if(!g_engine.Init(p))
      return INIT_FAILED;

   g_trade.SetExpertMagicNumber(InpMagic);
   g_trade.SetDeviationInPoints(InpSlippage);
   RefreshDay();
   SyncOpenSideFromPositions();
   g_status = "基差引擎就绪 — 等待Z分触发";
   PrintFormat("BasisArb spot=%s fut=%s TF=%d entryZ=%.1f exitZ=%.1f",
               spot, fut, (int)InpTF, InpEntryZ, InpExitZ);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason) { Comment(""); }

void OnTick()
  {
   RefreshDay();
   const bool newbar = g_engine.Update(true);
   SyncOpenSideFromPositions();

   if(!InpAllowTrade || g_paused)
     {
      g_status = g_paused ? "日亏损达限，暂停" : "交易关闭";
      RenderComment();
      return;
     }
   if(!InSession())
     {
      g_status = "非交易时段";
      // 时段外仅允许平仓逻辑在新棒执行
     }

   string why;
   const int act = g_engine.Decide(why);

   // 平仓不受时段限制
   if(act==3 || act==4)
     {
      CloseAllLegs(why);
      RenderComment();
      return;
     }

   if(!InSession())
     {
      RenderComment();
      return;
     }

   // 仅在新棒开仓，避免 tick 噪声重复触发
   if(newbar && act==1)
      OpenSpread(BASIS_SHORT_SPREAD, why);
   else if(newbar && act==2)
      OpenSpread(BASIS_LONG_SPREAD, why);
   else
      g_status = why;

   RenderComment();
  }
//+------------------------------------------------------------------+
