/* ===============================================================================
  Relative Path : 一次分配/核算单元惩罚金额.sql
  脚本名称: 核算单元惩罚金额.sql
  业务说明: 核算单元惩罚金额 = 惩罚类奖惩明细金额逐笔落库（category='PUNISH' × metric_type='AMOUNT'），
            按「核算单元 × 员工 × 奖惩项目」明细粒度入仓，结果恒为正数绝对值，作为一次分配结算中的独立扣减项展列。
  数据流向: dbo.[dwd_fin_reward_punish_detail] → dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
            (ITEM_CODE=ITEM_UNIT_PUNISH_AMOUNT / FINAL_VALUE_TYPE=AMOUNT)
  粒度定义: 核算单元 × 员工(STAFF_CODE，缺省 'NONE') × 奖惩项目(PROJ_CODE ← item_code)，逐笔快照下沉 CALC_DETAIL_JSON
  模板占位符: '{year}' / '{month}' / {struct_codes}

  ── 数据源契约（dwd_fin_reward_punish_detail）──
  账期卡口: [calc_year] INT / [calc_month] INT / [metric_type] = 'AMOUNT'（元；'SCORE' 分属积分算子消费域）
  方向卡口: [category] = 'PUNISH'（惩罚/扣款）
  数值语义: [unit_price] / [quantity] / [amount] 均 DECIMAL(18,8)，受物理 CHECK >= 0 约束恒为正数绝对值
  维度语义: [unit_code] VARCHAR(50) / [unit_name] NVARCHAR(100) 强制 NOT NULL；
            [staff_code] 允许 NULL（NULL=科室整体奖惩，落库兜底 'NONE'；有值=个人奖惩）
  分类维度: [item_cat_code]/[item_cat_name] 业务大类、[item_code]/[item_name] 奖惩项目
  快照来源: [id] / [record_date] / [org_code] / [remark] / [create_user] / [create_time] 序列化入 JSON

  ── 关键纠偏（防熵增）──
  1. 【明细级落库 + UQ 归并】日志表唯一键 UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 真实强制
     (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)；
     粒度锚定该 8 维，同键多笔（同科室同月同项目多笔奖惩）在键面累加，逐笔原始上下文由
     CALC_DETAIL_JSON 快照数组完整保留，规避撞键导致的整批 INSERT 失败。
  2. 【方向隔离】REWARD 由《核算单元奖励金额.sql》独立承载，收支分离、加扣项独立展列；
     本脚本零负号、零 CASE 取反——扣减性质由下游按 ITEM_CODE 独立项判断，严禁在此层写入负数。
  3. 【零符号函数】严禁 ABS() / 取反包装，非负性由 ck_dwd_fin_reward_punish_detail_amount 内核保障。
  4. 【落库键位显式化】PROJ_CODE 直取基表 [item_code]；EXEC_ROLE / DAY_TYPE_CODE 显式写死 N'NONE'
     （非角色/日历粒度），STAFF_CODE 显式 ISNULL(..., N'NONE')，三列均为 UQ 定位维度，严禁静默依赖默认值。
  5. 【精度对齐】金额与中间量统一 DECIMAL(18,8)；明细层账期与日期时间字段强制文本化（VARCHAR）。

  修改日志:
  2026-10-12 20:12:00 | 粒度重构 | 落库粒度由「核算单元级 + 大类/项目树形 JSON」改为「明细级」：PROJ_CODE/PROJ_NAME/ITEM_CAT_CODE/ITEM_CAT_NAME/STAFF_CODE/STAFF_NAME 直取基表，EXEC_ROLE/DAY_TYPE_CODE 显式 N'NONE'，JSON 改为逐笔基表快照数组；同键多笔按 UQ 归并累加，根绝撞键批失败。
  2026-10-12 19:12:00 | 脚本新建 | 新建核算单元惩罚金额算子。
  =============================================================================== */

-- 第一区块：生成与落库
~
-- 幂等清理历史数据
-- 占位符条件独占成行
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_UNIT_PUNISH_AMOUNT'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 算子计算与落库
WITH
-- 奖惩明细卡口直拉
src AS (
    SELECT
        r.[id]                                             AS DETAIL_ID,
        r.[org_code]                                       AS ORG_CODE,
        r.[unit_code]                                      AS UNIT_CODE,
        r.[unit_name]                                      AS UNIT_NAME,
        ISNULL(r.[staff_code], N'NONE')                    AS STAFF_CODE,
        r.[staff_name]                                     AS STAFF_NAME,
        r.[item_cat_code]                                  AS ITEM_CAT_CODE,
        r.[item_cat_name]                                  AS ITEM_CAT_NAME,
        r.[item_code]                                      AS ITEM_CODE,
        r.[item_name]                                      AS ITEM_NAME,
        r.[record_date]                                    AS RECORD_DATE,
        CAST(r.[unit_price] AS DECIMAL(18,8))              AS UNIT_PRICE,
        CAST(r.[quantity]   AS DECIMAL(18,8))              AS QUANTITY,
        CAST(r.[amount]     AS DECIMAL(18,8))              AS AMOUNT,
        r.[remark]                                         AS REMARK,
        r.[create_user]                                    AS CREATE_USER,
        r.[create_time]                                    AS CREATE_TIME
    FROM dbo.[dwd_fin_reward_punish_detail] AS r WITH (NOLOCK)
    -- 占位符条件独占成行
    WHERE 1=1
      AND r.[calc_year]   = CAST('{year}'  AS INT)
      AND r.[calc_month]  = CAST('{month}' AS INT)
      AND r.[metric_type] = N'AMOUNT'
      AND r.[category]    = N'PUNISH'
      AND r.[unit_code] IN {struct_codes}
),

