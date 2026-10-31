/* ===============================================================================
  Relative Path : 一次分配/一次分配最终绩效金额.sql
  脚本名称: 一次分配最终绩效金额.sql
  业务说明: 汇总当月核算单元涉及的各个核算子项（10 加 1 减），动态读取
            DWD_FIN_CALC_ALLOC1_DETAIL_LOG 表中各项真实 ITEM_NAME 并代数求和，
            最终结果四舍五入取整后落库。
  数据流向: dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]（11 项一次分配子项）
            → dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
            (ITEM_CODE=ITEM_ALLOC1_FINAL_PERF_AMOUNT / FINAL_VALUE_TYPE=AMOUNT)
  粒度定义: 核算单元(UNIT_CODE) 单行唯一；PROJ_CODE 兜底 N'NONE'；
            EXEC_ROLE / STAFF_CODE / DAY_TYPE_CODE 恒为 N'NONE'
  模板占位符: '{year}' / '{month}' / {struct_codes}

  关键约束: 源过滤显式排除自身核算项 ITEM_ALLOC1_FINAL_PERF_AMOUNT，杜绝二次重算自增；
            全部子项名称从日志表动态映射，交叉透视层零硬编码名称；
            每个核算单元的最终绩效在落库前四舍五入取整到元，FINAL_VALUE 与审计文本、
            CALC_DETAIL_JSON（取整前 / 取整差额 / 取整后）三处口径一致。

  修改日志:
  2026-10-31 09:30:00 | 取整环节 | 每个核算单元最终绩效新增「四舍五入取整到元」步骤：FINAL_VALUE 落取整后金额，审计文本增加取整结算段，JSON 补取整前金额/取整方式/取整差额。
  2026-10-27 18:00:00 | 脚本重构 | 物理更名为 一次分配最终绩效金额.sql，解耦硬编码，动态映射日志表 ITEM_NAME。
   =============================================================================== */

-- 第一区块：生成与落库
~
-- 幂等清理历史数据
-- 占位符条件独占成行
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_ALLOC1_FINAL_PERF_AMOUNT'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 算子计算与落库
WITH
-- 核算日志抽离（排除自身，防重算自增）
src_log AS (
    SELECT
        l.[ID]                                          AS LOG_ID,
        l.[UNIT_CODE],
        l.[UNIT_NAME],
        l.[ITEM_CODE],
        l.[ITEM_NAME],
        CAST(l.[FINAL_VALUE] AS DECIMAL(18,8))          AS FINAL_VALUE
    FROM dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] AS l WITH (NOLOCK)
    -- 占位符条件独占成行
    WHERE 1=1
      AND l.[CALC_YEAR]  = CAST('{year}'  AS INT)
      AND l.[CALC_MONTH] = CAST('{month}' AS INT)
      AND l.[ITEM_CODE] <> N'ITEM_ALLOC1_FINAL_PERF_AMOUNT'
      AND l.[ITEM_CODE] IN (
            N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE'
          , N'ITEM_MED_SVC_ORDER_SCORE'
          , N'ITEM_MED_SVC_EXEC_SCORE'
          , N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'
          , N'ITEM_OUTPATIENT_DIAG_SCORE_PED'
          , N'ITEM_DISCHARGE_PERSON_COUNT_SCORE'
          , N'ITEM_ADM_NOTICE_SCORE'
          , N'ITEM_SPECIAL_INCENTIVE'
          , N'ITEM_UNIT_REWARD_AMOUNT'
          , N'ITEM_UNIT_PUNISH_AMOUNT'
          , N'ITEM_OFFLINE_WORKLOAD_PERF'
      )
      AND l.[UNIT_CODE] IN {struct_codes}
),

-- 核算项名称真理源（日志最新名称 1:1）
dim_item_name AS (
    SELECT
        x.[ITEM_CODE],
        x.[ITEM_NAME]
    FROM (
        SELECT
            l.[ITEM_CODE],
            l.[ITEM_NAME],
            ROW_NUMBER() OVER (PARTITION BY l.[ITEM_CODE] ORDER BY l.[LOG_ID] DESC) AS RN
        FROM src_log AS l
    ) AS x
    WHERE x.[RN] = 1
),

