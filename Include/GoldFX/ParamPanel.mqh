//+------------------------------------------------------------------+
//| ParamPanel.mqh — 图表参数面板（人工选择模式 / 调参 / 一键操作）     |
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
#define GF_BTN_APPLY       GF_PREFIX "btn_apply"
#define GF_BTN_CLOSE       GF_PREFIX "btn_close"
#define GF_BTN_REFRESH     GF_PREFIX "btn_refresh"
#define GF_EDIT_ADX_TREND  GF_PREFIX "ed_adx_t"
#define GF_EDIT_ADX_RANGE  GF_PREFIX "ed_adx_r"
#define GF_EDIT_RISK       GF_PREFIX "ed_risk"
#define GF_EDIT_LOT        GF_PREFIX "ed_lot"
#define GF_EDIT_SL_T       GF_PREFIX "ed_sl_t"
#define GF_EDIT_TP_T       GF_PREFIX "ed_tp_t"
#define GF_EDIT_RSI_OS     GF_PREFIX "ed_rsi_os"
#define GF_EDIT_RSI_OB     GF_PREFIX "ed_rsi_ob"
#define GF_LBL_STATUS      GF_PREFIX "lbl_status"
#define GF_LBL_TITLE       GF_PREFIX "lbl_title"
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

   void ObjDelete(const string name)
     {
      ObjectDelete(m_chart, name);
     }

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
      ObjectSetInteger(m_chart, name, OBJPROP_FONTSIZE, 9);
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

   string EditText(const string name) const
     {
      return ObjectGetString(m_chart, name, OBJPROP_TEXT);
     }

   double EditDouble(const string name, const double fallback) const
     {
      string s = EditText(name);
      StringReplace(s, ",", ".");
      double v = StringToDouble(s);
      if(v == 0.0 && StringFind(s, "0") < 0)
         return fallback;
      return v;
     }

   void HighlightModeButtons(void)
     {
      const color on  = m_accent;
      const color off = m_btn;
      ObjectSetInteger(m_chart, GF_BTN_AUTO,  OBJPROP_BGCOLOR, (m_params.run_mode == MODE_AUTO)  ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_TREND, OBJPROP_BGCOLOR, (m_params.run_mode == MODE_TREND) ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_RANGE, OBJPROP_BGCOLOR, (m_params.run_mode == MODE_RANGE) ? on : off);
      ObjectSetInteger(m_chart, GF_BTN_FLAT,  OBJPROP_BGCOLOR, (m_params.run_mode == MODE_FLAT)  ? on : off);
     }

   void SyncEditsFromParams(void)
     {
      ObjectSetString(m_chart, GF_EDIT_ADX_TREND, OBJPROP_TEXT, DoubleToString(m_params.adx_trend_threshold, 1));
      ObjectSetString(m_chart, GF_EDIT_ADX_RANGE, OBJPROP_TEXT, DoubleToString(m_params.adx_range_threshold, 1));
      ObjectSetString(m_chart, GF_EDIT_RISK,      OBJPROP_TEXT, DoubleToString(m_params.risk_percent, 2));
      ObjectSetString(m_chart, GF_EDIT_LOT,       OBJPROP_TEXT, DoubleToString(m_params.fixed_lot, 2));
      ObjectSetString(m_chart, GF_EDIT_SL_T,      OBJPROP_TEXT, DoubleToString(m_params.trend_sl_atr_mult, 2));
      ObjectSetString(m_chart, GF_EDIT_TP_T,      OBJPROP_TEXT, DoubleToString(m_params.trend_tp_atr_mult, 2));
      ObjectSetString(m_chart, GF_EDIT_RSI_OS,    OBJPROP_TEXT, DoubleToString(m_params.rsi_oversold, 1));
      ObjectSetString(m_chart, GF_EDIT_RSI_OB,    OBJPROP_TEXT, DoubleToString(m_params.rsi_overbought, 1));
     }

