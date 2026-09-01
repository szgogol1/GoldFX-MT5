//+------------------------------------------------------------------+
//| GoldFX_BasisCheck.mq5 — 一次性期现套利可行性检查（脚本）            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property version   "1.00"
#property script_show_inputs
#property description "运行一次，在专家日志输出完整可行性报告"

#include <GoldFX/BasisFeasibility.mqh>

input string InpSpotSymbol     = "XAUUSD";
input string InpFutSymbol      = "GCZ26_CFD";
input ENUM_TIMEFRAMES InpTF    = PERIOD_M15;
input int    InpLookback       = 60;
input double InpEntryZ         = 2.0;
input double InpMinCorr        = 0.88;
input int    InpMinBars        = 120;
input double InpMinCostEdge    = 1.5;
input double InpContractTolPct = 5.0;
input int    InpMinDaysExpiry  = 14;
input bool   InpExportCsv      = true;

//------------------------------------------------------------------
void OnStart()
  {
   SBasisParams p;
   ZeroMemory(p);
   p.spot_symbol = InpSpotSymbol;
   p.fut_symbol  = InpFutSymbol;
   p.tf = InpTF;
   p.spread_mode = BASIS_DIFF;
   p.lookback = InpLookback;
   p.entry_z = InpEntryZ;
   p.exit_z = 0.40;
   p.stop_z = 3.5;
   p.min_corr = InpMinCorr;
   p.min_bars = InpMinBars;
   p.max_spread_spot = 0.60;
   p.max_spread_fut = 0.80;
   p.lot_spot = 0.01;
   p.auto_hedge = true;
   p.trade_both_legs = false;

   CBasisFeasibility feas;
   if(!feas.Init(p))
     {
      Print("初始化失败 — 检查品种是否在市场报价中可见");
      return;
     }

   // 等待历史
   int wait = 0;
   while(wait < 30)
     {
      feas.Refresh();
      const SBasisSnapshot s = feas.Engine().Snapshot();
      if(s.stdev > 0.0)
         break;
      Sleep(1000);
      wait++;
     }

   const SFeasibilityReport r = feas.Evaluate(InpMinCorr, InpMinCostEdge, InpContractTolPct, InpMinDaysExpiry);
   const string report = feas.FormatReport(r);
   Print(report);
   Alert(StringFormat("期现套利: %s 评分%d — 详见专家日志", r.verdict_text, r.score));

   if(InpExportCsv)
     {
      const string fn = StringFormat("GoldFX_BasisCheck_%s.csv", TimeToString(TimeCurrent(), TIME_DATE));
      int h = FileOpen(fn, FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_COMMON, ',');
      if(h != INVALID_HANDLE)
        {
         FileWrite(h, "time", "verdict", "score", "spot", "fut", "basis", "z", "corr",
                  "hedge_ratio", "cost_oz", "edge_oz", "cost_edge_ratio", "days_expiry", "signal");
         FileWrite(h,
                   TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES),
                   r.verdict_text, r.score,
                   r.spot_mid, r.fut_mid, r.basis, r.zscore, r.corr,
                   r.hedge_ratio, r.est_cost_per_oz, r.est_edge_to_mean,
                   r.cost_edge_ratio, r.days_to_expiry, r.signal_hint);
         FileClose(h);
         Print("已导出: ", TerminalInfoString(TERMINAL_COMMONDATA_PATH), "\\Files\\", fn);
        }
     }
  }
//+------------------------------------------------------------------+
