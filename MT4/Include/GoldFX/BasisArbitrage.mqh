//+------------------------------------------------------------------+
//| BasisArbitrage.mqh — MT4 黄金期货/现货基差均值回归引擎              |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_BASIS_ARBITRAGE_MT4_MQH
#define GOLDFX_BASIS_ARBITRAGE_MT4_MQH

enum ENUM_BASIS_SIDE
  {
   BASIS_FLAT         = 0,
   BASIS_SHORT_SPREAD = 1,  // 空期货 + 多现货
   BASIS_LONG_SPREAD  = 2   // 多期货 + 空现货
  };

enum ENUM_BASIS_SPREAD_MODE
  {
   BASIS_DIFF     = 0,
   BASIS_RATIO    = 1,
   BASIS_LOGRATIO = 2
  };

struct SBasisSnapshot
  {
   double spot_mid;
   double fut_mid;
   double spread;
   double mean;
   double stdev;
   double zscore;
   double corr;
   double hedge_ratio;
   ENUM_BASIS_SIDE side;
   string reason;
  };

struct SBasisParams
  {
   string spot_symbol;
   string fut_symbol;
   int    tf;                // PERIOD_M15 等
   int    spread_mode;       // ENUM_BASIS_SPREAD_MODE
   int    lookback;
   double entry_z;
   double exit_z;
   double stop_z;
   double min_corr;
   int    min_bars;
   int    max_hold_bars;
   double lot_spot;
   bool   auto_hedge;
   double max_spread_spot;
   double max_spread_fut;
   bool   trade_both_legs;
   int    magic;
   int    slippage;
   int    cooldown_bars;
   double min_profit_money;
  };

