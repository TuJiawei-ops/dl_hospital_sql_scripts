/*
================================================================================
  Relative Path : sqlserver/patches/20260915_patch_update_dim_work_calendar_type_coeff.sql
  脚本名称: 20260915_patch_update_dim_work_calendar_type_coeff.sql
  脚本类型: DML 数据刷洗补丁（幂等可重复执行，非表结构 DDL）
  目标表  : dbo.[DIM_WORK_CALENDAR]
  业务说明: 依据基础物理列（IS_MAKEUP_WORK / IS_HOLIDAY / WEEKDAY_CODE）逐级判定，
            将当前填充为「待确认」的 [DAY_TYPE_CODE] / [DAY_TYPE_NAME] 与
            默认恒为 1 的 [PERF_COEFF] 一次性刷洗为符合绩效核算口径的正确取值。
================================================================================
  【判定优先级 —— 严格有序，命中即止】
  优先级 1  调休补班 (MAKEUP)  : IS_MAKEUP_WORK = 1
                                  → DAY_TYPE_CODE = 'MAKEUP' / DAY_TYPE_NAME = N'调休补班' / PERF_COEFF = 1.00000000
  优先级 2  法定节假日 (HOLIDAY): IS_HOLIDAY = 1（且非补班）
                                  → DAY_TYPE_CODE = 'HOLIDAY' / DAY_TYPE_NAME = N'法定节假日' / PERF_COEFF = 2.00000000
  优先级 3  普通周末 (WEEKEND) : WEEKDAY_CODE IN (6, 7)（且非补班、非节假日）
                                  → DAY_TYPE_CODE = 'WEEKEND' / DAY_TYPE_NAME = N'普通周末' / PERF_COEFF = 2.00000000
  优先级 4  正常工作日 (WORKDAY): 其余全部情况（WEEKDAY_CODE 在 1~5 且非补班、非节假日）
                                  → DAY_TYPE_CODE = 'WORKDAY' / DAY_TYPE_NAME = N'正常工作日' / PERF_COEFF = 1.00000000
--------------------------------------------------------------------------------
  【优先级设计动因 —— 为什么补班必须压在周末与节假日之前】
  调休补班日天然具备「落在周末」的物理属性：
  · 若周末判定抢先，所有补班日会被 WEEKDAY_CODE IN (6,7) 判为 WEEKEND 并赋
    系数 2.00000000，导致补班日按双倍系数计发，绩效被人为放大且无任何报错拦截。
  · 同理，若 IS_MAKEUP_WORK = 1 与 IS_HOLIDAY = 1 同时成立（业务上不应出现），
    口径以「实际需上班」为准，锁定系数 1.00000000。
  因此本脚本采用 CASE ... WHEN 自上而下短路语义，补班判定置于最顶层。
--------------------------------------------------------------------------------
  【与 WEEKDAY_CODE 物理下沉的关系 —— 为什么本脚本绝对安全】
  星期判定完全依赖已物理下沉的 [WEEKDAY_CODE]，全程不调用 DATEPART / DATENAME：
  · 若沿用 DATEPART(WEEKDAY, CALC_DATE)，其返回值受会话级 DATEFIRST 支配
    （DATEFIRST 1 时周日=7；DATEFIRST 7 时周日=1），同一批数据在不同客户端
    登录下会被刷洗成不同的 DAY_TYPE，且重跑结果不可复现。
  · [WEEKDAY_CODE] 为落库静态值（ISO 口径 1=星期一 ... 7=星期日），与任何会话
    上下文解耦，保证本补丁在同一数据状态下**任意次重跑结果恒等**。
--------------------------------------------------------------------------------
  【编码字段字符串语义】
  DAY_TYPE_CODE 为 VARCHAR(16) 字符串编码，常量一律以单引号文本字面量写入，
  严禁 CAST 为整型（前导零丢失与关联失配风险）。
--------------------------------------------------------------------------------
  【幂等性说明】
  本脚本为「绝对值赋值」而非增量累加，可重复执行且结果恒等。
  重复执行时 [DAY_TYPE_CODE] / [DAY_TYPE_NAME] / [PERF_COEFF] 被重新推导并覆盖，
  但 [REMARK] / [HOLIDAY_NAME] / [CREATE_TIME] 等人工维护列**严格不触碰**，
  已录入的业务说明与逐日微调痕迹零污染。
--------------------------------------------------------------------------------
  【执行前必读 —— 覆盖范围声明】
  本脚本的 WHERE 过滤条件带「待确认 / 系数恒为 1」限定，仅刷洗未初始化或未校正的行。
  若某行是被业务老师**有意逐日微调**过的系数（如把某工作日调为 1.20000000），
  该行不会命中本补丁的过滤条件，微调成果得以保留。
  如需强制全量重算（覆盖一切人工微调），请显式移除 WHERE 子句后再执行。
================================================================================
  修改日志：
  2026-09-15 07:30:00 | 脚本新建 | 创建日历表类型与系数数据清洗补丁：
                                       依据 IS_MAKEUP_WORK / IS_HOLIDAY / WEEKDAY_CODE 三级基础列
                                       按 MAKEUP > HOLIDAY > WEEKEND > WORKDAY 优先级短路判定，
                                       刷洗 DAY_TYPE_CODE / DAY_TYPE_NAME / PERF_COEFF 三列；
                                       全程不依赖 DATEFIRST 敏感函数（基于物理下沉 WEEKDAY_CODE）；
                                       包裹显式事务并输出影响行数，末尾附 3 段刷洗结果核查 SELECT；
                                       全局禁 GO 协议、单批分号结束。
================================================================================
*/


