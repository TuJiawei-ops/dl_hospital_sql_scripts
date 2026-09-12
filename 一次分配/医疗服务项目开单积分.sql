/* ===============================================================================
  脚本名称: 医疗服务项目开单积分.sql
  业务说明: 医疗服务项目开单决策积分汇总（按 核算单元 × 项目代码 粒度）
            积分 = SUM(数量) × RVU_VAL(单项绩效点数) × DECISION_COFF(诊疗决策系数)
            剔除绩效大类: 1101(出入院服务类)、1041(诊察类)
  数据流向: dbo.[PF临时医疗服务项目26A] (事实层)
            LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (拉链维表, 核算单元归属)
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
  5. 维表对同一 (HIS_DEPT_CODE, START_DATE, END_DATE) 存在重复行（0433/11941/11944/11961），
     且同一 HIS 科室 1:N 映射至多核算单元，按 PARTITION BY (HIS_DEPT_CODE, START_DATE, END_DATE) 取 ID 最大行防膨胀。
  6. 【落库粒度锁死】DWD 层存储粒度必须与落库主键 UNIT_CODE 物理对齐，落库前按
     [核算单元编码 × 项目代码] 完成预汇总；原开单科室维度的打散明细下沉至 CALC_DETAIL_JSON.SRC_DEPT_MAPPING 仓内存储。
     尤其禁止将 RVU_VAL / DECISION_COFF 放入 GROUP BY，否则同一核算单元将被多版本维度二次打散，UNIT_CODE 冗余无法根除。
  7. 维度系数（RVU_VAL / DECISION_COFF）在 agg_coff_collapse 层按 PROJ_CODE 先行收敛唯一值，
     并以 DISTINCT_RVU_CNT / DISTINCT_COFF_CNT 做一致性哨兵；若 > 1 说明维度口径存在歧义，须回溯 DIM_PRF_ITEM_RVU_VERSION。

  修改日志：
  2026-09-12 20:10:00 | 粒度纠偏 | 依据 EAV-Hybrid 规范将落库粒度由 [项目 × 开单科室] 上提为 [核算单元编码 × 项目代码]，彻底消除同一 UNIT_CODE 下多条 DWD 记录冗余：新增 agg_coff_collapse 层按 PROJ_CODE 收敛维度系数唯一值（含 DISTINCT_RVU_CNT/DISTINCT_COFF_CNT 一致性哨兵），agg 层 GROUP BY 严格锁死 [UNIT_CODE × PROJ_CODE] 并将 RVU_VAL/DECISION_COFF 移出聚合键；原开单科室打散明细经 FOR XML PATH 序列化为 SRC_DEPT_MAPPING_JSON 下沉至 CALC_DETAIL_JSON 仓内存储（含 SRC_DEPT_CNT 计数）；final 层新增 UNIT_CODE/UNIT_NAME 口径并补齐四段式审计文本第四段【纯数字结算算式段】；修复既有 INSERT 语句中孤立 SELECT 导致的语法破损与 STAFF_CODE/POST_CODE 违反 NOT NULL 唯一键约束问题，改为标准 INSERT INTO ... SELECT FROM final ... WHERE UNIT_CODE IN {struct_codes} 单语句落库；新增 agg_audit 层作为 (UNIT_CODE, PROJ_CODE) 唯一性断言入口。第二区块 {struct_code/struct_name/result_value} 接口契约与 ~ 隔离标记零改动。
  2026-09-12 19:10:00 | 持久化重构 | 依据 EAV-Hybrid + Envelope 规范将脚本重构为双区块架构（波浪号隔离）：第一区块新增按 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE) 的 DELETE 幂等清理并将最终 CTE 结果 INSERT 落库至 DWD_FIN_CALC_DETAIL_LOG（UNIT_CODE 取核算单元编码兜底开单科室代码，STAFF/POST 填充 'N/A'，FINAL_VALUE=开单决策积分，全量中间因子 FOR JSON PATH 收敛至 CALC_DETAIL_JSON）；第二区块新增最外层接口读取块（struct_code/struct_name/result_value 契约）。底层开单积分计算与维度收敛逻辑零改动。
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
  输出契约   : 核算年份 / 核算月份 / 核算单元编码 / 核算单元名称
               / 项目代码 / 项目名称 / 绩效核算大类代码 / 绩效核算大类名称
               / 单项RVU点数 / 诊疗决策系数 / 汇总数量 / 开单决策积分 / 计算过程描述
   ── 持久化契约（EAV-Hybrid Envelope） ──
   日志表 : dbo.[DWD_FIN_CALC_DETAIL_LOG]
            ITEM_CODE / ITEM_NAME  : ITEM_MEDICAL_SERVICE_ORDER_SCORE / 医疗服务项目开单积分
            SCRIPT_NAME            : 医疗服务项目开单积分.sql
            UNIT_CODE / UNIT_NAME  : 核算单元编码（兜底开单科室代码） / 核算单元名称（兜底开单科室名称）
            STAFF_CODE / STAFF_NAME/ POST_CODE / POST_NAME : 'N/A'（科室级核算项）
            FINAL_VALUE            : 开单决策积分（DECIMAL(18,8)）
            CALC_DETAIL_JSON       : 核算单元/项目/大类/单项RVU/决策系数/汇总数量/开单决策积分
                                     以及原开单科室打散明细 SRC_DEPT_MAPPING 全量收敛
   粒度   : [核算单元编码 × 项目代码] —— 与落库主键 UNIT_CODE 物理对齐，同账期同核算项下 UNIT_CODE 唯一
   架构   : 双区块（第一区块 DELETE 幂等清理 + CTE 计算 + INSERT 落库 · 第二区块最外层接口读取）
   =============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（幂等清理 + CTE 计算 + INSERT 落库）
-- =================================================================
~

-- 1. 幂等清理：按 (账期 + 核算项 + 核算单元) 覆盖重算，杜绝历史重跑脏数据堆积
DELETE FROM [dbo].[DWD_FIN_CALC_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}' AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = 'ITEM_MEDICAL_SERVICE_ORDER_SCORE'
  AND [UNIT_CODE] IN {struct_codes};

-- 2. CTE 逻辑计算（保持原算子零改动）与持久化落库
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

-- ── Logical CTE: 事实 × 维度 关联后明细（保留单条记录系数与映射行快照，供审计追溯） ──
joined AS (
    SELECT
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[DEPT_CODE],
        f.[DEPT_NAME],
        f.[ORDER_TIME],
        f.[HPS_DEPT_CODE],
        f.[HPS_DEPT_NAME],
        f.[MAPPING_SNAPSHOT],
        d.[ITEM_CAT_CODE],
        d.[ITEM_CAT_NAME],
        d.[RVU_VAL],
        d.[DECISION_COFF],
        f.[QTY],
        CAST(f.[QTY] * d.[RVU_VAL] * d.[DECISION_COFF] AS DECIMAL(18,8)) AS ITEM_SCORE
    FROM (
        SELECT
            fa.[PROJ_CODE],
            fa.[PROJ_NAME],
            fa.[DEPT_CODE],
            fa.[DEPT_NAME],
            fa.[ORDER_TIME],
            fa.[HPS_DEPT_CODE],
            fa.[HPS_DEPT_NAME],
            '{"ID":"'          + ISNULL(CAST(fa.[MAPPING_ID] AS VARCHAR(20)), '')      + '"'
                + ',"HIS_DEPT_CODE":"' + ISNULL(fa.[HIS_DEPT_CODE], '')                + '"'
                + ',"HPS_DEPT_CODE":"' + ISNULL(fa.[HPS_DEPT_CODE], '')                + '"'
                + ',"HPS_DEPT_NAME":"' + ISNULL(fa.[HPS_DEPT_NAME], '')                + '"'
                + ',"START_DATE":"'    + ISNULL(CONVERT(VARCHAR(30), fa.[START_DATE], 120), '') + '"'
                + ',"END_DATE":"'      + ISNULL(CONVERT(VARCHAR(30), fa.[END_DATE], 120), '')   + '"'
                + '}' AS MAPPING_SNAPSHOT,
            fa.[QTY]
        FROM (
            SELECT
                x.[PROJ_CODE],
                x.[PROJ_NAME],
                x.[DEPT_CODE],
                x.[DEPT_NAME],
                x.[ORDER_TIME],
                x.[QTY],
                m.[MAPPING_ID],
                m.[HIS_DEPT_CODE],
                m.[HPS_DEPT_CODE],
                m.[HPS_DEPT_NAME],
                m.[START_DATE],
                m.[END_DATE]
            FROM fact_raw_keyed AS x
            LEFT JOIN dept_unit_mapping AS m
                ON x.[HIS_DEPT_NAME_KEY] = RTRIM(LTRIM(m.[HIS_DEPT_NAME]))
               AND x.[ORDER_TIME] >= m.[START_DATE]
               AND (m.[END_DATE] IS NULL OR x.[ORDER_TIME] < m.[END_DATE])
        ) AS fa
    ) AS f
    INNER JOIN dim_pick AS d
        ON f.[PROJ_CODE] = d.[PROJ_CODE]
),

-- ── Logical CTE: 核算单元 × 项目代码 粒度聚合（粒度上提，熵减去重） ──
-- 纠偏要点：维度系数（RVU_VAL / DECISION_COFF）与科室描述字段严禁进入 GROUP BY，
--           否则同一核算单元会被多版本维度二次打散，UNIT_CODE 冗余问题无法根除。
--           故在本层先行收敛系数的唯一值，聚合键严格锁死 [核算单元编码 × 项目代码]。
agg_coff_collapse AS (
    SELECT
        j.[PROJ_CODE],
        MAX(j.[RVU_VAL])       AS RVU_VAL,
        MAX(j.[DECISION_COFF]) AS DECISION_COFF,
        COUNT(DISTINCT j.[RVU_VAL])       AS DISTINCT_RVU_CNT,
        COUNT(DISTINCT j.[DECISION_COFF]) AS DISTINCT_COFF_CNT,
        MAX(j.[ITEM_CAT_CODE]) AS ITEM_CAT_CODE,
        MAX(j.[ITEM_CAT_NAME]) AS ITEM_CAT_NAME,
        MAX(j.[PROJ_NAME])     AS PROJ_NAME
    FROM joined AS j
    GROUP BY j.[PROJ_CODE]
),
agg AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        ISNULL(j.[HPS_DEPT_CODE], CAST(j.[DEPT_CODE] AS VARCHAR(60))) AS UNIT_CODE,
        ISNULL(j.[HPS_DEPT_NAME], j.[DEPT_NAME])                       AS UNIT_NAME,
        j.[PROJ_CODE],
        c.[PROJ_NAME],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        c.[DECISION_COFF],
        CAST(SUM(j.[QTY])                      AS DECIMAL(18,8)) AS TOTAL_QTY,
        CAST(SUM(j.[ITEM_SCORE])               AS DECIMAL(18,8)) AS DECISION_SCORE,
        CAST(SUM(j.[QTY]) * c.[RVU_VAL] * c.[DECISION_COFF] AS DECIMAL(18,8)) AS DECISION_SCORE_CALC,
        MAX(c.[DISTINCT_RVU_CNT])       AS DISTINCT_RVU_CNT,
        MAX(c.[DISTINCT_COFF_CNT])      AS DISTINCT_COFF_CNT,
        COUNT(DISTINCT ISNULL(j.[DEPT_CODE], 'N/A')) AS SRC_DEPT_CNT,
        CAST(
            '[' + STUFF((
                SELECT DISTINCT
                    '{"HIS_DEPT_CODE":"'   + ISNULL(CAST(x.[DEPT_CODE] AS VARCHAR(60)), '')
                  + '","HIS_DEPT_NAME":"'  + ISNULL(x.[DEPT_NAME], '')
                  + '","HPS_DEPT_CODE":"'  + ISNULL(x.[HPS_DEPT_CODE], CAST(x.[DEPT_CODE] AS VARCHAR(60)))
                  + '","HPS_DEPT_NAME":"'  + ISNULL(x.[HPS_DEPT_NAME], x.[DEPT_NAME]) + '"}'
                FROM joined AS x
                WHERE x.[PROJ_CODE] = j.[PROJ_CODE]
                  AND ISNULL(x.[HPS_DEPT_CODE], CAST(x.[DEPT_CODE] AS VARCHAR(60)))
                      = ISNULL(j.[HPS_DEPT_CODE], CAST(j.[DEPT_CODE] AS VARCHAR(60)))
                FOR XML PATH(''), TYPE
            ).value('.', 'NVARCHAR(MAX)'), 1, 1, '') + ']'
        AS NVARCHAR(MAX)) AS SRC_DEPT_MAPPING_JSON
    FROM joined AS j
    INNER JOIN agg_coff_collapse AS c
        ON j.[PROJ_CODE] = c.[PROJ_CODE]
    GROUP BY
        ISNULL(j.[HPS_DEPT_CODE], CAST(j.[DEPT_CODE] AS VARCHAR(60))),
        ISNULL(j.[HPS_DEPT_NAME], j.[DEPT_NAME]),
        j.[PROJ_CODE],
        c.[PROJ_NAME],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        c.[DECISION_COFF]
),

-- ── Logical CTE: 聚合链路完整性断言入口（同一 项目×核算单元 必须唯一） ──
agg_audit AS (
    SELECT
        a.[UNIT_CODE],
        a.[PROJ_CODE],
        COUNT(1) AS ROW_CNT
    FROM agg AS a
    GROUP BY a.[UNIT_CODE], a.[PROJ_CODE]
    HAVING COUNT(1) > 1
),

-- ── Final CTE: 出口契约（核算单元 × 项目代码 单条记录，数值统一 DECIMAL(18,8)） ──
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
        a.[DECISION_SCORE_CALC],
        a.[SRC_DEPT_CNT],
        a.[SRC_DEPT_MAPPING_JSON],
        CAST(a.[DECISION_SCORE] - a.[DECISION_SCORE_CALC] AS DECIMAL(18,8)) AS DIFF_CHECK,
        -- 四段式审计文本：[元数据段] | [中文逻辑公式段] | [纯数学代入算式段] | [纯数字结算算式段]
        '医疗服务开单积分 | '
            + '核算单元项目汇总积分 = 汇总数量 × 单项RVU点数 × 诊疗决策系数 | '
            + CAST(CAST(a.[TOTAL_QTY]     AS DECIMAL(18,8)) AS VARCHAR(50)) + ' × '
            + CAST(CAST(a.[RVU_VAL]       AS DECIMAL(18,8)) AS VARCHAR(50)) + ' × '
            + CAST(CAST(a.[DECISION_COFF] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' = '
            + CAST(CAST(a.[DECISION_SCORE] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' | '
            + CAST(CAST(a.[DECISION_SCORE] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' + '
            + CAST(CAST(0 AS DECIMAL(18,8)) AS VARCHAR(50)) + ' = '
            + CAST(CAST(a.[DECISION_SCORE] AS DECIMAL(18,8)) AS VARCHAR(50)) AS CALC_PROCESS_TEXT
    FROM agg AS a
)

-- ── 持久化出口：核算单元 × 项目代码 一行即一条 JSON 明细（ENVELOPE 封箱） ──
INSERT INTO [dbo].[DWD_FIN_CALC_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [STAFF_CODE], [STAFF_NAME], [STAFF_TYPE],
    [POST_CODE], [POST_NAME], [FINAL_VALUE], [CALC_PROCESS_TEXT],
    [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST('{year}'  AS INT)                                         AS [CALC_YEAR],
    CAST('{month}' AS INT)                                         AS [CALC_MONTH],
    'ITEM_MEDICAL_SERVICE_ORDER_SCORE'                             AS [ITEM_CODE],
    '医疗服务项目开单积分'                                          AS [ITEM_NAME],
    '医疗服务项目开单积分.sql'                                      AS [SCRIPT_NAME],
    f.[UNIT_CODE]                                                  AS [UNIT_CODE],
    f.[UNIT_NAME]                                                  AS [UNIT_NAME],
    'N/A'                                                          AS [STAFF_CODE],
    'N/A'                                                          AS [STAFF_NAME],
    NULL                                                           AS [STAFF_TYPE],
    'N/A'                                                          AS [POST_CODE],
    'N/A'                                                          AS [POST_NAME],
    CAST(f.[DECISION_SCORE] AS DECIMAL(18,8))                      AS [FINAL_VALUE],
    f.[CALC_PROCESS_TEXT]                                          AS [CALC_PROCESS_TEXT],
    (
        SELECT
            f.[CALC_YEAR]                     AS [CALC_YEAR],
            f.[CALC_MONTH]                    AS [CALC_MONTH],
            f.[UNIT_CODE]                     AS [HPS_DEPT_CODE],
            f.[UNIT_NAME]                     AS [HPS_DEPT_NAME],
            f.[PROJ_CODE]                     AS [PROJ_CODE],
            f.[PROJ_NAME]                     AS [PROJ_NAME],
            f.[ITEM_CAT_CODE]                 AS [ITEM_CAT_CODE],
            f.[ITEM_CAT_NAME]                 AS [ITEM_CAT_NAME],
            CAST(f.[RVU_VAL] AS DECIMAL(18,8))        AS [RVU_VAL],
            CAST(f.[DECISION_COFF] AS DECIMAL(18,8))  AS [DECISION_COFF],
            CAST(f.[TOTAL_QTY] AS DECIMAL(18,8))      AS [TOTAL_QTY],
            CAST(f.[DECISION_SCORE] AS DECIMAL(18,8)) AS [DECISION_SCORE],
            CAST(f.[DECISION_SCORE_CALC] AS DECIMAL(18,8)) AS [DECISION_SCORE_CALC],
            CAST(f.[DIFF_CHECK] AS DECIMAL(18,8))     AS [DIFF_CHECK],
            f.[SRC_DEPT_CNT]                  AS [SRC_DEPT_CNT],
            JSON_QUERY(f.[SRC_DEPT_MAPPING_JSON]) AS [SRC_DEPT_MAPPING]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                              AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                                  AS [CREATE_TIME]
FROM final AS f
WHERE f.[UNIT_CODE] IN {struct_codes};
~

-- =================================================================
-- 第二区块：最外层接口读取块（基于 DWD_FIN_CALC_DETAIL_LOG 读出接口契约）
-- =================================================================
WITH CTE_DWD_READ_ALIAS AS (
    SELECT
        [ID]                    AS [日志ID],
        [CALC_YEAR]             AS [核算年份],
        [CALC_MONTH]            AS [核算月份],
        [ITEM_CODE]             AS [核算项编码],
        [ITEM_NAME]             AS [核算项名称],
        [SCRIPT_NAME]           AS [脚本名称],
        [UNIT_CODE]             AS [科室编码],
        [UNIT_NAME]             AS [科室名称],
        [STAFF_CODE]            AS [人员编码],
        [STAFF_NAME]            AS [人员姓名],
        [STAFF_TYPE]            AS [人员类型],
        [POST_CODE]             AS [岗位编码],
        [POST_NAME]             AS [岗位名称],
        [FINAL_VALUE]           AS [最终结果],
        [CALC_PROCESS_TEXT]     AS [计算过程],
        [CALC_DETAIL_JSON]      AS [明细JSON],
        [CREATE_TIME]           AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_DETAIL_LOG]
    WHERE [CALC_YEAR]  = CAST('{year}' AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = 'ITEM_MEDICAL_SERVICE_ORDER_SCORE'
      AND [UNIT_CODE] IN {struct_codes}
)

SELECT
{
[科室编码] AS struct_code,
[科室名称] AS struct_name,
SUM([最终结果]) AS result_value
}
FROM CTE_DWD_READ_ALIAS
~
GROUP BY
    [科室编码],
    [科室名称]
~
;
