//+------------------------------------------------------------------+
//| Dashboard.mqh — Scarlet Forge 风格监控台（回测自动禁用）            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_DASHBOARD_MQH
#define GOLDFX_DASHBOARD_MQH

#include "Common.mqh"

#define DB_PREFIX "GFXdash_"

class CDashboard
  {
private:
   long              m_chart;
   bool              m_active;
   int               m_x, m_y, m_w;
   color             m_bg, m_fg, m_accent, m_btn, m_bad;
   SRuntimeParams    m_params;
   bool              m_apply, m_close_all, m_mode_chg, m_risk_chg, m_resume, m_manual_buy, m_manual_sell;

   void Del(const string n){ ObjectDelete(m_chart,n); }

   void Rect(const string n,int x,int y,int w,int h,color c)
     {
      Del(n);
      ObjectCreate(m_chart,n,OBJ_RECTANGLE_LABEL,0,0,0);
      ObjectSetInteger(m_chart,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,n,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,n,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,n,OBJPROP_XSIZE,w);
      ObjectSetInteger(m_chart,n,OBJPROP_YSIZE,h);
      ObjectSetInteger(m_chart,n,OBJPROP_BGCOLOR,c);
      ObjectSetInteger(m_chart,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,c);
      ObjectSetInteger(m_chart,n,OBJPROP_BACK,false);
      ObjectSetInteger(m_chart,n,OBJPROP_SELECTABLE,false);
     }

   void Lab(const string n,int x,int y,const string t,int fs=9,color c=clrNONE)
     {
      Del(n);
      ObjectCreate(m_chart,n,OBJ_LABEL,0,0,0);
      ObjectSetInteger(m_chart,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,n,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,n,OBJPROP_YDISTANCE,y);
      ObjectSetString(m_chart,n,OBJPROP_TEXT,t);
      ObjectSetString(m_chart,n,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(m_chart,n,OBJPROP_FONTSIZE,fs);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,(c==clrNONE?m_fg:c));
      ObjectSetInteger(m_chart,n,OBJPROP_SELECTABLE,false);
     }

   void Btn(const string n,int x,int y,int w,int h,const string t,color bg)
     {
      Del(n);
      ObjectCreate(m_chart,n,OBJ_BUTTON,0,0,0);
      ObjectSetInteger(m_chart,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart,n,OBJPROP_XDISTANCE,x);
      ObjectSetInteger(m_chart,n,OBJPROP_YDISTANCE,y);
      ObjectSetInteger(m_chart,n,OBJPROP_XSIZE,w);
      ObjectSetInteger(m_chart,n,OBJPROP_YSIZE,h);
      ObjectSetString(m_chart,n,OBJPROP_TEXT,t);
      ObjectSetString(m_chart,n,OBJPROP_FONT,"Consolas");
      ObjectSetInteger(m_chart,n,OBJPROP_FONTSIZE,8);
      ObjectSetInteger(m_chart,n,OBJPROP_COLOR,clrWhite);
      ObjectSetInteger(m_chart,n,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(m_chart,n,OBJPROP_BORDER_COLOR,clrDimGray);
      ObjectSetInteger(m_chart,n,OBJPROP_STATE,false);
      ObjectSetInteger(m_chart,n,OBJPROP_SELECTABLE,false);
     }

   string RName(const int i) const { return StringFormat("%sr%d", DB_PREFIX, i); }

public:
                     CDashboard(void)
                       : m_chart(0), m_active(false), m_x(8), m_y(20), m_w(320),
                         m_bg(C'18,24,32'), m_fg(C'220,228,235'),
                         m_accent(C'40,150,120'), m_btn(C'50,65,80'), m_bad(C'160,55,50'),
                         m_apply(false), m_close_all(false), m_mode_chg(false),
                         m_risk_chg(false), m_resume(false), m_manual_buy(false), m_manual_sell(false)
                     {
                      ZeroMemory(m_params);
                     }

                    ~CDashboard(void){ Destroy(); }

   bool Active(void) const { return m_active; }
   SRuntimeParams Params(void) const { return m_params; }

   bool Create(const long chart, const SRuntimeParams &p)
     {
      m_params = p;
      if(IsTesterMode() || !p.show_dashboard)
        {
         m_active = false;
         return true;
        }
      m_chart = chart;
      m_active = true;
      Destroy();

      Rect(DB_PREFIX "bg", m_x, m_y, m_w, 460, m_bg);
      Lab(DB_PREFIX "title", m_x+8, m_y+6, "GoldFX Forge 仪表盘 v3", 10);

      int cy = m_y + 28;
      Lab(DB_PREFIX "acct", m_x+8, cy, "账户...", 8);
      cy += 18;
      Lab(DB_PREFIX "sig", m_x+8, cy, "信号...", 8);
      cy += 18;
      Lab(DB_PREFIX "seven", m_x+8, cy, "七条件: --------", 8);
      cy += 18;
      Lab(DB_PREFIX "risk", m_x+8, cy, "风险...", 8);
      cy += 18;
      Lab(DB_PREFIX "filt", m_x+8, cy, "过滤...", 8);
      cy += 18;
      Lab(DB_PREFIX "perf", m_x+8, cy, "绩效...", 8);
      cy += 18;
      Lab(DB_PREFIX "port", m_x+8, cy, "组合...", 8);

      cy += 22;
      Lab(DB_PREFIX "lm", m_x+8, cy, "模式");
      cy += 16;
      Btn(DB_PREFIX "auto", m_x+8, cy, 70, 20, "自动", m_btn);
      Btn(DB_PREFIX "flat", m_x+82, cy, 70, 20, "观察", m_btn);
      Btn(DB_PREFIX "mm", m_x+156, cy, 140, 20, MoneyModeToString(p.money_mode), m_btn);

      cy += 26;
      Lab(DB_PREFIX "lr", m_x+8, cy, "风险 R1-R8");
      cy += 16;
      for(int i=1;i<=8;++i)
         Btn(RName(i), m_x+8+(i-1)*36, cy, 34, 18, IntegerToString(i), m_btn);

      cy += 26;
      Btn(DB_PREFIX "buy", m_x+8, cy, 70, 24, "买入", m_accent);
      Btn(DB_PREFIX "sell", m_x+82, cy, 70, 24, "卖出", m_bad);
      Btn(DB_PREFIX "resume", m_x+156, cy, 70, 24, "恢复", m_btn);
      Btn(DB_PREFIX "close", m_x+230, cy, 70, 24, "全平", m_bad);

      cy += 30;
      Lab(DB_PREFIX "status", m_x+8, cy, "就绪", 8);
      Highlight();
      ChartRedraw(m_chart);
      return true;
     }

   void Destroy(void)
     {
      if(m_chart!=0) ObjectsDeleteAll(m_chart, DB_PREFIX);
     }

   void SetParams(const SRuntimeParams &p)
     {
      m_params = p;
      if(!m_active) return;
      ObjectSetString(m_chart, DB_PREFIX "mm", OBJPROP_TEXT, MoneyModeToString(p.money_mode));
      Highlight();
     }

   void Highlight(void)
     {
      if(!m_active) return;
      ObjectSetInteger(m_chart, DB_PREFIX "auto", OBJPROP_BGCOLOR, m_params.run_mode!=MODE_FLAT?m_accent:m_btn);
      ObjectSetInteger(m_chart, DB_PREFIX "flat", OBJPROP_BGCOLOR, m_params.run_mode==MODE_FLAT?m_accent:m_btn);
      for(int i=1;i<=8;++i)
         ObjectSetInteger(m_chart, RName(i), OBJPROP_BGCOLOR, ((int)m_params.risk_level==i)?m_accent:m_btn);
     }

   void Update(const string acct, const string sig, const string seven,
               const string risk, const string filt, const string perf,
               const string port, const string status)
     {
      if(!m_active) return;
      ObjectSetString(m_chart, DB_PREFIX "acct", OBJPROP_TEXT, acct);
      ObjectSetString(m_chart, DB_PREFIX "sig", OBJPROP_TEXT, sig);
      ObjectSetString(m_chart, DB_PREFIX "seven", OBJPROP_TEXT, seven);
      ObjectSetString(m_chart, DB_PREFIX "risk", OBJPROP_TEXT, risk);
      ObjectSetString(m_chart, DB_PREFIX "filt", OBJPROP_TEXT, filt);
      ObjectSetString(m_chart, DB_PREFIX "perf", OBJPROP_TEXT, perf);
      ObjectSetString(m_chart, DB_PREFIX "port", OBJPROP_TEXT, port);
      string st = status;
      if(StringLen(st)>48) st = StringSubstr(st,0,48)+"...";
      ObjectSetString(m_chart, DB_PREFIX "status", OBJPROP_TEXT, st);
     }

   bool ConsumeClose(void){ if(!m_close_all)return false; m_close_all=false; return true; }
   bool ConsumeMode(void){ if(!m_mode_chg)return false; m_mode_chg=false; return true; }
   bool ConsumeRisk(void){ if(!m_risk_chg)return false; m_risk_chg=false; return true; }
   bool ConsumeResume(void){ if(!m_resume)return false; m_resume=false; return true; }
   bool ConsumeManualBuy(void){ if(!m_manual_buy)return false; m_manual_buy=false; return true; }
   bool ConsumeManualSell(void){ if(!m_manual_sell)return false; m_manual_sell=false; return true; }

   bool HandleChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
     {
      if(!m_active || id!=CHARTEVENT_OBJECT_CLICK) return false;
      if(StringFind(sparam, DB_PREFIX)!=0) return false;
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(sparam==DB_PREFIX "auto"){ m_params.run_mode=MODE_AUTO; m_mode_chg=true; Highlight(); return true; }
      if(sparam==DB_PREFIX "flat"){ m_params.run_mode=MODE_FLAT; m_mode_chg=true; Highlight(); return true; }
      if(sparam==DB_PREFIX "mm")
        {
         int m=((int)m_params.money_mode+1)%5;
         m_params.money_mode=(ENUM_MONEY_MODE)m;
         if(m_params.money_mode==MM_AUTO_LEVEL) ApplyRiskLevelToParams(m_params);
         ObjectSetString(m_chart, DB_PREFIX "mm", OBJPROP_TEXT, MoneyModeToString(m_params.money_mode));
         m_risk_chg=true;
         return true;
        }
      for(int i=1;i<=8;++i)
        {
         if(sparam==RName(i))
           {
            m_params.risk_level=(ENUM_RISK_LEVEL)i;
            ApplyRiskLevelToParams(m_params);
            Highlight();
            m_risk_chg=true;
            return true;
           }
        }
      if(sparam==DB_PREFIX "close"){ m_close_all=true; return true; }
      if(sparam==DB_PREFIX "resume"){ m_resume=true; return true; }
      if(sparam==DB_PREFIX "buy"){ m_manual_buy=true; return true; }
      if(sparam==DB_PREFIX "sell"){ m_manual_sell=true; return true; }
      return false;
     }
  };

#endif
//+------------------------------------------------------------------+
