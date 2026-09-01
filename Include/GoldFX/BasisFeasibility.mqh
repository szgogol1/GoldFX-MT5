//+------------------------------------------------------------------+
//| BasisFeasibility.mqh — 黄金期现基差套利可行性评估                   |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_BASIS_FEASIBILITY_MQH
#define GOLDFX_BASIS_FEASIBILITY_MQH

#include "BasisArbitrage.mqh"

enum ENUM_FEASIBILITY_VERDICT
  {
   FEAS_UNKNOWN      = 0,
   FEAS_NOT_FEASIBLE = 1,
   FEAS_MARGINAL     = 2,
   FEAS_FEASIBLE     = 3,
   FEAS_STRONG       = 4
  };

struct SFeasibilityReport
  {
   ENUM_FEASIBILITY_VERDICT verdict;
   int                      score;              // 0-100
   string                   verdict_text;
   string                   summary;

   double spot_mid;
   double fut_mid;
   double basis;
   double basis_mean;
   double basis_stdev;
   double zscore;
   double corr;
   double hedge_ratio;

   double spot_spread;
   double fut_spread;
   double spot_contract;
   double fut_contract;
   double spot_tick_value;
   double fut_tick_value;
   bool   contracts_aligned;

   double est_cost_per_oz;        // 开平双边点差折算 $/oz
   double est_edge_to_mean;       // |basis-mean| $
   double cost_edge_ratio;        // edge/cost
   double min_profitable_move;    // 至少需基差变动 $

   int    days_to_expiry;
   datetime fut_expiry;
   string signal_hint;            // 做空基差/做多基差/观望

   string blockers;
   string opportunities;
  };

class CBasisFeasibility
  {
private:
   CBasisArbitrage m_engine;
   SBasisParams    m_p;

   double TickValuePerOz(const string sym) const
     {
      const double tick_sz = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
      const double tick_val = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
      const double cs = SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE);
      if(tick_sz <= 0.0 || tick_val <= 0.0 || cs <= 0.0)
         return 0.0;
      return tick_val / tick_sz / cs;
     }

   int DaysToExpiry(const string sym) const
     {
      const datetime exp = (datetime)SymbolInfoInteger(sym, SYMBOL_EXPIRATION_TIME);
      if(exp <= 0)
         return -1;
      const int sec = (int)(exp - TimeCurrent());
      if(sec <= 0)
         return 0;
      return sec / 86400;
     }

   string VerdictText(const ENUM_FEASIBILITY_VERDICT v) const
     {
      switch(v)
        {
         case FEAS_STRONG:       return "强可行";
         case FEAS_FEASIBLE:     return "可行";
         case FEAS_MARGINAL:     return "边际";
         case FEAS_NOT_FEASIBLE: return "不可行";
         default:                return "未知";
        }
     }

