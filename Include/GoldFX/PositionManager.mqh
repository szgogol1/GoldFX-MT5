//+------------------------------------------------------------------+
//| PositionManager.mqh — 独立仓位管理：保本 / 追踪 / 动能衰减 / 时限   |
//| 无网格加仓、无马丁加倍；每笔从开仓起受止损保护                       |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_POSITION_MANAGER_MQH
#define GOLDFX_POSITION_MANAGER_MQH

#include "Common.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CPositionManager
  {
private:
   string            m_symbol;
   int               m_magic;
   int               m_slippage;
   int               m_atr_period;
   int               m_adx_period;
   int               m_atr_h;
   int               m_adx_h;
   ENUM_TIMEFRAMES   m_tf;
   bool              m_use_be;
   double            m_be_trigger;
   double            m_be_lock;
   bool              m_use_trail;
   double            m_trail_start;
   double            m_trail_step;
   bool              m_use_mom_exit;
   int               m_max_hold_min;
   bool              m_use_partial;
   double            m_partial_atr;
   double            m_partial_pct;
   CTrade            m_trade;

   // 简易状态：用 comment 标记部分平仓较脆，改用静态 map 不可靠 → 用全局数组按 ticket
   ulong             m_partial_done[];
   ulong             m_be_done[];

   bool CopyBuf(const int handle, const int buf, const int count, double &out[])
     {
      ArraySetAsSeries(out, true);
      return (CopyBuffer(handle, buf, 0, count, out) >= count);
     }

   bool IsMarked(ulong &arr[], const ulong ticket) const
     {
      const int n = ArraySize(arr);
      for(int i = 0; i < n; ++i)
         if(arr[i] == ticket)
            return true;
      return false;
     }

   void Mark(ulong &arr[], const ulong ticket)
     {
      if(IsMarked(arr, ticket))
         return;
      const int n = ArraySize(arr);
      ArrayResize(arr, n + 1);
      arr[n] = ticket;
     }

   void PruneMarks(void)
     {
      // 去掉已不存在的 ticket
      ulong keep[];
      ArrayResize(keep, 0);
      CPositionInfo pos;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol() != m_symbol || pos.Magic() != m_magic)
            continue;
         const ulong t = pos.Ticket();
         if(IsMarked(m_partial_done, t))
           {
            const int n = ArraySize(keep);
            ArrayResize(keep, n + 1);
            keep[n] = t;
           }
        }
      ArrayCopy(m_partial_done, keep);

      ArrayResize(keep, 0);
      for(int i = PositionsTotal() - 1; i >= 0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol() != m_symbol || pos.Magic() != m_magic)
            continue;
         const ulong t = pos.Ticket();
         if(IsMarked(m_be_done, t))
           {
            const int n = ArraySize(keep);
            ArrayResize(keep, n + 1);
            keep[n] = t;
           }
        }
      ArrayCopy(m_be_done, keep);
     }

   double ProfitInPrice(const CPositionInfo &pos) const
     {
      const double open = pos.PriceOpen();
      const double cur  = pos.PriceCurrent();
      if(pos.PositionType() == POSITION_TYPE_BUY)
         return (cur - open);
      return (open - cur);
     }

   bool ModifySL(const ulong ticket, const double new_sl, const double tp)
     {
      if(!m_trade.PositionModify(ticket, NormalizePrice(new_sl), tp))
        {
         PrintFormat("PositionModify 失败 ticket=%I64u %s", ticket, m_trade.ResultComment());
         return false;
        }
      return true;
     }

