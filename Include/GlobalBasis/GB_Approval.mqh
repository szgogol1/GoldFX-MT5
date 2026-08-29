//+------------------------------------------------------------------+
//| GB_Approval.mqh — 人工批准闸（ASSISTED 升级唯一入口）               |
//+------------------------------------------------------------------+
#property copyright "GlobalBasis Framework"
#property strict

#ifndef GLOBALBASIS_APPROVAL_MQH
#define GLOBALBASIS_APPROVAL_MQH

#include "GB_Types.mqh"

enum ENUM_GB_APPROVAL_STATE
  {
   GB_APPR_NONE     = 0,
   GB_APPR_PENDING  = 1,
   GB_APPR_APPROVED = 2,
   GB_APPR_REJECTED = 3,
   GB_APPR_IGNORED  = 4
  };

class CGBApproval
  {
private:
   ENUM_GB_APPROVAL_STATE m_state;
   SGBRecommendation      m_pending;
   bool                   m_has_pending;

public:
                     CGBApproval(void)
                       : m_state(GB_APPR_NONE), m_has_pending(false)
                     {
                      ZeroMemory(m_pending);
                     }

   bool HasPending(void) const { return m_has_pending && m_state == GB_APPR_PENDING; }
   ENUM_GB_APPROVAL_STATE State(void) const { return m_state; }
   SGBRecommendation Pending(void) const { return m_pending; }

   // AI 提交建议（不自动执行）
   void Submit(const SGBRecommendation &rec)
     {
      if(rec.action == GB_ACT_KEEP)
        {
         // KEEP 不占批准队列
         return;
        }
      m_pending = rec;
      m_has_pending = true;
      m_state = GB_APPR_PENDING;
     }

   void Approve(void)
     {
      if(!m_has_pending) return;
      m_state = GB_APPR_APPROVED;
     }

   void Reject(void)
     {
      if(!m_has_pending) return;
      m_state = GB_APPR_REJECTED;
      m_has_pending = false;
     }

   void Ignore(void)
     {
      if(!m_has_pending) return;
      m_state = GB_APPR_IGNORED;
      m_has_pending = false;
     }

   // 消费一次批准结果；若 APPROVED 返回 true 并清空 pending 标志
   bool ConsumeApproved(SGBRecommendation &out)
     {
      if(m_state != GB_APPR_APPROVED || !m_has_pending)
         return false;
      out = m_pending;
      m_has_pending = false;
      m_state = GB_APPR_NONE;
      return true;
     }
  };

#endif
//+------------------------------------------------------------------+