-- 核算单元名称确定性收敛（多名称不拆组）
unit_name AS (
    SELECT
        x.[UNIT_CODE],
        x.[UNIT_NAME]
    FROM (
        SELECT
            l.[UNIT_CODE],
            l.[UNIT_NAME],
            ROW_NUMBER() OVER (PARTITION BY l.[UNIT_CODE] ORDER BY l.[LOG_ID] DESC) AS RN
        FROM src_log AS l
    ) AS x
    WHERE x.[RN] = 1
),

-- 单元维度透视与加减代数和
unit_agg AS (
    SELECT
        a.[UNIT_CODE],
        a.[UNIT_NAME],
        a.[ENROLL_SCORE],
        a.[ORDER_SCORE],
        a.[EXEC_SCORE],
        a.[DIAG_NON_PED_SCORE],
        a.[DIAG_PED_SCORE],
        a.[DISCHARGE_SCORE],
        a.[ADM_NOTICE_SCORE],
        a.[SPECIAL_INCENTIVE],
        a.[UNIT_REWARD],
        a.[UNIT_PUNISH],
        a.[OFFLINE_PERF],
        CAST(
            a.[ENROLL_SCORE]
          + a.[ORDER_SCORE]
          + a.[EXEC_SCORE]
          + a.[DIAG_NON_PED_SCORE]
          + a.[DIAG_PED_SCORE]
          + a.[DISCHARGE_SCORE]
          + a.[ADM_NOTICE_SCORE]
          + a.[SPECIAL_INCENTIVE]
          + a.[UNIT_REWARD]
          - a.[UNIT_PUNISH]
          + a.[OFFLINE_PERF]
        AS DECIMAL(18,8))                               AS FINAL_PERF_RAW
    FROM (
        SELECT
            s.[UNIT_CODE],
            n.[UNIT_NAME],
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE'    THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS ENROLL_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_MED_SVC_ORDER_SCORE'            THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS ORDER_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_MED_SVC_EXEC_SCORE'             THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS EXEC_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'  THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS DIAG_NON_PED_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_OUTPATIENT_DIAG_SCORE_PED'      THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS DIAG_PED_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_DISCHARGE_PERSON_COUNT_SCORE'   THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS DISCHARGE_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_ADM_NOTICE_SCORE'               THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS ADM_NOTICE_SCORE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_SPECIAL_INCENTIVE'              THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS SPECIAL_INCENTIVE,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_UNIT_REWARD_AMOUNT'             THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS UNIT_REWARD,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_UNIT_PUNISH_AMOUNT'             THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS UNIT_PUNISH,
            CAST(ISNULL(SUM(CASE WHEN s.[ITEM_CODE] = N'ITEM_OFFLINE_WORKLOAD_PERF'          THEN s.[FINAL_VALUE] ELSE 0 END), 0) AS DECIMAL(18,8)) AS OFFLINE_PERF
        FROM src_log AS s
        LEFT JOIN unit_name AS n
            ON n.[UNIT_CODE] = s.[UNIT_CODE]
        GROUP BY
            s.[UNIT_CODE],
            n.[UNIT_NAME]
    ) AS a
),

-- 最终取整：四舍五入到元（0 位小数），持久化以此为准
unit_calc AS (
    SELECT
        u.[UNIT_CODE],
        u.[UNIT_NAME],
        u.[ENROLL_SCORE],
        u.[ORDER_SCORE],
        u.[EXEC_SCORE],
        u.[DIAG_NON_PED_SCORE],
        u.[DIAG_PED_SCORE],
        u.[DISCHARGE_SCORE],
        u.[ADM_NOTICE_SCORE],
        u.[SPECIAL_INCENTIVE],
        u.[UNIT_REWARD],
        u.[UNIT_PUNISH],
        u.[OFFLINE_PERF],
        u.[FINAL_PERF_RAW],
        CAST(ROUND(u.[FINAL_PERF_RAW], 0) AS DECIMAL(18,8)) AS FINAL_PERF
    FROM unit_agg AS u
),

