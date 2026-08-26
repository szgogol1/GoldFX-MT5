//+------------------------------------------------------------------+
//| ParamPanel.mqh — 模式 / 八档风险 / 资金管理 / 热调参面板            |
//+------------------------------------------------------------------+
#property copyright "GoldFX Intraday Framework"
#property strict

#ifndef GOLDFX_PARAM_PANEL_MQH
#define GOLDFX_PARAM_PANEL_MQH

#include "Common.mqh"

#define GF_PREFIX          "GFXpanel_"
#define GF_BTN_AUTO        GF_PREFIX "btn_auto"
#define GF_BTN_TREND       GF_PREFIX "btn_trend"
#define GF_BTN_RANGE       GF_PREFIX "btn_range"
#define GF_BTN_FLAT        GF_PREFIX "btn_flat"
#define GF_BTN_MM          GF_PREFIX "btn_mm"
#define GF_BTN_APPLY       GF_PREFIX "btn_apply"
#define GF_BTN_CLOSE       GF_PREFIX "btn_close"
#define GF_BTN_REFRESH     GF_PREFIX "btn_refresh"
#define GF_EDIT_ADX_TREND  GF_PREFIX "ed_adx_t"
#define GF_EDIT_ADX_RANGE  GF_PREFIX "ed_adx_r"
#define GF_EDIT_SPREAD     GF_PREFIX "ed_spread"
#define GF_EDIT_QUALITY    GF_PREFIX "ed_qual"
#define GF_EDIT_SL_T       GF_PREFIX "ed_sl_t"
#define GF_EDIT_TP_T       GF_PREFIX "ed_tp_t"
#define GF_LBL_STATUS      GF_PREFIX "lbl_status"
#define GF_LBL_TITLE       GF_PREFIX "lbl_title"
#define GF_LBL_RISKINFO    GF_PREFIX "lbl_riskinfo"
#define GF_BG              GF_PREFIX "bg"