SET XACT_ABORT ON;

-- ================================================================
-- 执行前基线：统计待刷洗行数与当前脏值分布（不改数据，仅审计）
-- ================================================================
SELECT
    COUNT(*)                                                                             AS [待刷洗总行数]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = 'MAKEUP'  THEN 1 ELSE 0 END)                           AS [现值_MAKEUP]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = 'HOLIDAY' THEN 1 ELSE 0 END)                           AS [现值_HOLIDAY]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = 'WEEKEND' THEN 1 ELSE 0 END)                           AS [现值_WEEKEND]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = 'WORKDAY' THEN 1 ELSE 0 END)                           AS [现值_WORKDAY]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = N'待确认'  THEN 1 ELSE 0 END)                           AS [现值_待确认]
   ,SUM(CASE WHEN [PERF_COEFF] = CAST(1.00000000 AS DECIMAL(18,8)) THEN 1 ELSE 0 END)      AS [现值_系数等于1]
FROM [dbo].[DIM_WORK_CALENDAR]
WHERE [DAY_TYPE_CODE] = N'待确认'
   OR [PERF_COEFF]    = CAST(1.00000000 AS DECIMAL(18,8));

BEGIN TRANSACTION;

-- ================================================================
-- 主刷洗：按优先级短路判定，一次性更新三个目标列
-- ================================================================
UPDATE cal
SET
    cal.[DAY_TYPE_CODE] = CASE
                              WHEN cal.[IS_MAKEUP_WORK] = 1           THEN 'MAKEUP'
                              WHEN cal.[IS_HOLIDAY]     = 1           THEN 'HOLIDAY'
                              WHEN cal.[WEEKDAY_CODE]   IN (6, 7)     THEN 'WEEKEND'
                              ELSE 'WORKDAY'
                          END
   ,cal.[DAY_TYPE_NAME] = CASE
                              WHEN cal.[IS_MAKEUP_WORK] = 1           THEN N'调休补班'
                              WHEN cal.[IS_HOLIDAY]     = 1           THEN N'法定节假日'
                              WHEN cal.[WEEKDAY_CODE]   IN (6, 7)     THEN N'普通周末'
                              ELSE N'正常工作日'
                          END
   ,cal.[PERF_COEFF]    = CAST(
                              CASE
                                  WHEN cal.[IS_MAKEUP_WORK] = 1       THEN 1.00000000
                                  WHEN cal.[IS_HOLIDAY]     = 1       THEN 2.00000000
                                  WHEN cal.[WEEKDAY_CODE]   IN (6, 7) THEN 2.00000000
                                  ELSE 1.00000000
                              END AS DECIMAL(18,8)
                          )
FROM [dbo].[DIM_WORK_CALENDAR] AS cal
WHERE cal.[DAY_TYPE_CODE] = N'待确认'
   OR cal.[PERF_COEFF]    = CAST(1.00000000 AS DECIMAL(18,8));

SELECT @@ROWCOUNT AS [UPDATED_ROW_COUNT];

COMMIT TRANSACTION;