-- 动态 JSON 明细构建（名称取自 dim_item_name）
item_unpivot AS (
    SELECT
        u.[UNIT_CODE],
        v.[SEQ],
        v.[ITEM_CODE],
        ISNULL(d.[ITEM_NAME], v.[ITEM_CODE])            AS ITEM_NAME,
        v.[OPERATOR],
        CAST(v.[ITEM_VALUE] AS DECIMAL(18,8))           AS ITEM_VALUE
    FROM unit_agg AS u
    CROSS APPLY (VALUES
        (1,  N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE',   N'+', u.[ENROLL_SCORE]),
        (2,  N'ITEM_MED_SVC_ORDER_SCORE',           N'+', u.[ORDER_SCORE]),
        (3,  N'ITEM_MED_SVC_EXEC_SCORE',            N'+', u.[EXEC_SCORE]),
        (4,  N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED', N'+', u.[DIAG_NON_PED_SCORE]),
        (5,  N'ITEM_OUTPATIENT_DIAG_SCORE_PED',     N'+', u.[DIAG_PED_SCORE]),
        (6,  N'ITEM_DISCHARGE_PERSON_COUNT_SCORE',  N'+', u.[DISCHARGE_SCORE]),
        (7,  N'ITEM_ADM_NOTICE_SCORE',              N'+', u.[ADM_NOTICE_SCORE]),
        (8,  N'ITEM_SPECIAL_INCENTIVE',             N'+', u.[SPECIAL_INCENTIVE]),
        (9,  N'ITEM_UNIT_REWARD_AMOUNT',            N'+', u.[UNIT_REWARD]),
        (10, N'ITEM_UNIT_PUNISH_AMOUNT',            N'-', u.[UNIT_PUNISH]),
        (11, N'ITEM_OFFLINE_WORKLOAD_PERF',         N'+', u.[OFFLINE_PERF])
    ) AS v (SEQ, ITEM_CODE, OPERATOR, ITEM_VALUE)
    LEFT JOIN dim_item_name AS d
        ON d.[ITEM_CODE] = v.[ITEM_CODE]
),

-- 四段式审计文本与打包
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(4))                   AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(2))                   AS CALC_MONTH,
        c.[UNIT_CODE],
        c.[UNIT_NAME],
        c.[ENROLL_SCORE],
        c.[ORDER_SCORE],
        c.[EXEC_SCORE],
        c.[DIAG_NON_PED_SCORE],
        c.[DIAG_PED_SCORE],
        c.[DISCHARGE_SCORE],
        c.[ADM_NOTICE_SCORE],
        c.[SPECIAL_INCENTIVE],
        c.[UNIT_REWARD],
        c.[UNIT_PUNISH],
        c.[OFFLINE_PERF],
        c.[FINAL_PERF_RAW],
        c.[FINAL_PERF],
        -- 审计文本四段式（末段体现取整结算）
        CONCAT(
            N'一次分配最终绩效金额 | '
           ,N'一次分配最终绩效金额 = 10项子金额累加 - 单元惩罚金额，最终结果四舍五入取整 | '
           ,CAST(c.[ENROLL_SCORE]       AS VARCHAR(50)), N' + '
           ,CAST(c.[ORDER_SCORE]        AS VARCHAR(50)), N' + '
           ,CAST(c.[EXEC_SCORE]         AS VARCHAR(50)), N' + '
           ,CAST(c.[DIAG_NON_PED_SCORE] AS VARCHAR(50)), N' + '
           ,CAST(c.[DIAG_PED_SCORE]     AS VARCHAR(50)), N' + '
           ,CAST(c.[DISCHARGE_SCORE]    AS VARCHAR(50)), N' + '
           ,CAST(c.[ADM_NOTICE_SCORE]   AS VARCHAR(50)), N' + '
           ,CAST(c.[SPECIAL_INCENTIVE]  AS VARCHAR(50)), N' + '
           ,CAST(c.[UNIT_REWARD]        AS VARCHAR(50)), N' - '
           ,CAST(c.[UNIT_PUNISH]        AS VARCHAR(50)), N' + '
           ,CAST(c.[OFFLINE_PERF]       AS VARCHAR(50)), N' = '
           ,CAST(c.[FINAL_PERF_RAW]     AS VARCHAR(50)), N' | '
           ,CAST(c.[FINAL_PERF_RAW]     AS VARCHAR(50)), N' = '
           ,CAST(c.[FINAL_PERF]         AS VARCHAR(50))
        )                                               AS CALC_PROCESS_TEXT
    FROM unit_calc AS c
)