public:
                     CParamPanel(void)
                       : m_chart(0),
                         m_x(10),
                         m_y(30),
                         m_w(280),
                         m_bg(C'24,32,40'),
                         m_fg(C'220,228,235'),
                         m_accent(C'38,140,110'),
                         m_btn(C'55,70,85'),
                         m_status_line(""),
                         m_apply_requested(false),
                         m_close_requested(false),
                         m_mode_changed(false),
                         m_refresh_requested(false)
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
      const int row = 24;
      const int h   = 320;
      CreateRect(GF_BG, m_x, m_y, m_w, h, m_bg);
      CreateLabel(GF_LBL_TITLE, m_x + pad, m_y + 6, "GoldFX 日内 · 参数面板", 10);

      int cy = m_y + 32;
      CreateLabel(GF_PREFIX "lbl_mode", m_x + pad, cy, "运行模式:");
      cy += row;
      const int bw = 60;
      CreateButton(GF_BTN_AUTO,  m_x + pad, cy, bw, 22, "自动", m_btn);
      CreateButton(GF_BTN_TREND, m_x + pad + 66, cy, bw, 22, "趋势", m_btn);
      CreateButton(GF_BTN_RANGE, m_x + pad + 132, cy, bw, 22, "震荡", m_btn);
      CreateButton(GF_BTN_FLAT,  m_x + pad + 198, cy, bw, 22, "观察", m_btn);

      cy += row + 6;
      CreateLabel(GF_PREFIX "lbl_adx", m_x + pad, cy, "ADX趋势/震荡阈:");
      CreateEdit(GF_EDIT_ADX_TREND, m_x + 150, cy - 2, 50, 20, "");
      CreateEdit(GF_EDIT_ADX_RANGE, m_x + 210, cy - 2, 50, 20, "");

      cy += row;
      CreateLabel(GF_PREFIX "lbl_risk", m_x + pad, cy, "风险%/手数:");
      CreateEdit(GF_EDIT_RISK, m_x + 150, cy - 2, 50, 20, "");
      CreateEdit(GF_EDIT_LOT,  m_x + 210, cy - 2, 50, 20, "");

      cy += row;
      CreateLabel(GF_PREFIX "lbl_tr", m_x + pad, cy, "趋势 SL/TP×ATR:");
      CreateEdit(GF_EDIT_SL_T, m_x + 150, cy - 2, 50, 20, "");
      CreateEdit(GF_EDIT_TP_T, m_x + 210, cy - 2, 50, 20, "");

      cy += row;
      CreateLabel(GF_PREFIX "lbl_rsi", m_x + pad, cy, "RSI 超卖/超买:");
      CreateEdit(GF_EDIT_RSI_OS, m_x + 150, cy - 2, 50, 20, "");
      CreateEdit(GF_EDIT_RSI_OB, m_x + 210, cy - 2, 50, 20, "");

      cy += row + 8;
      CreateButton(GF_BTN_APPLY,   m_x + pad, cy, 80, 26, "应用参数", m_accent);
      CreateButton(GF_BTN_REFRESH, m_x + pad + 90, cy, 80, 26, "刷新识别", m_btn);
      CreateButton(GF_BTN_CLOSE,   m_x + pad + 180, cy, 80, 26, "全部平仓", C'160,60,50');

      cy += 36;
      CreateLabel(GF_LBL_STATUS, m_x + pad, cy, "状态: 初始化", 8);

      SyncEditsFromParams();
      HighlightModeButtons();
      ChartRedraw(m_chart);
      return true;
     }

   void Destroy(void)
     {
      ObjectsDeleteAll(m_chart, GF_PREFIX);
     }

   SRuntimeParams Params(void) const { return m_params; }

   void SetParams(const SRuntimeParams &p)
     {
      m_params = p;
      SyncEditsFromParams();
      HighlightModeButtons();
     }

   void SetStatus(const string line)
     {
      m_status_line = line;
      // 多行状态用短文本
      string short_line = line;
      if(StringLen(short_line) > 42)
         short_line = StringSubstr(short_line, 0, 42) + "...";
      ObjectSetString(m_chart, GF_LBL_STATUS, OBJPROP_TEXT, short_line);
      ChartRedraw(m_chart);
     }

   bool ConsumeApplyRequest(void)
     {
      if(!m_apply_requested)
         return false;
      m_apply_requested = false;
      return true;
     }

   bool ConsumeCloseRequest(void)
     {
      if(!m_close_requested)
         return false;
      m_close_requested = false;
      return true;
     }

   bool ConsumeModeChanged(void)
     {
      if(!m_mode_changed)
         return false;
      m_mode_changed = false;
      return true;
     }

   bool ConsumeRefreshRequest(void)
     {
      if(!m_refresh_requested)
         return false;
      m_refresh_requested = false;
      return true;
     }

   // 面板事件：返回 true 表示需要主程序刷新状态显示
   bool HandleChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
     {
      if(id != CHARTEVENT_OBJECT_CLICK)
         return false;
      if(StringFind(sparam, GF_PREFIX) != 0)
         return false;

      // 复位按钮状态
      ObjectSetInteger(m_chart, sparam, OBJPROP_STATE, false);

      if(sparam == GF_BTN_AUTO)
        {
         m_params.run_mode = MODE_AUTO;
         m_mode_changed = true;
         HighlightModeButtons();
         return true;
        }
      if(sparam == GF_BTN_TREND)
        {
         m_params.run_mode = MODE_TREND;
         m_mode_changed = true;
         HighlightModeButtons();
         return true;
        }
      if(sparam == GF_BTN_RANGE)
        {
         m_params.run_mode = MODE_RANGE;
         m_mode_changed = true;
         HighlightModeButtons();
         return true;
        }
      if(sparam == GF_BTN_FLAT)
        {
         m_params.run_mode = MODE_FLAT;
         m_mode_changed = true;
         HighlightModeButtons();
         return true;
        }
      if(sparam == GF_BTN_APPLY)
        {
         ReadEditsIntoParams();
         m_apply_requested = true;
         return true;
        }
      if(sparam == GF_BTN_CLOSE)
        {
         m_close_requested = true;
         return true;
        }
      if(sparam == GF_BTN_REFRESH)
        {
         m_refresh_requested = true;
         return true;
        }
      return false;
     }

   void ReadEditsIntoParams(void)
     {
      m_params.adx_trend_threshold = MathMax(1.0, EditDouble(GF_EDIT_ADX_TREND, m_params.adx_trend_threshold));
      m_params.adx_range_threshold = MathMax(1.0, EditDouble(GF_EDIT_ADX_RANGE, m_params.adx_range_threshold));
      if(m_params.adx_range_threshold > m_params.adx_trend_threshold)
         m_params.adx_range_threshold = m_params.adx_trend_threshold;
      m_params.risk_percent        = MathMax(0.01, EditDouble(GF_EDIT_RISK, m_params.risk_percent));
      m_params.fixed_lot           = MathMax(0.01, EditDouble(GF_EDIT_LOT, m_params.fixed_lot));
      m_params.trend_sl_atr_mult   = MathMax(0.2, EditDouble(GF_EDIT_SL_T, m_params.trend_sl_atr_mult));
      m_params.trend_tp_atr_mult   = MathMax(0.2, EditDouble(GF_EDIT_TP_T, m_params.trend_tp_atr_mult));
      m_params.rsi_oversold        = MathMax(1.0, EditDouble(GF_EDIT_RSI_OS, m_params.rsi_oversold));
      m_params.rsi_overbought      = MathMin(99.0, EditDouble(GF_EDIT_RSI_OB, m_params.rsi_overbought));
      if(m_params.rsi_oversold >= m_params.rsi_overbought)
        {
         m_params.rsi_oversold   = 30.0;
         m_params.rsi_overbought = 70.0;
        }
     }
  };

#endif
//+------------------------------------------------------------------+