-- 唯一键维度聚合落库
agg AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10))                     AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10))                     AS CALC_MONTH,
        s.[UNIT_CODE],
        s.[UNIT_NAME],
        s.[STAFF_CODE],
        s.[STAFF_NAME],
        s.[ITEM_CAT_CODE],
        s.[ITEM_CAT_NAME],
        s.[ITEM_CODE]                                      AS PROJ_CODE,
        s.[ITEM_NAME]                                      AS PROJ_NAME,
        CAST(SUM(s.[AMOUNT])   AS DECIMAL(18,8))           AS PUNISH_AMOUNT,
        CAST(SUM(s.[QUANTITY]) AS DECIMAL(18,8))           AS TOTAL_QTY,
        CAST(COUNT(1)          AS DECIMAL(18,8))           AS DETAIL_ROWS
    FROM src AS s
    GROUP BY
        s.[UNIT_CODE],
        s.[UNIT_NAME],
        s.[STAFF_CODE],
        s.[STAFF_NAME],
        s.[ITEM_CAT_CODE],
        s.[ITEM_CAT_NAME],
        s.[ITEM_CODE],
        s.[ITEM_NAME]
),

-- 出口与审计文本
final AS (
    SELECT
        a.[CALC_YEAR],
        a.[CALC_MONTH],
        a.[UNIT_CODE],
        a.[UNIT_NAME],
        a.[STAFF_CODE],
        a.[STAFF_NAME],
        a.[ITEM_CAT_CODE],
        a.[ITEM_CAT_NAME],
        a.[PROJ_CODE],
        a.[PROJ_NAME],
        a.[PUNISH_AMOUNT],
        a.[TOTAL_QTY],
        a.[DETAIL_ROWS],
        -- 审计文本三段式
        CONCAT(
            N'核算单元惩罚金额 | 核算单元惩罚金额 = 惩罚类明细金额逐笔累加（同键多笔归并，正数绝对值，扣减项） | '
           ,'0.00000000 + '
           ,CAST(a.[PUNISH_AMOUNT] AS VARCHAR(50)), ' = '
           ,CAST(a.[PUNISH_AMOUNT] AS VARCHAR(50))
        )                                                  AS CALC_PROCESS_TEXT
    FROM agg AS a
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
    N'ITEM_UNIT_PUNISH_AMOUNT'                           AS [ITEM_CODE],
    N'核算单元惩罚金额'                                   AS [ITEM_NAME],
    N'核算单元惩罚金额.sql'                               AS [SCRIPT_NAME],
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
    CAST(f.[PUNISH_AMOUNT] AS DECIMAL(18,8))             AS [FINAL_VALUE],
    CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))                 AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                                AS [CALC_PROCESS_TEXT],
    (
        SELECT
            f.[CALC_YEAR]                                 AS [核算年份],
            f.[CALC_MONTH]                                AS [核算月份],
            f.[UNIT_CODE]                                 AS [核算单元编码],
            f.[UNIT_NAME]                                 AS [核算单元名称],
            f.[STAFF_CODE]                                AS [员工编码],
            f.[STAFF_NAME]                                AS [员工姓名],
            N'PUNISH'                                     AS [奖惩方向],
            N'AMOUNT'                                     AS [度量类型],
            f.[ITEM_CAT_CODE]                             AS [奖惩大类编码],
            f.[ITEM_CAT_NAME]                             AS [奖惩大类名称],
            f.[PROJ_CODE]                                 AS [奖惩项目编码],
            f.[PROJ_NAME]                                 AS [奖惩项目名称],
            CAST(f.[TOTAL_QTY]   AS DECIMAL(18,8))        AS [数量合计],
            CAST(f.[DETAIL_ROWS] AS DECIMAL(18,8))        AS [明细笔数],
            -- 逐笔基表快照
            JSON_QUERY((
                SELECT
                    CAST(d.[DETAIL_ID] AS VARCHAR(20))             AS [明细ID],
                    CONVERT(VARCHAR(10), d.[RECORD_DATE], 120)     AS [发生日期],
                    d.[ORG_CODE]                                   AS [机构编码],
                    CAST(d.[UNIT_PRICE] AS DECIMAL(18,8))          AS [标准值],
                    CAST(d.[QUANTITY]   AS DECIMAL(18,8))          AS [数量],
                    CAST(d.[AMOUNT]     AS DECIMAL(18,8))          AS [奖惩值],
                    d.[REMARK]                                     AS [事由备注],
                    d.[CREATE_USER]                                AS [录入人],
                    CONVERT(VARCHAR(19), d.[CREATE_TIME], 120)     AS [录入时间]
                FROM src AS d
                WHERE d.[UNIT_CODE]  = f.[UNIT_CODE]
                  AND d.[STAFF_CODE] = f.[STAFF_CODE]
                  AND d.[ITEM_CODE]  = f.[PROJ_CODE]
                ORDER BY d.[RECORD_DATE], d.[DETAIL_ID]
                FOR JSON PATH
            ))                                            AS [奖惩明细快照]
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
      AND [ITEM_CODE]  = N'ITEM_UNIT_PUNISH_AMOUNT'
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
