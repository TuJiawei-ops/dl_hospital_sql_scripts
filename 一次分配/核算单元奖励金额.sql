/* ===============================================================================
  Relative Path : 一次分配/核算单元奖励金额.sql
  脚本名称: 核算单元奖励金额.sql
  业务说明: 核算单元奖励金额 = 奖励类奖惩明细金额按「核算单元 × 员工 × 奖惩项目」单行聚合落库
            （category='REWARD' × metric_type='AMOUNT'），同键多笔 SUM 累加，结果恒为正数绝对值，作为一次分配结算中的独立加项展列。
  数据流向: dbo.[dwd_fin_reward_punish_detail] → dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
            (ITEM_CODE=ITEM_UNIT_REWARD_AMOUNT / FINAL_VALUE_TYPE=AMOUNT)
  粒度定义: 核算单元 × 员工(STAFF_CODE，缺省 'NONE') × 奖惩项目(PROJ_CODE ← item_code) 单行唯一，与唯一键
            UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 对齐；PROJ_CODE 直取基表 [item_code]，[EXEC_ROLE]/[DAY_TYPE_CODE] 显式写死 N'NONE'。
  模板占位符: '{year}' / '{month}' / {struct_codes}

  ── 数据源契约（dwd_fin_reward_punish_detail）──
  账期/方向卡口: [calc_year] INT / [calc_month] INT / [metric_type] = 'AMOUNT'（金额·元）/ [category] = 'REWARD'（奖励）
  数值语义: [unit_price] / [quantity] / [amount] 均 DECIMAL(18,8)，受物理 CHECK >= 0 约束恒为正数绝对值
  维度语义: [unit_code] / [unit_name] 强制 NOT NULL；[staff_code] 允许 NULL（NULL=科室整体奖惩，落库兜底 'NONE'）
  分类维度: [item_cat_code]/[item_cat_name] 业务大类、[item_code]/[item_name] 奖惩项目

  ── JSON 结构（主体 + 快照）──
  主体: 核算年月 / 机构 / 核算单元 / 员工 / 奖惩方向 / 奖惩大类 / 奖惩项目 / 金额合计 / 数量合计 / 明细笔数 /
        发生日期起止 / 计算过程描述。
  快照: [奖惩明细快照] = 当前汇总键对应的原始基表明细数组（JSON_QUERY + FOR JSON PATH，按明细ID升序）。

  修改日志:
  2026-10-12 23:55:00 | 结构对齐 | 标头精简为业务契约（撤销纠偏条款）；CALC_DETAIL_JSON 升级为「主体 + 快照」双层结构，主体携带汇总因子与计算过程描述，嵌套 [奖惩明细快照]（同键原始基表明细数组，JSON_QUERY + FOR JSON PATH）；src 增补 [unit_price]/[create_user]；三层聚合与 CROSS APPLY TOP (1) 直取口径零改动。
  2026-10-12 23:40:00 | 极简瘦身 | 属性代表值降维为 final 内 CROSS APPLY TOP (1) 确定性直取，CTE 链收敛为 src → agg → final 三层。
  2026-10-12 23:00:00 | 极简瘦身 | JSON 改为单行轻量对象；src 精简至 18 列；agg 增事实级日期区间。
  2026-10-12 21:30:00 | 快照全量化 | 启用 INCLUDE_NULL_VALUES 逐笔快照，键面收敛为 UQ 三键。
  2026-10-12 20:10:00 | 粒度重构 | 落库粒度改为明细级，JSON 改为逐笔快照数组。
  2026-10-12 19:10:00 | 脚本新建 | 新建核算单元奖励金额算子。
  =============================================================================== */

-- 第一区块：生成与落库
~
-- 幂等清理历史数据
-- 占位符条件独占成行
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_UNIT_REWARD_AMOUNT'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 算子计算与落库
WITH
-- 奖惩明细卡口直拉
src AS (
    SELECT
        r.[id]                                             AS DETAIL_ID,
        r.[record_date]                                    AS RECORD_DATE,
        r.[org_code]                                       AS ORG_CODE,
        r.[org_name]                                       AS ORG_NAME,
        r.[unit_code]                                      AS UNIT_CODE,
        r.[unit_name]                                      AS UNIT_NAME,
        -- UQ 键位兜底值（科室整体奖惩落 'NONE'）
        ISNULL(r.[staff_code], N'NONE')                    AS STAFF_CODE,
        r.[staff_name]                                     AS STAFF_NAME,
        r.[item_cat_code]                                  AS ITEM_CAT_CODE,
        r.[item_cat_name]                                  AS ITEM_CAT_NAME,
        r.[item_code]                                      AS ITEM_CODE,
        r.[item_name]                                      AS ITEM_NAME,
        CAST(r.[unit_price] AS DECIMAL(18,8))              AS UNIT_PRICE,
        CAST(r.[quantity]   AS DECIMAL(18,8))              AS QUANTITY,
        CAST(r.[amount]     AS DECIMAL(18,8))              AS AMOUNT,
        r.[remark]                                         AS REMARK,
        r.[create_user]                                    AS CREATE_USER,
        r.[create_time]                                    AS CREATE_TIME,
        r.[update_user]                                    AS UPDATE_USER,
        r.[update_time]                                    AS UPDATE_TIME
    FROM dbo.[dwd_fin_reward_punish_detail] AS r WITH (NOLOCK)
    -- 占位符条件独占成行
    WHERE 1=1
      AND r.[calc_year]   = CAST('{year}'  AS INT)
      AND r.[calc_month]  = CAST('{month}' AS INT)
      AND r.[metric_type] = N'AMOUNT'
      AND r.[category]    = N'REWARD'
      AND r.[unit_code] IN {struct_codes}
),

