/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分_非小儿科.sql
  脚本名称: 门诊诊察类项目执行积分_非小儿科.sql
  业务说明: 门诊诊察类项目（1043）执行积分持久化（核算单元 × 执行人员 × 项目 × 日期类型 粒度），
            执行科室代码 <> 36 硬隔离（NULL 安全）；学科系数常量 1.0。
  积分口径: 积分 = 项目点数 × 汇总数量 × 学科系数(1.0) × 绩效核算系数
  模板占位符: '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes}

  修改日志：
  2026-09-18 13:00:00 | 字段微调 | 第一区块持久化 INSERT/SELECT 补齐 [RVU_VAL] 物理列投影，与 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 新增属性列 1:1 对齐（投影源 = final 层 [项目点数]（由 cte_rvu.[RVU_VAL] 于 L97 经 CAST(... AS DECIMAL(18,8)) 派生），经 CAST(... AS DECIMAL(18,8)) 二次收敛；INSERT 列位插入于 [ITEM_CAT_NAME] 之后、[EXEC_ROLE] 之前）。
  2026-09-18 12:00:00 | 人员黑名单过滤 | 响应业务要求，WHERE 条件追加 (f.[执行人员代码] NOT IN (123, 2523, 2343) OR f.[执行人员代码] IS NULL)，排除管理员(123)、丛勇滋(2523)、马光宇(2343) 等非业务执行人员记录。纠偏说明：源列 dbo.[PF临时医疗服务项目26A].[执行人员代码] 物理类型为 BIGINT（对应 sjjk_ryb_2025_06_01.[id] int 代理主键，属数值 ID 而非业务编码），故黑名单字面量以数值形态书写，严禁 N'123' 字符串字面量触发 BIGINT↔NVARCHAR 隐式转换导致执行计划对源列施加转换与 SARGability 衰减；IS NULL 兜底保留，防止 NOT IN 对 NULL 求值为 UNKNOWN 而静默丢弃执行人员代码为空的记录。计算链路、聚合粒度、落库投影与 JSON 序列化链路零改动。
  2026-09-18 11:20:00 | 唯一约束纠偏 | 根治 UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 唯一键冲突：WHERE 追加 f.[来源] = N'门诊' 门诊来源硬隔离（独占一行，保障 -- 单行零副作用隔离）；final CTE 剥离 [来源] / [项目大类] 投影列与 GROUP BY 分组维度，消除同一 核算单元 × 项目 × 执行人员 × 日期类型 粒度下因来源/项目大类差异产生的重复行（唯一键 8 维无 [来源]/[项目大类]，属粒度伪维度）。计算链路（积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数）、第一区块 INSERT 落库投影、JSON 序列化链路与第二区块读取逻辑零改动。
  2026-09-18 10:00:00 | 维度解耦 | cte_rvu 解构伪聚合：剥离 GROUP BY v0.[PROJ_CODE] 与 MAX() 聚合函数，遵循零版本寻址与 VERSION_NO 备注化法则，维表直拉 1:1 字段投影。VERSION_NO / VERSION_DESC 降级为普通属性列，严禁作为动态寻址主控条件。
  2026-09-17 18:30:00 | 聚合降维 | final CTE 剥离 [单价] 分组维度：GROUP BY 移除 CAST(f.[单价] AS DECIMAL(18,8))，消除因单价异动/退费记录（如正向 0.00 与退费 1.00 并存）导致的聚合粒度碎片化，从根因上规避 UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 唯一约束冲突；SELECT 列表 [单价] 改由 SUM([金额]) ÷ SUM([数量]) 动态计算加权平均单价，并以 CASE WHEN SUM([数量]) = 0 THEN 0 实现零除保护，保障退费净额完全抵消场景不抛错。[数量] / [金额] 维持 SUM 聚合，正反向交易净额抵消口径成立；第一区块 INSERT 落库投影与 JSON 序列化链路零改动。
  2026-09-17 17:00:00 | 参数纠偏 | 落库日志表筛选解耦：DELETE 幂等清场与第二区块 CTE_DWD_READ_ALIAS 读取块的账期条件，由 YEAR(CAST('{start_time}' AS DATETIME)) / MONTH(...) 动态日期解析改为 '{year}' / '{month}' 显式参数直取（经 CAST(... AS INT) 与物理列类型对齐）；'{start_time}' / '{end_time}' 严格收敛至底层事实表 dbo.[PF临时医疗服务项目26A] 的 [缴费时间] 精确时间窗口筛选，严禁外溢至汇总日志表操作；头部模板占位符清单补录 '{year}' / '{month}'。计算链路、落库投影与占位符契约零改动。
*/

-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
~

DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'
--   AND [UNIT_CODE] IN {struct_codes}
;

