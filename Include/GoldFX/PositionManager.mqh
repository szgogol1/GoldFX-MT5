//+------------------------------------------------------------------+
//| PositionManager.mqh — 组合内独立仓位：保本/追踪/部分平/动能/超时   |
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
   int               m_magic;
   int               m_slippage;
   int               m_atr_period;
   int               m_adx_period;
   ENUM_TIMEFRAMES   m_tf;
   bool              m_use_be;
   double            m_be_trigger, m_be_lock;
   bool              m_use_trail;
   double            m_trail_start, m_trail_step;
   bool              m_use_mom_exit;
   int               m_max_hold_min;
   bool              m_use_partial;
   double            m_partial_atr, m_partial_pct;
   CTrade            m_trade;
   ulong             m_partial_done[];
   ulong             m_be_done[];

   bool IsMarked(ulong &arr[], const ulong ticket) const
     {
      for(int i=0;i<ArraySize(arr);++i) if(arr[i]==ticket) return true;
      return false;
     }
   void Mark(ulong &arr[], const ulong ticket)
     {
      if(IsMarked(arr, ticket)) return;
      int n=ArraySize(arr); ArrayResize(arr,n+1); arr[n]=ticket;
     }

   bool ReadATR_ADX(const string symbol, double &atr_v, double &adx_now, double &adx_prev)
     {
      atr_v=0; adx_now=0; adx_prev=0;
      int ah = iATR(symbol, m_tf, m_atr_period);
      int dh = iADX(symbol, m_tf, m_adx_period);
      if(ah==INVALID_HANDLE || dh==INVALID_HANDLE)
        {
         if(ah!=INVALID_HANDLE) IndicatorRelease(ah);
         if(dh!=INVALID_HANDLE) IndicatorRelease(dh);
         return false;
        }
      double atr[], adx[];
      ArraySetAsSeries(atr,true); ArraySetAsSeries(adx,true);
      bool ok = (CopyBuffer(ah,0,0,3,atr)>=3 && CopyBuffer(dh,0,0,3,adx)>=3);
      IndicatorRelease(ah); IndicatorRelease(dh);
      if(!ok) return false;
      atr_v = atr[1]; adx_now = adx[1]; adx_prev = adx[2];
      return (atr_v > 0.0);
     }

   double ProfitPrice(const CPositionInfo &pos) const
     {
      if(pos.PositionType()==POSITION_TYPE_BUY) return pos.PriceCurrent()-pos.PriceOpen();
      return pos.PriceOpen()-pos.PriceCurrent();
     }

   bool ModifySL(const ulong ticket, const double new_sl, const double tp)
     {
      return m_trade.PositionModify(ticket, new_sl, tp);
     }

