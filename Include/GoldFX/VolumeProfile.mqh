//+------------------------------------------------------------------+
//| VolumeProfile.mqh — 会话 VWAP / POC / Value Area                   |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_VOLUME_PROFILE_MQH
#define GOLDFX_VOLUME_PROFILE_MQH

#include "Common.mqh"

#define VP_MAX_BUCKETS 4000
#define VP_IDX_MIN    (-2000000000)
#define VP_IDX_MAX    (2000000000)

class CVolumeProfile
  {
private:
   string            m_symbol;
   int               m_bucket_points;  // 桶宽（点）
   double            m_va_pct;
   double            m_point;
   int               m_day_stamp;
   double            m_sum_pv;
   double            m_sum_v;
   double            m_buckets[VP_MAX_BUCKETS];
   int               m_base_idx;       // 桶 0 对应的价格索引
   int               m_min_idx;
   int               m_max_idx;
   double            m_vwap;
   double            m_poc;
   double            m_vah;
   double            m_val;
   bool              m_valid;

   int TodayStamp(void) const
     {
      MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
      return dt.year*10000 + dt.mon*100 + dt.day;
     }

   int PriceToIdx(const double price) const
     {
      if(m_point <= 0.0) return 0;
      const double step = m_point * MathMax(1, m_bucket_points);
      return (int)MathFloor(price / step + 0.5);
     }

   double IdxToPrice(const int idx) const
     {
      const double step = m_point * MathMax(1, m_bucket_points);
      return idx * step;
     }

   void ClearBuckets(void)
     {
      ArrayInitialize(m_buckets, 0.0);
      m_sum_pv = 0; m_sum_v = 0;
      m_base_idx = 0; m_min_idx = VP_IDX_MAX; m_max_idx = VP_IDX_MIN;
      m_vwap = 0; m_poc = 0; m_vah = 0; m_val = 0;
      m_valid = false;
     }

   void Recompute(void)
     {
      if(m_sum_v <= 0.0 || m_min_idx > m_max_idx)
        {
         m_valid = false;
         return;
        }
      m_vwap = m_sum_pv / m_sum_v;

      int poc_i = m_min_idx;
      double poc_v = -1.0;
      for(int i=m_min_idx; i<=m_max_idx; ++i)
        {
         const int bi = i - m_base_idx;
         if(bi < 0 || bi >= VP_MAX_BUCKETS) continue;
         if(m_buckets[bi] > poc_v)
           {
            poc_v = m_buckets[bi];
            poc_i = i;
           }
        }
      m_poc = IdxToPrice(poc_i);

      // Value Area：从 POC 向两侧扩展至 va_pct
      const double target = m_sum_v * m_va_pct;
      double acc = 0.0;
      int lo = poc_i, hi = poc_i;
      const int bi0 = poc_i - m_base_idx;
      if(bi0 >= 0 && bi0 < VP_MAX_BUCKETS) acc = m_buckets[bi0];

      while(acc < target && (lo > m_min_idx || hi < m_max_idx))
        {
         double v_lo = 0, v_hi = 0;
         if(lo > m_min_idx)
           {
            const int b = (lo-1) - m_base_idx;
            if(b>=0 && b<VP_MAX_BUCKETS) v_lo = m_buckets[b];
           }
         if(hi < m_max_idx)
           {
            const int b = (hi+1) - m_base_idx;
            if(b>=0 && b<VP_MAX_BUCKETS) v_hi = m_buckets[b];
           }
         if(v_hi >= v_lo && hi < m_max_idx)
           {
            hi++;
            acc += v_hi;
           }
         else if(lo > m_min_idx)
           {
            lo--;
            acc += v_lo;
           }
         else if(hi < m_max_idx)
           {
            hi++;
            acc += v_hi;
           }
         else break;
        }
      m_val = IdxToPrice(lo);
      m_vah = IdxToPrice(hi);
      m_valid = true;
     }

public:
                     CVolumeProfile(void)
                       : m_symbol(""), m_bucket_points(10), m_va_pct(0.70),
                         m_point(0), m_day_stamp(0), m_sum_pv(0), m_sum_v(0),
                         m_base_idx(0), m_min_idx(VP_IDX_MAX), m_max_idx(VP_IDX_MIN),
                         m_vwap(0), m_poc(0), m_vah(0), m_val(0), m_valid(false)
                     {
                     }

   bool Init(const string symbol, const int bucket_points, const double va_pct)
     {
      m_symbol = symbol;
      m_bucket_points = MathMax(1, bucket_points);
      m_va_pct = MathMax(0.50, MathMin(0.90, va_pct));
      m_point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(m_point <= 0.0) m_point = _Point;
      m_day_stamp = 0;
      ClearBuckets();
      return true;
     }

   void Configure(const int bucket_points, const double va_pct)
     {
      m_bucket_points = MathMax(1, bucket_points);
      m_va_pct = MathMax(0.50, MathMin(0.90, va_pct));
     }

   // 换日重置会话
   bool EnsureSession(void)
     {
      const int d = TodayStamp();
      if(d != m_day_stamp)
        {
         m_day_stamp = d;
         ClearBuckets();
         return true; // 发生了重置
        }
      return false;
     }

   void AddTrade(const double price, const double volume)
     {
      if(price <= 0.0 || volume <= 0.0) return;
      EnsureSession();

      const int idx = PriceToIdx(price);
      if(m_sum_v <= 0.0)
        {
         // 以首笔为中心锚定桶数组
         m_base_idx = idx - VP_MAX_BUCKETS / 2;
        }
      int bi = idx - m_base_idx;
      if(bi < 0 || bi >= VP_MAX_BUCKETS)
        {
         // 越界：简单忽略极端尖刺，避免整表重映射开销
         return;
        }
      m_buckets[bi] += volume;
      m_sum_pv += price * volume;
      m_sum_v  += volume;
      if(idx < m_min_idx) m_min_idx = idx;
      if(idx > m_max_idx) m_max_idx = idx;
     }

   void Rebuild(void) { Recompute(); }

   bool Valid(void) const { return m_valid && m_sum_v > 0.0; }
   double Vwap(void) const { return m_vwap; }
   double Poc(void) const { return m_poc; }
   double Vah(void) const { return m_vah; }
   double Val(void) const { return m_val; }
   double TotalVolume(void) const { return m_sum_v; }

   // 价格相对 VWAP / 回踩 POC 后收回
   bool PositionLong(const double close, const double atr_v) const
     {
      if(!Valid()) return false;
      if(close > m_vwap) return true;
      // 回踩 POC/VAL 区域后收回：收盘回到 POC 上方且距 VAL 不太远
      const double zone = MathMax(atr_v * 0.25, m_point * m_bucket_points);
      if(close >= m_poc - zone && close <= m_poc + zone * 2.0 && close > m_val)
         return true;
      return false;
     }

   bool PositionShort(const double close, const double atr_v) const
     {
      if(!Valid()) return false;
      if(close < m_vwap) return true;
      const double zone = MathMax(atr_v * 0.25, m_point * m_bucket_points);
      if(close <= m_poc + zone && close >= m_poc - zone * 2.0 && close < m_vah)
         return true;
      return false;
     }
  };

#endif
//+------------------------------------------------------------------+
