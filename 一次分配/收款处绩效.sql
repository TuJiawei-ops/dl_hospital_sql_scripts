/* ===============================================================================
  Relative Path : 一次分配/收款处绩效.sql
  脚本名称: 收款处绩效.sql
  业务定义: 收款处（收费处）一次分配绩效金额 = Σ(线下导入细目工作量 × 单项RVU点数)，
            按 核算单元 × 细目 粒度落库。
  数据流向: dbo.[dwd_fin_charge_workload_detail]  (事实层: 线下导入工作量, 唯一度量 workload_qty)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION]      (RVU 点数维表, 单版本 1:1 直连)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_CHARGE_PERFORMANCE / AMOUNT)
  粒度定义: 核算单元编码 × 核算单元名称 × 细目编码(PROJ_CODE)

  ── 依赖契约 ──
  事实层 : dbo.[dwd_fin_charge_workload_detail]
           [calc_year] INT / [calc_month] INT / [org_code] VARCHAR(50) / [unit_code] VARCHAR(50)
           [item_code] VARCHAR(50) / [item_name] NVARCHAR(200) / [workload_qty] DECIMAL(18,8)
           单价(unit_price)与结算金额(calc_amount)已剥离，本算子唯读 workload_qty 原始工作量。
  RVU维表: dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)；[RVU_VAL] numeric(12,4) NOT NULL
           当前系统仅存单版本，按 [PROJ_CODE] 1:1 直连；VERSION_NO 退化为快照属性列，零寻址零过滤。
  落库表 : dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]（一次分配专用 EAV-Hybrid 日志表）
           业务唯一键 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE,
                       EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE) —— 本算子后三维恒为 N'NONE'。

  ── 关键纠偏（防熵增） ──
  1. 【单版本零寻址】RVU 维表移除 ROW_NUMBER() 开窗收敛与 VERSION_NO 常量过滤，按 [PROJ_CODE] 1:1
     直连（对齐标杆 医疗服务项目开单积分.sql）；VERSION_NO 仅作普通属性，严禁动态版本寻址，
     全链零 ROW_NUMBER / 零 MAX() 黑箱折叠。
  2. 【未配置不静默丢弃】细目未命中维表时 RVU 兜底 0.00000000，仍落库 AMOUNT = 0 行，
     维持工作量对账闭环并外显配置缺口，禁止为掩盖配置缺失而静默剔除事实行。
  3. 【零折叠落库】事实层契约保障「一月 × 一单元 × 一细目」仅一行，joined 输出即物理唯一，
     故不设名称收敛链，8 维唯一键 (…, UNIT_CODE, PROJ_CODE, …) 落库无碰撞面。
  4. 【编码族关联】unit_code / item_code 全为字符串编码族，原值裸引用，无 CAST / 补零改造。
  5. 【明细层文本化】final 为程序读写倒数第二层，年份/月份强制文本化，上层仅透传不重复叠加 CAST。
  6. 【账期口径唯一】账期取自 '{year}' / '{month}' 模板参数并与事实层过滤条件同源同参；
     事实层为「账期 + 细目 + 值」三要素导入表、无时间戳流水，故本算子不消费 '{start_time}' / '{end_time}'。

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份 (如 '2026')
  '{month}'     : 核算月份 (如 '10')
  {struct_codes}: 核算单元过滤集 (如 ('100031'))

  修改日志
  2026-10-13 18:55:00 | 架构纠偏 | 对齐标杆《医疗服务项目开单积分.sql》：RVU 维表移除 ROW_NUMBER 开窗与 VERSION_NO 'V04' 常量过滤，退化为单版本 1:1 直连；撤 rvu_snap 收敛层、proj_name 名称链与嵌套 [RVU配置快照] 节点，CALC_DETAIL_JSON 收敛为单层扁平；agg 层一次算定 Σ工作量 × 点值；落库列、第二区块契约与占位符零改动。
  2026-10-13 17:40:00 | 脚本新建 | 新建收款处绩效算子：线下导入工作量事实表直连 RVU 点数维表，按(核算单元×细目)汇总工作量乘点值落库 AMOUNT；Envelope 双区块 + 幂等 DELETE。
=============================================================================== */