public:
                     CPositionManager(void)
                       : m_magic(20260826), m_slippage(30), m_atr_period(14), m_adx_period(14),
                         m_tf(PERIOD_CURRENT), m_use_be(true), m_be_trigger(1.0), m_be_lock(0.1),
                         m_use_trail(true), m_trail_start(1.5), m_trail_step(0.8),
                         m_use_mom_exit(true), m_max_hold_min(240),
                         m_use_partial(true), m_partial_atr(1.2), m_partial_pct(50.0)
                     {
                      ArrayResize(m_partial_done,0); ArrayResize(m_be_done,0);
                     }

   bool Init(const ENUM_TIMEFRAMES tf, const SRuntimeParams &p)
     {
      m_tf = tf;
      return Configure(p);
     }

   bool Configure(const SRuntimeParams &p)
     {
      m_magic = p.magic;
      m_slippage = MathMax(1, p.slippage);
      m_atr_period = MathMax(2, p.atr_period);
      m_adx_period = MathMax(2, p.adx_period);
      m_use_be = p.use_breakeven;
      m_be_trigger = MathMax(0.1, p.be_trigger_atr);
      m_be_lock = MathMax(0.0, p.be_lock_atr);
      m_use_trail = p.use_trailing;
      m_trail_start = MathMax(0.1, p.trail_start_atr);
      m_trail_step = MathMax(0.1, p.trail_step_atr);
      m_use_mom_exit = p.use_momentum_exit;
      m_max_hold_min = MathMax(0, p.max_hold_minutes);
      m_use_partial = p.use_partial_close;
      m_partial_atr = MathMax(0.1, p.partial_at_atr);
      m_partial_pct = MathMax(10.0, MathMin(90.0, p.partial_percent));
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
      return true;
     }

   void Release(void) {}

   int ManageAll(void)
     {
      CPositionInfo pos;
      int actions = 0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()!=m_magic) continue;

         const string symbol = pos.Symbol();
         const ulong ticket = pos.Ticket();
         double atr_v, adx1, adx2;
         if(!ReadATR_ADX(symbol, atr_v, adx1, adx2))
            continue;

         m_trade.SetTypeFillingBySymbol(symbol);
         const double open = pos.PriceOpen();
         const double sl = pos.StopLoss();
         const double tp = pos.TakeProfit();
         const double profit_price = ProfitPrice(pos);
         const bool is_buy = (pos.PositionType()==POSITION_TYPE_BUY);

         if(m_max_hold_min > 0)
           {
            const int held = (int)((TimeCurrent()-pos.Time())/60);
            if(held >= m_max_hold_min)
              {
               if(m_trade.PositionClose(ticket)) { actions++; PrintFormat("超时平仓 %s #%I64u", symbol, ticket); }
               continue;
              }
           }

         if(m_use_mom_exit && profit_price > atr_v*0.3 && adx1 < adx2 && adx1 < 22.0 && profit_price < atr_v*0.6)
           {
            if(m_trade.PositionClose(ticket)) { actions++; PrintFormat("动能离场 %s #%I64u", symbol, ticket); }
            continue;
           }

         if(m_use_partial && !IsMarked(m_partial_done, ticket) && profit_price >= atr_v*m_partial_atr)
           {
            double vol = pos.Volume();
            double close_vol = NormalizeDouble(vol*(m_partial_pct/100.0), 2);
            double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(vstep>0) close_vol = MathFloor(close_vol/vstep)*vstep;
            if(close_vol>=vmin && (vol-close_vol)>=vmin-1e-8)
              {
               if(m_trade.PositionClosePartial(ticket, close_vol))
                 { Mark(m_partial_done, ticket); actions++; }
              }
           }

         if(m_use_be && !IsMarked(m_be_done, ticket) && profit_price >= atr_v*m_be_trigger)
           {
            double new_sl = is_buy ? open + atr_v*m_be_lock : open - atr_v*m_be_lock;
            new_sl = NormalizePriceSym(new_sl, symbol);
            bool improve = is_buy ? (new_sl>sl || sl==0) : (new_sl<sl || sl==0);
            if(improve && ModifySL(ticket, new_sl, tp))
              { Mark(m_be_done, ticket); actions++; }
           }

         if(m_use_trail && profit_price >= atr_v*m_trail_start)
           {
            double new_sl = is_buy ? pos.PriceCurrent()-atr_v*m_trail_step
                                   : pos.PriceCurrent()+atr_v*m_trail_step;
            new_sl = NormalizePriceSym(new_sl, symbol);
            double gap = atr_v*0.15;
            bool improve = is_buy ? (new_sl > sl+gap || (sl==0 && new_sl>open))
                                  : (new_sl < sl-gap || (sl==0 && new_sl<open));
            if(improve && ModifySL(ticket, new_sl, tp)) actions++;
           }

         if(sl == 0.0)
           {
            double emergency = is_buy ? open - atr_v*1.5 : open + atr_v*1.5;
            if(ModifySL(ticket, NormalizePriceSym(emergency, symbol), tp)) actions++;
           }
        }
      return actions;
     }
  };

#endif
//+------------------------------------------------------------------+
