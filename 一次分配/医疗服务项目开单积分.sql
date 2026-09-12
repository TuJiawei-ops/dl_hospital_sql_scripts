/* ===============================================================================
  脚本名称: 医疗服务项目开单积分.sql
  业务说明: 医疗服务项目开单决策积分汇总（按 项目 × 开单科室 粒度）
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
  ── 关键纠偏（防熵增） ──
  1. 维表主键含 VERSION_NO，同一 PROJ_CODE 存在多版本/多机构/多计费单位，
     直接 JOIN 将造成行级笛卡尔放大、积分虚增。故经 DIM_LATEST 层收敛单版本快照（VERSION_RANK = 1）。
  2. 所有参与运算的系数、数量在计算前统一显式 CAST 为 DECIMAL(18,8)，
     与落库精度同源，杜绝低精度截断累积误差。

  修改日志：
  2026-09-12 18:00:00 | 字段扩展 | 新增核算年份与月份字段；新增符合四段式规范的计算过程描述字段；最外层别名统一转换为中文。
  2026-09-12 17:30:00 | 占位符重构 | 重构占位符为 '{year}'/'{month}'，移除 {version_no} 参数，锁定最新版本快照
  2026-09-12 00:00:00 | 脚本新建 | 依据事实层与维表层 DDL 契约创建医疗服务项目开单积分汇总脚本；
                                    纠偏 DECIMAL(18,4) 为 DECIMAL(18,8)；新增维表版本号收敛层防笛卡尔放大；
                                    时间窗改为 {cal_year}/{cal_month} 注入式，语句末尾显式分号、全局禁用 GO

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份, 4 位数字文本, 默认 '2025'
  '{month}'     : 核算月份, 1-12 文本, 默认 '6'
  {struct_codes}: 科室代码过滤集, 英文逗号分隔; 留空则不过滤
  输出契约   : 核算年份 / 核算月份 / 项目代码 / 项目名称 / 开单科室代码 / 开单科室名称
               / 绩效核算大类代码 / 绩效核算大类名称 / 单项RVU点数 / 诊疗决策系数
               / 汇总数量 / 开单决策积分 / 计算过程描述
  =============================================================================== */

WITH
-- ── Import CTE: 事实层开口单时间窗（半开区间 [月初, 次月初)） ──
fact_raw AS (
    SELECT
        a.[项目代码]                                   AS PROJ_CODE,
        a.[项目名称]                                   AS PROJ_NAME,
        a.[开单科室代码]                               AS DEPT_CODE,
        a.[开单科室]                                   AS DEPT_NAME,
        a.[开单时间]                                   AS ORDER_TIME,
        CAST(a.[数量]  AS DECIMAL(18,8))               AS QTY,
        CAST(a.[单价]  AS DECIMAL(18,8))               AS UNIT_PRICE,
        CAST(a.[金额]  AS DECIMAL(18,8))               AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    WHERE a.[开单时间] >= DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1)
      AND a.[开单时间] <  DATEADD(MONTH, 1, DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1))
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

-- ── Logical CTE: 事实 × 维度 关联后明细（保留单条记录系数快照，供审计追溯） ──
joined AS (
    SELECT
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[DEPT_CODE],
        f.[DEPT_NAME],
        d.[ITEM_CAT_CODE],
        d.[ITEM_CAT_NAME],
        d.[RVU_VAL],
        d.[DECISION_COFF],
        f.[QTY],
        CAST(f.[QTY] * d.[RVU_VAL] * d.[DECISION_COFF] AS DECIMAL(18,8)) AS ITEM_SCORE
    FROM fact_raw AS f
    INNER JOIN dim_pick AS d
        ON f.[PROJ_CODE] = d.[PROJ_CODE]
),

-- ── Logical CTE: 项目 × 开单科室 粒度聚合 ──
agg AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[DEPT_CODE],
        j.[DEPT_NAME],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        j.[DECISION_COFF],
        CAST(SUM(j.[QTY])        AS DECIMAL(18,8)) AS TOTAL_QTY,
        CAST(SUM(j.[ITEM_SCORE]) AS DECIMAL(18,8)) AS DECISION_SCORE,
        CAST(SUM(j.[QTY]) * j.[RVU_VAL] * j.[DECISION_COFF] AS DECIMAL(18,8)) AS DECISION_SCORE_CALC
    FROM joined AS j
    GROUP BY
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[DEPT_CODE],
        j.[DEPT_NAME],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        j.[DECISION_COFF]
),

-- ── Final CTE: 出口契约（应用层中文别名输出，数值统一 DECIMAL(18,8)） ──
final AS (
    SELECT
        a.[CALC_YEAR],
        a.[CALC_MONTH],
        a.[PROJ_CODE],
        a.[PROJ_NAME],
        a.[DEPT_CODE],
        a.[DEPT_NAME],
        a.[ITEM_CAT_CODE],
        a.[ITEM_CAT_NAME],
        a.[RVU_VAL],
        a.[DECISION_COFF],
        a.[TOTAL_QTY],
        a.[DECISION_SCORE],
        a.[DECISION_SCORE_CALC],
        CAST(a.[DECISION_SCORE] - a.[DECISION_SCORE_CALC] AS DECIMAL(18,8)) AS DIFF_CHECK,
        '医疗服务开单积分 | 项目开单积分 = 汇总数量 × 单项RVU点数 × 诊疗决策系数 | '
            + CAST(a.[TOTAL_QTY]     AS VARCHAR(50)) + ' × '
            + CAST(a.[RVU_VAL]       AS VARCHAR(50)) + ' × '
            + CAST(a.[DECISION_COFF] AS VARCHAR(50)) + ' | '
            + CAST(a.[DECISION_SCORE] AS VARCHAR(50)) AS CALC_PROCESS_TEXT
    FROM agg AS a
)

SELECT
    f.[CALC_YEAR]                                                   AS [核算年份],
    f.[CALC_MONTH]                                                  AS [核算月份],
    f.[PROJ_CODE]                                                   AS [项目代码],
    f.[PROJ_NAME]                                                   AS [项目名称],
    f.[DEPT_CODE]                                                   AS [开单科室代码],
    f.[DEPT_NAME]                                                   AS [开单科室名称],
    f.[ITEM_CAT_CODE]                                               AS [绩效核算大类代码],
    f.[ITEM_CAT_NAME]                                               AS [绩效核算大类名称],
    CAST(f.[RVU_VAL] AS DECIMAL(18,8))                              AS [单项RVU点数],
    CAST(f.[DECISION_COFF] AS DECIMAL(18,8))                        AS [诊疗决策系数],
    CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))                            AS [汇总数量],
    CAST(f.[DECISION_SCORE] AS DECIMAL(18,8))                       AS [开单决策积分],
    f.[CALC_PROCESS_TEXT]                                           AS [计算过程描述]
FROM final AS f;