WITH
cte_rvu AS (
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,v0.[VERSION_NO]                             AS VERSION_NO
       ,v0.[VERSION_DESC]                           AS VERSION_DESC
       ,v0.[ORG_CODE]                               AS ORG_CODE
       ,v0.[ORG_NAME]                               AS ORG_NAME
       ,v0.[SRC_SYS_CODE]                           AS SRC_SYS_CODE
       ,v0.[PROJ_NAME]                              AS PROJ_NAME
       ,v0.[MEAS_UNIT]                              AS MEAS_UNIT
       ,v0.[ITEM_CAT_CODE]                          AS ITEM_CAT_CODE
       ,v0.[ITEM_CAT_NAME]                          AS ITEM_CAT_NAME
       ,v0.[OPR_LEVEL_CODE]                         AS OPR_LEVEL_CODE
       ,v0.[OPR_LEVEL_NAME]                         AS OPR_LEVEL_NAME
       ,v0.[CREATE_USER]                            AS CREATE_USER
       ,v0.[CREATE_TIME]                            AS CREATE_TIME
       ,v0.[UPDATE_USER]                            AS UPDATE_USER
       ,v0.[UPDATE_TIME]                            AS UPDATE_TIME
       ,v0.[REMARK]                                 AS REMARK
       ,v0.[SCORE_REASON]                           AS SCORE_REASON
       ,CAST(v0.[RVU_VAL]       AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(v0.[EXEC_COFF]     AS DECIMAL(18,8))  AS EXEC_COFF
       ,CAST(v0.[DECISION_COFF] AS DECIMAL(18,8))  AS DECISION_COFF
       ,CAST(v0.[UNIT_PRICE]    AS DECIMAL(18,8))  AS UNIT_PRICE
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
    f.[项目代码]                                              AS [项目代码]
   ,f.[项目名称]                                              AS [项目名称]

   ,v.[ITEM_CAT_CODE]                                         AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                         AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                      AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                      AS [执行系数]

    -- 【聚合降维】剥离 f.[单价] 分组维度：正反向交易（退费/异动）归并后按 金额 ÷ 数量 动态计算加权平均单价
    -- 【零除保护】汇总数量为 0（净额完全抵消）时单价兜底为 0，严禁裸除法
   ,CASE
        WHEN SUM(CAST(f.[数量] AS DECIMAL(18,8))) = 0 THEN CAST(0 AS DECIMAL(18,8))
        ELSE CAST(SUM(CAST(f.[金额] AS DECIMAL(18,8))) / SUM(CAST(f.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8))
    END                                                       AS [单价]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [数量]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [金额]

   ,CAST(1.0 AS DECIMAL(18,8))                                AS [学科系数]

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

   ,CAST(v.[RVU_VAL] * SUM(CAST(f.[数量] AS DECIMAL(18,8))) * CAST(1.0 AS DECIMAL(18,8)) * ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [积分]
   ,CONCAT(
        CAST(CAST(v.[RVU_VAL] AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × '
       ,CAST(CAST(SUM(CAST(f.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × 1.00000000 × '
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
  AND f.[来源] = N'门诊'
  AND (f.[执行科室代码] IS NULL OR f.[执行科室代码] <> 36)
  AND (f.[执行人员代码] NOT IN (123, 2523, 2343) OR f.[执行人员代码] IS NULL)
GROUP BY
    f.[项目代码]
   ,f.[项目名称]
   ,v.[ITEM_CAT_CODE]
   ,v.[ITEM_CAT_NAME]
   ,v.[RVU_VAL]
   ,v.[EXEC_COFF]
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
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [RVU_VAL],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[缴费日期年份] AS INT)                       AS [CALC_YEAR],
    CAST(f.[缴费日期月份] AS INT)                       AS [CALC_MONTH],
    N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'              AS [ITEM_CODE],
    N'门诊诊察类项目执行积分_非小儿科'                  AS [ITEM_NAME],
    N'门诊诊察类项目执行积分_非小儿科.sql'              AS [SCRIPT_NAME],
    f.[执行人员所在核算单元编码]                         AS [UNIT_CODE],
    f.[执行人员所在核算单元名称]                         AS [UNIT_NAME],
    f.[项目代码]                                        AS [PROJ_CODE],
    f.[项目名称]                                        AS [PROJ_NAME],
    f.[绩效大类编码]                                    AS [ITEM_CAT_CODE],
    f.[绩效大类名称]                                    AS [ITEM_CAT_NAME],
    CAST(f.[项目点数] AS DECIMAL(18,8))                 AS [RVU_VAL],
    N'执行人员'                                         AS [EXEC_ROLE],
    ISNULL(mdm_exec_staff.[staff_code], N'未匹配')      AS [STAFF_CODE],
    f.[执行人员]                                        AS [STAFF_NAME],
    f.[日期类型编码]                                    AS [DAY_TYPE_CODE],
    f.[日期类型名称]                                    AS [DAY_TYPE_NAME],
    N'SCORE'                                           AS [FINAL_VALUE_TYPE],
    CAST(f.[积分] AS DECIMAL(18,8))                     AS [FINAL_VALUE],
    CAST(f.[数量] AS DECIMAL(18,8))                     AS [TOTAL_QTY],
    CONCAT(
        N'门诊诊察类项目执行积分_非小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
       ,f.[积分计算过程]
       ,' = '
       ,CAST(CAST(f.[积分] AS DECIMAL(18,8)) AS VARCHAR(50))
    )                                                   AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[缴费日期年份] AS VARCHAR(11))                  AS [核算年份],
            CAST(f.[缴费日期月份] AS VARCHAR(11))                  AS [核算月份],
            N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'                  AS [核算项编码],
            N'门诊诊察类项目执行积分_非小儿科'                      AS [核算项名称],
            N'门诊诊察类项目执行积分_非小儿科.sql'                  AS [脚本名称],
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
                N'门诊诊察类项目执行积分_非小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
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
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'
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