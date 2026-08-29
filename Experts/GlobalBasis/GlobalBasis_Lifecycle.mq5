//+------------------------------------------------------------------+
//| GlobalBasis_Lifecycle.mq5 — AI 策略生命周期 Demo（ASSISTED）        |
//| AI 分析 + 建议；Hard Risk 强制；人工 APPROVE/REJECT                 |
//| 本 EA 不实盘下单，仅演示闸门与面板（可对接 BasisArb / 加密引擎）    |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property version   "4.00"
#property description "GlobalBasis 4.0 AI Strategy Lifecycle Manager (ASSISTED)"

#include <GlobalBasis/GB_Lifecycle.mqh>

input group "=== Strategy Identity ==="
input string InpVenue          = "Binance";      // Venue
input string InpSymbolTag      = "BTC";          // Symbol tag
input string InpStratName      = "BTC_Funding_V1";

input group "=== Hard Limits (AI cannot loosen) ==="
input double InpMaxPortfolioDD = 5.0;            // Max portfolio DD %
input double InpMaxDailyLoss   = 2.0;            // Max daily loss %
input int    InpMaxPositions   = 2;

input group "=== Live Params (seed) ==="
input double InpEntryZ         = 1.8;
input double InpExitZ          = 0.30;
input double InpStopZ          = 3.5;
input double InpMaxRiskPct     = 2.0;

input group "=== Demo simulation feeds ==="
input bool   InpSimulateFeeds  = true;           // 模拟绩效/执行以便演示面板
input int    InpReviewSeconds  = 60;             // Demo 复盘间隔(秒)；实盘用 86400

input group "=== Panel ==="
input bool   InpShowPanel      = true;
input int    InpPanelX         = 12;
input int    InpPanelY         = 24;

#define PFX "GB4_"

CGBLifecycle g_lc;
datetime     g_last_review_tick = 0;
bool         g_btn_approve = false;
bool         g_btn_reject  = false;
bool         g_btn_ignore  = false;
bool         g_btn_review  = false;

//------------------------------------------------------------------
void PanelRect(const string n,int x,int y,int w,int h,color bg)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_TYPE,BORDER_FLAT);
   ObjectSetInteger(0,n,OBJPROP_COLOR,C'40,50,65');
   ObjectSetInteger(0,n,OBJPROP_BACK,false);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
  }

void PanelLab(const string n,int x,int y,const string t,int fs,color c)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_LABEL,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetString(0,n,OBJPROP_TEXT,t);
   ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,fs);
   ObjectSetInteger(0,n,OBJPROP_COLOR,c);
   ObjectSetInteger(0,n,OBJPROP_SELECTABLE,false);
  }

void PanelBtn(const string n,int x,int y,int w,int h,const string t,color bg)
  {
   if(ObjectFind(0,n)<0) ObjectCreate(0,n,OBJ_BUTTON,0,0,0);
   ObjectSetInteger(0,n,OBJPROP_CORNER,CORNER_LEFT_UPPER);
   ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,n,OBJPROP_XSIZE,w);
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h);
   ObjectSetString(0,n,OBJPROP_TEXT,t);
   ObjectSetString(0,n,OBJPROP_FONT,"Consolas");
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE,9);
   ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bg);
   ObjectSetInteger(0,n,OBJPROP_BORDER_COLOR,C'70,80,95');
   ObjectSetInteger(0,n,OBJPROP_STATE,false);
  }

void PanelCreate()
  {
   const int x=InpPanelX,y=InpPanelY,w=340,h=320;
   color bg=C'16,22,30';
   color fg=C'220,228,235';
   PanelRect(PFX "bg",x,y,w,h,bg);
   PanelLab(PFX "title",x+8,y+6,"GlobalBasis 4.0  AI Lifecycle",10,fg);
   PanelLab(PFX "L1",x+8,y+28,"...",8,fg);
   PanelLab(PFX "L2",x+8,y+46,"...",8,fg);
   PanelLab(PFX "L3",x+8,y+64,"...",8,fg);
   PanelLab(PFX "L4",x+8,y+82,"...",8,fg);
   PanelLab(PFX "L5",x+8,y+100,"...",8,fg);
   PanelLab(PFX "L6",x+8,y+118,"...",8,clrGold);
   PanelLab(PFX "L7",x+8,y+148,"...",8,fg);
   PanelLab(PFX "L8",x+8,y+166,"...",8,fg);
   PanelLab(PFX "L9",x+8,y+184,"...",8,fg);
   PanelBtn(PFX "approve",x+8,y+220,100,28,"APPROVE",C'40,150,120');
   PanelBtn(PFX "reject", x+116,y+220,100,28,"REJECT",C'160,55,50');
   PanelBtn(PFX "ignore", x+224,y+220,100,28,"IGNORE",C'50,65,80');
   PanelBtn(PFX "review", x+8,y+258,316,28,"RUN REVIEW NOW",C'50,65,80');
   ChartRedraw();
  }

