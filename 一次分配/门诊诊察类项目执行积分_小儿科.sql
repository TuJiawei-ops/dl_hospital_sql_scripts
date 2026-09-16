/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分_小儿科.sql
  脚本名称: 门诊诊察类项目执行积分_小儿科.sql
  业务说明: 门诊诊察类项目（1043）按日汇总执行数据，执行科室代码 36 硬隔离。
  学科系数: 常量 1.1
  修改日志：
  2026-09-16 | 易用性增强 | 追加 ORDER BY 按 缴费年月->日期类型->核算单元->人员代码->项目代码 显式排序，提升财务对账与报表展示体验。
  2026-09-16 17:05:00 | 粒度压缩 | 剥离 [执行日期] 与 [缴费日期] 维度，按 人员+项目+月份+日期类型 进行聚合，实现数据高倍率压缩并提升计算性能。
  2026-09-16 16:20:00 | 维度扩充 | 接入 DIM_WORK_CALENDAR 表，以缴费日期关联提取 DAY_TYPE_CODE, DAY_TYPE_NAME, PERF_COEFF 投影与分组。
  2026-09-16 15:40:00 | 维度剪枝 | 核算归属改以「执行人员所在核算单元」为准，剥离 cte_bmb/cte_dept_map 及主查询对应 JOIN，删除 [执行绩效核算单元编码]/[执行绩效核算单元名称] 投影与分组；保留 f.[执行科室代码] = 36 硬隔离。
  2026-09-16 15:10:00 | 主数据路由纠偏 | 人员链路接入 MAP_MDM_STAFF（cte_ryb[编号] → cte_mdm_staff[SRC_STAFF_CODE] → [STAFF_CODE]），剥离不存在的 IS_ACTIVE 谓词（运行库无该列）。
=============================================================================== */


WITH cte_rvu AS (
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,MAX(v0.[ITEM_CAT_CODE])                     AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])                     AS ITEM_CAT_NAME
       ,CAST(MAX(v0.[RVU_VAL])   AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF]) AS DECIMAL(18,8))  AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
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
    SELECT
        m.[staff_code]                              AS staff_code
       ,m.[year]                                    AS [year]
       ,m.[month]                                   AS [month]
       ,m.[unit_code]                               AS unit_code
       ,m.[unit_name]                               AS unit_name
       ,CAST(m.[post_coefficient] AS DECIMAL(18,8)) AS post_coefficient
    FROM dbo.[ads_dept_post_coefficient_m] AS m WITH (NOLOCK)
    WHERE m.[staff_code] IS NOT NULL
    GROUP BY
        m.[staff_code]
       ,m.[year]
       ,m.[month]
       ,m.[unit_code]
       ,m.[unit_name]
       ,m.[post_coefficient]
)
SELECT
    f.[来源]                                                  AS [来源]

   ,f.[项目大类]                                              AS [项目大类]
   ,f.[项目代码]                                              AS [项目代码]
   ,f.[项目名称]                                              AS [项目名称]

   ,v.[ITEM_CAT_CODE]                                         AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                         AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                      AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                      AS [执行系数]

   ,CAST(f.[单价] AS DECIMAL(18,8))                           AS [单价]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [数量]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [金额]

   ,CAST(1.1 AS DECIMAL(18,8))                                AS [学科系数]

   ,f.[执行人员代码]                                          AS [执行人员代码]
   ,f.[执行人员]                                              AS [执行人员]

   ,ISNULL(sp_exec.[unit_code], N'未匹配')                     AS [执行人员所在核算单元编码]
   ,ISNULL(sp_exec.[unit_name], N'未匹配')                     AS [执行人员所在核算单元名称]
   ,ISNULL(CAST(sp_exec.[post_coefficient] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS [岗位系数]

   -- ── 工作日历维度（按缴费日期关联，LEFT JOIN + ISNULL 双保险防覆盖缺口） ──
   ,ISNULL(cal.[DAY_TYPE_CODE], 'WORKDAY')                    AS [日期类型编码]
   ,ISNULL(cal.[DAY_TYPE_NAME], N'正常工作日')                  AS [日期类型名称]
   ,ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS [绩效核算系数]

   ,YEAR(f.[缴费时间])                                        AS [缴费日期年份]
   ,MONTH(f.[缴费时间])                                       AS [缴费日期月份]
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
LEFT JOIN dbo.[DIM_WORK_CALENDAR] AS cal WITH (NOLOCK)
    ON CAST(f.[缴费时间] AS DATE) = cal.[CALC_DATE]
WHERE f.[执行科室代码] = 36
GROUP BY
    f.[来源]
   ,f.[项目大类]
   ,f.[项目代码]
   ,f.[项目名称]
   ,v.[ITEM_CAT_CODE]
   ,v.[ITEM_CAT_NAME]
   ,v.[RVU_VAL]
   ,v.[EXEC_COFF]
   ,CAST(f.[单价] AS DECIMAL(18,8))
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,ISNULL(sp_exec.[unit_code], N'未匹配')
   ,ISNULL(sp_exec.[unit_name], N'未匹配')
   ,ISNULL(CAST(sp_exec.[post_coefficient] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8)))
   ,cal.[DAY_TYPE_CODE]
   ,cal.[DAY_TYPE_NAME]
   ,cal.[PERF_COEFF]
   ,YEAR(f.[缴费时间])
   ,MONTH(f.[缴费时间])
-- ── 输出顺序显式化：GROUP BY 不保证输出顺序（Hash Aggregate 下顺序随机），
--    按 缴费年月 ▸ 日期类型 ▸ 核算单元 ▸ 人员代码 ▸ 项目代码 的业务流向多阶升序排序，
--    便于财务逐行对账与同一人员同月记录紧密聚合（仅约束输出序，不参与分组与计算）。
ORDER BY
    YEAR(f.[缴费时间])                      ASC
   ,MONTH(f.[缴费时间])                     ASC
   ,cal.[DAY_TYPE_CODE]                     ASC
   ,ISNULL(sp_exec.[unit_code], N'未匹配')  ASC
   ,f.[执行人员代码]                         ASC
   ,f.[项目代码]                             ASC
;
