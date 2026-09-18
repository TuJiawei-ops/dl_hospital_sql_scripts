/* ===============================================================================
  Relative Path : 一次分配/医疗服务项目执行积分.sql
  脚本名称: 医疗服务项目执行积分.sql
  业务说明: 医疗服务项目执行积分基础数据抽取（按 核算单元 × 收费项目 × 执行角色 粒度），
            剔除绩效大类 1101(出入院服务类)、1041(诊察类)。
  数据流向: dbo.[PF临时医疗服务项目26A]
            ──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接 id -> 编码)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (维表全字段直连)
            ──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO] (医技护执行比例)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_MED_SVC_EXEC_SCORE)

  ── 依赖契约 ──
  事实表 : dbo.[PF临时医疗服务项目26A] ([项目代码] NVARCHAR(60) / [数量] [金额] DECIMAL(18,8))
  桥接表 : dbo.[sjjk_bmb_2025_06_01] ([id] BIGINT -> [编码] NVARCHAR(10)，桥接输出 VARCHAR(60))
  维表 A : dbo.[DIM_PRF_ITEM_RVU_VERSION] (全字段直连，[ID] 别名 RVU_ID 规避 ID 碰撞)
  维表 B : dbo.[DIM_DEPT_ITEM_EXEC_RATIO] (生效态 IS_ENABLED = 1)

  ── 核心架构与约束规范（极简版） ──
  1. 【血缘桥接】：事实层 [执行科室代码](BIGINT id) 必须经字典表映射为业务 [编码] 后，方可与维表 B 关联。
  2. 【全字段直连】：维表 A 全字段 1:1 直连，前提为当前账期内为【单版本单计费单位】，严禁在脚本内写 ROW_NUMBER() / MAX() 隐式寻址。
  3. 【预聚合剪枝】：事实层在 fact_raw 先按 (执行科室 × 项目) GROUP BY 压降行数，移除开单科室、单价及执行时间。
  4. 【角色行转列】：cte_role_unpivot 层通过 CROSS APPLY 将医技护展开，强制过滤 u.[EXEC_RATIO] > 0 且核算单元不为空。
  5. 【键冲突解决】：多 HIS 执行科室可映射至同一绩效核算单元，必须在 cte_role_unpivot 按【单元 × 项目 × 角色】预聚合。
  6. 【反推综合比例】：final 层统一通过 [总执行积分] ÷ ([总数量] × [点数]) 反推加权比例，全链 DECIMAL(18,8) 同精度。
  7. 【JSON 性能红线】：CALC_DETAIL_JSON 采用单层扁平标量 + 索引命中的 RVU 嵌套快照，严格限制为 O(N) 内存拼接，禁止外部表回表。
  8. 【BIZ_EPOCH】：账期右端点哨兵（次月 1 日 00:00:00），仅穿越 CTE 链供下游半开区间匹配，严禁对外输出或参与聚合/分组。

  ── 模板占位符 ──
  '{year}'      : 核算年份 (如 '2025')
  '{month}'     : 核算月份 (如 '6')
  '{start_time}': 核算开始时间 (如 '2024-01-01 00:00:00.000')，仅作用于 fact_raw 事实层时间窗口
  '{end_time}'  : 核算结束时间 (如 '2024-01-31 23:59:59.997')，仅作用于 fact_raw 事实层时间窗口
  {struct_codes}: 核算单元过滤集 (如 ('10001', '10002'))

  修改日志：
  2026-09-18 10:30:00 | 时间维度重构 | 动态路由门诊/缴费时间与非门诊/执行时间，筛选范围切换为 '{start_time}' 与 '{end_time}' 标准占位符。fact_raw 事实层过滤由固定 [执行时间] 月度半开区间（DATEFROMPARTS(年,月,1) 至次月1日）重构为按 [来源] 动态分流：门诊来源走 [缴费时间] 闭区间，非门诊来源走 [执行时间] 闭区间，两分支均显式 CAST(... AS DATETIME) 避免隐式转换衰减性能，闭区间采用 >= 与 <= 保证 SARGability；WHERE 恒真锚点 1=1 与动态分支独占一行、行首 AND 前缀，保障 -- 单行零副作用隔离。'{year}' / '{month}' 占位符予以保留，其作用域收敛至落库日志表账期幂等清场、BIZ_EPOCH 账期右端点哨兵（契约 §8）及 final 出口账期契约，与事实层时间窗口筛选完全正交，严禁在本次变更中一并移除（否则 BIZ_EPOCH 派生链崩溃）。下游 CTE 链条（dept_dict / dim_version_scope / dim_exec_ratio_raw / joined / cte_role_unpivot / final）、幂等清场、INSERT 落库投影与第二区块读取逻辑零改动。风险登记：若源端存在 [来源]='住院' 且 [执行时间] IS NULL（或 [来源]='门诊' 且 [缴费时间] IS NULL）的记录，两分支均不命中将被静默过滤，需业务侧确认源表完整性；[来源] 物理列可空，非门诊分支已通过 ISNULL(a.[来源], '') 兜底 NULL 语义，防止三值逻辑 UNKNOWN 导致漏数。
  2026-09-18 13:00:00 | 字段微调 | 第一区块持久化 INSERT/SELECT 补齐 [RVU_VAL] 物理列投影，与 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 新增属性列 1:1 对齐（投影源 = final 层已携带的 [RVU_VAL] 单项绩效点数，经 CAST(... AS DECIMAL(18,8)) 收敛至全局强制精度；INSERT 列位插入于 [ITEM_CAT_NAME] 之后、[EXEC_ROLE] 之前）。
  2026-09-14 15:20:00 | 注释极简重构 | 剥离历史演进叙事与冗长推演，将原 20 条纠偏收敛为 8 条原子化约束清单；SQL 逻辑零改动。
  2026-09-14 15:10:00 | 审计文本精简与RVU快照 | 剔除 CALC_PROCESS_TEXT 冗余零加段；dim_version_scope 升级为全字段直连并删除 dim_collapse；追加 [RVU配置快照] 单层嵌套 JSON。
  2026-09-14 14:20:00 | 预聚合层解耦重构 | 新增 cte_role_unpivot 实现跨 HIS 科室预聚合，final 降级为纯 1:1 契约投影 + 综合比例反推。
=============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 执行科室 × 项目 × 角色 粒度专用物理表）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE)
-- =================================================================
~
-- 1. 幂等清理历史数据（清场范围 = ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_MED_SVC_EXEC_SCORE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（dept_dict → fact_raw → dim_version_scope(全字段) → dim_exec_ratio_raw
--    → joined → cte_role_unpivot → final 计算链路，仅 dim_collapse 收敛层被整体删除
--    并以 1:1 直连替代；Envelope 包装、模板占位符与落库列零改动）
WITH
-- ── Import CTE: 部门字典桥接层（事实层数值主键 id → 维表业务编码 编码） ──
dept_dict AS (
    SELECT
        b.[id]                                        AS DEPT_ID,
        CAST(b.[编码] AS VARCHAR(60))                 AS DEPT_CODE
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
),

-- ── Import CTE: 事实层【执行科室 × 项目】预聚合（字典桥接取业务编码，压降明细行数） ──
fact_raw AS (
    SELECT
        a.[项目代码]                                        AS PROJ_CODE,
        a.[项目名称]                                        AS PROJ_NAME,
        a.[执行科室代码]                                    AS EXEC_DEPT_ID,
        a.[执行科室]                                        AS EXEC_DEPT_NAME,
        d.[DEPT_CODE]                                       AS EXEC_DEPT_CODE_KEY,
        CAST(SUM(CAST(a.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS QTY,
        CAST(SUM(CAST(a.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    INNER JOIN dept_dict AS d
        ON a.[执行科室代码] = d.[DEPT_ID]
    WHERE 1=1
      AND (
          (a.[来源] = N'门诊' AND a.[缴费时间] >= CAST('{start_time}' AS DATETIME) AND a.[缴费时间] <= CAST('{end_time}' AS DATETIME))
          OR (ISNULL(a.[来源], '') <> N'门诊' AND a.[执行时间] >= CAST('{start_time}' AS DATETIME) AND a.[执行时间] <= CAST('{end_time}' AS DATETIME))
      )
    GROUP BY
        a.[项目代码],
        a.[项目名称],
        a.[执行科室代码],
        a.[执行科室],
        d.[DEPT_CODE]
),

-- ── Import CTE: 绩效大类维表作用域（全字段 1:1 直连，大类剔除前置剪枝；[ID] 别名 RVU_ID 防与日志表主键碰撞） ──
dim_version_scope AS (
    SELECT
        b.[VERSION_NO],
        b.[VERSION_DESC],
        b.[ORG_CODE],
        b.[ORG_NAME],
        b.[SRC_SYS_CODE],
        b.[PROJ_CODE],
        b.[PROJ_NAME],
        b.[MEAS_UNIT],
        CAST(b.[RVU_VAL] AS DECIMAL(18,8))        AS RVU_VAL,
        b.[ITEM_CAT_CODE],
        b.[ITEM_CAT_NAME],
        CAST(b.[UNIT_PRICE] AS DECIMAL(18,8))     AS UNIT_PRICE,
        b.[OPR_LEVEL_CODE],
        b.[OPR_LEVEL_NAME],
        b.[CREATE_USER],
        b.[CREATE_TIME],
        b.[UPDATE_USER],
        b.[UPDATE_TIME],
        b.[ID]                                    AS RVU_ID,
        CAST(b.[DECISION_COFF] AS DECIMAL(18,8))  AS DECISION_COFF,
        CAST(b.[EXEC_COFF] AS DECIMAL(18,8))      AS EXEC_COFF,
        b.[REMARK],
        b.[SCORE_REASON]
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS b WITH (NOLOCK)
    WHERE b.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND b.[PROJ_CODE] IS NOT NULL
),

-- ── Import CTE: 医技护执行划分维表作用域（仅取启用态规则） ──
dim_exec_ratio_raw AS (
    SELECT
        r.[HIS_DEPT_CODE],
        r.[ITEM_CODE],
        r.[DOC_EXEC_RATIO],
        r.[TECH_EXEC_RATIO],
        r.[NURSE_EXEC_RATIO],
        r.[DOC_HPS_DEPT_CODE],
        r.[DOC_HPS_DEPT_NAME],
        r.[TECH_HPS_DEPT_CODE],
        r.[TECH_HPS_DEPT_NAME],
        r.[NURSE_HPS_DEPT_CODE],
        r.[NURSE_HPS_DEPT_NAME]
    FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS r WITH (NOLOCK)
    WHERE r.[IS_ENABLED] = 1
),

-- ── Logical CTE: 事实(聚合) × 绩效大类 × 医技护执行划分 关联（宽表三角色并列，供下游行转列消费） ──
joined AS (
    SELECT
        DATEADD(MONTH, 1, DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1)) AS BIZ_EPOCH,
        f.[EXEC_DEPT_ID],
        f.[EXEC_DEPT_NAME],
        f.[EXEC_DEPT_CODE_KEY],
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[QTY],
        f.[AMOUNT],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        ISNULL(x.[DOC_EXEC_RATIO],   CAST(0.00000000 AS DECIMAL(18,8))) AS DOC_EXEC_RATIO,
        ISNULL(x.[TECH_EXEC_RATIO],  CAST(0.00000000 AS DECIMAL(18,8))) AS TECH_EXEC_RATIO,
        ISNULL(x.[NURSE_EXEC_RATIO], CAST(0.00000000 AS DECIMAL(18,8))) AS NURSE_EXEC_RATIO,
        x.[DOC_HPS_DEPT_CODE],
        x.[DOC_HPS_DEPT_NAME],
        x.[TECH_HPS_DEPT_CODE],
        x.[TECH_HPS_DEPT_NAME],
        x.[NURSE_HPS_DEPT_CODE],
        x.[NURSE_HPS_DEPT_NAME]
    FROM fact_raw AS f
    INNER JOIN dim_version_scope AS c
        ON f.[PROJ_CODE] = c.[PROJ_CODE]
    LEFT JOIN dim_exec_ratio_raw AS x
        ON f.[EXEC_DEPT_CODE_KEY] = x.[HIS_DEPT_CODE]
       AND f.[PROJ_CODE]          = x.[ITEM_CODE]
),

-- ── Intermediate CTE: 角色展开与核算单元预聚合（按 核算单元 × 项目 × 角色 维度切分并消除 HIS 科室差异） ──
cte_role_unpivot AS (
    SELECT
        j.[BIZ_EPOCH],
        u.[HPS_DEPT_CODE],
        u.[HPS_DEPT_NAME],
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        u.[ROLE_NAME]                                                                 AS EXEC_ROLE,
        CAST(SUM(CAST(j.[QTY]    AS DECIMAL(18,8))) AS DECIMAL(18,8))                 AS TOTAL_QTY,
        CAST(SUM(CAST(j.[AMOUNT] AS DECIMAL(18,8))) AS DECIMAL(18,8))                 AS TOTAL_AMOUNT,
        CAST(SUM(CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS TOTAL_EXEC_POINTS
    FROM joined AS j
    CROSS APPLY (
        VALUES
            ('医生', j.[DOC_EXEC_RATIO],   j.[DOC_HPS_DEPT_CODE],   j.[DOC_HPS_DEPT_NAME]),
            ('技师', j.[TECH_EXEC_RATIO],  j.[TECH_HPS_DEPT_CODE],  j.[TECH_HPS_DEPT_NAME]),
            ('护士', j.[NURSE_EXEC_RATIO], j.[NURSE_HPS_DEPT_CODE], j.[NURSE_HPS_DEPT_NAME])
    ) AS u([ROLE_NAME], [EXEC_RATIO], [HPS_DEPT_CODE], [HPS_DEPT_NAME])
    WHERE u.[HPS_DEPT_CODE] IN {struct_codes}
      AND u.[EXEC_RATIO] > CAST(0.00000000 AS DECIMAL(18,8))
      AND u.[HPS_DEPT_CODE] IS NOT NULL
    GROUP BY
        j.[BIZ_EPOCH],
        u.[HPS_DEPT_CODE],
        u.[HPS_DEPT_NAME],
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        u.[ROLE_NAME]
),

-- ── Final CTE: 出口契约（防污点隔离，按【核算单元 × 项目 × 角色】严格 1:1 输出单行，计算综合执行比例） ──
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        r.[BIZ_EPOCH],
        r.[HPS_DEPT_CODE],
        r.[HPS_DEPT_NAME],
        r.[PROJ_CODE],
        r.[PROJ_NAME],
        r.[ITEM_CAT_CODE],
        r.[ITEM_CAT_NAME],
        r.[RVU_VAL],
        r.[EXEC_ROLE],
        -- 综合反推执行比例 = 总积分 / (总数量 × RVU)，若总基数为 0 则兜底 0
        CAST(ISNULL(r.[TOTAL_EXEC_POINTS] / NULLIF(r.[TOTAL_QTY] * r.[RVU_VAL], 0), 0) AS DECIMAL(18,8)) AS EXEC_RATIO,
        r.[TOTAL_QTY]                                                                                     AS QTY,
        r.[TOTAL_AMOUNT]                                                                                  AS AMOUNT,
        r.[TOTAL_EXEC_POINTS]                                                                             AS EXEC_POINTS,
        -- 三段式审计文本：[元数据段] | [中文逻辑公式段] | [纯数学代入算式段 = 最终积分]
        -- 已剔除原 "积分 + 0.00000000 = 积分" 无效加数恒等段（恒等零加增熵），
        -- 末段直接收敛至最终执行积分，数学算式自身已完成唯一数字收口
        '医疗服务执行积分 | 科室项目角色执行积分 = 汇总数量 × 单项RVU点数 × 执行比例 | '
            + CAST(r.[TOTAL_QTY] AS VARCHAR(50)) + ' × '
            + CAST(r.[RVU_VAL] AS VARCHAR(50)) + ' × '
            + CAST(CAST(ISNULL(r.[TOTAL_EXEC_POINTS] / NULLIF(r.[TOTAL_QTY] * r.[RVU_VAL], 0), 0) AS DECIMAL(18,8)) AS VARCHAR(50)) + ' = '
            + CAST(r.[TOTAL_EXEC_POINTS] AS VARCHAR(50))                                              AS CALC_PROCESS_TEXT
    FROM cte_role_unpivot AS r
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [RVU_VAL], [EXEC_ROLE],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[CALC_YEAR]  AS INT)                     AS [CALC_YEAR],
    CAST(f.[CALC_MONTH] AS INT)                     AS [CALC_MONTH],
    N'ITEM_MED_SVC_EXEC_SCORE'                      AS [ITEM_CODE],
    N'医疗服务项目执行积分'                          AS [ITEM_NAME],
    N'医疗服务项目执行积分.sql'                      AS [SCRIPT_NAME],
    f.[HPS_DEPT_CODE]                               AS [UNIT_CODE],
    f.[HPS_DEPT_NAME]                               AS [UNIT_NAME],
    f.[PROJ_CODE]                                   AS [PROJ_CODE],
    f.[PROJ_NAME]                                   AS [PROJ_NAME],
    f.[ITEM_CAT_CODE]                               AS [ITEM_CAT_CODE],
    f.[ITEM_CAT_NAME]                               AS [ITEM_CAT_NAME],
    CAST(f.[RVU_VAL] AS DECIMAL(18,8))              AS [RVU_VAL],
    f.[EXEC_ROLE]                                   AS [EXEC_ROLE],
    N'SCORE'                                        AS [FINAL_VALUE_TYPE],
    CAST(f.[EXEC_POINTS] AS DECIMAL(18,8))          AS [FINAL_VALUE],
    CAST(f.[QTY]         AS DECIMAL(18,8))          AS [TOTAL_QTY],
    f.[CALC_PROCESS_TEXT]                           AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[CALC_YEAR]  AS VARCHAR(10))         AS [核算年份],
            CAST(f.[CALC_MONTH] AS VARCHAR(10))         AS [核算月份],
            f.[HPS_DEPT_CODE]                           AS [核算单元编码],
            f.[HPS_DEPT_NAME]                           AS [核算单元名称],
            f.[PROJ_CODE]                               AS [项目代码],
            f.[PROJ_NAME]                               AS [项目名称],
            f.[ITEM_CAT_CODE]                           AS [绩效核算大类代码],
            f.[ITEM_CAT_NAME]                           AS [绩效核算大类名称],
            CAST(f.[RVU_VAL]     AS DECIMAL(18,8))      AS [单项RVU点数],
            f.[EXEC_ROLE]                               AS [执行角色],
            CAST(f.[EXEC_RATIO]  AS DECIMAL(18,8))      AS [执行比例],
            CAST(f.[QTY]         AS DECIMAL(18,8))      AS [汇总数量],
            CAST(f.[AMOUNT]      AS DECIMAL(18,8))      AS [汇总金额],
            CAST(f.[EXEC_POINTS] AS DECIMAL(18,8))      AS [最终执行积分],
            f.[CALC_PROCESS_TEXT]                       AS [计算过程描述],
            -- RVU 配置全字段快照（FOR JSON PATH 纯常量投影，零表回表；按 PROJ_CODE 1:1 直连 dim_version_scope）
            -- 注：与同级扁平节点互不干扰，位于根对象内联；父级 WITHOUT_ARRAY_WRAPPER 必须保留
            JSON_QUERY((
                SELECT
                    c.[VERSION_NO]       AS [版本号],
                    c.[VERSION_DESC]     AS [版本描述],
                    c.[ORG_CODE]         AS [机构编码],
                    c.[ORG_NAME]         AS [机构名称],
                    c.[SRC_SYS_CODE]     AS [源系统编码],
                    c.[PROJ_CODE]        AS [收费项目编码],
                    c.[PROJ_NAME]        AS [收费项目名称],
                    c.[MEAS_UNIT]        AS [原始计费单位],
                    c.[RVU_VAL]          AS [单项绩效点数],
                    c.[ITEM_CAT_CODE]    AS [绩效核算大类编码],
                    c.[ITEM_CAT_NAME]    AS [绩效核算大类名称],
                    c.[UNIT_PRICE]       AS [历史参考单价],
                    c.[OPR_LEVEL_CODE]   AS [手术等级编码],
                    c.[OPR_LEVEL_NAME]   AS [手术等级名称],
                    c.[CREATE_USER]      AS [创建人],
                    CONVERT(VARCHAR(19), c.[CREATE_TIME], 120) AS [创建时间],
                    c.[UPDATE_USER]      AS [修改人],
                    CONVERT(VARCHAR(19), c.[UPDATE_TIME], 120) AS [修改时间],
                    c.[RVU_ID]           AS [冗余ID],
                    c.[DECISION_COFF]    AS [诊疗决策系数],
                    c.[EXEC_COFF]        AS [执行系数],
                    c.[REMARK]           AS [备注说明],
                    c.[SCORE_REASON]     AS [评分理由依据]
                FROM dim_version_scope AS c
                WHERE c.[PROJ_CODE] = f.[PROJ_CODE]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ))                                          AS [RVU配置快照]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                               AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                   AS [CREATE_TIME]
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
        [EXEC_ROLE]             AS [执行角色],
        [FINAL_VALUE_TYPE]      AS [值类型],
        [FINAL_VALUE]           AS [最终结果],
        [TOTAL_QTY]             AS [汇总数量],
        [CALC_PROCESS_TEXT]     AS [计算过程描述],
        [CALC_DETAIL_JSON]      AS [明细JSON],
        [CREATE_TIME]           AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_MED_SVC_EXEC_SCORE'
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

