//+------------------------------------------------------------------+
//| OrderFlowBook.mqh — 可选 DOM（Market Book）；不可用则静默降级      |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_ORDER_FLOW_BOOK_MQH
#define GOLDFX_ORDER_FLOW_BOOK_MQH

#include "Common.mqh"

class COrderFlowBook
  {
private:
   string            m_symbol;
   bool              m_subscribed;
   bool              m_available;
   double            m_bid_wall_price;
   double            m_bid_wall_vol;
   double            m_ask_wall_price;
   double            m_ask_wall_vol;
   double            m_near_bid_vol;
   double            m_near_ask_vol;

public:
                     COrderFlowBook(void)
                       : m_symbol(""), m_subscribed(false), m_available(false),
                         m_bid_wall_price(0), m_bid_wall_vol(0),
                         m_ask_wall_price(0), m_ask_wall_vol(0),
                         m_near_bid_vol(0), m_near_ask_vol(0)
                     {
                     }

                    ~COrderFlowBook(void) { Release(); }

   bool Available(void) const { return m_available; }
   double BidWallPrice(void) const { return m_bid_wall_price; }
   double AskWallPrice(void) const { return m_ask_wall_price; }
   double BidWallVol(void) const { return m_bid_wall_vol; }
   double AskWallVol(void) const { return m_ask_wall_vol; }
   double NearBidVol(void) const { return m_near_bid_vol; }
   double NearAskVol(void) const { return m_near_ask_vol; }

   bool Init(const string symbol, const bool enable)
     {
      Release();
      m_symbol = symbol;
      m_available = false;
      if(!enable || IsTesterMode())
         return true; // 静默：测试器通常无 DOM
      if(!MarketBookAdd(m_symbol))
        {
         PrintFormat("OrderFlowBook: MarketBookAdd 失败 %s（经纪商可能无深度）", m_symbol);
         return true; // 不阻断
        }
      m_subscribed = true;
      Refresh();
      return true;
     }

   void Release(void)
     {
      if(m_subscribed)
        {
         MarketBookRelease(m_symbol);
         m_subscribed = false;
        }
      m_available = false;
     }

   bool Refresh(void)
     {
      if(!m_subscribed) return false;
      MqlBookInfo book[];
      if(!MarketBookGet(m_symbol, book) || ArraySize(book) == 0)
        {
         m_available = false;
         return false;
        }

      m_bid_wall_vol = 0; m_ask_wall_vol = 0;
      m_bid_wall_price = 0; m_ask_wall_price = 0;
      m_near_bid_vol = 0; m_near_ask_vol = 0;

      const double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      const double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      const double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      const double near = point * 50.0; // 近端约 50 点

      for(int i=0;i<ArraySize(book);++i)
        {
         const double vol = (double)book[i].volume_real > 0.0
                            ? (double)book[i].volume_real
                            : (double)book[i].volume;
         if(book[i].type == BOOK_TYPE_BUY || book[i].type == BOOK_TYPE_BUY_MARKET)
           {
            if(vol > m_bid_wall_vol)
              {
               m_bid_wall_vol = vol;
               m_bid_wall_price = book[i].price;
              }
            if(bid > 0 && MathAbs(book[i].price - bid) <= near)
               m_near_bid_vol += vol;
           }
         else if(book[i].type == BOOK_TYPE_SELL || book[i].type == BOOK_TYPE_SELL_MARKET)
           {
            if(vol > m_ask_wall_vol)
              {
               m_ask_wall_vol = vol;
               m_ask_wall_price = book[i].price;
              }
            if(ask > 0 && MathAbs(book[i].price - ask) <= near)
               m_near_ask_vol += vol;
           }
        }
      m_available = (m_bid_wall_vol > 0.0 || m_ask_wall_vol > 0.0);
      return m_available;
     }

   // 做多：近端买墙不低于卖墙（无 DOM 时返回 true = 不否决）
   bool SupportsLong(void) const
     {
      if(!m_available) return true;
      if(m_near_bid_vol <= 0.0 && m_near_ask_vol <= 0.0) return true;
      return (m_near_bid_vol >= m_near_ask_vol * 0.85);
     }

   bool SupportsShort(void) const
     {
      if(!m_available) return true;
      if(m_near_bid_vol <= 0.0 && m_near_ask_vol <= 0.0) return true;
      return (m_near_ask_vol >= m_near_bid_vol * 0.85);
     }
  };

#endif
//+------------------------------------------------------------------+