-- 第一区块：生成与落库
~
-- 幂等清理历史数据
-- 占位符条件独占成行
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_CHARGE_PERFORMANCE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 算子计算与落库
WITH
-- RVU 点数维表（单版本 1:1 直连，仅投影直连属性集）
dim_rvu AS (
    SELECT
        v.[PROJ_CODE]                                  AS PROJ_CODE,
        v.[PROJ_NAME]                                  AS PROJ_NAME,
        v.[ITEM_CAT_CODE]                              AS ITEM_CAT_CODE,
        v.[ITEM_CAT_NAME]                              AS ITEM_CAT_NAME,
        v.[VERSION_NO]                                 AS VERSION_NO,
        v.[MEAS_UNIT]                                  AS MEAS_UNIT,
        CAST(v.[RVU_VAL] AS DECIMAL(18,8))             AS RVU_VAL
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v WITH (NOLOCK)
    -- 单版本维表 1:1 直连，仅剔除空项目码
    WHERE v.[PROJ_CODE] IS NOT NULL
),

-- 事实层账期截面（唯一度量 workload_qty）
src AS (
    SELECT
        f.[org_code]                                   AS ORG_CODE,
        f.[org_name]                                   AS ORG_NAME,
        f.[unit_code]                                  AS UNIT_CODE,
        f.[unit_name]                                  AS UNIT_NAME,
        f.[item_code]                                  AS PROJ_CODE,
        f.[item_name]                                  AS PROJ_NAME,
        CAST(f.[workload_qty] AS DECIMAL(18,8))        AS WORKLOAD_QTY
    FROM dbo.[dwd_fin_charge_workload_detail] AS f WITH (NOLOCK)
    -- 占位符条件独占成行
    WHERE 1=1
      AND f.[calc_year]  = CAST('{year}'  AS INT)
      AND f.[calc_month] = CAST('{month}' AS INT)
      AND f.[unit_code] IN {struct_codes}
),

-- 事实 × RVU 点值 1:1 直连（未命中细目兜底 0，事实行不丢弃）
joined AS (
    SELECT
        s.[ORG_CODE]                                        AS ORG_CODE,
        s.[ORG_NAME]                                        AS ORG_NAME,
        s.[UNIT_CODE]                                       AS UNIT_CODE,
        s.[UNIT_NAME]                                       AS UNIT_NAME,
        s.[PROJ_CODE]                                       AS PROJ_CODE,
        COALESCE(NULLIF(d.[PROJ_NAME], N''), s.[PROJ_NAME]) AS PROJ_NAME,
        d.[ITEM_CAT_CODE]                                   AS ITEM_CAT_CODE,
        d.[ITEM_CAT_NAME]                                   AS ITEM_CAT_NAME,
        CAST(ISNULL(d.[RVU_VAL], 0.00000000) AS DECIMAL(18,8)) AS RVU_VAL,
        s.[WORKLOAD_QTY]                                    AS WORKLOAD_QTY
    FROM src AS s
    LEFT JOIN dim_rvu AS d
        ON d.[PROJ_CODE] = s.[PROJ_CODE]
),

-- 核算单元 × 细目 粒度汇总（工作量 Σ 与 汇总×点值 同层一次算定）
agg AS (
    SELECT
        j.[ORG_CODE]                                   AS ORG_CODE,
        j.[ORG_NAME]                                   AS ORG_NAME,
        j.[UNIT_CODE]                                  AS UNIT_CODE,
        j.[UNIT_NAME]                                  AS UNIT_NAME,
        j.[PROJ_CODE]                                  AS PROJ_CODE,
        j.[PROJ_NAME]                                  AS PROJ_NAME,
        j.[ITEM_CAT_CODE]                              AS ITEM_CAT_CODE,
        j.[ITEM_CAT_NAME]                              AS ITEM_CAT_NAME,
        j.[RVU_VAL]                                    AS RVU_VAL,
        CAST(SUM(j.[WORKLOAD_QTY]) AS DECIMAL(18,8))               AS TOTAL_QTY,
        CAST(SUM(j.[WORKLOAD_QTY]) * j.[RVU_VAL] AS DECIMAL(18,8)) AS CHARGE_AMOUNT
    FROM joined AS j
    GROUP BY
        j.[ORG_CODE],
        j.[ORG_NAME],
        j.[UNIT_CODE],
        j.[UNIT_NAME],
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL]
),

