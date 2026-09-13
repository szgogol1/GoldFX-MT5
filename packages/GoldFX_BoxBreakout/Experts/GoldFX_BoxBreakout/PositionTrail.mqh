//+------------------------------------------------------------------+
//| PositionTrail.mqh — BE / ATR trail / partial close               |
//+------------------------------------------------------------------+
#ifndef GOLDFX_BOX_POSITION_TRAIL_MQH
#define GOLDFX_BOX_POSITION_TRAIL_MQH

#include "Common.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CPositionTrail
  {
private:
   int             m_magic;
   int             m_slippage;
   int             m_atr_period;
   ENUM_TIMEFRAMES m_tf;
   bool            m_use_be;
   double          m_be_trig;
   double          m_be_lock;
   bool            m_use_trail;
   double          m_trail_start;
   double          m_trail_step;
   bool            m_use_partial;
   double          m_partial_atr;
   double          m_partial_pct;
   int             m_max_hold_min;
   CTrade          m_trade;
   ulong           m_be_done[];
   ulong           m_partial_done[];

   bool IsMarked(const ulong &arr[], const ulong ticket) const
     {
      for(int i=0; i<ArraySize(arr); ++i)
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

   double ProfitPrice(CPositionInfo &pos) const
     {
      if(pos.PositionType() == POSITION_TYPE_BUY)
         return pos.PriceCurrent() - pos.PriceOpen();
      return pos.PriceOpen() - pos.PriceCurrent();
     }

public:
   void Configure(const int magic, const int slippage, const int atr_period,
                  const ENUM_TIMEFRAMES tf,
                  const bool use_be, const double be_trig, const double be_lock,
                  const bool use_trail, const double trail_start, const double trail_step,
                  const bool use_partial, const double partial_atr, const double partial_pct,
                  const int max_hold_min)
     {
      m_magic = magic;
      m_slippage = MathMax(1, slippage);
      m_atr_period = MathMax(2, atr_period);
      m_tf = tf;
      m_use_be = use_be;
      m_be_trig = MathMax(0.1, be_trig);
      m_be_lock = MathMax(0.0, be_lock);
      m_use_trail = use_trail;
      m_trail_start = MathMax(0.1, trail_start);
      m_trail_step = MathMax(0.1, trail_step);
      m_use_partial = use_partial;
      m_partial_atr = MathMax(0.1, partial_atr);
      m_partial_pct = MathMax(10.0, MathMin(90.0, partial_pct));
      m_max_hold_min = MathMax(0, max_hold_min);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
     }

   int CountMine(const string symbol = "") const
     {
      CPositionInfo pos;
      int n = 0;
      for(int i=PositionsTotal()-1; i>=0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Magic() != m_magic)
            continue;
         if(StringLen(symbol) > 0 && pos.Symbol() != symbol)
            continue;
         n++;
        }
      return n;
     }

   int Manage(void)
     {
      CPositionInfo pos;
      int actions = 0;
      for(int i=PositionsTotal()-1; i>=0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Magic() != m_magic)
            continue;

         const string symbol = pos.Symbol();
         const ulong ticket = pos.Ticket();
         const int ah = iATR(symbol, m_tf, m_atr_period);
         if(ah == INVALID_HANDLE)
            continue;

         double atr[];
         ArraySetAsSeries(atr, true);
         if(CopyBuffer(ah, 0, 0, 3, atr) < 3)
           {
            IndicatorRelease(ah);
            continue;
           }
         IndicatorRelease(ah);
         const double atr_v = atr[1];
         if(atr_v <= 0.0)
            continue;

         m_trade.SetTypeFillingBySymbol(symbol);
         const double open_price = pos.PriceOpen();
         const double sl = pos.StopLoss();
         const double tp = pos.TakeProfit();
         const double profit = ProfitPrice(pos);
         const bool is_buy = (pos.PositionType() == POSITION_TYPE_BUY);

         if(m_max_hold_min > 0)
           {
            const int held = (int)((TimeCurrent() - pos.Time()) / 60);
            if(held >= m_max_hold_min)
              {
               if(m_trade.PositionClose(ticket))
                  actions++;
               continue;
              }
           }

         if(m_use_partial && !IsMarked(m_partial_done, ticket) && profit >= atr_v * m_partial_atr)
           {
            double vol = pos.Volume();
            double close_vol = NormalizeDouble(vol * (m_partial_pct / 100.0), 2);
            const double vmin = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            const double vstep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(vstep > 0.0)
               close_vol = MathFloor(close_vol / vstep) * vstep;
            if(close_vol >= vmin && (vol - close_vol) >= vmin - 1e-8)
              {
               if(m_trade.PositionClosePartial(ticket, close_vol))
                 {
                  Mark(m_partial_done, ticket);
                  actions++;
                 }
              }
           }

         if(m_use_be && !IsMarked(m_be_done, ticket) && profit >= atr_v * m_be_trig)
           {
            double new_sl = is_buy ? open_price + atr_v * m_be_lock
                                   : open_price - atr_v * m_be_lock;
            new_sl = BoxNormPrice(new_sl, symbol);
            const bool improve = is_buy ? (new_sl > sl || sl == 0.0)
                                        : (new_sl < sl || sl == 0.0);
            if(improve && m_trade.PositionModify(ticket, new_sl, tp))
              {
               Mark(m_be_done, ticket);
               actions++;
              }
           }

         if(m_use_trail && profit >= atr_v * m_trail_start)
           {
            double new_sl = is_buy ? pos.PriceCurrent() - atr_v * m_trail_step
                                   : pos.PriceCurrent() + atr_v * m_trail_step;
            new_sl = BoxNormPrice(new_sl, symbol);
            const double gap = atr_v * 0.20;
            const bool improve = is_buy ? (new_sl > sl + gap || (sl == 0.0 && new_sl > open_price))
                                        : (new_sl < sl - gap || (sl == 0.0 && new_sl < open_price));
            if(improve && m_trade.PositionModify(ticket, new_sl, tp))
               actions++;
           }

         if(sl == 0.0)
           {
            const double emergency = is_buy ? open_price - atr_v * 1.5
                                            : open_price + atr_v * 1.5;
            if(m_trade.PositionModify(ticket, BoxNormPrice(emergency, symbol), tp))
               actions++;
           }
        }
      return actions;
     }
  };

#endif