-- 落库封装
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[CALC_YEAR]  AS INT)                         AS [CALC_YEAR],
    CAST(f.[CALC_MONTH] AS INT)                         AS [CALC_MONTH],
    N'ITEM_ALLOC1_FINAL_PERF_AMOUNT'                    AS [ITEM_CODE],
    N'一次分配最终绩效金额'                              AS [ITEM_NAME],
    N'一次分配最终绩效金额.sql'                          AS [SCRIPT_NAME],
    f.[UNIT_CODE]                                       AS [UNIT_CODE],
    f.[UNIT_NAME]                                       AS [UNIT_NAME],
    -- 单元粒度无项目码，UQ 兜底 N'NONE'
    N'NONE'                                             AS [PROJ_CODE],
    N'一次分配最终绩效金额'                              AS [PROJ_NAME],
    -- 键位显式化
    N'NONE'                                             AS [EXEC_ROLE],
    N'NONE'                                             AS [STAFF_CODE],
    NULL                                                AS [STAFF_NAME],
    N'NONE'                                             AS [DAY_TYPE_CODE],
    -- 值类型锁定 AMOUNT
    N'AMOUNT'                                           AS [FINAL_VALUE_TYPE],
    CAST(f.[FINAL_PERF] AS DECIMAL(18,8))               AS [FINAL_VALUE],
    CAST(NULL AS DECIMAL(18,8))                         AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                               AS [CALC_PROCESS_TEXT],
    (
        SELECT
            f.[CALC_YEAR]                               AS [核算年份],
            f.[CALC_MONTH]                              AS [核算月份],
            f.[UNIT_CODE]                               AS [核算单元编码],
            f.[UNIT_NAME]                               AS [核算单元名称],
            CAST(f.[FINAL_PERF_RAW] AS DECIMAL(18,8))   AS [取整前金额],
            N'四舍五入取整到元（保留 0 位小数）'          AS [取整方式],
            CAST(f.[FINAL_PERF] - f.[FINAL_PERF_RAW] AS DECIMAL(18,8)) AS [取整差额],
            CAST(f.[FINAL_PERF] AS DECIMAL(18,8))       AS [一次分配最终绩效金额],
            f.[CALC_PROCESS_TEXT]                       AS [计算过程描述],
            -- 子项明细快照（名称动态映射）
            JSON_QUERY((
                SELECT
                    p.[SEQ]                             AS [序号],
                    p.[ITEM_CODE]                       AS [核算项编码],
                    p.[ITEM_NAME]                       AS [核算项名称],
                    p.[OPERATOR]                        AS [运算符],
                    CAST(p.[ITEM_VALUE] AS DECIMAL(18,8)) AS [核算项金额]
                FROM item_unpivot AS p
                WHERE p.[UNIT_CODE] = f.[UNIT_CODE]
                ORDER BY p.[SEQ]
                FOR JSON PATH
            ))                                          AS [核算项明细]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                   AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                       AS [CREATE_TIME]
FROM final AS f;

~
-- 第二区块：接口读取
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
        [FINAL_VALUE_TYPE]      AS [值类型],
        [FINAL_VALUE]           AS [最终结果],
        [TOTAL_QTY]             AS [汇总数量],
        [CALC_PROCESS_TEXT]     AS [计算过程描述],
        [CALC_DETAIL_JSON]      AS [明细JSON],
        CONVERT(VARCHAR(19), [CREATE_TIME], 120) AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    -- 占位符条件独占成行
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_ALLOC1_FINAL_PERF_AMOUNT'
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