-- UQ 三键聚合（单行唯一，零撞键）
agg AS (
    SELECT
        s.[UNIT_CODE],
        s.[STAFF_CODE],
        s.[ITEM_CODE]                                      AS PROJ_CODE,
        CAST(SUM(s.[AMOUNT])   AS DECIMAL(18,8))           AS REWARD_AMOUNT,
        CAST(SUM(s.[QUANTITY]) AS DECIMAL(18,8))           AS TOTAL_QTY,
        CAST(COUNT(1)          AS DECIMAL(18,8))           AS DETAIL_ROWS,
        -- 事实级发生日期区间
        MIN(s.[RECORD_DATE])                               AS DATE_FROM,
        MAX(s.[RECORD_DATE])                               AS DATE_TO
    FROM src AS s
    GROUP BY
        s.[UNIT_CODE],
        s.[STAFF_CODE],
        s.[ITEM_CODE]
),

-- 出口与审计文本
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(4))                      AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(2))                      AS CALC_MONTH,
        k.[ORG_CODE],
        k.[ORG_NAME],
        a.[UNIT_CODE],
        k.[UNIT_NAME],
        a.[STAFF_CODE],
        k.[STAFF_NAME],
        k.[ITEM_CAT_CODE],
        k.[ITEM_CAT_NAME],
        a.[PROJ_CODE],
        k.[ITEM_NAME]                                      AS PROJ_NAME,
        a.[REWARD_AMOUNT],
        a.[TOTAL_QTY],
        a.[DETAIL_ROWS],
        -- 明细层日期文本化
        CONVERT(VARCHAR(10), a.[DATE_FROM], 120)           AS DATE_FROM,
        CONVERT(VARCHAR(10), a.[DATE_TO],   120)           AS DATE_TO,
        -- 审计文本三段式
        CONCAT(
            N'核算单元奖励金额 | 核算单元奖励金额 = 奖励类明细金额逐笔累加（同键多笔归并，正数绝对值） | '
           ,'0.00000000 + '
           ,CAST(a.[REWARD_AMOUNT] AS VARCHAR(50)), ' = '
           ,CAST(a.[REWARD_AMOUNT] AS VARCHAR(50))
        )                                                  AS CALC_PROCESS_TEXT
    FROM agg AS a
    -- 属性代表值：确定性直取最新一笔
    CROSS APPLY (
        SELECT TOP (1)
            s.[UNIT_NAME],
            s.[STAFF_NAME],
            s.[ITEM_CAT_CODE],
            s.[ITEM_CAT_NAME],
            s.[ITEM_NAME],
            s.[ORG_CODE],
            s.[ORG_NAME]
        FROM src AS s
        WHERE s.[UNIT_CODE]  = a.[UNIT_CODE]
          AND s.[STAFF_CODE] = a.[STAFF_CODE]
          AND s.[ITEM_CODE]  = a.[PROJ_CODE]
        ORDER BY s.[DETAIL_ID] DESC
    ) AS k
)