-- ================================================================
-- 核查 1：刷洗后日期类型分布总览（应仅剩 4 种合法编码，无「待确认」残留）
-- ================================================================
SELECT
    [DAY_TYPE_CODE]                                                                       AS [日期类型编码]
   ,[DAY_TYPE_NAME]                                                                       AS [日期类型名称]
   ,COUNT(*)                                                                              AS [天数]
   ,MIN([CALC_DATE])                                                                      AS [最早日期]
   ,MAX([CALC_DATE])                                                                      AS [最晚日期]
   ,MIN([PERF_COEFF])                                                                     AS [最小系数]
   ,MAX([PERF_COEFF])                                                                     AS [最大系数]
FROM [dbo].[DIM_WORK_CALENDAR]
GROUP BY [DAY_TYPE_CODE], [DAY_TYPE_NAME]
ORDER BY [DAY_TYPE_CODE];

-- ================================================================
-- 核查 2：口径一致性断言（6 项异常计数期望全部为 0）
-- ================================================================
SELECT
    SUM(CASE WHEN [IS_MAKEUP_WORK] = 1
                              AND [DAY_TYPE_CODE] <> 'MAKEUP'                        THEN 1 ELSE 0 END) AS [异常_补班未判为MAKEUP]
   ,SUM(CASE WHEN [IS_MAKEUP_WORK] = 0 AND [IS_HOLIDAY] = 1
                              AND [DAY_TYPE_CODE] <> 'HOLIDAY'                       THEN 1 ELSE 0 END) AS [异常_节假日未判为HOLIDAY]
   ,SUM(CASE WHEN [IS_MAKEUP_WORK] = 0 AND [IS_HOLIDAY] = 0
                              AND [WEEKDAY_CODE] IN (6, 7)
                              AND [DAY_TYPE_CODE] <> 'WEEKEND'                       THEN 1 ELSE 0 END) AS [异常_周末未判为WEEKEND]
   ,SUM(CASE WHEN [IS_MAKEUP_WORK] = 0 AND [IS_HOLIDAY] = 0
                              AND [WEEKDAY_CODE] NOT IN (6, 7)
                              AND [DAY_TYPE_CODE] <> 'WORKDAY'                       THEN 1 ELSE 0 END) AS [异常_工作日未判为WORKDAY]
   ,SUM(CASE WHEN [PERF_COEFF] <> CAST(
                                  CASE
                                      WHEN [IS_MAKEUP_WORK] = 1       THEN 1.00000000
                                      WHEN [IS_HOLIDAY]     = 1       THEN 2.00000000
                                      WHEN [WEEKDAY_CODE]   IN (6, 7) THEN 2.00000000
                                      ELSE 1.00000000
                                  END AS DECIMAL(18,8))                                  THEN 1 ELSE 0 END) AS [异常_系数与口径偏离]
   ,SUM(CASE WHEN [DAY_TYPE_CODE] = N'待确认'                                              THEN 1 ELSE 0 END) AS [异常_残留待确认]
FROM [dbo].[DIM_WORK_CALENDAR];

-- ================================================================
-- 核查 3：异常明细抽样（定位具体是哪一天判错，便于人工复核）
-- ================================================================
SELECT
    [CALC_DATE]                                                                           AS [日期]
   ,[WEEKDAY_CODE]                                                                        AS [星期编码]
   ,[WEEKDAY_NAME]                                                                        AS [星期名称]
   ,[DAY_TYPE_CODE]                                                                       AS [日期类型编码]
   ,[DAY_TYPE_NAME]                                                                       AS [日期类型名称]
   ,[IS_HOLIDAY]                                                                          AS [是否节假日]
   ,[HOLIDAY_NAME]                                                                        AS [节假日名称]
   ,[IS_MAKEUP_WORK]                                                                      AS [是否调休上班]
   ,[PERF_COEFF]                                                                          AS [绩效系数]
FROM [dbo].[DIM_WORK_CALENDAR]
WHERE [DAY_TYPE_CODE] NOT IN ('WORKDAY', 'HOLIDAY', 'WEEKEND', 'MAKEUP')
   OR [PERF_COEFF]    NOT IN (CAST(1.00000000 AS DECIMAL(18,8)), CAST(2.00000000 AS DECIMAL(18,8)))
ORDER BY [CALC_DATE];
