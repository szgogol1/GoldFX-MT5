//+------------------------------------------------------------------+
//| TradeManager.mqh — 多品种下单 / 全平 / 强制止损                     |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TRADE_MANAGER_MQH
#define GOLDFX_TRADE_MANAGER_MQH

#include "Common.mqh"
#include "RiskManager.mqh"
#include "SelectivityFilter.mqh"
#include "TradeJournal.mqh"
#include "TelegramBridge.mqh"
#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

class CTradeManager
  {
private:
   int                  m_magic;
   int                  m_slippage;
   CTrade               m_trade;
   CRiskManager        *m_risk;
   CSelectivityFilter  *m_filter;
   CTradeJournal       *m_journal;
   CTelegramBridge     *m_tg;

public:
                     CTradeManager(void)
                       : m_magic(20260826), m_slippage(30),
                         m_risk(NULL), m_filter(NULL), m_journal(NULL), m_tg(NULL)
                     {
                     }

   void Init(CRiskManager *risk, CSelectivityFilter *filter,
             CTradeJournal *journal, CTelegramBridge *tg, const SRuntimeParams &p)
     {
      m_risk = risk; m_filter = filter; m_journal = journal; m_tg = tg;
      Configure(p);
     }

   void Configure(const SRuntimeParams &p)
     {
      m_magic = p.magic;
      m_slippage = MathMax(1, p.slippage);
      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_slippage);
     }

   bool OpenBySignal(const SSignalResult &sig, string &msg)
     {
      msg = "";
      if(sig.signal == SIGNAL_NONE) { msg="无信号"; return false; }
      if(m_risk == NULL) { msg="风控未绑定"; return false; }
      string symbol = sig.symbol;
      if(StringLen(symbol)==0) symbol = _Symbol;

      if(sig.sl <= 0.0) { msg="拒绝无止损信号"; return false; }

      if(m_filter != NULL)
        {
         string fr;
         if(!m_filter.Pass(sig, fr)) { msg=fr; return false; }
        }

      string reason;
      if(!m_risk.CanOpenNew(symbol, sig.signal, reason)) { msg=reason; return false; }

      const double lot = m_risk.CalcLot(symbol, sig.entry, sig.sl, sig.atr);
      if(lot <= 0.0) { msg="手数无效"; return false; }

      ENUM_ORDER_TYPE ot = (sig.signal==SIGNAL_BUY)? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(!m_risk.MarginSafe(symbol, lot, ot, reason)) { msg=reason; return false; }

      m_trade.SetTypeFillingBySymbol(symbol);
      string tag = sig.engine_tag;
      if(StringLen(tag)==0) tag = "7C";
      string cmt = StringFormat("Q%d|%s", sig.quality, tag);
      if(StringLen(cmt)>31) cmt = StringSubstr(cmt,0,31);

      bool ok = (sig.signal==SIGNAL_BUY)
                ? m_trade.Buy(lot, symbol, 0.0, sig.sl, sig.tp, cmt)
                : m_trade.Sell(lot, symbol, 0.0, sig.sl, sig.tp, cmt);
      if(!ok)
        {
         msg = StringFormat("下单失败 %s ret=%u %s", symbol, m_trade.ResultRetcode(), m_trade.ResultComment());
         Print(msg);
         return false;
        }

      if(m_filter != NULL) m_filter.NotifyEntryFilled();
      const double risk_used = m_risk.LastEffRisk();
      if(m_journal != NULL) m_journal.LogEntry(sig, lot, risk_used);
      if(m_tg != NULL) m_tg.NotifyEntry(sig, lot);

      msg = StringFormat("开仓 %s %s lot=%.2f risk%%=%.2f Q=%d",
                         symbol, SignalToString(sig.signal), lot, risk_used, sig.quality);
      Print(msg);
      return true;
     }

   int CloseAll(const string comment="平仓", const string only_symbol="")
     {
      CPositionInfo pos; int closed=0;
      for(int i=PositionsTotal()-1;i>=0;--i)
        {
         if(!pos.SelectByIndex(i)) continue;
         if(pos.Magic()!=m_magic) continue;
         if(StringLen(only_symbol)>0 && pos.Symbol()!=only_symbol) continue;
         const double pnl = pos.Profit();
         const string sym = pos.Symbol();
         if(m_trade.PositionClose(pos.Ticket()))
           {
            closed++;
            if(m_tg != NULL) m_tg.NotifyExit(sym, comment, pnl);
            if(m_risk != NULL && m_risk.Adapt()!=NULL)
               m_risk.Adapt().OnTradeClosed(pnl >= 0.0);
           }
        }
      if(closed>0) PrintFormat("%s: 已平 %d", comment, closed);
      return closed;
     }
  };

#endif
//+------------------------------------------------------------------+
