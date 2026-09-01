//+------------------------------------------------------------------+
//| GoldFX_BasisMonitor.mq5 — 黄金期现基差套利可行性监测（仅监控不下单） |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.00"
#property indicator_chart_window
#property description "监测 XAUUSD vs GC 期货基差、Z分、成本与可行性评分"

#include <GoldFX/BasisFeasibility.mqh>

input group "=== 品种 (IC Markets SC) ==="
input string InpSpotSymbol     = "XAUUSD";        // 现货
input string InpFutSymbol      = "GCZ26_CFD";     // 期货 CFD
input ENUM_TIMEFRAMES InpTF    = PERIOD_M15;

input group "=== 统计 ==="
input ENUM_BASIS_SPREAD_MODE InpSpreadMode = BASIS_DIFF;
input int    InpLookback       = 60;
input double InpEntryZ         = 2.0;
input double InpExitZ        = 0.40;
input double InpStopZ          = 3.5;
input double InpMinCorr        = 0.88;
input int    InpMinBars        = 120;

input group "=== 可行性阈值 ==="
input double InpMinCostEdge    = 1.5;           // 边际/成本最低比
input double InpContractTolPct = 5.0;           // 对冲比容差 %
input int    InpMinDaysExpiry  = 14;            // 到期前最少天数
input double InpMaxSpreadSpot  = 0.60;
input double InpMaxSpreadFut   = 0.80;

input group "=== 显示 ==="
input bool   InpShowPanel      = true;
input int    InpPanelX         = 12;
input int    InpPanelY         = 28;
input color  InpColorGood      = clrLime;
input color  InpColorWarn      = clrGold;
input color  InpColorBad       = clrTomato;

//---
CBasisFeasibility g_feas;
string            g_prefix = "GFX_BasisMon_";
datetime          g_last_log = 0;

//------------------------------------------------------------------
color VerdictColor(const ENUM_FEASIBILITY_VERDICT v)
  {
   if(v >= FEAS_FEASIBLE) return InpColorGood;
   if(v == FEAS_MARGINAL)  return InpColorWarn;
   return InpColorBad;
  }

void DeleteObjects(void)
  {
   const int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; --i)
     {
      const string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, g_prefix) == 0)
         ObjectDelete(0, name);
     }
  }

void DrawLabel(const string id, const int y, const string text, const color clr, const int font_size=9)
  {
   const string name = g_prefix + id;
   if(ObjectFind(0, name) < 0)
     {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
     }
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, InpPanelX);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, InpPanelY + y);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, font_size);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
  }

void RenderPanel(const SFeasibilityReport &r)
  {
   if(!InpShowPanel)
     {
      Comment(g_feas.FormatReport(r));
      return;
     }

   const color vc = VerdictColor(r.verdict);
   DrawLabel("title", 0, "GoldFX 期现套利监测", clrWhite, 10);
   DrawLabel("verdict", 16, StringFormat("结论: %s  评分 %d/100", r.verdict_text, r.score), vc, 10);
   DrawLabel("prices", 34, StringFormat("现 %.2f | 期 %.2f | 基差 %.2f", r.spot_mid, r.fut_mid, r.basis), clrSilver);
   DrawLabel("stats", 50, StringFormat("Z=%.2f  μ=%.2f  σ=%.2f  Corr=%.2f", r.zscore, r.basis_mean, r.basis_stdev, r.corr), clrSilver);
   DrawLabel("hedge", 66, StringFormat("对冲比 %.3f | 合约 %.0f/%.0f oz | %s",
              r.hedge_ratio, r.spot_contract, r.fut_contract,
              (r.contracts_aligned ? "对齐" : "未对齐")), clrSilver);
   DrawLabel("cost", 82, StringFormat("点差 现%.2f+期%.2f | 成本≈$%.2f/oz | 空间$%.2f | 比%.2f",
              r.spot_spread, r.fut_spread, r.est_cost_per_oz, r.est_edge_to_mean, r.cost_edge_ratio), clrSilver);
   DrawLabel("exp", 98, StringFormat("到期 %s (%d天) | 信号: %s",
              (r.fut_expiry>0 ? TimeToString(r.fut_expiry, TIME_DATE) : "—"),
              r.days_to_expiry, r.signal_hint), clrSilver);
   DrawLabel("opp", 114, "机会: " + (StringLen(r.opportunities)>0 ? r.opportunities : "—"), InpColorGood);
   DrawLabel("blk", 130, "阻碍: " + (StringLen(r.blockers)>0 ? r.blockers : "—"), InpColorBad);
   DrawLabel("sym", 146, StringFormat("%s vs %s | %s", InpSpotSymbol, InpFutSymbol,
              TimeToString(TimeCurrent(), TIME_MINUTES)), clrDarkGray);
  }

//------------------------------------------------------------------
int OnInit()
  {
   string spot = InpSpotSymbol;
   string fut  = InpFutSymbol;
   StringTrimLeft(spot); StringTrimRight(spot);
   StringTrimLeft(fut);  StringTrimRight(fut);
   if(StringLen(fut)==0)
     {
      Print("请填写 InpFutSymbol，如 GCZ26_CFD");
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
   p.max_spread_spot = InpMaxSpreadSpot;
   p.max_spread_fut = InpMaxSpreadFut;
   p.lot_spot = 0.01;
   p.auto_hedge = true;
   p.trade_both_legs = false;

   if(!g_feas.Init(p))
      return INIT_FAILED;

   IndicatorSetString(INDICATOR_SHORTNAME, "GoldFX Basis Monitor");
   Print("BasisMonitor 启动 spot=", spot, " fut=", fut);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   DeleteObjects();
   Comment("");
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   g_feas.Refresh();
   const SFeasibilityReport r = g_feas.Evaluate(InpMinCorr, InpMinCostEdge, InpContractTolPct, InpMinDaysExpiry);
   RenderPanel(r);

   // 每小时打印一次日志
   if(TimeCurrent() - g_last_log >= 3600)
     {
      Print(g_feas.FormatReport(r));
      g_last_log = TimeCurrent();
     }
   return rates_total;
  }
//+------------------------------------------------------------------+
