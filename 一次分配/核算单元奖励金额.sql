/* ===============================================================================
  Relative Path : 一次分配/核算单元奖励金额.sql
  脚本名称: 核算单元奖励金额.sql
  业务说明: 核算单元奖励金额 = 奖励类奖惩明细金额按「核算单元 × 员工 × 奖惩项目」单行聚合落库
            （category='REWARD' × metric_type='AMOUNT'），同键多笔 SUM 累加，结果恒为正数绝对值，作为一次分配结算中的独立加项展列。
  数据流向: dbo.[dwd_fin_reward_punish_detail] → dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
            (ITEM_CODE=ITEM_UNIT_REWARD_AMOUNT / FINAL_VALUE_TYPE=AMOUNT)
  粒度定义: 核算单元 × 员工(STAFF_CODE，缺省 'NONE') × 奖惩项目(PROJ_CODE ← item_code) 单行唯一，轻量对象快照下沉 CALC_DETAIL_JSON
  模板占位符: '{year}' / '{month}' / {struct_codes}

  ── 数据源契约（dwd_fin_reward_punish_detail）──
  账期卡口: [calc_year] INT / [calc_month] INT / [metric_type] = 'AMOUNT'（元；'SCORE' 分属积分算子消费域）
  方向卡口: [category] = 'REWARD'（奖励/加分）
  数值语义: [unit_price] / [quantity] / [amount] 均 DECIMAL(18,8)，受物理 CHECK >= 0 约束恒为正数绝对值
  维度语义: [unit_code] VARCHAR(50) / [unit_name] NVARCHAR(100) 强制 NOT NULL；
            [staff_code] 允许 NULL（NULL=科室整体奖惩，落库兜底 'NONE'；有值=个人奖惩）
  分类维度: [item_cat_code]/[item_cat_name] 业务大类、[item_code]/[item_name] 奖惩项目
  快照来源: 轻量对象快照（单行唯一，零数组嵌套，FOR JSON PATH + WITHOUT_ARRAY_WRAPPER）——汇总键 + 机构元数据 +
            SUM 计算因子（金额合计 / 数量合计 / 明细笔数）+ 发生日期区间 + 最新一笔的备注与审计留痕；
            NULL 属性按需省略，保持快照小而美。

  ── 关键纠偏（防熵增）──
  1. 【单行唯一 + UQ 对齐】日志表唯一键 UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 真实强制
     (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)；
     agg 阶段即按 UQ 三键 (UNIT_CODE, STAFF_CODE, ITEM_CODE) 聚合为单行，与 UQ 完美对齐，零撞键、零批失败。
  2. 【方向隔离】PUNISH 由《核算单元惩罚金额.sql》独立承载，收支分离、加扣项独立展列；
     本脚本零负号、零 CASE 取反。如口径收窄为仅取「科室整体奖惩」，在 src 卡口追加 AND r.[staff_code] IS NULL。
  3. 【零符号函数】严禁 ABS() / 取反包装，非负性由 ck_dwd_fin_reward_punish_detail_amount 内核保障。
  4. 【落库键位显式化】PROJ_CODE 直取基表 [item_code]；EXEC_ROLE / DAY_TYPE_CODE 显式写死 N'NONE'
     （非角色/日历粒度），STAFF_CODE 显式 ISNULL(..., N'NONE')，三列均为 UQ 定位维度，严禁静默依赖默认值。
  5. 【精度对齐】金额与中间量统一 DECIMAL(18,8)；明细层账期与日期时间字段强制文本化（VARCHAR）。
  6. 【属性代表值确定性直取】描述属性（名称 / 大类 / 机构 / 备注 / 审计）由 final 内
     CROSS APPLY (SELECT TOP (1) … ORDER BY s.[DETAIL_ID] DESC) 直取最新一笔代表值，严禁并入 GROUP BY
     （同一 item_code 出现多 item_name / 多 item_cat_code 的脏数据会拆行撞键，导致整批 INSERT 失败）；
     严禁回退 ROW_NUMBER() 窗口收敛与临时表派生——TOP (1) 为同语义但零开窗、零临时结构的确定性写法。
  7. 【事实聚合非维度折叠】agg 内 SUM / COUNT / MIN / MAX 均作用于事实明细度量（金额、数量、笔数、发生日期区间），
     属正当收敛，并非用聚合掩盖源头维度重复。

  修改日志:
  2026-10-12 23:40:00 | 极简瘦身 | 撤销 attr/pick 两层 ROW_NUMBER 派生，属性代表值降维为 final 内 CROSS APPLY (SELECT TOP (1) … ORDER BY DETAIL_ID DESC) 确定性直取；CTE 链收敛为 src → agg → final 三层（零开窗、零临时表）；聚合口径、落库列、JSON 快照与占位符零改动。
  2026-10-12 23:00:00 | 极简瘦身 | 撤销逐笔明细数组快照，CALC_DETAIL_JSON 改为单行轻量对象（汇总键 + 机构 + SUM 因子 + 日期区间 + 最新备注审计）；src 精简至 18 列；agg 增事实级 MIN/MAX 发生日期区间；落库严格一行一条对齐 UQ。
  2026-10-12 21:30:00 | 快照全量化 | src 扩展至基表全 24 列并启用 INCLUDE_NULL_VALUES 逐笔快照，键面聚合收敛为 UQ 三键。
  2026-10-12 20:10:00 | 粒度重构 | 落库粒度改为明细级，PROJ_CODE/ITEM_CAT/STAFF 直取基表，JSON 改为逐笔快照数组。
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
        CAST(r.[quantity] AS DECIMAL(18,8))                AS QUANTITY,
        CAST(r.[amount]   AS DECIMAL(18,8))                AS AMOUNT,
        r.[remark]                                         AS REMARK,
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
        k.[REMARK],
        CONVERT(VARCHAR(19), k.[CREATE_TIME], 120)         AS LAST_CREATE_TIME,
        k.[UPDATE_USER]                                    AS LAST_UPDATE_USER,
        CONVERT(VARCHAR(19), k.[UPDATE_TIME], 120)         AS LAST_UPDATE_TIME,
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
            s.[ORG_NAME],
            s.[REMARK],
            s.[CREATE_TIME],
            s.[UPDATE_USER],
            s.[UPDATE_TIME]
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
        -- 轻量对象快照（无数组嵌套）
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
            f.[REMARK]                                    AS [最新事由备注],
            f.[LAST_CREATE_TIME]                          AS [最后录入时间],
            f.[LAST_UPDATE_USER]                          AS [最后修改人],
            f.[LAST_UPDATE_TIME]                          AS [最后修改时间]
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