class CBasisArbitrage
  {
private:
   SBasisParams      m_p;
   SBasisSnapshot    m_snap;
   datetime          m_last_bar;
   datetime          m_entry_bar_time;
   ENUM_BASIS_SIDE   m_open_side;
   int               m_cooldown_until_shift;

   void ClearSnap(void)
     {
      m_snap.spot_mid=0; m_snap.fut_mid=0; m_snap.spread=0;
      m_snap.mean=0; m_snap.stdev=0; m_snap.zscore=0;
      m_snap.corr=0; m_snap.hedge_ratio=0;
      m_snap.side=BASIS_FLAT; m_snap.reason="";
     }

   bool MidPrice(const string sym, double &mid, double &spread) const
     {
      RefreshRates();
      const double bid = MarketInfo(sym, MODE_BID);
      const double ask = MarketInfo(sym, MODE_ASK);
      if(bid<=0.0 || ask<=0.0) return false;
      mid = 0.5*(bid+ask);
      spread = ask-bid;
      return true;
     }

   double RawSpread(const double fut, const double spot) const
     {
      if(spot<=0.0) return 0.0;
      if(m_p.spread_mode==BASIS_RATIO) return fut/spot-1.0;
      if(m_p.spread_mode==BASIS_LOGRATIO) return MathLog(fut/spot);
      return fut-spot;
     }

   double CalcHedgeRatio(void) const
     {
      const double cs_s = MarketInfo(m_p.spot_symbol, MODE_LOTSIZE);
      const double cs_f = MarketInfo(m_p.fut_symbol, MODE_LOTSIZE);
      double mid_s, mid_f, sp;
      if(!MidPrice(m_p.spot_symbol, mid_s, sp) || !MidPrice(m_p.fut_symbol, mid_f, sp))
         return 1.0;
      const double tv_s = (cs_s>0 ? cs_s : 100.0)*mid_s;
      const double tv_f = (cs_f>0 ? cs_f : 100.0)*mid_f;
      if(tv_f<=0.0) return 1.0;
      return tv_s/tv_f;
     }

   double NormalizeLot(const string sym, double lot) const
     {
      double amin = MarketInfo(sym, MODE_MINLOT);
      double amax = MarketInfo(sym, MODE_MAXLOT);
      double step = MarketInfo(sym, MODE_LOTSTEP);
      if(step<=0.0) step=0.01;
      lot = MathFloor(lot/step+1e-12)*step;
      if(lot<amin) lot=amin;
      if(lot>amax) lot=amax;
      return lot;
     }

public:
                     CBasisArbitrage(void)
                       : m_last_bar(0), m_entry_bar_time(0),
                         m_open_side(BASIS_FLAT), m_cooldown_until_shift(-1)
                     {
                      m_p.spot_symbol=""; m_p.fut_symbol="";
                      m_p.tf=PERIOD_M15; m_p.spread_mode=BASIS_DIFF;
                      m_p.lookback=60; m_p.entry_z=2.0; m_p.exit_z=0.5;
                      m_p.stop_z=3.5; m_p.min_corr=0.85; m_p.min_bars=120;
                      m_p.max_hold_bars=48; m_p.lot_spot=0.10;
                      m_p.auto_hedge=true; m_p.max_spread_spot=0;
                      m_p.max_spread_fut=0; m_p.trade_both_legs=true;
                      m_p.magic=0; m_p.slippage=30; m_p.cooldown_bars=4;
                      m_p.min_profit_money=5.0;
                      ClearSnap();
                     }

   SBasisSnapshot Snapshot(void) const { return m_snap; }
   ENUM_BASIS_SIDE OpenSide(void) const { return m_open_side; }

   bool Init(SBasisParams &p)
     {
      m_p = p;
      if(StringLen(m_p.spot_symbol)==0) m_p.spot_symbol = Symbol();
      if(StringLen(m_p.fut_symbol)==0)
        {
         Print("CBasisArbitrage: 必须指定期货品种");
         return false;
        }
      if(!SymbolSelect(m_p.spot_symbol, true) || !SymbolSelect(m_p.fut_symbol, true))
        {
         Print("CBasisArbitrage: 无法选择品种 spot=", m_p.spot_symbol,
               " fut=", m_p.fut_symbol);
         return false;
        }
      if(m_p.lookback<20) m_p.lookback=20;
      if(m_p.entry_z<0.5) m_p.entry_z=0.5;
      if(m_p.exit_z<0.0) m_p.exit_z=0.0;
      if(m_p.exit_z>m_p.entry_z-0.1) m_p.exit_z=m_p.entry_z-0.1;
      if(m_p.stop_z<m_p.entry_z+0.5) m_p.stop_z=m_p.entry_z+0.5;
      m_open_side = BASIS_FLAT;
      m_last_bar  = 0;
      return true;
     }

   void SetOpenSide(const ENUM_BASIS_SIDE side)
     {
      m_open_side = side;
      if(side != BASIS_FLAT)
         m_entry_bar_time = iTime(m_p.spot_symbol, m_p.tf, 0);
     }

   void NotifyClosed(void)
     {
      m_open_side = BASIS_FLAT;
      m_cooldown_until_shift = m_p.cooldown_bars;
     }

   bool Update(const bool new_bar_only)
     {
      const double prev_mean  = m_snap.mean;
      const double prev_stdev = m_snap.stdev;
      const double prev_corr  = m_snap.corr;
      const double prev_hr    = m_snap.hedge_ratio;

      ClearSnap();
      m_snap.side = m_open_side;
      m_snap.mean  = prev_mean;
      m_snap.stdev = prev_stdev;
      m_snap.corr  = prev_corr;
      m_snap.hedge_ratio = prev_hr;

      const int bars_s = iBars(m_p.spot_symbol, m_p.tf);
      const int bars_f = iBars(m_p.fut_symbol, m_p.tf);
      if(bars_s < m_p.min_bars || bars_f < m_p.min_bars)
        {
         m_snap.reason = "K线不足";
         return false;
        }

      datetime bar = iTime(m_p.spot_symbol, m_p.tf, 0);
      const bool is_new = (bar!=0 && bar!=m_last_bar);
      if(new_bar_only && !is_new)
        {
         double ms, mf, ss, sf;
         if(MidPrice(m_p.spot_symbol, ms, ss) && MidPrice(m_p.fut_symbol, mf, sf))
           {
            m_snap.spot_mid = ms;
            m_snap.fut_mid  = mf;
            m_snap.spread   = RawSpread(mf, ms);
            if(prev_stdev > 1e-12)
               m_snap.zscore = (m_snap.spread-prev_mean)/prev_stdev;
            m_snap.reason = "ok";
            if(m_p.max_spread_spot>0 && ss>m_p.max_spread_spot)
               m_snap.reason = "现货点差过大";
            else if(m_p.max_spread_fut>0 && sf>m_p.max_spread_fut)
               m_snap.reason = "期货点差过大";
           }
         return false;
        }
      if(is_new) m_last_bar = bar;
      if(m_cooldown_until_shift>0) m_cooldown_until_shift--;

      const int n = m_p.lookback;
      double sum=0, sum2=0;
      double sum_s=0, sum_f=0, sum_sf=0, sum_s2=0, sum_f2=0;
      for(int i=1; i<=n; i++)
        {
         const double cs = iClose(m_p.spot_symbol, m_p.tf, i);
         const double cf = iClose(m_p.fut_symbol, m_p.tf, i);
         if(cs<=0 || cf<=0)
           {
            m_snap.reason = "复制收盘价失败";
            return is_new;
           }
         const double sp = RawSpread(cf, cs);
         sum += sp; sum2 += sp*sp;
         sum_s += cs; sum_f += cf;
         sum_sf += cs*cf;
         sum_s2 += cs*cs; sum_f2 += cf*cf;
        }

      const double mean = sum/n;
      const double var  = MathMax(0.0, sum2/n - mean*mean);
      const double stdev = MathSqrt(var);
      const double mean_s = sum_s/n, mean_f = sum_f/n;
      const double cov = sum_sf/n - mean_s*mean_f;
      const double vs = MathMax(1e-12, sum_s2/n - mean_s*mean_s);
      const double vf = MathMax(1e-12, sum_f2/n - mean_f*mean_f);
      const double corr = cov/MathSqrt(vs*vf);

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
      m_snap.zscore   = (stdev>1e-12) ? (m_snap.spread-mean)/stdev : 0.0;
      m_snap.side     = m_open_side;
      m_snap.reason   = "ok";
      if(m_p.max_spread_spot>0 && ss>m_p.max_spread_spot)
         m_snap.reason = "现货点差过大";
      else if(m_p.max_spread_fut>0 && sf>m_p.max_spread_fut)
         m_snap.reason = "期货点差过大";
      return is_new;
     }

   // 0=无 1=开空基差 2=开多基差 3=平仓 4=止损/超时
   int Decide(string &why, const double floating_profit) const
     {
      why = m_snap.reason;
      if(m_snap.stdev<=0.0){ why="标准差无效"; return 0; }
      if(StringFind(m_snap.reason, "点差")>=0) return 0;
      if(m_cooldown_until_shift>0 && m_open_side==BASIS_FLAT)
        { why="冷却中"; return 0; }

      const double z = m_snap.zscore;
      if(m_open_side != BASIS_FLAT)
        {
         if(m_p.max_hold_bars>0)
           {
            const int held = iBarShift(m_p.spot_symbol, m_p.tf, m_entry_bar_time);
            if(held>=m_p.max_hold_bars)
              { why=StringFormat("超时平仓 held=%d", held); return 4; }
           }
         if(m_open_side==BASIS_SHORT_SPREAD && z>=m_p.stop_z)
           { why=StringFormat("Z止损 %.2f>=%.2f", z, m_p.stop_z); return 4; }
         if(m_open_side==BASIS_LONG_SPREAD && z<=-m_p.stop_z)
           { why=StringFormat("Z止损 %.2f<=-%.2f", z, m_p.stop_z); return 4; }
         if(MathAbs(z)<=m_p.exit_z)
           {
            if(m_p.min_profit_money>0.0 && floating_profit<m_p.min_profit_money)
              {
               why=StringFormat("回归待利 |Z|=%.2f 浮盈%.2f<%.2f",
                                MathAbs(z), floating_profit, m_p.min_profit_money);
               return 0;
              }
            why=StringFormat("回归出场 |Z|=%.2f<=%.2f 盈=%.2f",
                             MathAbs(z), m_p.exit_z, floating_profit);
            return 3;
           }
         why=StringFormat("持仓中 Z=%.2f 盈=%.2f", z, floating_profit);
         return 0;
        }

      if(m_snap.corr < m_p.min_corr)
        { why=StringFormat("相关不足 %.2f<%.2f", m_snap.corr, m_p.min_corr); return 0; }
      if(z >= m_p.entry_z)
        { why=StringFormat("基差过高 Z=%.2f 做空基差(空期+多现)", z); return 1; }
      if(z <= -m_p.entry_z)
        { why=StringFormat("基差过低 Z=%.2f 做多基差(多期+空现)", z); return 2; }
      why=StringFormat("观望 Z=%.2f corr=%.2f", z, m_snap.corr);
      return 0;
     }

   void LotsForSide(const ENUM_BASIS_SIDE side, double &lot_spot, double &lot_fut) const
     {
      lot_spot = NormalizeLot(m_p.spot_symbol, m_p.lot_spot);
      double hr = m_p.auto_hedge ? m_snap.hedge_ratio : 1.0;
      if(hr<=0.0) hr=1.0;
      lot_fut = NormalizeLot(m_p.fut_symbol, lot_spot*hr);
      if(side==BASIS_FLAT){ lot_spot=0; lot_fut=0; }
     }

   string SpotSymbol(void) const { return m_p.spot_symbol; }
   string FutSymbol(void) const { return m_p.fut_symbol; }
  };

#endif
//+------------------------------------------------------------------+
