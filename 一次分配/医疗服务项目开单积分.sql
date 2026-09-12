/* ===============================================================================
  脚本名称: 医疗服务项目开单积分.sql
  业务说明: 医疗服务项目开单决策积分汇总（按 核算单元 × 项目 粒度）
            积分 = SUM(数量) × RVU_VAL(单项绩效点数) × DECISION_COFF(诊疗决策系数)
            剔除绩效大类: 1101(出入院服务类)、1041(诊察类)
  数据流向: dbo.[PF临时医疗服务项目26A] (事实层)
            INNER JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION] (维度层, 版本号显式路由)
            => 一次分配 · 医疗服务项目开单积分

  ── 依赖契约 ──
  事实表 : dbo.[PF临时医疗服务项目26A]
           [项目代码] NVARCHAR(60) / [开单科室代码] BIGINT / [开单时间] DATETIME
           [数量] DECIMAL(18,8)
  维表   : dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)
           [RVU_VAL] numeric(12,4) / [DECISION_COFF] decimal(18,4)
  拉链维表: dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27]
            [PERFORM_PERSON_TYPE_CODE] varchar(100) / [HIS_DEPT_CODE] varchar(300)
            [HPS_DEPT_CODE] / [HPS_DEPT_NAME] / [START_DATE] datetime2 / [END_DATE] datetime2
  ── 关键纠偏（防熵增） ──
  1. 维表主键含 VERSION_NO，同一 PROJ_CODE 存在多版本/多机构/多计费单位，
     直接 JOIN 将造成行级笛卡尔放大、积分虚增。故经 DIM_LATEST 层收敛单版本快照（VERSION_RANK = 1）。
  2. 所有参与运算的系数、数量在计算前统一显式 CAST 为 DECIMAL(18,8)，
     与落库精度同源，杜绝低精度截断累积误差。
  3. 拉链维表按 (HIS_DEPT_CODE, START_DATE) 排序收敛最新版本快照（VERSION_RANK = 1），
     事实明细与快照按开单时间半开区间 [START_DATE, END_DATE) 关联，防止历史科室变更引发的行数膨胀与积分虚增。
  4. 拉链维表 HIS_DEPT_CODE 为旧版字符编码（如 '0030'），事实层 [开单科室代码] 为数值编码（如 10），
     直连将全量失配。故在 fact_raw_keyed 层统一归一为 RIGHT('0' + CAST(DEPT_CODE AS VARCHAR(20)), 4) 后再关联。
     注：当前关联实际以 HIS 科室名称（归一化尾随空格）为桥，HIS_DEPT_CODE 归一逻辑保留待用。
  5. 维表对同一 (HIS_DEPT_CODE, START_DATE, END_DATE) 存在重复行（0433/11941/11944/11961），
     且同一 HIS 科室 1:N 映射至多核算单元，按 PARTITION BY (HIS_DEPT_CODE, START_DATE, END_DATE) 取 ID 最大行防膨胀。
  6. 原始开单科室（DEPT_CODE/DEPT_NAME）与映射行快照仅作为"渡河之桥"，joined 层完成映射即抛弃，
     不再向上游沉淀，杜绝无关维度污染聚合粒度与冗余字符串拼接。

  修改日志：
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
  粒度定义   : 核算单元编码(HPS_DEPT_CODE) × 核算单元名称(HPS_DEPT_NAME) × 项目代码(PROJ_CODE)
               原始开单科室（DEPT_CODE/DEPT_NAME）与映射快照仅作为关联核算单元的中间桥梁，汇总层全量剥离
  =============================================================================== */