-- 明细层出口契约（三段式审计文本 + 账期文本化）
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(4))                  AS [核算年份],
        CAST('{month}' AS VARCHAR(2))                  AS [核算月份],
        a.[ORG_CODE]                                   AS [机构编码],
        a.[ORG_NAME]                                   AS [机构名称],
        a.[UNIT_CODE]                                  AS [核算单元编码],
        a.[UNIT_NAME]                                  AS [核算单元名称],
        a.[PROJ_CODE]                                  AS [项目编码],
        a.[PROJ_NAME]                                  AS [项目名称],
        a.[ITEM_CAT_CODE]                              AS [绩效核算大类编码],
        a.[ITEM_CAT_NAME]                              AS [绩效核算大类名称],
        a.[TOTAL_QTY]                                  AS [汇总工作量],
        a.[RVU_VAL]                                    AS [单项绩效点数],
        a.[CHARGE_AMOUNT]                              AS [收款处绩效],
        CONCAT(
             N'收款处绩效 | 收费绩效 = 汇总工作量 × RVU点值 | ',
             CAST(a.[TOTAL_QTY]     AS VARCHAR(32)), ' × ',
             CAST(a.[RVU_VAL]       AS VARCHAR(32)), ' = ',
             CAST(a.[CHARGE_AMOUNT] AS VARCHAR(32))
        )                                              AS [计算过程]
    FROM agg AS a
)

-- 投影落库（账期常量经 SELECT 投影；CALC_DETAIL_JSON 单层扁平承载主体汇总）
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [RVU_VAL],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST('{year}'  AS INT)                          AS [CALC_YEAR],
    CAST('{month}' AS INT)                          AS [CALC_MONTH],
    N'ITEM_CHARGE_PERFORMANCE'                      AS [ITEM_CODE],
    N'收款处绩效'                                    AS [ITEM_NAME],
    N'收款处绩效.sql'                                AS [SCRIPT_NAME],
    f.[核算单元编码]                                 AS [UNIT_CODE],
    f.[核算单元名称]                                 AS [UNIT_NAME],
    f.[项目编码]                                     AS [PROJ_CODE],
    f.[项目名称]                                     AS [PROJ_NAME],
    f.[绩效核算大类编码]                             AS [ITEM_CAT_CODE],
    f.[绩效核算大类名称]                             AS [ITEM_CAT_NAME],
    CAST(f.[单项绩效点数] AS DECIMAL(18,8))          AS [RVU_VAL],
    N'NONE'                                         AS [EXEC_ROLE],
    N'NONE'                                         AS [STAFF_CODE],
    N'NONE'                                         AS [STAFF_NAME],
    N'NONE'                                         AS [DAY_TYPE_CODE],
    N'NONE'                                         AS [DAY_TYPE_NAME],
    N'AMOUNT'                                       AS [FINAL_VALUE_TYPE],
    CAST(f.[收款处绩效] AS DECIMAL(18,8))            AS [FINAL_VALUE],
    CAST(f.[汇总工作量] AS DECIMAL(18,8))            AS [TOTAL_QTY],
    f.[计算过程]                                     AS [CALC_PROCESS_TEXT],

    (
        SELECT
            -- 透传原则：账期在 final 层已文本化，此处直接透传
            f.[核算年份]                                          AS [核算年份],
            f.[核算月份]                                          AS [核算月份],
            f.[机构编码]                                          AS [机构编码],
            f.[机构名称]                                          AS [机构名称],
            f.[核算单元编码]                                      AS [核算单元编码],
            f.[核算单元名称]                                      AS [核算单元名称],
            f.[项目编码]                                          AS [项目代码],
            f.[项目名称]                                          AS [项目名称],
            f.[绩效核算大类编码]                                  AS [绩效核算大类代码],
            f.[绩效核算大类名称]                                  AS [绩效核算大类名称],
            CAST(f.[汇总工作量]   AS DECIMAL(18,8))               AS [汇总工作量],
            CAST(f.[单项绩效点数] AS DECIMAL(18,8))               AS [单项RVU点数],
            CAST(f.[收款处绩效]   AS DECIMAL(18,8))               AS [收款处绩效],
            f.[计算过程]                                          AS [计算过程描述]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                             AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                                 AS [CREATE_TIME]
FROM final AS f;

~
-- =================================================================
-- 第二区块：最外层接口读取块（查询明细时仅执行此块，严格承接 struct_code / struct_name / result_value 契约）
-- =================================================================
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
        [RVU_VAL]               AS [单项绩效点数],
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
        -- 明细层日期时间强制文本化（防原生类型外泄）
        CONVERT(VARCHAR(19), [CREATE_TIME], 120) AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    -- 占位符条件独占成行
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_CHARGE_PERFORMANCE'
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