void PanelDestroy(){ ObjectsDeleteAll(0,PFX); }

void PanelUpdate()
  {
   if(!InpShowPanel) return;
   SGBStrategyId id=g_lc.Id();
   SGBHealth h=g_lc.Health();
   SGBRecommendation rec=g_lc.LastRecommendation();
   SGBGateResult g=g_lc.Gates();
   SGBParams live=g_lc.AI().LiveParams();

   string st_color = h.color;
   color cstat = clrLime;
   if(st_color=="YELLOW") cstat=clrGold;
   if(st_color=="RED") cstat=clrTomato;

   PanelLab(PFX "L1", InpPanelX+8, InpPanelY+28,
            StringFormat("%s / %s  V%d  |  Auth %s",
                         id.venue, id.symbol, id.version, GB_AuthToString(g_lc.Authority())),
            8, C'220,228,235');
   PanelLab(PFX "L2", InpPanelX+8, InpPanelY+46,
            StringFormat("Status %-10s  Health %d",
                         GB_LifecycleToString(g_lc.Lifecycle()), h.overall),
            8, cstat);
   PanelLab(PFX "L3", InpPanelX+8, InpPanelY+64,
            StringFormat("Perf %d  Risk %d  Exec %d  Stab %d  Regime %d",
                         h.performance,h.risk,h.execution,h.stability,h.regime_fit),
            8, C'220,228,235');
   PanelLab(PFX "L4", InpPanelX+8, InpPanelY+82,
            StringFormat("Live Z entry=%.1f exit=%.1f risk=%.1f%%",
                         live.entry_z, live.exit_z, live.max_risk_pct),
            8, C'220,228,235');

   string sh="Shadow OFF";
   if(g_lc.Shadow().Active())
      sh=StringFormat("Shadow %s  hypPL=%.0f  n=%d",
                      g_lc.Shadow().Label(),
                      g_lc.Shadow().ShadowPL(),
                      g_lc.Shadow().HypotheticalTrades());
   PanelLab(PFX "L5", InpPanelX+8, InpPanelY+100, sh, 8, C'180,200,220');

   PanelLab(PFX "L6", InpPanelX+8, InpPanelY+118,
            StringFormat("AI: %s | %s", GB_ActionToString(rec.action), rec.title),
            8, clrGold);

   string issue = rec.main_issue;
   if(StringLen(issue)>48) issue=StringSubstr(issue,0,48)+"...";
   PanelLab(PFX "L7", InpPanelX+8, InpPanelY+148,
            StringLen(issue)>0 ? ("Issue: "+issue) : "Issue: (none)",
            8, C'200,210,220');

   PanelLab(PFX "L8", InpPanelX+8, InpPanelY+166,
            StringFormat("Gates AI=%s Risk=%s Exec=%s",
                         g.ai_why, g.risk_why, g.exec_why),
            8, C'180,190,200');

   bool pend = g_lc.Approval().HasPending();
   PanelLab(PFX "L9", InpPanelX+8, InpPanelY+184,
            pend ? "Pending HUMAN approval" : "No pending approval",
            8, pend ? clrOrange : clrSilver);

   ChartRedraw();
  }