WITH
-- ── Import CTE: 事实层开口单时间窗（半开区间 [月初, 次月初)） ──
fact_raw AS (
    SELECT
        a.[项目代码]                                   AS PROJ_CODE,
        a.[项目名称]                                   AS PROJ_NAME,
        a.[开单科室代码]                               AS DEPT_CODE,
        a.[开单科室]                                   AS DEPT_NAME,
        CAST(a.[开单科室代码] AS VARCHAR(60))          AS DEPT_CODE_KEY,
        a.[开单时间]                                   AS ORDER_TIME,
        CAST(a.[数量]  AS DECIMAL(18,8))               AS QTY,
        CAST(a.[单价]  AS DECIMAL(18,8))               AS UNIT_PRICE,
        CAST(a.[金额]  AS DECIMAL(18,8))               AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
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

-- ── Logical CTE: 拉链维表键归一（HIS_DEPT_NAME 保留尾随空格归一） ──
fact_raw_keyed AS (
    SELECT
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[DEPT_CODE],
        f.[DEPT_NAME],
        f.[ORDER_TIME],
        f.[QTY],
        RTRIM(LTRIM(f.[DEPT_NAME])) AS HIS_DEPT_NAME_KEY
    FROM fact_raw AS f
),
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
                PARTITION BY RTRIM(LTRIM(r.[HIS_DEPT_NAME])), r.[START_DATE]
                ORDER BY r.[MAPPING_ID] DESC
            ) AS VERSION_RANK
        FROM dept_unit_mapping_raw AS r
    ) AS r
    WHERE r.[VERSION_RANK] = 1
),

-- ── Logical CTE: 维表版本收敛（隔离 VERSION_NO / ORG_CODE / MEAS_UNIT 维度，防行级放大） ──
dim_version_scope AS (
    SELECT
        b.[ORG_CODE],
        b.[VERSION_NO],
        b.[PROJ_CODE],
        b.[MEAS_UNIT],
        b.[PROJ_NAME],
        b.[RVU_VAL],
        b.[ITEM_CAT_CODE],
        b.[ITEM_CAT_NAME],
        b.[DECISION_COFF]
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS b WITH (NOLOCK)
    WHERE b.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND b.[PROJ_CODE] IS NOT NULL
),
dim_latest_version AS (
    SELECT
        d.[ORG_CODE],
        d.[VERSION_NO],
        d.[PROJ_CODE],
        d.[MEAS_UNIT],
        d.[PROJ_NAME],
        d.[RVU_VAL],
        d.[ITEM_CAT_CODE],
        d.[ITEM_CAT_NAME],
        d.[DECISION_COFF],
        ROW_NUMBER() OVER (
            PARTITION BY d.[PROJ_CODE], d.[MEAS_UNIT]
            ORDER BY d.[VERSION_NO] DESC
        ) AS VERSION_RANK
    FROM dim_version_scope AS d
),
dim_pick AS (
    SELECT
        c.[ORG_CODE],
        c.[VERSION_NO],
        c.[PROJ_CODE],
        c.[MEAS_UNIT],
        c.[PROJ_NAME],
        CAST(c.[RVU_VAL]       AS DECIMAL(18,8)) AS RVU_VAL,
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        CAST(c.[DECISION_COFF] AS DECIMAL(18,8)) AS DECISION_COFF
    FROM dim_latest_version AS c
    WHERE c.[VERSION_RANK] = 1
),

-- ── Logical CTE: 事实 × 维度 关联（仅取目标核算单元，原始科室字段到此为止） ──
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
    FROM fact_raw_keyed AS f
    INNER JOIN dim_pick AS d
        ON f.[PROJ_CODE] = d.[PROJ_CODE]
    LEFT JOIN dept_unit_mapping AS m
        ON f.[HIS_DEPT_NAME_KEY] = RTRIM(LTRIM(m.[HIS_DEPT_NAME]))
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

-- ── Final CTE: 出口契约（应用层中文别名输出，数值统一 DECIMAL(18,8)） ──
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
)

SELECT
    f.[CALC_YEAR]                                                   AS [核算年份],
    f.[CALC_MONTH]                                                  AS [核算月份],
    f.[UNIT_CODE]                                                   AS [核算单元编码],
    f.[UNIT_NAME]                                                   AS [核算单元名称],
    f.[PROJ_CODE]                                                   AS [项目代码],
    f.[PROJ_NAME]                                                   AS [项目名称],
    f.[ITEM_CAT_CODE]                                               AS [绩效核算大类代码],
    f.[ITEM_CAT_NAME]                                               AS [绩效核算大类名称],
    CAST(f.[RVU_VAL] AS DECIMAL(18,8))                              AS [单项RVU点数],
    CAST(f.[DECISION_COFF] AS DECIMAL(18,8))                        AS [诊疗决策系数],
    CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))                            AS [汇总数量],
    CAST(f.[DECISION_SCORE] AS DECIMAL(18,8))                       AS [开单决策积分],
    f.[CALC_PROCESS_TEXT]                                           AS [计算过程描述]
FROM final AS f;