-- 落库封装
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[CALC_YEAR]  AS INT)                          AS [CALC_YEAR],
    CAST(f.[CALC_MONTH] AS INT)                          AS [CALC_MONTH],
    N'ITEM_UNIT_REWARD_AMOUNT'                           AS [ITEM_CODE],
    N'核算单元奖励金额'                                   AS [ITEM_NAME],
    N'核算单元奖励金额.sql'                               AS [SCRIPT_NAME],
    f.[UNIT_CODE]                                        AS [UNIT_CODE],
    f.[UNIT_NAME]                                        AS [UNIT_NAME],
    f.[PROJ_CODE]                                        AS [PROJ_CODE],
    f.[PROJ_NAME]                                        AS [PROJ_NAME],
    f.[ITEM_CAT_CODE]                                    AS [ITEM_CAT_CODE],
    f.[ITEM_CAT_NAME]                                    AS [ITEM_CAT_NAME],
    -- 键位显式化和 UQ 定位
    N'NONE'                                              AS [EXEC_ROLE],
    f.[STAFF_CODE]                                       AS [STAFF_CODE],
    f.[STAFF_NAME]                                       AS [STAFF_NAME],
    N'NONE'                                              AS [DAY_TYPE_CODE],
    -- 值类型锁定 AMOUNT
    N'AMOUNT'                                            AS [FINAL_VALUE_TYPE],
    CAST(f.[REWARD_AMOUNT] AS DECIMAL(18,8))             AS [FINAL_VALUE],
    CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))                 AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                                AS [CALC_PROCESS_TEXT],
    (
        -- 主体 + 快照双层结构（主体看汇总，快照看明细）
        SELECT
            f.[CALC_YEAR]                                 AS [核算年份],
            f.[CALC_MONTH]                                AS [核算月份],
            f.[ORG_CODE]                                  AS [机构编码],
            f.[ORG_NAME]                                  AS [机构名称],
            f.[UNIT_CODE]                                 AS [核算单元编码],
            f.[UNIT_NAME]                                 AS [核算单元名称],
            f.[STAFF_CODE]                                AS [员工编码],
            f.[STAFF_NAME]                                AS [员工姓名],
            N'REWARD'                                     AS [奖惩方向],
            N'AMOUNT'                                     AS [度量类型],
            f.[ITEM_CAT_CODE]                             AS [奖惩大类编码],
            f.[ITEM_CAT_NAME]                             AS [奖惩大类名称],
            f.[PROJ_CODE]                                 AS [奖惩项目编码],
            f.[PROJ_NAME]                                 AS [奖惩项目名称],
            CAST(f.[REWARD_AMOUNT] AS DECIMAL(18,8))      AS [金额合计],
            CAST(f.[TOTAL_QTY]     AS DECIMAL(18,8))      AS [数量合计],
            CAST(f.[DETAIL_ROWS]   AS DECIMAL(18,8))      AS [明细笔数],
            f.[DATE_FROM]                                 AS [发生日期起],
            f.[DATE_TO]                                   AS [发生日期止],
            f.[CALC_PROCESS_TEXT]                         AS [计算过程描述],
            -- 快照层：同键原始基表明细数组（方向与度量由 src 卡口锁定，见主体）
            JSON_QUERY((
                SELECT
                    s.[DETAIL_ID]                              AS [明细ID],
                    CONVERT(VARCHAR(10), s.[RECORD_DATE], 120) AS [发生日期],
                    s.[ORG_CODE]                               AS [机构编码],
                    s.[ORG_NAME]                               AS [机构名称],
                    s.[UNIT_CODE]                              AS [核算单元编码],
                    s.[UNIT_NAME]                              AS [核算单元名称],
                    s.[STAFF_CODE]                             AS [员工编码],
                    s.[STAFF_NAME]                             AS [员工姓名],
                    s.[ITEM_CAT_CODE]                          AS [奖惩大类编码],
                    s.[ITEM_CAT_NAME]                          AS [奖惩大类名称],
                    s.[ITEM_CODE]                              AS [奖惩项目编码],
                    s.[ITEM_NAME]                              AS [奖惩项目名称],
                    s.[UNIT_PRICE]                             AS [标准值],
                    s.[QUANTITY]                               AS [数量],
                    s.[AMOUNT]                                 AS [奖惩金额],
                    s.[REMARK]                                 AS [事由备注],
                    s.[CREATE_USER]                            AS [创建人],
                    CONVERT(VARCHAR(19), s.[CREATE_TIME], 120)  AS [创建时间],
                    s.[UPDATE_USER]                            AS [修改人],
                    CONVERT(VARCHAR(19), s.[UPDATE_TIME], 120)  AS [修改时间]
                FROM src AS s
                WHERE s.[UNIT_CODE]  = f.[UNIT_CODE]
                  AND s.[STAFF_CODE] = f.[STAFF_CODE]
                  AND s.[ITEM_CODE]  = f.[PROJ_CODE]
                ORDER BY s.[DETAIL_ID]
                FOR JSON PATH
            ))                                                AS [奖惩明细快照]
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
        [STAFF_CODE]            AS [员工编码],
        [STAFF_NAME]            AS [员工姓名],
        [ITEM_CAT_CODE]         AS [绩效核算大类编码],
        [ITEM_CAT_NAME]         AS [绩效核算大类名称],
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
      AND [ITEM_CODE]  = N'ITEM_UNIT_REWARD_AMOUNT'
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
