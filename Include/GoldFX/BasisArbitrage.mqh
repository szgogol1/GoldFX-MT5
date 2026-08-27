//+------------------------------------------------------------------+
//| BasisArbitrage.mqh — 黄金期货/现货基差均值回归套利引擎              |
//| 基差 B = Futures - Spot；滚动 Z 分触发双边对冲；无网格无马丁        |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_BASIS_ARBITRAGE_MQH
#define GOLDFX_BASIS_ARBITRAGE_MQH

#include "Common.mqh"

enum ENUM_BASIS_SIDE
  {
   BASIS_FLAT     = 0,
   BASIS_SHORT_SPREAD = 1,  // 做空基差：空期货 + 多现货（基差过高）
   BASIS_LONG_SPREAD  = 2   // 做多基差：多期货 + 空现货（基差过低）
  };

enum ENUM_BASIS_SPREAD_MODE
  {
   BASIS_DIFF     = 0,  // Futures - Spot
   BASIS_RATIO    = 1,  // Futures / Spot - 1
   BASIS_LOGRATIO = 2   // ln(Futures/Spot)
  };

struct SBasisSnapshot
  {
   double spot_mid;
   double fut_mid;
   double spread;       // 原始基差
   double mean;
   double stdev;
   double zscore;
   double corr;         // 滚动相关
   double hedge_ratio;  // 期货手数 / 现货手数
   ENUM_BASIS_SIDE side;
   string reason;
  };

struct SBasisParams
  {
   string spot_symbol;
   string fut_symbol;
   ENUM_TIMEFRAMES tf;
   ENUM_BASIS_SPREAD_MODE spread_mode;
   int    lookback;          // 滚动窗口
   double entry_z;           // |Z| >= 入场
   double exit_z;            // |Z| <= 出场
   double stop_z;            // |Z| 逆向扩大止损
   double min_corr;          // 最低相关，否则禁开
   int    min_bars;
   int    max_hold_bars;     // 最大持仓 K 线数
   double lot_spot;          // 现货基准手数
   bool   auto_hedge;        // 按名义价值自动对冲
   double max_spread_spot;   // 现货最大点差（价格）
   double max_spread_fut;
   bool   trade_both_legs;   // false=仅信号模式
   int    magic;
   int    slippage;
   int    cooldown_bars;
   double min_profit_money;  // 回归平仓前最小双边浮盈（账户货币）；0=不要求
  };

