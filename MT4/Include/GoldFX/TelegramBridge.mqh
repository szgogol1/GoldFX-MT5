//+------------------------------------------------------------------+
//| TelegramBridge.mqh — MT4 原生 WebRequest 推送                      |
//| 工具→选项→专家顾问：允许 WebRequest 到 https://api.telegram.org    |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_TELEGRAM_BRIDGE_MT4_MQH
#define GOLDFX_TELEGRAM_BRIDGE_MT4_MQH

class CTelegramBridge
  {
private:
   bool   m_enable;
   string m_token;
   string m_chat;

   string UrlEncode(string s) const
     {
      StringReplace(s, " ", "%20");
      StringReplace(s, "\n", "%0A");
      StringReplace(s, "|", "%7C");
      return s;
     }

public:
                     CTelegramBridge(void): m_enable(false), m_token(""), m_chat("") {}

   void ConfigureDirect(const bool enable, const string token, const string chat_id)
     {
      m_enable = enable && StringLen(token)>10 && StringLen(chat_id)>0;
      m_token  = token;
      m_chat   = chat_id;
     }

   bool Enabled(void) const { return m_enable; }

   bool Send(const string text)
     {
      if(!m_enable) return false;
      if(IsTesting() || IsOptimization()) return false;
      string url = StringFormat("https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s",
                                m_token, m_chat, UrlEncode(text));
      char result[];
      char data[];
      string headers = "";
      ResetLastError();
      const int code = WebRequest("GET", url, "", "", 5000, data, 0, result, headers);
      if(code==-1)
        {
         Print("Telegram WebRequest 失败 err=", GetLastError(),
               " 请允许 https://api.telegram.org");
         return false;
        }
      return (code==200 || code==201);
     }

   void NotifyEvent(const string text) { Send(text); }
  };

#endif
//+------------------------------------------------------------------+
