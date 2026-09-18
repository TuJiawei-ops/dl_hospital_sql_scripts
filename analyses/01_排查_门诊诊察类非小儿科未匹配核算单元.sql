/* ===============================================================================
  Relative Path : analyses/01_排查_门诊诊察类非小儿科未匹配核算单元.sql
  脚本名称: 01_排查_门诊诊察类非小儿科未匹配核算单元.sql
  业务说明: 全账期（不限账期）扫描门诊诊察类项目（1043）中由于人员映射或岗位系数表缺失，
            导致核算单元匹配为 N'未匹配' 的原始人员、科室及对应记录统计。
            提供清晰的补全配置指引（缺少人员主数据映射 vs 缺少账期岗位系数）。
  排查链路: dbo.[PF临时医疗服务项目26A] (执行人员代码)
            ──▶ dbo.[sjjk_ryb_2025_06_01]      (id ➔ 编号 = src_staff_code，数值主键 → 原始工号桥接)
            ──▶ dbo.[MAP_MDM_STAFF]            (SRC_STAFF_CODE ➔ STAFF_CODE，主数据标准工号路由)
            ──▶ dbo.[ads_dept_post_coefficient_m] (staff_code + year + month ➔ unit_code 核算单元)
            聚合口径: 账期年月 × 原始执行科室 × 原始执行人员 粒度，输出断链根因与影响量级。
  只读声明: 纯 SELECT 分析报表，无任何 INSERT / UPDATE / DELETE / DDL 副作用。
  模板占位符: 无（全账期扫描，不接受 '{year}' / '{month}' / {struct_codes} 注入）

  修改日志：
  2026-09-18 11:45:00 | 脚本新建 | 建立门诊诊察类（1043）非小儿科核算单元未匹配全账期排查报表：复用门诊诊察类项目执行积分_非小儿科.sql 的四段式人员链路，反查 sp_exec.[unit_code] IS NULL 的断链人员，按「账期年月 × 原始执行科室 × 原始执行人员 × 断链层级」聚合输出未匹配明细笔数、影响业务数量与金额汇总、首末次出现时间，并给出补全配置指引（缺少 sjjk_ryb 人员基础映射 / 缺少 MAP_MDM_STAFF 主数据映射 / 缺少 ads_dept_post_coefficient_m 当月岗位系数及单元配置）。
================================================================================ */

WITH cte_rvu AS (
    SELECT DISTINCT
        v0.[PROJ_CODE]                              AS PROJ_CODE
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
)
,cte_ryb AS (
    SELECT
        r.[id]                                      AS id
       ,MAX(r.[编号])                               AS src_staff_code
    FROM dbo.[sjjk_ryb_2025_06_01] AS r WITH (NOLOCK)
    WHERE r.[id] IS NOT NULL
    GROUP BY r.[id]
)
,cte_mdm_staff AS (
    SELECT
        s.[SRC_STAFF_CODE]                          AS src_staff_code
       ,MAX(s.[STAFF_CODE])                         AS staff_code
    FROM dbo.[MAP_MDM_STAFF] AS s WITH (NOLOCK)
    WHERE s.[SRC_STAFF_CODE] IS NOT NULL
    GROUP BY s.[SRC_STAFF_CODE]
)
,cte_staff_post AS (
    SELECT DISTINCT
        m.[staff_code]                              AS staff_code
       ,m.[year]                                    AS [year]
       ,m.[month]                                   AS [month]
       ,m.[unit_code]                               AS unit_code
       ,m.[unit_name]                               AS unit_name
    FROM dbo.[ads_dept_post_coefficient_m] AS m WITH (NOLOCK)
    WHERE m.[staff_code] IS NOT NULL
)
SELECT
    YEAR(f.[缴费时间])                                        AS [账期年份]
   ,MONTH(f.[缴费时间])                                       AS [账期月份]
   ,f.[执行科室代码]                                          AS [原始执行科室代码]
   ,f.[执行科室]                                              AS [原始执行科室名称]
   ,f.[执行人员代码]                                          AS [原始执行人员代码]
   ,f.[执行人员]                                              AS [原始执行人员姓名]
   ,ryb_exec.[src_staff_code]                                 AS [映射前源人员编号]
   ,mdm_exec.[staff_code]                                     AS [主数据标准员工工号]
   ,CASE
        WHEN ryb_exec.[src_staff_code] IS NULL THEN N'缺少 [sjjk_ryb_2025_06_01] 人员基础映射'
        WHEN mdm_exec.[staff_code] IS NULL THEN N'缺少 [MAP_MDM_STAFF] 主数据映射'
        WHEN sp_exec.[unit_code] IS NULL THEN N'缺少 [ads_dept_post_coefficient_m] 当月岗位系数及单元配置'
        ELSE N'未知原因'
    END                                                       AS [排查与修复指引]
   ,COUNT(*)                                                  AS [未匹配明细笔数]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [影响业务数量汇总]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [影响业务金额汇总]
   ,MIN(f.[缴费时间])                                         AS [首次出现缴费时间]
   ,MAX(f.[缴费时间])                                         AS [最近出现缴费时间]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN cte_rvu AS v
    ON f.[项目代码] = v.[PROJ_CODE]
LEFT JOIN cte_ryb AS ryb_exec
    ON f.[执行人员代码] = ryb_exec.[id]
LEFT JOIN cte_mdm_staff AS mdm_exec
    ON ryb_exec.[src_staff_code] = mdm_exec.[src_staff_code]
LEFT JOIN cte_staff_post AS sp_exec
    ON mdm_exec.[staff_code] = sp_exec.[staff_code]
   AND YEAR(f.[缴费时间])    = sp_exec.[year]
   AND MONTH(f.[缴费时间])   = sp_exec.[month]
WHERE f.[来源] = N'门诊'
  AND (f.[执行科室代码] IS NULL OR f.[执行科室代码] <> 36)
  AND sp_exec.[unit_code] IS NULL
GROUP BY
    YEAR(f.[缴费时间])
   ,MONTH(f.[缴费时间])
   ,f.[执行科室代码]
   ,f.[执行科室]
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,ryb_exec.[src_staff_code]
   ,mdm_exec.[staff_code]
   ,CASE
        WHEN ryb_exec.[src_staff_code] IS NULL THEN N'缺少 [sjjk_ryb_2025_06_01] 人员基础映射'
        WHEN mdm_exec.[staff_code] IS NULL THEN N'缺少 [MAP_MDM_STAFF] 主数据映射'
        WHEN sp_exec.[unit_code] IS NULL THEN N'缺少 [ads_dept_post_coefficient_m] 当月岗位系数及单元配置'
        ELSE N'未知原因'
    END
ORDER BY
    [账期年份] DESC
   ,[账期月份] DESC
   ,[影响业务金额汇总] DESC;