//------------------------------------------------------------------
void SeedDemoMetrics()
  {
   // 演示：注入一窗「健康」再一窗「恶化」，触发建议
   static int phase=0;
   phase++;
   CGBPerformance *p = g_lc.Perf();
   CGBExecution *e = g_lc.Exec();

   if(phase==1)
     {
      // 好窗口
      for(int i=0;i<30;i++)
         p.RecordTrade(40 + (i%5)*5, 0.8, 2.5);
      p.SetRiskMetrics(1.6, 0.5);
      SGBExecution ex;
      ZeroMemory(ex);
      ex.avg_slippage_pct=0.018;
      ex.avg_latency_ms=82;
      ex.fees=210;
      ex.funding=430;
      ex.gross_edge_pct=0.12;
      ex.cost_pct=0.06;
      e.Update(ex);
      g_lc.UpdateMarket(45, 80, 25, 0.12, 0.06);
      p.SnapshotAsPrevious();
     }
   else
     {
      // 恶化窗口：PF 下降 + 滑点上升 → REDUCE 或调查
      p.ResetCurrent(); // 保留 Previous 对照窗
      for(int i=0;i<25;i++)
         p.RecordTrade((i%3==0)? 30 : -25, 1.4, 2.0);
      p.SetRiskMetrics(3.2, 1.1);
      SGBExecution ex;
      ZeroMemory(ex);
      ex.avg_slippage_pct=0.08;
      ex.avg_latency_ms=160;
      ex.fees=280;
      ex.funding=50;
      ex.gross_edge_pct=0.10;
      ex.cost_pct=0.09;
      e.Update(ex);
      g_lc.UpdateMarket(70, 55, 5, 0.10, 0.09);
     }
  }

//------------------------------------------------------------------
int OnInit()
  {
   SGBStrategyId id;
   id.venue = InpVenue;
   id.symbol = InpSymbolTag;
   id.name = InpStratName;
   id.version = 1;

   SGBHardLimits hard;
   ZeroMemory(hard);
   hard.max_portfolio_dd_pct = InpMaxPortfolioDD;
   hard.max_daily_loss_pct   = InpMaxDailyLoss;
   hard.max_positions        = InpMaxPositions;
   hard.max_position_notional= 0;
   hard.emergency_stop       = false;

   SGBParams prm;
   ZeroMemory(prm);
   prm.entry_z = InpEntryZ;
   prm.exit_z  = InpExitZ;
   prm.stop_z  = InpStopZ;
   prm.max_risk_pct = InpMaxRiskPct;
   prm.lot_spot = 0.10;
   prm.lookback = 60;
   prm.max_hold_bars = 48;

   g_lc.Init(id, hard, prm, GB_AUTH_ASSISTED);

   if(InpShowPanel) PanelCreate();

   if(InpSimulateFeeds)
     {
      SeedDemoMetrics(); // phase1 healthy
      g_lc.RunReview(true);
      SeedDemoMetrics(); // phase2 worse — next review will see prev vs cur
     }

   Print(g_lc.HealthReport());
   PanelUpdate();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   PanelDestroy();
   Comment("");
  }

void OnTick()
  {
   // 处理按钮
   if(g_btn_approve)
     {
      g_btn_approve=false;
      g_lc.Approval().Approve();
      g_lc.ProcessApprovals();
     }
   if(g_btn_reject)
     {
      g_btn_reject=false;
      g_lc.Approval().Reject();
     }
   if(g_btn_ignore)
     {
      g_btn_ignore=false;
      g_lc.Approval().Ignore();
     }
   if(g_btn_review)
     {
      g_btn_review=false;
      if(InpSimulateFeeds) SeedDemoMetrics();
      g_lc.RunReview(true);
      Print(g_lc.HealthReport());
     }

   // 定时复盘
   if(g_last_review_tick==0) g_last_review_tick=TimeCurrent();
   if(TimeCurrent()-g_last_review_tick >= InpReviewSeconds)
     {
      g_last_review_tick=TimeCurrent();
      g_lc.RunReview(true);
     }

   // 演示三道闸门探测（不下单）
   string why;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   g_lc.CanOpenNewTrade(eq, 0, 1000, why);

   g_lc.ProcessApprovals();
   PanelUpdate();
   Comment(g_lc.HealthReport(), "\nGate: ", why);
  }

void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
  {
   if(id!=CHARTEVENT_OBJECT_CLICK) return;
   if(StringFind(sparam,PFX)!=0) return;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   if(sparam==PFX "approve") g_btn_approve=true;
   if(sparam==PFX "reject")  g_btn_reject=true;
   if(sparam==PFX "ignore")  g_btn_ignore=true;
   if(sparam==PFX "review")  g_btn_review=true;
  }
//+------------------------------------------------------------------+
