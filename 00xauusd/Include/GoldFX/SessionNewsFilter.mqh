//+------------------------------------------------------------------+
//| SessionNewsFilter.mqh — 时段 / 点差 / 新闻 / 周五截止               |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_SESSION_NEWS_FILTER_MQH
#define GOLDFX_SESSION_NEWS_FILTER_MQH

#include "Common.mqh"

class CSessionNewsFilter
  {
private:
   bool              m_use_news;
   int               m_pad_before;
   int               m_pad_after;
   bool              m_friday_cut;
   int               m_friday_hour;
   int               m_sess_start;
   int               m_sess_end;
   bool              m_use_session;
   string            m_last_reason;

   // 高影响新闻窗口（原生日历；失败则降级为仅周五/时段）
   bool InHighImpactNewsWindow(void)
     {
      if(!m_use_news)
         return false;
      datetime now = TimeCurrent();
      datetime from = now - m_pad_before * 60;
      datetime to   = now + m_pad_after * 60;

      MqlCalendarValue values[];
      // 国家码空=全部；importance 过滤在循环中做
      ResetLastError();
      int n = CalendarValueHistory(values, from, to);
      if(n < 0)
        {
         // 日历不可用（部分经纪商/测试器）——不阻断交易
         return false;
        }
      for(int i=0; i<n; ++i)
        {
         MqlCalendarEvent ev;
         if(!CalendarEventById(values[i].event_id, ev))
            continue;
         if(ev.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
         // 事件时间：使用 values[i].time
         datetime et = values[i].time;
         // 处理跨午夜：from/to 已覆盖
         if(et >= from && et <= to)
            return true;
        }
      return false;
     }

public:
                     CSessionNewsFilter(void)
                       : m_use_news(true), m_pad_before(30), m_pad_after(30),
                         m_friday_cut(true), m_friday_hour(16),
                         m_sess_start(8), m_sess_end(20), m_use_session(true),
                         m_last_reason("")
                     {
                     }

   void Configure(const SRuntimeParams &p, const int sess_start, const int sess_end, const bool use_sess)
     {
      m_use_news    = p.use_news_filter;
      m_pad_before  = MathMax(0, p.news_pause_minutes_before);
      m_pad_after   = MathMax(0, p.news_pause_minutes_after);
      m_friday_cut  = p.friday_cutoff;
      m_friday_hour = MathMax(0, MathMin(23, p.friday_cutoff_hour));
      m_sess_start  = sess_start;
      m_sess_end    = sess_end;
      m_use_session = use_sess;
     }

   string LastReason(void) const { return m_last_reason; }

   bool AllowTrade(string &reason)
     {
      reason = "";
      m_last_reason = "";
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);

      if(m_friday_cut && dt.day_of_week == 5 && dt.hour >= m_friday_hour)
        {
         reason = StringFormat("周五%d点后截止，避周末跳空", m_friday_hour);
         m_last_reason = reason;
         return false;
        }

      if(m_use_session)
        {
         bool in_sess = false;
         if(m_sess_start == m_sess_end)
            in_sess = true;
         else if(m_sess_start < m_sess_end)
            in_sess = (dt.hour >= m_sess_start && dt.hour < m_sess_end);
         else
            in_sess = (dt.hour >= m_sess_start || dt.hour < m_sess_end);
         if(!in_sess)
           {
            reason = "非交易时段";
            m_last_reason = reason;
            return false;
           }
        }

      if(InHighImpactNewsWindow())
        {
         reason = "高影响新闻窗口暂停";
         m_last_reason = reason;
         return false;
        }

      reason = "过滤器通过";
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
