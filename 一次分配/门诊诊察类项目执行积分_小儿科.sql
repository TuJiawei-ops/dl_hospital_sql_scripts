/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分_小儿科.sql
  脚本名称: 门诊诊察类项目执行积分_小儿科.sql
  业务说明: 门诊诊察类项目（1043）执行积分持久化（核算单元 × 执行人员 × 项目 × 日期类型 粒度），
            执行科室代码 36 硬隔离；学科系数常量 1.1。
  积分口径: 积分 = 项目点数 × 汇总数量 × 学科系数(1.1) × 绩效核算系数
  模板占位符: '{start_time}' / '{end_time}' / {struct_codes}
*/

-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
~

DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = YEAR(CAST('{start_time}' AS DATETIME))
  AND [CALC_MONTH] = MONTH(CAST('{start_time}' AS DATETIME))
  AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_PED'
--   AND [UNIT_CODE] IN {struct_codes}
;

WITH
cte_rvu AS (
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,MAX(v0.[VERSION_NO])                        AS VERSION_NO
       ,MAX(v0.[VERSION_DESC])                      AS VERSION_DESC
       ,MAX(v0.[ORG_CODE])                          AS ORG_CODE
       ,MAX(v0.[ORG_NAME])                          AS ORG_NAME
       ,MAX(v0.[SRC_SYS_CODE])                      AS SRC_SYS_CODE
       ,MAX(v0.[PROJ_NAME])                         AS PROJ_NAME
       ,MAX(v0.[MEAS_UNIT])                         AS MEAS_UNIT
       ,MAX(v0.[ITEM_CAT_CODE])                     AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])                     AS ITEM_CAT_NAME
       ,MAX(v0.[OPR_LEVEL_CODE])                    AS OPR_LEVEL_CODE
       ,MAX(v0.[OPR_LEVEL_NAME])                    AS OPR_LEVEL_NAME
       ,MAX(v0.[CREATE_USER])                       AS CREATE_USER
       ,MAX(v0.[CREATE_TIME])                       AS CREATE_TIME
       ,MAX(v0.[UPDATE_USER])                       AS UPDATE_USER
       ,MAX(v0.[UPDATE_TIME])                       AS UPDATE_TIME
       ,MAX(v0.[REMARK])                            AS REMARK
       ,MAX(v0.[SCORE_REASON])                      AS SCORE_REASON
       ,CAST(MAX(v0.[RVU_VAL])       AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF])     AS DECIMAL(18,8))  AS EXEC_COFF
       ,CAST(MAX(v0.[DECISION_COFF]) AS DECIMAL(18,8))  AS DECISION_COFF
       ,CAST(MAX(v0.[UNIT_PRICE])    AS DECIMAL(18,8))  AS UNIT_PRICE
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
,final AS (
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

   ,ISNULL(cal.[DAY_TYPE_CODE], 'WORKDAY')                    AS [日期类型编码]
   ,ISNULL(cal.[DAY_TYPE_NAME], N'正常工作日')                  AS [日期类型名称]
   ,ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS [绩效核算系数]

   ,YEAR(f.[缴费时间])                                        AS [缴费日期年份]
   ,MONTH(f.[缴费时间])                                       AS [缴费日期月份]

   ,CAST(v.[RVU_VAL] * SUM(CAST(f.[数量] AS DECIMAL(18,8))) * CAST(1.1 AS DECIMAL(18,8)) * ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [积分]
   ,CONCAT(
        CAST(CAST(v.[RVU_VAL] AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × '
       ,CAST(CAST(SUM(CAST(f.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × 1.10000000 × '
       ,CAST(ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS VARCHAR(32))
    )                                                         AS [积分计算过程]
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
WHERE f.[缴费时间] >= '{start_time}'
  AND f.[缴费时间] <= '{end_time}'
  AND f.[执行科室代码] = 36
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
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[缴费日期年份] AS INT)                       AS [CALC_YEAR],
    CAST(f.[缴费日期月份] AS INT)                       AS [CALC_MONTH],
    N'ITEM_OUTPATIENT_DIAG_SCORE_PED'                  AS [ITEM_CODE],
    N'门诊诊察类项目执行积分_小儿科'                    AS [ITEM_NAME],
    N'门诊诊察类项目执行积分_小儿科.sql'                AS [SCRIPT_NAME],
    f.[执行人员所在核算单元编码]                         AS [UNIT_CODE],
    f.[执行人员所在核算单元名称]                         AS [UNIT_NAME],
    f.[项目代码]                                        AS [PROJ_CODE],
    f.[项目名称]                                        AS [PROJ_NAME],
    f.[绩效大类编码]                                    AS [ITEM_CAT_CODE],
    f.[绩效大类名称]                                    AS [ITEM_CAT_NAME],
    N'执行人员'                                         AS [EXEC_ROLE],
    ISNULL(mdm_exec_staff.[staff_code], N'未匹配')      AS [STAFF_CODE],
    f.[执行人员]                                        AS [STAFF_NAME],
    f.[日期类型编码]                                    AS [DAY_TYPE_CODE],
    f.[日期类型名称]                                    AS [DAY_TYPE_NAME],
    N'SCORE'                                           AS [FINAL_VALUE_TYPE],
    CAST(f.[积分] AS DECIMAL(18,8))                     AS [FINAL_VALUE],
    CAST(f.[数量] AS DECIMAL(18,8))                     AS [TOTAL_QTY],
    CONCAT(
        N'门诊诊察类项目执行积分_小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
       ,f.[积分计算过程]
       ,' = '
       ,CAST(CAST(f.[积分] AS DECIMAL(18,8)) AS VARCHAR(50))
    )                                                   AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[缴费日期年份] AS VARCHAR(11))                  AS [核算年份],
            CAST(f.[缴费日期月份] AS VARCHAR(11))                  AS [核算月份],
            N'ITEM_OUTPATIENT_DIAG_SCORE_PED'                      AS [核算项编码],
            N'门诊诊察类项目执行积分_小儿科'                        AS [核算项名称],
            N'门诊诊察类项目执行积分_小儿科.sql'                    AS [脚本名称],
            f.[执行人员所在核算单元编码]                             AS [核算单元编码],
            f.[执行人员所在核算单元名称]                             AS [核算单元名称],
            f.[项目代码]                                          AS [项目代码],
            f.[项目名称]                                          AS [项目名称],
            f.[绩效大类编码]                                      AS [绩效核算大类代码],
            f.[绩效大类名称]                                      AS [绩效核算大类名称],
            N'执行人员'                                            AS [执行角色],
            ISNULL(mdm_exec_staff.[staff_code], N'未匹配')          AS [员工编码],
            f.[执行人员]                                          AS [员工姓名],
            f.[日期类型编码]                                      AS [日期类型编码],
            f.[日期类型名称]                                      AS [日期类型名称],
            N'SCORE'                                             AS [值类型],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [最终结果],
            CAST(f.[数量] AS DECIMAL(18,8))                        AS [汇总数量],
            CONCAT(
                N'门诊诊察类项目执行积分_小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
               ,f.[积分计算过程]
               ,' = '
               ,CAST(CAST(f.[积分] AS DECIMAL(18,8)) AS VARCHAR(50))
            )                                                     AS [计算过程描述],
            CAST(f.[项目点数] AS DECIMAL(18,8))                    AS [单项RVU点数],
            CAST(f.[执行系数] AS DECIMAL(18,8))                    AS [执行系数],
            f.[执行人员代码]                                      AS [执行人员代码],
            f.[执行人员]                                          AS [执行人员],
            CAST(f.[岗位系数] AS DECIMAL(18,8))                    AS [岗位系数],
            CAST(f.[学科系数] AS DECIMAL(18,8))                    AS [学科系数],
            CAST(f.[绩效核算系数] AS DECIMAL(18,8))                AS [绩效核算系数],
            CAST(f.[单价] AS DECIMAL(18,8))                        AS [单价],
            CAST(f.[金额] AS DECIMAL(18,8))                        AS [汇总金额],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [门诊诊察类执行积分],
            JSON_QUERY((
                SELECT
                    c.[VERSION_NO]       AS [版本号],
                    c.[VERSION_DESC]     AS [版本描述],
                    c.[ORG_CODE]         AS [机构编码],
                    c.[ORG_NAME]         AS [机构名称],
                    c.[SRC_SYS_CODE]     AS [源系统编码],
                    c.[PROJ_CODE]        AS [收费项目编码],
                    c.[PROJ_NAME]        AS [收费项目名称],
                    c.[MEAS_UNIT]        AS [原始计费单位],
                    CAST(c.[RVU_VAL] AS DECIMAL(18,8))       AS [单项绩效点数],
                    c.[ITEM_CAT_CODE]    AS [绩效核算大类编码],
                    c.[ITEM_CAT_NAME]    AS [绩效核算大类名称],
                    CAST(c.[UNIT_PRICE] AS DECIMAL(18,8))    AS [历史参考单价],
                    c.[OPR_LEVEL_CODE]   AS [手术等级编码],
                    c.[OPR_LEVEL_NAME]   AS [手术等级名称],
                    c.[CREATE_USER]      AS [创建人],
                    CONVERT(VARCHAR(19), c.[CREATE_TIME], 120) AS [创建时间],
                    c.[UPDATE_USER]      AS [修改人],
                    CONVERT(VARCHAR(19), c.[UPDATE_TIME], 120) AS [修改时间],
                    CAST(c.[DECISION_COFF] AS DECIMAL(18,8)) AS [诊疗决策系数],
                    CAST(c.[EXEC_COFF] AS DECIMAL(18,8))     AS [执行系数],
                    c.[REMARK]           AS [备注说明],
                    c.[SCORE_REASON]     AS [评分理由依据]
                FROM cte_rvu AS c
                WHERE c.[PROJ_CODE] = f.[项目代码]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ))                                                    AS [RVU配置快照]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                   AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                       AS [CREATE_TIME]
FROM final AS f
LEFT JOIN cte_ryb AS ryb_staff
    ON f.[执行人员代码] = ryb_staff.[id]
LEFT JOIN cte_mdm_staff AS mdm_exec_staff
    ON ryb_staff.[src_staff_code] = mdm_exec_staff.[src_staff_code]
    ;
    ~

-- 第二区块：最外层接口读取块（查询明细时仅执行此块，严格承接 struct_code / struct_name / result_value 契约）
WITH CTE_DWD_READ_ALIAS AS (
    SELECT
        [ID]                    AS [日志ID],
        [CALC_YEAR]             AS [核算年份],
        [CALC_MONTH]            AS [核算月份],
        [ITEM_CODE]             AS [核算项编码],
        [ITEM_NAME]             AS [核算项名称],
        [SCRIPT_NAME]           AS [脚本名称],
        [UNIT_CODE]             AS [核算单元编码],
        [UNIT_NAME]             AS [核算单元名称],
        [PROJ_CODE]             AS [项目代码],
        [PROJ_NAME]             AS [项目名称],
        [ITEM_CAT_CODE]         AS [绩效核算大类代码],
        [ITEM_CAT_NAME]         AS [绩效核算大类名称],
        [EXEC_ROLE]             AS [执行角色],
        [STAFF_CODE]            AS [员工编码],
        [STAFF_NAME]            AS [员工姓名],
        [DAY_TYPE_CODE]         AS [日期类型编码],
        [DAY_TYPE_NAME]         AS [日期类型名称],
        [FINAL_VALUE_TYPE]      AS [值类型],
        [FINAL_VALUE]           AS [最终结果],
        [TOTAL_QTY]             AS [汇总数量],
        [CALC_PROCESS_TEXT]     AS [计算过程描述],
        [CALC_DETAIL_JSON]      AS [明细JSON],
        [CREATE_TIME]           AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    WHERE [CALC_YEAR]  = YEAR(CAST('{start_time}' AS DATETIME))
      AND [CALC_MONTH] = MONTH(CAST('{start_time}' AS DATETIME))
      AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_PED'
      AND [UNIT_CODE] IN {struct_codes}
)

SELECT
    {
    [核算单元编码] AS struct_code,
    [核算单元名称] AS struct_name,
    SUM([最终结果]) AS result_value
    }
FROM CTE_DWD_READ_ALIAS
    ~
GROUP BY
    [核算单元编码],
    [核算单元名称]
    ~
    ;
