/* ===============================================================================
  Relative Path : 一次分配/医疗服务项目开单积分.sql
  脚本名称: 医疗服务项目开单积分.sql
  业务说明: 医疗服务项目开单决策积分汇总（按 核算单元 × 项目 粒度）
            积分 = SUM(数量) × RVU_VAL(单项绩效点数) × DECISION_COFF(诊疗决策系数)
            剔除绩效大类: 1101(出入院服务类)、1041(诊察类)
  数据流向: dbo.[PF临时医疗服务项目26A] (事实层)
            ──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接 开单科室代码 id -> 编码)
            ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (HIS 编码 -> 绩效核算单元)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (维度层, 单版本 1:1 直连)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_MED_SVC_ORDER_SCORE)

  ── 依赖契约 ──
  事实表 : dbo.[PF临时医疗服务项目26A]
           [项目代码] NVARCHAR(60) / [开单科室代码] BIGINT / [开单时间] DATETIME
           [数量] DECIMAL(18,8)
  桥接表 : dbo.[sjjk_bmb_2025_06_01]（部门字典表）
           [id] bigint 主键聚簇 / [编码] nvarchar(10) —— 事实层数值主键 → HIS 业务编码的唯一桥接通道
  维表   : dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)；当前系统仅存单版本，
           VERSION_NO 退化为纯快照/备注属性，脚本内做 1:1 直连，不开窗收敛
           [RVU_VAL] numeric(12,4) / [DECISION_COFF] decimal(18,4)
  拉链维表: dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27]
            [PERFORM_PERSON_TYPE_CODE] varchar(100) / [HIS_DEPT_CODE] varchar(300)
            [HPS_DEPT_CODE] / [HPS_DEPT_NAME] / [START_DATE] datetime2 / [END_DATE] datetime2
  ── 关键纠偏（防熵增） ──
  1. 【解耦科室名称】取消以 HIS 科室名称作映射桥，改用事实层 [开单科室代码]
     ──(id)──▶ sjjk_bmb_2025_06_01.[编码] ──(HIS_DEPT_CODE)──▶ 直连映射表，全链以编码驱动。
  2. 【单版本直连】RVU 维表移除 ROW_NUMBER() 开窗排序，按单版本 1:1 直连（VERSION_NO 仅作快照属性）。
  3. 【拉链时间截面】拉链维表按 (HIS_DEPT_CODE, START_DATE) 收敛快照，事实明细以 [START_DATE, END_DATE) 时间窗匹配。

  修改日志：
  2026-09-14 16:30:00 | 键匹配精简 | 移除 bmb_bridge / fact_raw 中 HIS_DEPT_CODE 的 RIGHT 补零与 RTRIM/LTRIM 格式化拼接，改为字典层 [编码] 原值直连匹配；头部纠偏收敛为 3 条核心架构决策。
  2026-09-14 16:00:00 | 强主键关联与维表降维 | 引入部门字典 id->编码 强关联解耦名称：新增 bmb_bridge CTE，以 [开单科室代码](BIGINT) 直连 sjjk_bmb_2025_06_01.id 取出 [编码] 精准匹配拉链维表；删除 fact_raw_keyed（HIS_DEPT_NAME_KEY 字符串归一）并将 dept_unit_mapping 的 ROW_NUMBER() 分区键由 HIS_DEPT_NAME 改为 HIS_DEPT_CODE，joined 关联条件同步改键。简化单版本 RVU 维表获取：删除 dim_latest_version / dim_pick 两层开窗收敛 CTE，dim_version_scope 直接 1:1 供 joined 消费，VERSION_NO 退化为纯快照属性。下游积分算式与落库、第二区块读取逻辑零改动。
  2026-09-12 22:50:00 | 字段扩展 | 追加 TOTAL_QTY 物理列映射（CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))）至 DWD_FIN_CALC_ALLOC1_DETAIL_LOG，将工作量/工分一等公民化（BI 可直接 SUM 对账，免解析 JSON）；CALC_DETAIL_JSON 由 9 节点扩展为 13 节点全量过程仓，补齐 核算年份/核算月份/核算单元编码/核算单元名称 及 计算过程描述（账期与单元编码因 agg 层为文本形态，按源列声明宽度 CAST AS VARCHAR(10) 序列化，与物理 INT 列语义同源）；其余计算 CTE 与双区块 Envelope 结构零改动。
  2026-09-12 22:30:00 | 架构持久化 | Envelope Pattern 双区块重构：第一区块前置幂等 DELETE（按 CALC_YEAR/CALC_MONTH/ITEM_CODE/UNIT_CODE 清理，清场范围 ⊇ UQ 前缀 (CALC_YEAR,CALC_MONTH,ITEM_CODE,UNIT_CODE,PROJ_CODE) 故语义安全），计算收敛后 INSERT 落至一次分配专用物理表 DWD_FIN_CALC_ALLOC1_DETAIL_LOG（ITEM_CODE='ITEM_MED_SVC_ORDER_SCORE' / FINAL_VALUE_TYPE='SCORE'），显式下沉 PROJ_CODE/PROJ_NAME/ITEM_CAT_CODE/ITEM_CAT_NAME 命脉列，过程因子（单项RVU/决策系数/汇总数量）经 FOR JSON PATH 收敛入 CALC_DETAIL_JSON；第二区块以 波浪号 隔离，从物理表读取生成 CTE_DWD_READ_ALIAS 并严格承接 struct_code/struct_name/result_value 模板契约（末尾补分号闭合）。原 fact_raw → final 全部计算 CTE 零改动。
  2026-09-12 21:10:00 | 架构瘦身 | 链路剪枝：彻底剥离原始开单科室字段（DEPT_CODE/DEPT_NAME）及中间映射快照 JSON（MAPPING_SNAPSHOT），原始科室降级为纯"渡河之桥"仅用于匹配映射表；聚合粒度锁死为【核算单元编码 × 核算单元名称 × 项目代码】；移除 agg 层 O(N²) 冗余自连接，重构为"明细计算 → 维度系数收敛 → 目标粒度汇总"三段解耦，消除行级放大与嵌套子查询卡顿；新增 UNKNOWN/未映射 兜底标记。
  2026-09-12 18:30:00 | 维度扩展 | 引入 sjjk_DEPT_UNIT_MAPPING_2025_11_27 拉链映射表（限定 PERFORM_PERSON_TYPE_CODE='1001' 且基于开单时间半开区间匹配），扩展绩效核算单元编码、名称及映射行快照 JSON；纠偏关联键编码口径（事实层数值补零归一至维表旧版字符编码），纠偏同键重复行导致的行级膨胀。
  2026-09-12 18:00:00 | 字段扩展 | 新增核算年份与月份字段；新增符合四段式规范的计算过程描述字段；最外层别名统一转换为中文。
  2026-09-12 17:30:00 | 占位符重构 | 重构占位符为 '{year}'/'{month}'，移除 {version_no} 参数，锁定最新版本快照
  2026-09-12 00:00:00 | 脚本新建 | 依据事实层与维表层 DDL 契约创建医疗服务项目开单积分汇总脚本；
                                    纠偏 DECIMAL(18,4) 为 DECIMAL(18,8)；新增维表版本号收敛层防笛卡尔放大；
                                    时间窗改为 {cal_year}/{cal_month} 注入式，语句末尾显式分号、全局禁用 GO

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份, 4 位数字文本, 默认 '2025'
  '{month}'     : 核算月份, 1-12 文本, 默认 '6'
  {struct_codes}: 科室代码过滤集, 英文逗号分隔; 留空则不过滤
  输出契约   : 核算年份 / 核算月份 / 核算单元编码 / 核算单元名称 / 项目代码 / 项目名称
               / 绩效核算大类代码 / 绩效核算大类名称 / 单项RVU点数 / 诊疗决策系数
               / 汇总数量 / 开单决策积分 / 计算过程描述
  落库契约   : 第一区块写入 dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配专用物理表）
               列化核对列: FINAL_VALUE(开单决策积分) + TOTAL_QTY(汇总工作量)
               JSON 过程仓: CALC_DETAIL_JSON 全量 13 节点（账期/单元/项目/大类/因子/过程描述）
  粒度定义   : 核算单元编码(HPS_DEPT_CODE) × 核算单元名称(HPS_DEPT_NAME) × 项目代码(PROJ_CODE)
               原始开单科室（DEPT_CODE/DEPT_NAME）与映射快照仅作为关联核算单元的中间桥梁，汇总层全量剥离
  =============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 项目 粒度专用物理表）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE)
-- =================================================================
~
-- 1. 幂等清理历史数据（清场范围 = ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_MED_SVC_ORDER_SCORE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（bmb_bridge → fact_raw → dept_unit_mapping → dim_version_scope
--    → joined → agg_coff_collapse → agg → final；已解耦科室名称硬关联并剥离单版本开窗收敛）
WITH
-- ── Import CTE: 部门字典桥接层（事实层数值主键 [开单科室代码] → 业务编码 [编码]） ──
--    原样透传数据库物理值，不做任何补零/去空格/格式化加工（查询出来是什么就是什么）。
bmb_bridge AS (
    SELECT
        b.[id]                          AS DEPT_ID,
        b.[编码]                        AS HIS_DEPT_CODE
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
),

-- ── Import CTE: 事实层开口单时间窗（半开区间 [月初, 次月初)） ──
fact_raw AS (
    SELECT
        a.[项目代码]                                   AS PROJ_CODE,
        a.[项目名称]                                   AS PROJ_NAME,
        a.[开单科室代码]                               AS DEPT_ID,
        a.[开单科室]                                   AS DEPT_NAME,
        -- HIS 科室编码：字典层原值直连，作为拉链维表关联键
        b.[HIS_DEPT_CODE],
        a.[开单时间]                                   AS ORDER_TIME,
        CAST(a.[数量]  AS DECIMAL(18,8))               AS QTY,
        CAST(a.[单价]  AS DECIMAL(18,8))               AS UNIT_PRICE,
        CAST(a.[金额]  AS DECIMAL(18,8))               AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    INNER JOIN bmb_bridge AS b
        ON a.[开单科室代码] = b.[DEPT_ID]
    WHERE a.[开单时间] >= DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1)
      AND a.[开单时间] <  DATEADD(MONTH, 1, DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1))
),

-- ── Import CTE: HIS 科室 → 绩效核算单元 拉链维表收敛（锁定最新快照, 防范围膨胀） ──
dept_unit_mapping_raw AS (
    SELECT
        m.[ID]                          AS MAPPING_ID,
        m.[HIS_DEPT_CODE],
        m.[HIS_DEPT_NAME],
        m.[HPS_DEPT_CODE],
        m.[HPS_DEPT_NAME],
        m.[START_DATE],
        m.[END_DATE]
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] = '1001'
),

-- ── Logical CTE: 拉链维表收敛（按 HIS_DEPT_CODE 强关联键去重，锁定最新快照防范围膨胀） ──
dept_unit_mapping AS (
    SELECT
        r.[MAPPING_ID],
        r.[HIS_DEPT_CODE],
        r.[HIS_DEPT_NAME],
        r.[HPS_DEPT_CODE],
        r.[HPS_DEPT_NAME],
        r.[START_DATE],
        r.[END_DATE],
        r.[VERSION_RANK]
    FROM (
        SELECT
            r.[MAPPING_ID],
            r.[HIS_DEPT_CODE],
            r.[HIS_DEPT_NAME],
            r.[HPS_DEPT_CODE],
            r.[HPS_DEPT_NAME],
            r.[START_DATE],
            r.[END_DATE],
            ROW_NUMBER() OVER (
                PARTITION BY r.[HIS_DEPT_CODE], r.[START_DATE]
                ORDER BY r.[MAPPING_ID] DESC
            ) AS VERSION_RANK
        FROM dept_unit_mapping_raw AS r
    ) AS r
    WHERE r.[VERSION_RANK] = 1
),

-- ── Import CTE: 绩效大类维表作用域（单版本假设下 1:1 直连，VERSION_NO 退化为纯快照属性；
--              大类 1101/1041 与空项目编码在 JOIN 前完成剪枝） ──
dim_version_scope AS (
    SELECT
        b.[PROJ_CODE],
        b.[PROJ_NAME],
        CAST(b.[RVU_VAL]       AS DECIMAL(18,8)) AS RVU_VAL,
        b.[ITEM_CAT_CODE],
        b.[ITEM_CAT_NAME],
        CAST(b.[DECISION_COFF] AS DECIMAL(18,8)) AS DECISION_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS b WITH (NOLOCK)
    WHERE b.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND b.[PROJ_CODE] IS NOT NULL
),

-- ── Logical CTE: 事实 × 维度 关联（HIS 编码强关联核算单元，原始科室字段到此为止） ──
joined AS (
    SELECT
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN')            AS UNIT_CODE,
        ISNULL(m.[HPS_DEPT_NAME], '未映射核算单元')      AS UNIT_NAME,
        d.[ITEM_CAT_CODE],
        d.[ITEM_CAT_NAME],
        d.[RVU_VAL],
        d.[DECISION_COFF],
        f.[QTY],
        CAST(f.[QTY] * d.[RVU_VAL] * d.[DECISION_COFF] AS DECIMAL(18,8)) AS ITEM_SCORE
    FROM fact_raw AS f
    INNER JOIN dim_version_scope AS d
        ON f.[PROJ_CODE] = d.[PROJ_CODE]
    LEFT JOIN dept_unit_mapping AS m
        ON f.[HIS_DEPT_CODE] = m.[HIS_DEPT_CODE]
       AND f.[ORDER_TIME] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR f.[ORDER_TIME] < m.[END_DATE])
),

-- ── Logical CTE: 维度系数收敛（隔离 ORG_CODE / MEAS_UNIT 多维分支，防最外层聚合被污染） ──
agg_coff_collapse AS (
    SELECT
        j.[PROJ_CODE],
        MAX(j.[PROJ_NAME])     AS PROJ_NAME,
        MAX(j.[ITEM_CAT_CODE]) AS ITEM_CAT_CODE,
        MAX(j.[ITEM_CAT_NAME]) AS ITEM_CAT_NAME,
        MAX(j.[RVU_VAL])       AS RVU_VAL,
        MAX(j.[DECISION_COFF]) AS DECISION_COFF
    FROM joined AS j
    GROUP BY j.[PROJ_CODE]
),

-- ── Logical CTE: 核算单元 × 项目代码 粒度聚合 ──
agg AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        j.[UNIT_CODE],
        j.[UNIT_NAME],
        j.[PROJ_CODE],
        c.[PROJ_NAME],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        c.[DECISION_COFF],
        CAST(SUM(j.[QTY])        AS DECIMAL(18,8)) AS TOTAL_QTY,
        CAST(SUM(j.[ITEM_SCORE]) AS DECIMAL(18,8)) AS DECISION_SCORE
    FROM joined AS j
    INNER JOIN agg_coff_collapse AS c
        ON j.[PROJ_CODE] = c.[PROJ_CODE]
    GROUP BY
        j.[UNIT_CODE],
        j.[UNIT_NAME],
        j.[PROJ_CODE],
        c.[PROJ_NAME],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        c.[DECISION_COFF]
),

-- ── Final CTE: 出口契约与 JSON 过程仓打包（仅追加核算单元过滤，防全院单元越界落库） ──
final AS (
    SELECT
        a.[CALC_YEAR],
        a.[CALC_MONTH],
        a.[UNIT_CODE],
        a.[UNIT_NAME],
        a.[PROJ_CODE],
        a.[PROJ_NAME],
        a.[ITEM_CAT_CODE],
        a.[ITEM_CAT_NAME],
        a.[RVU_VAL],
        a.[DECISION_COFF],
        a.[TOTAL_QTY],
        a.[DECISION_SCORE],
        '医疗服务开单积分 | 核算单元项目开单积分 = 汇总数量 × 单项RVU点数 × 诊疗决策系数 | '
            + CAST(a.[TOTAL_QTY]     AS VARCHAR(50)) + ' × '
            + CAST(a.[RVU_VAL]       AS VARCHAR(50)) + ' × '
            + CAST(a.[DECISION_COFF] AS VARCHAR(50)) + ' = '
            + CAST(a.[DECISION_SCORE] AS VARCHAR(50)) + ' | '
            + CAST(a.[DECISION_SCORE] AS VARCHAR(50)) + ' + 0 = '
            + CAST(a.[DECISION_SCORE] AS VARCHAR(50)) AS CALC_PROCESS_TEXT
    FROM agg AS a
    WHERE a.[UNIT_CODE] IN {struct_codes}
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[CALC_YEAR]  AS INT)                 AS [CALC_YEAR],
    CAST(f.[CALC_MONTH] AS INT)                 AS [CALC_MONTH],
    N'ITEM_MED_SVC_ORDER_SCORE'                 AS [ITEM_CODE],
    N'医疗服务项目开单积分'                     AS [ITEM_NAME],
    N'医疗服务项目开单积分.sql'                 AS [SCRIPT_NAME],
    f.[UNIT_CODE]                               AS [UNIT_CODE],
    f.[UNIT_NAME]                               AS [UNIT_NAME],
    f.[PROJ_CODE]                               AS [PROJ_CODE],
    f.[PROJ_NAME]                               AS [PROJ_NAME],
    f.[ITEM_CAT_CODE]                           AS [ITEM_CAT_CODE],
    f.[ITEM_CAT_NAME]                           AS [ITEM_CAT_NAME],
    N'SCORE'                                    AS [FINAL_VALUE_TYPE],
    CAST(f.[DECISION_SCORE] AS DECIMAL(18,8))   AS [FINAL_VALUE],
    CAST(f.[TOTAL_QTY]      AS DECIMAL(18,8))   AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                       AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[CALC_YEAR]  AS VARCHAR(10))        AS [核算年份],
            CAST(f.[CALC_MONTH] AS VARCHAR(10))        AS [核算月份],
            f.[UNIT_CODE]                              AS [核算单元编码],
            f.[UNIT_NAME]                              AS [核算单元名称],
            f.[PROJ_CODE]                              AS [项目代码],
            f.[PROJ_NAME]                              AS [项目名称],
            f.[ITEM_CAT_CODE]                          AS [绩效核算大类代码],
            f.[ITEM_CAT_NAME]                          AS [绩效核算大类名称],
            CAST(f.[RVU_VAL]       AS DECIMAL(18,8))   AS [单项RVU点数],
            CAST(f.[DECISION_COFF] AS DECIMAL(18,8))   AS [诊疗决策系数],
            CAST(f.[TOTAL_QTY]     AS DECIMAL(18,8))   AS [汇总数量],
            CAST(f.[DECISION_SCORE] AS DECIMAL(18,8))  AS [开单决策积分],
            f.[CALC_PROCESS_TEXT]                      AS [计算过程描述]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                           AS [CALC_DETAIL_JSON],
    SYSDATETIME()                               AS [CREATE_TIME]
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
        [FINAL_VALUE_TYPE]      AS [值类型],
        [FINAL_VALUE]           AS [最终结果],
        [CALC_PROCESS_TEXT]     AS [计算过程描述],
        [CALC_DETAIL_JSON]      AS [明细JSON],
        [CREATE_TIME]           AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_MED_SVC_ORDER_SCORE'
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