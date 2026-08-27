//+------------------------------------------------------------------+
//| TelegramBridge.mqh — 原生 WebRequest 推送与简易远程命令轮询         |
//| 需在 MT5「工具→选项→专家」允许 WebRequest: https://api.telegram.org |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TELEGRAM_BRIDGE_MQH
#define GOLDFX_TELEGRAM_BRIDGE_MQH

#include "Common.mqh"

class CTelegramBridge
  {
private:
   bool              m_enable;
   string            m_token;
   string            m_chat;
   long              m_last_update_id;
   datetime          m_last_poll;
   string            m_pending_cmd;   // 最近解析命令
   double            m_pending_risk;  // /risk X

   string UrlEncode(const string s) const
     {
      // 简化：替换常见字符
      string o = s;
      StringReplace(o, " ", "%20");
      StringReplace(o, "\n", "%0A");
      StringReplace(o, "|", "%7C");
      return o;
     }

   bool HttpGet(const string url, string &body)
     {
      body = "";
      if(IsTesterMode())
         return false;
      char result[];
      char data[];
      string headers = "";
      ResetLastError();
      const int code = WebRequest("GET", url, headers, 5000, data, result, headers);
      if(code == -1)
        {
         Print("Telegram WebRequest 失败 err=", GetLastError(),
               " 请允许 https://api.telegram.org");
         return false;
        }
      body = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return (code == 200 || code == 201);
     }

public:
                     CTelegramBridge(void)
                       : m_enable(false), m_token(""), m_chat(""),
                         m_last_update_id(0), m_last_poll(0),
                         m_pending_cmd(""), m_pending_risk(0)
                     {
                     }

   void Configure(const SRuntimeParams &p)
     {
      m_enable = p.telegram_enable && StringLen(p.telegram_token) > 10 && StringLen(p.telegram_chat_id) > 0;
      m_token  = p.telegram_token;
      m_chat   = p.telegram_chat_id;
     }

   void ConfigureDirect(const bool enable, const string token, const string chat_id)
     {
      m_enable = enable && StringLen(token) > 10 && StringLen(chat_id) > 0;
      m_token  = token;
      m_chat   = chat_id;
     }

   bool Enabled(void) const { return m_enable; }

   bool Send(const string text)
     {
      if(!m_enable)
         return false;
      string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
                                m_token, m_chat, UrlEncode(text));
      string body;
      return HttpGet(url, body);
     }

   void NotifyEntry(const SSignalResult &sig, const double lot)
     {
      Send(StringFormat("ENTRY %s %s lot=%.2f @%.5f SL=%.5f TP=%.5f Q=%d\n%s",
                        sig.symbol, SignalToString(sig.signal), lot, sig.entry, sig.sl, sig.tp,
                        sig.quality, sig.reason));
     }

   void NotifyExit(const string symbol, const string reason, const double pnl)
     {
      Send(StringFormat("EXIT %s %s PnL=%.2f", symbol, reason, pnl));
     }

   void NotifyEvent(const string text) { Send(text); }

   // 返回是否有新命令；命令写入 out_cmd（status/stop/resume/pause/risk）
   bool PollCommand(string &out_cmd, string &out_arg)
     {
      out_cmd = ""; out_arg = "";
      if(!m_enable || IsTesterMode())
         return false;
      if(TimeCurrent() - m_last_poll < 15)
         return false;
      m_last_poll = TimeCurrent();

      string url = StringFormat("https://api.telegram.org/bot%s/getUpdates?offset=%I64d&timeout=0",
                                m_token, m_last_update_id + 1);
      string body;
      if(!HttpGet(url, body))
         return false;

      // 极简解析：找最后一个 "text":"/..."
      int pos = StringLen(body);
      string found = "";
      long upd = m_last_update_id;
      // 扫描 update_id
      int p = 0;
      while(true)
        {
         int u = StringFind(body, "\"update_id\":", p);
         if(u < 0) break;
         int start = u + 12;
         long id = (long)StringToInteger(StringSubstr(body, start, 16));
         if(id > upd) upd = id;
         p = start;
        }
      int t = StringFind(body, "\"text\":\"");
      if(t >= 0)
        {
         int ts = t + 8;
         int te = StringFind(body, "\"", ts);
         if(te > ts)
            found = StringSubstr(body, ts, te - ts);
        }
      if(upd > m_last_update_id)
         m_last_update_id = upd;
      if(StringLen(found) == 0)
         return false;

      StringTrimLeft(found); StringTrimRight(found);
      StringToLower(found);
      if(StringFind(found, "/status") == 0) { out_cmd="status"; return true; }
      if(StringFind(found, "/stop") == 0)   { out_cmd="stop"; return true; }
      if(StringFind(found, "/resume") == 0) { out_cmd="resume"; return true; }
      if(StringFind(found, "/pause") == 0)
        {
         out_cmd = "pause";
         // /pause SYMBOL
         int sp = StringFind(found, " ");
         if(sp > 0) out_arg = StringSubstr(found, sp + 1);
         StringToUpper(out_arg);
         return true;
        }
      if(StringFind(found, "/risk") == 0)
        {
         out_cmd = "risk";
         int sp = StringFind(found, " ");
         if(sp > 0) out_arg = StringSubstr(found, sp + 1);
         return true;
        }
      return false;
     }
  };

#endif
//+------------------------------------------------------------------+