class CParamPanel
  {
private:
   long              m_chart;
   int               m_x;
   int               m_y;
   int               m_w;
   color             m_bg;
   color             m_fg;
   color             m_accent;
   color             m_btn;
   SRuntimeParams    m_params;
   string            m_status_line;
   bool              m_apply_requested;
   bool              m_close_requested;
   bool              m_mode_changed;
   bool              m_refresh_requested;
   bool              m_risk_changed;

   void ObjDelete(const string name) { ObjectDelete(m_chart, name); }

   bool CreateRect(const string name, const int x, const int y, const int w, const int h, const color clr)
     {
      ObjDelete(name);
      if(!ObjectCreate(m_chart, name, OBJ_RECTANGLE_LABEL, 0, 0, 0))
         return false;
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart, name, OBJPROP_YSIZE, h);
      ObjectSetInteger(m_chart, name, OBJPROP_BGCOLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chart, name, OBJPROP_BACK, false);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
      return true;
     }

   bool CreateLabel(const string name, const int x, const int y, const string text, const int font_size = 9)
     {
      ObjDelete(name);
      if(!ObjectCreate(m_chart, name, OBJ_LABEL, 0, 0, 0))
         return false;
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE, y);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, font_size);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, m_fg);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
      return true;
     }

   bool CreateButton(const string name, const int x, const int y, const int w, const int h,
                     const string text, const color bg)
     {
      ObjDelete(name);
      if(!ObjectCreate(m_chart, name, OBJ_BUTTON, 0, 0, 0))
         return false;
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart, name, OBJPROP_YSIZE, h);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, 8);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clrWhite);
      ObjectSetInteger(m_chart, name, OBJPROP_BGCOLOR, bg);
      ObjectSetInteger(m_chart, name, OBJPROP_BORDER_COLOR, clrDimGray);
      ObjectSetInteger(m_chart, name, OBJPROP_STATE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
      return true;
     }

   bool CreateEdit(const string name, const int x, const int y, const int w, const int h, const string text)
     {
      ObjDelete(name);
      if(!ObjectCreate(m_chart, name, OBJ_EDIT, 0, 0, 0))
         return false;
      ObjectSetInteger(m_chart, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(m_chart, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(m_chart, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(m_chart, name, OBJPROP_XSIZE, w);
      ObjectSetInteger(m_chart, name, OBJPROP_YSIZE, h);
      ObjectSetString(m_chart, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chart, name, OBJPROP_FONT, "Consolas");
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(m_chart, name, OBJPROP_COLOR, clrBlack);
      ObjectSetInteger(m_chart, name, OBJPROP_BGCOLOR, clrWhite);
      ObjectSetInteger(m_chart, name, OBJPROP_BORDER_COLOR, clrSilver);
      ObjectSetInteger(m_chart, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(m_chart, name, OBJPROP_READONLY, false);
      ObjectSetInteger(m_chart, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chart, name, OBJPROP_HIDDEN, true);
      return true;
     }

   string RiskBtnName(const int level) const
     {
      return StringFormat("%sbtn_r%d", GF_PREFIX, level);
     }

   double EditDouble(const string name, const double fallback) const
     {
      string s = ObjectGetString(m_chart, name, OBJPROP_TEXT);
      StringReplace(s, ",", ".");
      double v = StringToDouble(s);
      if(v == 0.0 && StringFind(s, "0") < 0)
         return fallback;
      return v;
     }

   void HighlightModeButtons(void)
     {
      const color on = m_accent, off = m_btn;
      ObjectSetInteger(m_chart, GF_BTN_AUTO,  OBJPROP_BGCOLOR, (m_params.run_mode == MODE_AUTO)  ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_TREND, OBJPROP_BGCOLOR, (m_params.run_mode == MODE_TREND) ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_RANGE, OBJPROP_BGCOLOR, (m_params.run_mode == MODE_RANGE) ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_FLAT,  OBJPROP_BGCOLOR, (m_params.run_mode == MODE_FLAT)  ? on : off);
     }

   void HighlightRiskButtons(void)
     {
      for(int i = 1; i <= 8; ++i)
        {
         const string n = RiskBtnName(i);
         ObjectSetInteger(m_chart, n, OBJPROP_BGCOLOR,
                          ((int)m_params.risk_level == i) ? m_accent : m_btn);
        }
     }

   void SyncRiskInfoLabel(void)
     {
      const string t = StringFormat("资金=%s | 档=%s | 风险%%=%.2f | 日限%.1f%% | 回撤%.1f%%",
                                    MoneyModeToString(m_params.money_mode),
                                    RiskLevelToString(m_params.risk_level),
                                    m_params.risk_percent,
                                    m_params.max_daily_loss_pct,
                                    m_params.max_equity_dd_pct);
      ObjectSetString(m_chart, GF_LBL_RISKINFO, OBJPROP_TEXT, t);
      ObjectSetString(m_chart, GF_BTN_MM, OBJPROP_TEXT, MoneyModeToString(m_params.money_mode));
     }

   void SyncEditsFromParams(void)
     {
      ObjectSetString(m_chart, GF_EDIT_ADX_TREND, OBJPROP_TEXT, DoubleToString(m_params.adx_trend_threshold, 1));
      ObjectSetString(m_chart, GF_EDIT_ADX_RANGE, OBJPROP_TEXT, DoubleToString(m_params.adx_range_threshold, 1));
      ObjectSetString(m_chart, GF_EDIT_SPREAD,    OBJPROP_TEXT, DoubleToString(m_params.max_spread_price, 2));
      ObjectSetString(m_chart, GF_EDIT_QUALITY,   OBJPROP_TEXT, IntegerToString(m_params.min_quality_score));
      ObjectSetString(m_chart, GF_EDIT_SL_T,      OBJPROP_TEXT, DoubleToString(m_params.trend_sl_atr_mult, 2));
      ObjectSetString(m_chart, GF_EDIT_TP_T,      OBJPROP_TEXT, DoubleToString(m_params.trend_tp_atr_mult, 2));
      SyncRiskInfoLabel();
     }

   void CycleMoneyMode(void)
     {
      int m = (int)m_params.money_mode;
      m = (m + 1) % 4;
      m_params.money_mode = (ENUM_MONEY_MODE)m;
      if(m_params.money_mode == MM_AUTO_LEVEL)
         ApplyRiskLevelToParams(m_params);
      SyncRiskInfoLabel();
      m_risk_changed = true;
     }

public:
                     CParamPanel(void)
                       : m_chart(0), m_x(8), m_y(24), m_w(300),
                         m_bg(C'22,30,38'), m_fg(C'220,228,235'),
                         m_accent(C'38,140,110'), m_btn(C'55,70,85'),
                         m_status_line(""),
                         m_apply_requested(false), m_close_requested(false),
                         m_mode_changed(false), m_refresh_requested(false),
                         m_risk_changed(false)
                     {
                      ZeroMemory(m_params);
                     }

                    ~CParamPanel(void) { Destroy(); }

   bool Create(const long chart_id, const SRuntimeParams &p)
     {
      m_chart  = chart_id;
      m_params = p;
      Destroy();

      const int pad = 8;
      const int row = 22;
      CreateRect(GF_BG, m_x, m_y, m_w, 390, m_bg);
      CreateLabel(GF_LBL_TITLE, m_x + pad, m_y + 6, "GoldFX Selective · 控制台", 10);

      int cy = m_y + 30;
      CreateLabel(GF_PREFIX "lbl_mode", m_x + pad, cy, "运行模式");
      cy += row;
      CreateButton(GF_BTN_AUTO,  m_x + pad, cy, 66, 20, "自动", m_btn);
      CreateButton(GF_BTN_TREND, m_x + pad + 70, cy, 66, 20, "趋势", m_btn);
      CreateButton(GF_BTN_RANGE, m_x + pad + 140, cy, 66, 20, "震荡", m_btn);
      CreateButton(GF_BTN_FLAT,  m_x + pad + 210, cy, 66, 20, "观察", m_btn);

      cy += row + 4;
      CreateLabel(GF_PREFIX "lbl_rl", m_x + pad, cy, "风险档位 R1-R8（无网格/无马丁）");
      cy += row;
      for(int i = 1; i <= 8; ++i)
        {
         const int bx = m_x + pad + (i - 1) * 34;
         CreateButton(RiskBtnName(i), bx, cy, 32, 20, IntegerToString(i), m_btn);
        }

      cy += row + 4;
      CreateLabel(GF_PREFIX "lbl_mm", m_x + pad, cy, "资金管理:");
      CreateButton(GF_BTN_MM, m_x + 90, cy - 2, 190, 20, MoneyModeToString(m_params.money_mode), m_btn);

      cy += row + 2;
      CreateLabel(GF_LBL_RISKINFO, m_x + pad, cy, "", 8);

      cy += row;
      CreateLabel(GF_PREFIX "lbl_adx", m_x + pad, cy, "ADX趋势/震荡:");
      CreateEdit(GF_EDIT_ADX_TREND, m_x + 150, cy - 2, 55, 18, "");
      CreateEdit(GF_EDIT_ADX_RANGE, m_x + 215, cy - 2, 55, 18, "");

      cy += row;
      CreateLabel(GF_PREFIX "lbl_sel", m_x + pad, cy, "点差上限/质量分:");
      CreateEdit(GF_EDIT_SPREAD,  m_x + 150, cy - 2, 55, 18, "");
      CreateEdit(GF_EDIT_QUALITY, m_x + 215, cy - 2, 55, 18, "");

      cy += row;
      CreateLabel(GF_PREFIX "lbl_tr", m_x + pad, cy, "趋势SL/TP×ATR:");
      CreateEdit(GF_EDIT_SL_T, m_x + 150, cy - 2, 55, 18, "");
      CreateEdit(GF_EDIT_TP_T, m_x + 215, cy - 2, 55, 18, "");

      cy += row + 6;
      CreateButton(GF_BTN_APPLY,   m_x + pad, cy, 88, 24, "应用参数", m_accent);
      CreateButton(GF_BTN_REFRESH, m_x + pad + 96, cy, 88, 24, "刷新识别", m_btn);
      CreateButton(GF_BTN_CLOSE,   m_x + pad + 192, cy, 88, 24, "全部平仓", C'160,60,50');

      cy += 32;
      CreateLabel(GF_LBL_STATUS, m_x + pad, cy, "状态: 初始化", 8);

      SyncEditsFromParams();
      HighlightModeButtons();
      HighlightRiskButtons();
      ChartRedraw(m_chart);
      return true;
     }

   void Destroy(void) { ObjectsDeleteAll(m_chart, GF_PREFIX); }

   SRuntimeParams Params(void) const { return m_params; }

   void SetParams(const SRuntimeParams &p)
     {
      m_params = p;
      SyncEditsFromParams();
      HighlightModeButtons();
      HighlightRiskButtons();
     }

   void SetStatus(const string line)
     {
      m_status_line = line;
      string short_line = line;
      if(StringLen(short_line) > 46)
         short_line = StringSubstr(short_line, 0, 46) + "...";
      ObjectSetString(m_chart, GF_LBL_STATUS, OBJPROP_TEXT, short_line);
      ChartRedraw(m_chart);
     }

   bool ConsumeApplyRequest(void)   { if(!m_apply_requested) return false; m_apply_requested=false; return true; }
   bool ConsumeCloseRequest(void)   { if(!m_close_requested) return false; m_close_requested=false; return true; }
   bool ConsumeModeChanged(void)    { if(!m_mode_changed) return false; m_mode_changed=false; return true; }
   bool ConsumeRefreshRequest(void) { if(!m_refresh_requested) return false; m_refresh_requested=false; return true; }
   bool ConsumeRiskChanged(void)    { if(!m_risk_changed) return false; m_risk_changed=false; return true; }

   bool HandleChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
     {
      if(id != CHARTEVENT_OBJECT_CLICK)
         return false;
      if(StringFind(sparam, GF_PREFIX) != 0)
         return false;
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(sparam == GF_BTN_AUTO)  { m_params.run_mode = MODE_AUTO;  m_mode_changed=true; HighlightModeButtons(); return true; }
      if(sparam == GF_BTN_TREND) { m_params.run_mode = MODE_TREND; m_mode_changed=true; HighlightModeButtons(); return true; }
      if(sparam == GF_BTN_RANGE) { m_params.run_mode = MODE_RANGE; m_mode_changed=true; HighlightModeButtons(); return true; }
      if(sparam == GF_BTN_FLAT)  { m_params.run_mode = MODE_FLAT;  m_mode_changed=true; HighlightModeButtons(); return true; }

      if(sparam == GF_BTN_MM)
        {
         CycleMoneyMode();
         return true;
        }

      for(int i = 1; i <= 8; ++i)
        {
         if(sparam == RiskBtnName(i))
           {
            m_params.risk_level = (ENUM_RISK_LEVEL)i;
            ApplyRiskLevelToParams(m_params);
            HighlightRiskButtons();
            SyncEditsFromParams();
            m_risk_changed = true;
            return true;
           }
        }

      if(sparam == GF_BTN_APPLY)   { ReadEditsIntoParams(); m_apply_requested = true; return true; }
      if(sparam == GF_BTN_CLOSE)   { m_close_requested = true; return true; }
      if(sparam == GF_BTN_REFRESH) { m_refresh_requested = true; return true; }
      return false;
     }

   void ReadEditsIntoParams(void)
     {
      m_params.adx_trend_threshold = MathMax(1.0, EditDouble(GF_EDIT_ADX_TREND, m_params.adx_trend_threshold));
      m_params.adx_range_threshold = MathMax(1.0, EditDouble(GF_EDIT_ADX_RANGE, m_params.adx_range_threshold));
      if(m_params.adx_range_threshold > m_params.adx_trend_threshold)
         m_params.adx_range_threshold = m_params.adx_trend_threshold;
      m_params.max_spread_price  = MathMax(0.0, EditDouble(GF_EDIT_SPREAD, m_params.max_spread_price));
      m_params.min_quality_score = (int)MathMax(0, EditDouble(GF_EDIT_QUALITY, m_params.min_quality_score));
      m_params.trend_sl_atr_mult = MathMax(0.2, EditDouble(GF_EDIT_SL_T, m_params.trend_sl_atr_mult));
      m_params.trend_tp_atr_mult = MathMax(0.2, EditDouble(GF_EDIT_TP_T, m_params.trend_tp_atr_mult));
      m_params.allow_martingale  = false;
     }
  };

#endif
//+------------------------------------------------------------------+