class CBasisArbitrage
  {
private:
   SBasisParams      m_p;
   SBasisSnapshot    m_snap;
   datetime          m_last_bar;
   datetime          m_entry_bar_time;
   int               m_entry_bar_index;
   ENUM_BASIS_SIDE   m_open_side;
   int               m_cooldown_until_shift;

   bool MidPrice(const string sym, double &mid, double &spread) const
     {
      MqlTick t;
      if(!SymbolInfoTick(sym, t)) return false;
      mid = 0.5 * (t.ask + t.bid);
      spread = t.ask - t.bid;
      return (mid > 0.0);
     }

   double RawSpread(const double fut, const double spot) const
     {
      if(spot <= 0.0) return 0.0;
      if(m_p.spread_mode == BASIS_RATIO)
         return fut / spot - 1.0;
      if(m_p.spread_mode == BASIS_LOGRATIO)
         return MathLog(fut / spot);
      return fut - spot; // DIFF
     }

   // 名义价值对冲比：1 手现货对应多少手期货
   double CalcHedgeRatio(void) const
     {
      const double cs_s = SymbolInfoDouble(m_p.spot_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      const double cs_f = SymbolInfoDouble(m_p.fut_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      double mid_s, mid_f, sp;
      if(!MidPrice(m_p.spot_symbol, mid_s, sp) || !MidPrice(m_p.fut_symbol, mid_f, sp))
         return 1.0;
      const double tv_s = (cs_s > 0 ? cs_s : 100.0) * mid_s;
      const double tv_f = (cs_f > 0 ? cs_f : 100.0) * mid_f;
      if(tv_f <= 0.0) return 1.0;
      return tv_s / tv_f;
     }

   double NormalizeLot(const string sym, double lot) const
     {
      double amin = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
      double amax = SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX);
      double step = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
      if(step <= 0.0) step = 0.01;
      lot = MathFloor(lot / step + 1e-12) * step;
      return MathMax(amin, MathMin(amax, lot));
     }

public:
                     CBasisArbitrage(void)
                       : m_last_bar(0), m_entry_bar_time(0), m_entry_bar_index(0),
                         m_open_side(BASIS_FLAT), m_cooldown_until_shift(-1)
                     {
                      ZeroMemory(m_p);
                      ZeroMemory(m_snap);
                      m_p.lookback = 60;
                      m_p.entry_z = 2.0;
                      m_p.exit_z = 0.5;
                      m_p.stop_z = 3.5;
                      m_p.min_corr = 0.85;
                      m_p.min_bars = 120;
                      m_p.max_hold_bars = 48;
                      m_p.lot_spot = 0.10;
                      m_p.auto_hedge = true;
                      m_p.trade_both_legs = true;
                      m_p.spread_mode = BASIS_DIFF;
                      m_p.min_profit_money = 5.0;
                     }

   SBasisSnapshot Snapshot(void) const { return m_snap; }
   ENUM_BASIS_SIDE OpenSide(void) const { return m_open_side; }

   bool Init(const SBasisParams &p)
     {
      m_p = p;
      if(StringLen(m_p.spot_symbol)==0) m_p.spot_symbol = _Symbol;
      if(StringLen(m_p.fut_symbol)==0)
        {
         Print("CBasisArbitrage: 必须指定期货品种");
         return false;
        }
      if(!SymbolSelect(m_p.spot_symbol, true) || !SymbolSelect(m_p.fut_symbol, true))
        {
         Print("CBasisArbitrage: 无法选择品种 spot=", m_p.spot_symbol, " fut=", m_p.fut_symbol);
         return false;
        }
      m_p.lookback = MathMax(20, m_p.lookback);
      m_p.entry_z  = MathMax(0.5, m_p.entry_z);
      m_p.exit_z   = MathMax(0.0, MathMin(m_p.entry_z - 0.1, m_p.exit_z));
      m_p.stop_z   = MathMax(m_p.entry_z + 0.5, m_p.stop_z);
      m_open_side  = BASIS_FLAT;
      m_last_bar   = 0;
      return true;
     }

   void SetOpenSide(const ENUM_BASIS_SIDE side)
     {
      m_open_side = side;
      if(side != BASIS_FLAT)
        {
         m_entry_bar_time = iTime(m_p.spot_symbol, m_p.tf, 0);
         m_entry_bar_index = 0;
        }
     }

   void NotifyClosed(void)
     {
      m_open_side = BASIS_FLAT;
      m_cooldown_until_shift = m_p.cooldown_bars;
     }

   // 刷新统计（每根新 K 调用）；返回是否新棒
   bool Update(const bool new_bar_only=true)
     {
      // 保留上次滚动统计，供非新棒路径刷新实时 Z（避免 ZeroMemory 后 stdev=0）
      const double prev_mean  = m_snap.mean;
      const double prev_stdev = m_snap.stdev;
      const double prev_corr  = m_snap.corr;
      const double prev_hr    = m_snap.hedge_ratio;

      ZeroMemory(m_snap);
      m_snap.side = m_open_side;
      m_snap.reason = "";
      m_snap.mean  = prev_mean;
      m_snap.stdev = prev_stdev;
      m_snap.corr  = prev_corr;
      m_snap.hedge_ratio = prev_hr;

      const int bars_s = Bars(m_p.spot_symbol, m_p.tf);
      const int bars_f = Bars(m_p.fut_symbol, m_p.tf);
      if(bars_s < m_p.min_bars || bars_f < m_p.min_bars)
        {
         m_snap.reason = "K线不足";
         return false;
        }

      datetime bar = iTime(m_p.spot_symbol, m_p.tf, 0);
      const bool is_new = (bar != 0 && bar != m_last_bar);
      if(new_bar_only && !is_new)
        {
         // 仍刷新实时 mid/z（用上次统计）
         double ms, mf, ss, sf;
         if(MidPrice(m_p.spot_symbol, ms, ss) && MidPrice(m_p.fut_symbol, mf, sf))
           {
            m_snap.spot_mid = ms;
            m_snap.fut_mid = mf;
            m_snap.spread = RawSpread(mf, ms);
            if(prev_stdev > 1e-12)
               m_snap.zscore = (m_snap.spread - prev_mean) / prev_stdev;
            m_snap.reason = "ok";
            if(m_p.max_spread_spot > 0 && ss > m_p.max_spread_spot)
               m_snap.reason = "现货点差过大";
            else if(m_p.max_spread_fut > 0 && sf > m_p.max_spread_fut)
               m_snap.reason = "期货点差过大";
           }
         return false;
        }
      if(is_new) m_last_bar = bar;
      if(m_cooldown_until_shift > 0) m_cooldown_until_shift--;

      const int n = m_p.lookback;
      double cs[], cf[];
      ArraySetAsSeries(cs, true);
      ArraySetAsSeries(cf, true);
      if(CopyClose(m_p.spot_symbol, m_p.tf, 1, n, cs) < n ||
         CopyClose(m_p.fut_symbol, m_p.tf, 1, n, cf) < n)
        {
         m_snap.reason = "复制收盘价失败";
         return is_new;
        }

      double sum=0, sum2=0;
      double sum_s=0, sum_f=0, sum_sf=0, sum_s2=0, sum_f2=0;
      for(int i=0;i<n;++i)
        {
         const double sp = RawSpread(cf[i], cs[i]);
         sum += sp;
         sum2 += sp*sp;
         sum_s += cs[i]; sum_f += cf[i];
         sum_sf += cs[i]*cf[i];
         sum_s2 += cs[i]*cs[i];
         sum_f2 += cf[i]*cf[i];
        }
      const double mean = sum / n;
      const double var  = MathMax(0.0, sum2/n - mean*mean);
      const double stdev = MathSqrt(var);

      const double mean_s = sum_s/n, mean_f = sum_f/n;
      const double cov = sum_sf/n - mean_s*mean_f;
      const double vs = MathMax(1e-12, sum_s2/n - mean_s*mean_s);
      const double vf = MathMax(1e-12, sum_f2/n - mean_f*mean_f);
      const double corr = cov / MathSqrt(vs*vf);

      double ms, mf, ss, sf;
      if(!MidPrice(m_p.spot_symbol, ms, ss) || !MidPrice(m_p.fut_symbol, mf, sf))
        {
         m_snap.reason = "Tick失败";
         return is_new;
        }

      m_snap.spot_mid = ms;
      m_snap.fut_mid  = mf;
      m_snap.spread   = RawSpread(mf, ms);
      m_snap.mean     = mean;
      m_snap.stdev    = stdev;
      m_snap.corr     = corr;
      m_snap.hedge_ratio = CalcHedgeRatio();
      m_snap.zscore   = (stdev > 1e-12) ? (m_snap.spread - mean)/stdev : 0.0;
      m_snap.side     = m_open_side;
      m_snap.reason   = "ok";

      // 点差闸门标记
      if(m_p.max_spread_spot > 0 && ss > m_p.max_spread_spot)
         m_snap.reason = "现货点差过大";
      else if(m_p.max_spread_fut > 0 && sf > m_p.max_spread_fut)
         m_snap.reason = "期货点差过大";

      return is_new;
     }

   // 决策：entry / exit / stop / hold
   // out_action: 0=无 1=开空基差 2=开多基差 3=平仓 4=止损平仓
   // floating_profit: 双边合计浮盈（账户货币）；回归平仓需 >= min_profit_money
   int Decide(string &why, const double floating_profit=0.0) const
     {
      why = m_snap.reason;
      if(m_snap.stdev <= 0.0)
        { why="标准差无效"; return 0; }
      if(StringFind(m_snap.reason, "点差")>=0)
         return 0;
      if(m_cooldown_until_shift > 0 && m_open_side==BASIS_FLAT)
        { why="冷却中"; return 0; }

      const double z = m_snap.zscore;

      // 持仓管理
      if(m_open_side != BASIS_FLAT)
        {
         // 时间止损（不受最小盈利限制）
         if(m_p.max_hold_bars > 0)
           {
            const int held = iBarShift(m_p.spot_symbol, m_p.tf, m_entry_bar_time, true);
            if(held >= m_p.max_hold_bars)
              { why=StringFormat("超时平仓 held=%d", held); return 4; }
           }
         // Z 止损：偏离进一步扩大
         if(m_open_side == BASIS_SHORT_SPREAD && z >= m_p.stop_z)
           { why=StringFormat("Z止损 %.2f>=%.2f", z, m_p.stop_z); return 4; }
         if(m_open_side == BASIS_LONG_SPREAD && z <= -m_p.stop_z)
           { why=StringFormat("Z止损 %.2f<=-%.2f", z, m_p.stop_z); return 4; }
         // 均值回归出场：价差收敛且达到最小盈利
         if(MathAbs(z) <= m_p.exit_z)
           {
            if(m_p.min_profit_money > 0.0 && floating_profit < m_p.min_profit_money)
              {
               why = StringFormat("回归待利 |Z|=%.2f 浮盈%.2f<%.2f",
                                  MathAbs(z), floating_profit, m_p.min_profit_money);
               return 0;
              }
            why = StringFormat("回归出场 |Z|=%.2f<=%.2f 盈=%.2f",
                               MathAbs(z), m_p.exit_z, floating_profit);
            return 3;
           }
         why = StringFormat("持仓中 Z=%.2f 盈=%.2f", z, floating_profit);
         return 0;
        }

      // 开仓过滤
      if(m_snap.corr < m_p.min_corr)
        { why=StringFormat("相关不足 %.2f<%.2f", m_snap.corr, m_p.min_corr); return 0; }

      if(z >= m_p.entry_z)
        {
         why = StringFormat("基差过高 Z=%.2f 做空基差(空期+多现)", z);
         return 1; // SHORT_SPREAD
        }
      if(z <= -m_p.entry_z)
        {
         why = StringFormat("基差过低 Z=%.2f 做多基差(多期+空现)", z);
         return 2; // LONG_SPREAD
        }
      why = StringFormat("观望 Z=%.2f corr=%.2f", z, m_snap.corr);
      return 0;
     }

   void LotsForSide(const ENUM_BASIS_SIDE side, double &lot_spot, double &lot_fut) const
     {
      lot_spot = NormalizeLot(m_p.spot_symbol, m_p.lot_spot);
      double hr = m_p.auto_hedge ? m_snap.hedge_ratio : 1.0;
      if(hr <= 0.0) hr = 1.0;
      lot_fut = NormalizeLot(m_p.fut_symbol, lot_spot * hr);
      // side 只决定方向，手数对称
      if(side == BASIS_FLAT)
        { lot_spot=0; lot_fut=0; }
     }

   string SpotSymbol(void) const { return m_p.spot_symbol; }
   string FutSymbol(void) const { return m_p.fut_symbol; }
   SBasisParams Params(void) const { return m_p; }
  };

#endif
//+------------------------------------------------------------------+
