//+------------------------------------------------------------------+
//| TradeManager.mqh — 下单与平仓封装                                   |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TRADE_MANAGER_MQH
#define GOLDFX_TRADE_MANAGER_MQH

#include "Common.mqh"
#include "RiskManager.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CTradeManager
  {
private:
   string            m_symbol;
   int               m_magic;
   int               m_slippage;
   CTrade            m_trade;
   CRiskManager     *m_risk;

public:
                     CTradeManager(void)
                       : m_symbol(_Symbol),
                         m_magic(20260826),
                         m_slippage(30),
                         m_risk(NULL)
                     {
                     }

   void Init(const string symbol, CRiskManager *risk, const SRuntimeParams &p)
     {
      m_symbol = symbol;
      m_risk   = risk;
      Configure(p);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
      m_trade.SetTypeFillingBySymbol(m_symbol);
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic    = p.magic;
      m_slippage = MathMax(1, p.slippage);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
     }

   bool OpenBySignal(const SSignalResult &sig, string &msg)
     {
      msg = "";
      if(sig.signal == SIGNAL_NONE)
        {
         msg = "无信号";
         return false;
        }
      if(m_risk == NULL)
        {
         msg = "风控未绑定";
         return false;
        }

      string reason;
      if(!m_risk.CanOpenNew(reason))
        {
         msg = reason;
         return false;
        }

      const double lot = m_risk.CalcLot(sig.entry, sig.sl);
      if(lot <= 0.0)
        {
         msg = "手数计算无效";
         return false;
        }

      bool ok = false;
      if(sig.signal == SIGNAL_BUY)
         ok = m_trade.Buy(lot, m_symbol, 0.0, sig.sl, sig.tp, sig.reason);
      else
         ok = m_trade.Sell(lot, m_symbol, 0.0, sig.sl, sig.tp, sig.reason);

      if(!ok)
        {
         msg = StringFormat("下单失败 retcode=%u %s", m_trade.ResultRetcode(), m_trade.ResultComment());
         Print(msg);
         return false;
        }

      msg = StringFormat("开仓成功 %s lot=%.2f SL=%.5f TP=%.5f | %s",
                         SignalToString(sig.signal), lot, sig.sl, sig.tp, sig.reason);
      Print(msg);
      return true;
     }

   int CloseAll(const string comment = "面板平仓")
     {
      CPositionInfo pos;
      int closed = 0;
      for(int i = PositionsTotal() - 1; i >= 0; --i)
        {
         if(!pos.SelectByIndex(i))
            continue;
         if(pos.Symbol() != m_symbol || pos.Magic() != m_magic)
            continue;
         if(m_trade.PositionClose(pos.Ticket()))
            closed++;
         else
            PrintFormat("平仓失败 ticket=%I64u %s", pos.Ticket(), m_trade.ResultComment());
        }
      if(closed > 0)
         PrintFormat("%s: 已平 %d 笔", comment, closed);
      return closed;
     }
  };

#endif
//+------------------------------------------------------------------+
