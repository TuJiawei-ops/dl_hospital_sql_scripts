/* ===============================================================================
  Relative Path : 一次分配/专项激励金额.sql
  脚本名称: 专项激励金额.sql
  业务说明: 专项激励金额 = SUM(数量) × 专项激励金额标准(incentive_money)，按 核算单元 × 项目 粒度落库
  数据流向: PF临时医疗服务项目26A → sjjk_bmb_2025_06_01 → sjjk_DEPT_UNIT_MAPPING_2025_11_27
            → dim_prf_special_incentive → DWD_FIN_CALC_ALLOC1_DETAIL_LOG
            (ITEM_CODE=ITEM_SPECIAL_INCENTIVE / FINAL_VALUE_TYPE=AMOUNT)
  粒度定义: 核算单元编码 × 核算单元名称 × 项目代码
  模板占位符: '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes}

  修改日志:
  2026-10-12 13:30:00 | 脚本新建 | 新建专项激励金额算子：完成配置表直连、算式降维、AMOUNT 落库与去熵瘦身。
  =============================================================================== */

-- 第一区块：生成与落库
~
-- 幂等清理历史数据
-- 占位符条件独占成行
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_SPECIAL_INCENTIVE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 算子计算与落库
WITH
-- 部门字典桥接
bmb_bridge AS (
    SELECT
        b.[id]                          AS DEPT_ID,
        b.[编码]                        AS HIS_DEPT_CODE
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
),

-- 事实层时间窗
fact_raw AS (
    SELECT
        a.[项目代码]                                   AS PROJ_CODE,
        a.[项目名称]                                   AS PROJ_NAME,
        b.[HIS_DEPT_CODE],
        a.[缴费时间]                                   AS PAY_TIME,
        CAST(a.[数量] AS DECIMAL(18,8))                AS QTY
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    INNER JOIN bmb_bridge AS b
        ON a.[开单科室代码] = b.[DEPT_ID]
    -- 占位符条件独占成行
    WHERE 1=1
      AND a.[缴费时间] >= CAST('{start_time}' AS DATETIME)
      AND a.[缴费时间] <= CAST('{end_time}' AS DATETIME)
),

-- 拉链映射维表
dept_unit_mapping AS (
    SELECT
        m.[ID]                          AS MAPPING_ID,
        m.[HIS_DEPT_CODE],
        m.[HPS_DEPT_CODE],
        m.[HPS_DEPT_NAME],
        m.[START_DATE],
        m.[END_DATE]
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] IN ('1001', '1021', '1005')
),

-- 专项激励配置维表
incentive_cfg AS (
    SELECT
        c.[org_code]                                   AS ORG_CODE,
        c.[org_name]                                   AS ORG_NAME,
        c.[item_code]                                  AS ITEM_CODE,
        c.[item_name]                                  AS ITEM_NAME,
        c.[effective_date]                             AS EFFECTIVE_DATE,
        c.[expire_date]                                AS EXPIRE_DATE,
        c.[incentive_money]                            AS INCENTIVE_MONEY,
        c.[remark]                                     AS REMARK,
        c.[create_user]                                AS CREATE_USER,
        c.[create_time]                                AS CREATE_TIME,
        c.[update_user]                                AS UPDATE_USER,
        c.[update_time]                                AS UPDATE_TIME
    FROM dbo.[dim_prf_special_incentive] AS c WITH (NOLOCK)
    -- 机构口径锁定
    WHERE 1=1
      AND c.[org_code]  = N'1001'
      AND c.[item_code] IS NOT NULL
),

-- 明细计算
src AS (
    SELECT
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[QTY],
        ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN')                      AS UNIT_CODE,
        ISNULL(m.[HPS_DEPT_NAME], '未映射核算单元')                 AS UNIT_NAME,
        c.[ORG_CODE],
        c.[ORG_NAME],
        c.[ITEM_NAME]                                             AS CFG_ITEM_NAME,
        c.[EFFECTIVE_DATE],
        c.[EXPIRE_DATE],
        c.[INCENTIVE_MONEY],
        CAST(f.[QTY] * c.[INCENTIVE_MONEY] AS DECIMAL(18,8))        AS ITEM_AMOUNT
    FROM fact_raw AS f
    INNER JOIN incentive_cfg AS c
        ON f.[PROJ_CODE] = c.[ITEM_CODE]
       AND f.[PAY_TIME] >= c.[EFFECTIVE_DATE]
       AND f.[PAY_TIME] <  DATEADD(DAY, 1, c.[EXPIRE_DATE])
    LEFT JOIN dept_unit_mapping AS m
        ON f.[HIS_DEPT_CODE] = m.[HIS_DEPT_CODE]
       AND f.[PAY_TIME] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR f.[PAY_TIME] < m.[END_DATE])
),

-- 账期与单元聚合
agg AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10))                              AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10))                              AS CALC_MONTH,
        s.[UNIT_CODE],
        s.[UNIT_NAME],
        s.[PROJ_CODE],
        s.[PROJ_NAME],
        s.[ORG_CODE],
        s.[ORG_NAME],
        s.[CFG_ITEM_NAME],
        s.[EFFECTIVE_DATE],
        s.[EXPIRE_DATE],
        s.[INCENTIVE_MONEY],
        CAST(SUM(s.[QTY])         AS DECIMAL(18,8))                 AS TOTAL_QTY,
        CAST(SUM(s.[ITEM_AMOUNT]) AS DECIMAL(18,8))                 AS SPECIAL_INCENTIVE_AMOUNT
    FROM src AS s
    GROUP BY
        s.[UNIT_CODE],
        s.[UNIT_NAME],
        s.[PROJ_CODE],
        s.[PROJ_NAME],
        s.[ORG_CODE],
        s.[ORG_NAME],
        s.[CFG_ITEM_NAME],
        s.[EFFECTIVE_DATE],
        s.[EXPIRE_DATE],
        s.[INCENTIVE_MONEY]
),