public:
                     CPositionManager(void)
                       : m_symbol(_Symbol),
                         m_magic(20260826),
                         m_slippage(30),
                         m_atr_period(14),
                         m_adx_period(14),
                         m_atr_h(INVALID_HANDLE),
                         m_adx_h(INVALID_HANDLE),
                         m_tf(PERIOD_CURRENT),
                         m_use_be(true),
                         m_be_trigger(1.0),
                         m_be_lock(0.1),
                         m_use_trail(true),
                         m_trail_start(1.5),
                         m_trail_step(0.8),
                         m_use_mom_exit(true),
                         m_max_hold_min(240),
                         m_use_partial(true),
                         m_partial_atr(1.2),
                         m_partial_pct(50.0)
                     {
                      ArrayResize(m_partial_done, 0);
                      ArrayResize(m_be_done, 0);
                     }

                    ~CPositionManager(void) { Release(); }

   bool Init(const string symbol, const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_tf     = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      Release();
      m_magic        = p.magic;
      m_slippage     = MathMax(1, p.slippage);
      m_atr_period   = MathMax(2, p.atr_period);
      m_adx_period   = MathMax(2, p.adx_period);
      m_use_be       = p.use_breakeven;
      m_be_trigger   = MathMax(0.1, p.be_trigger_atr);
      m_be_lock      = MathMax(0.0, p.be_lock_atr);
      m_use_trail    = p.use_trailing;
      m_trail_start  = MathMax(0.1, p.trail_start_atr);
      m_trail_step   = MathMax(0.1, p.trail_step_atr);
      m_use_mom_exit = p.use_momentum_exit;
      m_max_hold_min = MathMax(0, p.max_hold_minutes);
      m_use_partial  = p.use_partial_close;
      m_partial_atr  = MathMax(0.1, p.partial_at_atr);
      m_partial_pct  = MathMax(10.0, MathMin(90.0, p.partial_percent));

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      m_atr_h = iATR(m_symbol, m_tf, m_atr_period);
      m_adx_h = iADX(m_symbol, m_tf, m_adx_period);
      if(m_atr_h == INVALID_HANDLE || m_adx_h == INVALID_HANDLE)
        {
         Print("CPositionManager: 指标失败");
         return false;
        }
      return true;
     }

   void Release(void)
     {
      if(m_atr_h != INVALID_HANDLE) { IndicatorRelease(m_atr_h); m_atr_h = INVALID_HANDLE; }
      if(m_adx_h != INVALID_HANDLE) { IndicatorRelease(m_adx_h); m_adx_h = INVALID_HANDLE; }
     }

   // 每个 Tick / 定时调用：独立评估每笔仓位
   int ManageAll(void)
     {
      double atr[], adx[];
      if(!CopyBuf(m_atr_h, 0, 3, atr) || !CopyBuf(m_adx_h, 0, 3, adx))
         return 0;
      const double atr_v = atr[1];
      if(atr_v <= 0.0)
         return 0;

      PruneMarks();
      CPositionInfo pos;
      int actions = 0;

      for(int i = PositionsTotal() - 1; i >= 0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol() != m_symbol || pos.Magic() != m_magic)
            continue;

         const ulong ticket = pos.Ticket();
         const double open  = pos.PriceOpen();
         const double sl    = pos.StopLoss();
         const double tp    = pos.TakeProfit();
         const double profit_price = ProfitInPrice(pos);
         const bool   is_buy = (pos.PositionType() == POSITION_TYPE_BUY);

         // 1) 最长持仓 — 短线避免无谓暴露
         if(m_max_hold_min > 0)
           {
            const int held_min = (int)((TimeCurrent() - pos.Time()) / 60);
            if(held_min >= m_max_hold_min)
              {
               if(m_trade.PositionClose(ticket))
                 {
                  PrintFormat("持仓超时平仓 ticket=%I64u held=%dmin", ticket, held_min);
                  actions++;
                 }
               continue;
              }
           }

         // 2) 动能减弱提前离场：已有浮盈但 ADX 回落且价格回吐
         if(m_use_mom_exit && profit_price > atr_v * 0.3)
           {
            if(adx[1] < adx[2] && adx[1] < 22.0 && profit_price < atr_v * 0.6)
              {
               if(m_trade.PositionClose(ticket))
                 {
                  PrintFormat("动能衰减离场 ticket=%I64u ADX=%.1f", ticket, adx[1]);
                  actions++;
                 }
               continue;
              }
           }

         // 3) 部分止盈（利润保护）
         if(m_use_partial && !IsMarked(m_partial_done, ticket) &&
            profit_price >= atr_v * m_partial_atr)
           {
            const double vol = pos.Volume();
            double close_vol = NormalizeDouble(vol * (m_partial_pct / 100.0), 2);
            const double vmin = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
            const double vstep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
            if(vstep > 0.0)
               close_vol = MathFloor(close_vol / vstep) * vstep;
            if(close_vol >= vmin && (vol - close_vol) >= vmin - 1e-8)
              {
               if(m_trade.PositionClosePartial(ticket, close_vol))
                 {
                  Mark(m_partial_done, ticket);
                  PrintFormat("部分止盈 %.2f 手 ticket=%I64u", close_vol, ticket);
                  actions++;
                 }
              }
           }

         // 4) 保本
         if(m_use_be && !IsMarked(m_be_done, ticket) &&
            profit_price >= atr_v * m_be_trigger)
           {
            double new_sl = is_buy
                            ? open + atr_v * m_be_lock
                            : open - atr_v * m_be_lock;
            new_sl = NormalizePrice(new_sl);
            const bool improve = is_buy ? (new_sl > sl || sl == 0.0)
                                        : (new_sl < sl || sl == 0.0);
            if(improve && ModifySL(ticket, new_sl, tp))
              {
               Mark(m_be_done, ticket);
               PrintFormat("保本止损 ticket=%I64u SL=%.5f", ticket, new_sl);
               actions++;
              }
           }

         // 5) 动态追踪止损
         if(m_use_trail && profit_price >= atr_v * m_trail_start)
           {
            double new_sl = is_buy
                            ? pos.PriceCurrent() - atr_v * m_trail_step
                            : pos.PriceCurrent() + atr_v * m_trail_step;
            new_sl = NormalizePrice(new_sl);
            const double min_gap = atr_v * 0.15;
            bool improve = false;
            if(is_buy)
               improve = (new_sl > sl + min_gap) || (sl == 0.0 && new_sl > open);
            else
               improve = (new_sl < sl - min_gap) || (sl == 0.0 && new_sl < open);
            if(improve && ModifySL(ticket, new_sl, tp))
              {
               actions++;
              }
           }

         // 6) 安全网：若经纪商端丢失 SL，立即补回（开仓即保护）
         if(sl == 0.0)
           {
            double emergency = is_buy
                               ? open - atr_v * 1.5
                               : open + atr_v * 1.5;
            if(ModifySL(ticket, emergency, tp))
              {
               PrintFormat("紧急补止损 ticket=%I64u", ticket);
               actions++;
              }
           }
        }
      return actions;
     }
  };

#endif
//+------------------------------------------------------------------+