public:
   bool Init(const SBasisParams &p)
     {
      m_p = p;
      return m_engine.Init(p);
     }

   bool Refresh(void)
     {
      return m_engine.Update(false);
     }

   CBasisArbitrage &Engine(void) { return m_engine; }

   SFeasibilityReport Evaluate(const double min_corr,
                               const double min_cost_edge_ratio,
                               const double contract_tol_pct,
                               const int    min_days_to_expiry) const
     {
      SFeasibilityReport r;
      ZeroMemory(r);
      r.verdict = FEAS_UNKNOWN;
      r.score = 0;
      r.verdict_text = "未知";
      r.summary = "数据不足";

      const SBasisSnapshot s = m_engine.Snapshot();
      r.spot_mid = s.spot_mid;
      r.fut_mid  = s.fut_mid;
      r.basis    = s.spread;
      r.basis_mean = s.mean;
      r.basis_stdev = s.stdev;
      r.zscore = s.zscore;
      r.corr = s.corr;
      r.hedge_ratio = s.hedge_ratio;

      const string spot = m_engine.SpotSymbol();
      const string fut  = m_engine.FutSymbol();

      MqlTick ts, tf;
      double ss = 0.0, sf = 0.0;
      if(SymbolInfoTick(spot, ts))
         ss = ts.ask - ts.bid;
      if(SymbolInfoTick(fut, tf))
         sf = tf.ask - tf.bid;

      r.spot_spread = ss;
      r.fut_spread  = sf;
      r.spot_contract = SymbolInfoDouble(spot, SYMBOL_TRADE_CONTRACT_SIZE);
      r.fut_contract  = SymbolInfoDouble(fut, SYMBOL_TRADE_CONTRACT_SIZE);
      r.spot_tick_value = TickValuePerOz(spot);
      r.fut_tick_value  = TickValuePerOz(fut);

      const double hr_tol = MathMax(0.01, contract_tol_pct / 100.0);
      r.contracts_aligned =
         (r.hedge_ratio >= 1.0 - hr_tol && r.hedge_ratio <= 1.0 + hr_tol) &&
         (r.spot_contract > 0.0 && r.fut_contract > 0.0 &&
          MathAbs(r.spot_contract - r.fut_contract) / MathMax(r.spot_contract, r.fut_contract) <= hr_tol);

      r.fut_expiry = (datetime)SymbolInfoInteger(fut, SYMBOL_EXPIRATION_TIME);
      r.days_to_expiry = DaysToExpiry(fut);

      // 开平各一次：两腿点差之和 ≈ 每盎司成本（同报价货币、同合约规模时）
      r.est_cost_per_oz = ss + sf;
      r.est_edge_to_mean = MathAbs(r.basis - r.basis_mean);
      r.min_profitable_move = r.est_cost_per_oz * 1.15; // 15% 安全边际
      r.cost_edge_ratio = (r.est_cost_per_oz > 1e-9) ? r.est_edge_to_mean / r.est_cost_per_oz : 0.0;

      string blockers = "";
      string opps = "";

      int score = 0;

      // --- 相关性与统计 ---
      if(s.stdev <= 1e-9)
        {
         blockers += "基差标准差无效; ";
        }
      else
        {
         score += 15;
         if(s.corr >= min_corr) score += 20;
         else blockers += StringFormat("相关不足(%.2f<%.2f); ", s.corr, min_corr);

         if(s.stdev >= 1.0) score += 10;
         else blockers += "基差波动过小; ";
        }

      // --- 合约对齐 ---
      if(r.contracts_aligned)
         score += 20;
      else
         blockers += StringFormat("对冲比偏离(%.3f); ", r.hedge_ratio);

      // --- 成本 vs 边际 ---
      if(r.est_cost_per_oz > 0.0 && r.cost_edge_ratio >= min_cost_edge_ratio)
         score += 20;
      else if(r.est_cost_per_oz > 0.0 && r.cost_edge_ratio >= 1.0)
         score += 10;
      else
         blockers += StringFormat("边际/成本比偏低(%.2f); ", r.cost_edge_ratio);

      if(r.est_edge_to_mean >= r.min_profitable_move)
         score += 10;
      else
         blockers += StringFormat("距均值空间不足($%.2f<$%.2f); ", r.est_edge_to_mean, r.min_profitable_move);

      // --- 点差闸门 ---
      if(m_p.max_spread_spot > 0.0 && ss > m_p.max_spread_spot)
         blockers += "现货点差过大; ";
      else score += 5;

      if(m_p.max_spread_fut > 0.0 && sf > m_p.max_spread_fut)
         blockers += "期货点差过大; ";
      else score += 5;

      // --- 到期 ---
      if(r.days_to_expiry >= 0)
        {
         if(r.days_to_expiry < min_days_to_expiry)
            blockers += StringFormat("距到期仅%d天; ", r.days_to_expiry);
         else
            score += 10;
        }
      else
         score += 5; // 无到期（现货腿）

      // --- 信号机会 ---
      if(s.zscore >= m_p.entry_z)
        {
         r.signal_hint = "做空基差(买现货+卖期货)";
         opps += StringFormat("Z=%.2f 偏高; ", s.zscore);
         score += 15;
        }
      else if(s.zscore <= -m_p.entry_z)
        {
         r.signal_hint = "做多基差(卖现货+买期货)";
         opps += StringFormat("Z=%.2f 偏低; ", s.zscore);
         score += 15;
        }
      else if(MathAbs(s.zscore) >= m_p.entry_z * 0.75)
        {
         r.signal_hint = "接近入场区，继续观察";
         opps += StringFormat("Z=%.2f 临近阈值; ", s.zscore);
         score += 8;
        }
      else
        {
         r.signal_hint = "观望(基差未极端)";
         blockers += "Z未达入场; ";
        }

      if(r.contracts_aligned && s.corr >= min_corr)
         opps += "合约可对冲; ";

      if(r.est_edge_to_mean >= r.min_profitable_move)
         opps += StringFormat("潜在空间$%.2f/oz; ", r.est_edge_to_mean);

      score = MathMin(100, MathMax(0, score));

      if(score >= 75 && StringFind(blockers, "相关") < 0 && r.contracts_aligned)
         r.verdict = FEAS_STRONG;
      else if(score >= 60 && r.contracts_aligned && s.corr >= min_corr - 0.05)
         r.verdict = FEAS_FEASIBLE;
      else if(score >= 45)
         r.verdict = FEAS_MARGINAL;
      else
         r.verdict = FEAS_NOT_FEASIBLE;

      r.score = score;
      r.verdict_text = VerdictText(r.verdict);
      r.blockers = blockers;
      r.opportunities = opps;
      r.summary = StringFormat("%s | 评分%d | Z=%.2f Corr=%.2f 基差=%.2f",
                               r.verdict_text, r.score, r.zscore, r.corr, r.basis);
      return r;
     }

   string FormatReport(const SFeasibilityReport &r) const
     {
      string exp = (r.fut_expiry > 0) ? TimeToString(r.fut_expiry, TIME_DATE) : "无";
      return StringFormat(
         "=== 黄金期现套利可行性 ===\n"
         "结论: %s (评分 %d/100)\n"
         "现货 %s = %.2f (点差 %.2f)\n"
         "期货 %s = %.2f (点差 %.2f)\n"
         "基差 F-S = %.2f | 均值 %.2f | σ %.2f\n"
         "Z = %.2f | 相关 = %.2f | 对冲比 = %.3f\n"
         "合约 oz: 现 %.0f / 期 %.0f | 对齐: %s\n"
         "预估成本 $/oz = %.2f | 至均值空间 $ = %.2f | 比 = %.2f\n"
         "最小盈利基差变动 ≈ $%.2f/oz\n"
         "期货到期: %s (%d 天)\n"
         "信号: %s\n"
         "机会: %s\n"
         "阻碍: %s\n"
         "时间: %s\n",
         r.verdict_text, r.score,
         m_engine.SpotSymbol(), r.spot_mid, r.spot_spread,
         m_engine.FutSymbol(), r.fut_mid, r.fut_spread,
         r.basis, r.basis_mean, r.basis_stdev,
         r.zscore, r.corr, r.hedge_ratio,
         r.spot_contract, r.fut_contract, (r.contracts_aligned ? "是" : "否"),
         r.est_cost_per_oz, r.est_edge_to_mean, r.cost_edge_ratio,
         r.min_profitable_move,
         exp, r.days_to_expiry,
         r.signal_hint,
         (StringLen(r.opportunities) > 0 ? r.opportunities : "—"),
         (StringLen(r.blockers) > 0 ? r.blockers : "—"),
         TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES)
      );
     }
  };

#endif
//+------------------------------------------------------------------+