-- 出口与过程仓打包
final AS (
    SELECT
        a.[CALC_YEAR],
        a.[CALC_MONTH],
        a.[UNIT_CODE],
        a.[UNIT_NAME],
        a.[PROJ_CODE],
        a.[PROJ_NAME],
        a.[ORG_CODE],
        a.[ORG_NAME],
        a.[CFG_ITEM_NAME],
        CONVERT(VARCHAR(10), a.[EFFECTIVE_DATE], 120)               AS EFFECTIVE_DATE,
        CONVERT(VARCHAR(10), a.[EXPIRE_DATE], 120)                  AS EXPIRE_DATE,
        a.[INCENTIVE_MONEY],
        a.[TOTAL_QTY],
        a.[SPECIAL_INCENTIVE_AMOUNT],
        -- 审计文本三段式
        CONCAT(
            N'专项激励金额 | 项目专项激励 = 汇总数量 × 专项激励金额标准 | '
           ,CAST(a.[TOTAL_QTY]                AS VARCHAR(50)), ' × '
           ,CAST(a.[INCENTIVE_MONEY]          AS VARCHAR(50)), ' = '
           ,CAST(a.[SPECIAL_INCENTIVE_AMOUNT] AS VARCHAR(50))
        )                                                           AS CALC_PROCESS_TEXT
    FROM agg AS a
    -- 占位符条件独占成行
    WHERE a.[UNIT_CODE] IN {struct_codes}
)

-- 落库封装
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[CALC_YEAR]  AS INT)                          AS [CALC_YEAR],
    CAST(f.[CALC_MONTH] AS INT)                          AS [CALC_MONTH],
    N'ITEM_SPECIAL_INCENTIVE'                            AS [ITEM_CODE],
    N'专项激励金额'                                       AS [ITEM_NAME],
    N'专项激励金额.sql'                                   AS [SCRIPT_NAME],
    f.[UNIT_CODE]                                        AS [UNIT_CODE],
    f.[UNIT_NAME]                                        AS [UNIT_NAME],
    f.[PROJ_CODE]                                        AS [PROJ_CODE],
    f.[PROJ_NAME]                                        AS [PROJ_NAME],
    -- 值类型锁定 AMOUNT
    N'AMOUNT'                                            AS [FINAL_VALUE_TYPE],
    CAST(f.[SPECIAL_INCENTIVE_AMOUNT] AS DECIMAL(18,8))   AS [FINAL_VALUE],
    CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))                  AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                                AS [CALC_PROCESS_TEXT],
    (
        SELECT
            f.[CALC_YEAR]                                 AS [核算年份],
            f.[CALC_MONTH]                                AS [核算月份],
            f.[UNIT_CODE]                                 AS [核算单元编码],
            f.[UNIT_NAME]                                 AS [核算单元名称],
            f.[PROJ_CODE]                                 AS [项目代码],
            f.[PROJ_NAME]                                 AS [项目名称],
            f.[ORG_CODE]                                  AS [机构编码],
            f.[ORG_NAME]                                  AS [机构名称],
            f.[EFFECTIVE_DATE]                            AS [生效日期],
            f.[EXPIRE_DATE]                               AS [失效日期],
            f.[INCENTIVE_MONEY]                           AS [专项激励金额标准],
            f.[TOTAL_QTY]                                 AS [汇总数量],
            f.[SPECIAL_INCENTIVE_AMOUNT]                  AS [专项激励金额],
            f.[CALC_PROCESS_TEXT]                         AS [计算过程描述],
            -- 配置全字段快照
            JSON_QUERY((
                SELECT
                    c.[ORG_CODE]                              AS [机构编码],
                    c.[ORG_NAME]                              AS [机构名称],
                    c.[ITEM_CODE]                             AS [项目编码],
                    c.[ITEM_NAME]                             AS [项目名称],
                    CONVERT(VARCHAR(10), c.[EFFECTIVE_DATE], 120) AS [生效日期],
                    CONVERT(VARCHAR(10), c.[EXPIRE_DATE], 120)    AS [失效日期],
                    c.[INCENTIVE_MONEY]                       AS [专项激励金额标准],
                    c.[REMARK]                                AS [备注],
                    c.[CREATE_USER]                           AS [创建人],
                    CONVERT(VARCHAR(19), c.[CREATE_TIME], 120) AS [创建时间],
                    c.[UPDATE_USER]                           AS [修改人],
                    CONVERT(VARCHAR(19), c.[UPDATE_TIME], 120) AS [修改时间]
                FROM incentive_cfg AS c
                WHERE c.[ORG_CODE] = f.[ORG_CODE]
                  AND c.[ITEM_CODE] = f.[PROJ_CODE]
                  AND CONVERT(VARCHAR(10), c.[EFFECTIVE_DATE], 120) = f.[EFFECTIVE_DATE]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ))                                            AS [专项激励配置快照]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                    AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                        AS [CREATE_TIME]
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
      AND [ITEM_CODE]  = N'ITEM_SPECIAL_INCENTIVE'
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
