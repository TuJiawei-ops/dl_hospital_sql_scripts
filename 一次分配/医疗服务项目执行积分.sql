/* ===============================================================================
  Relative Path : 一次分配/医疗服务项目执行积分.sql
  脚本名称: 医疗服务项目执行积分.sql
  业务说明: 医疗服务项目执行积分基础数据抽取（按 执行科室 × 收费项目 粒度）
            以事实层收费明细为驱动，关联【绩效大类维表】与【各科室收费项目医技护执行划分维表】，
            输出医技护执行比例与医技护三路核算单元映射，供后续执行积分按角色切分使用。
            剔除绩效大类: 1101(出入院服务类)、1041(诊察类)
  数据流向: dbo.[PF临时医疗服务项目26A] (事实层, 别名 a)
            LEFT  JOIN dbo.[sjjk_bmb_2025_06_01]          (部门字典桥接层, 别名 d, id → 编码)
            INNER JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION]     (维度层, 别名 v, 绩效大类)
            LEFT  JOIN dbo.[DIM_DEPT_ITEM_EXEC_RATIO]     (维度层, 别名 r, 仅取 IS_ENABLED = 1)
            => 持久化至 dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (一次分配专用物理表, ITEM_CODE = ITEM_MED_SVC_EXEC_SCORE)
            => 一次分配 · 医疗服务项目执行积分

  ── 依赖契约 ──
  事实表 : dbo.[PF临时医疗服务项目26A]
           [项目代码] NVARCHAR(60) / [项目名称] NVARCHAR(600)
           [执行科室代码] BIGINT / [执行科室] NVARCHAR(300)
           [数量] [单价] [金额] DECIMAL(18,8) / [执行时间] DATETIME
  桥接表 : dbo.[sjjk_bmb_2025_06_01]（部门字典表, 表级注释「部门表」）
           主键 [id] BIGINT 聚簇；[编码] nvarchar(10) NOT NULL
           [名称] nvarchar(100) / [建档时间] datetime / [撤档时间] datetime
           该表为事实层数值主键 [执行科室代码] 与维表业务编码 [HIS_DEPT_CODE] 的唯一桥接通道。
  维表 A : dbo.[DIM_PRF_ITEM_RVU_VERSION]（绩效大类来源）
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)——本脚本按系统单版本假设，
           不使用 VERSION_NO / ORG_CODE 做开窗收敛，仅按 PROJ_CODE 做 MAX() 拉平
           [PROJ_CODE] varchar(50) / [ITEM_CAT_CODE] varchar(50) / [ITEM_CAT_NAME] nvarchar(100)
           [RVU_VAL] numeric(12,4) / [DECISION_COFF] decimal(18,4)
  维表 B : dbo.[DIM_DEPT_ITEM_EXEC_RATIO]（执行比例与核算单元来源）
           [HIS_DEPT_CODE] VARCHAR(60) / [ITEM_CODE] VARCHAR(60) / [IS_ENABLED] TINYINT
           [DOC_EXEC_RATIO] [TECH_EXEC_RATIO] [NURSE_EXEC_RATIO] DECIMAL(18,8)
           [DOC_HPS_DEPT_CODE] [TECH_HPS_DEPT_CODE] [NURSE_HPS_DEPT_CODE] VARCHAR(60)
           [DOC_HPS_DEPT_NAME] [TECH_HPS_DEPT_NAME] [NURSE_HPS_DEPT_NAME] NVARCHAR(300)

  ── 关键纠偏（防熵增） ──
  1. 【主键血缘修复】事实层 [执行科室代码] 存储的是部门字典表物理主键 [id]（BIGINT, 如 100241），
     而维表 B [HIS_DEPT_CODE] 存储的是业务编码（如 '0102'）。二者语义不同层级，
     直接字符串化比对将 100% 漏配，导致全部执行比例与医技护三路核算单元退化为 NULL 兜底。
     故必须引入部门字典表 sjjk_bmb_2025_06_01 做桥接：
     事实层 [执行科室代码] ──(id = id)──▶ 字典层 [编码] ──▶ 作为 EXEC_DEPT_CODE_KEY 与维表 B 匹配。
  2. 字典关联采用 INNER JOIN：字典未命中即意味着该执行科室缺少业务编码，
     下游维表必然无法匹配，此类行对执行积分切分无贡献价值，提前剪枝减少无效链路开销。
  3. 维表 A 按系统单版本假设直接抽取，不再做 VERSION_NO 开窗收敛；
     仍保留按 PROJ_CODE 的 MAX() 拉平（防多计费单位/多机构分支造成行级放大）。
  4. 维表 B 的生效唯一键为 (HIS_DEPT_CODE, ITEM_CODE) 且受 IS_ENABLED = 1 过滤唯一索引约束，
     故 LEFT JOIN 在启用态下天然 1:1，不会放大行数；关联条件中显式携带 r.[IS_ENABLED] = 1，
     避免停用历史行参与匹配。
  5. 类型安全：字典层 [编码] 为 nvarchar(10)，维表 B [HIS_DEPT_CODE] 为 VARCHAR(60)。
     桥接输出统一做一次性字符串化 CAST(d.[编码] AS VARCHAR(60))，宽度锁定 VARCHAR(60)
     与目标列声明宽度一一对齐，严禁窄化截断至 nvarchar(10) 造成长编码静默截断。
     关联两侧均为原生字符串，业务编码前导零（如 '0102'）零丢失。
  6. 过滤条件收敛于 dim_version_scope 层（v.[ITEM_CAT_CODE] NOT IN ('1101','1041')），
     在 JOIN 之前完成剪枝，杜绝无效行进入关联链路。
  7. 医技护三路核算单元映射与执行比例均可能为 NULL（未配置规则行），
     比例列统一 ISNULL 兜底 0.00000000（与 .clinerules 第 7 节精度规范同源）；
     核算单元映射列保留 NULL 原值不做字符兜底，由下游按缺失语义显式判定，
     防止 'UNKNOWN' 与真实编码混淆。
  8. 维表 B 与事实层严格 1:1 左连接，事实层每条收费明细恰产出一行，
     不做任何 GROUP BY 聚合，保持明细粒度以供下游按医技护角色二次切分。
  9. 【字段裁剪】开单科室（[开单科室代码] / [开单科室]）与执行积分核算口径无关，
     已从事实层抽取、关联层、收敛层及出口契约中全量移除，杜绝无关维度污染与冗余 I/O。
  10.【粒度收敛】事实层在取得字典业务编码后立即完成 (执行科室 × 项目代码) 预聚合，
     输出 SUM(数量) 与 SUM(金额)；[执行时间] 与 [单价] 不再向上游沉淀。
     价值：同一科室同一项目的成百上千笔收费明细在此坍缩为单行，压降 90%+ 物理行数，
     使后续维度关联与出口 IO 成本与【科室 × 项目】数量级对齐，而非与收费笔数对齐。
  11.【字段裁剪·单价语义】[平均单价] 仅为原 [单价] 聚合后的还原度量（导出型展示列），
     不具备独立聚合可加性，且下游执行积分切分（数量 × 执行比例 × RVU）全程不依赖单价，
     故已在 dim_version_scope / dim_collapse / joined / final 及出口契约中全量移除，
     同步消除零除守卫与除法算子开销。若后续确需单价，须重新走 SUM(金额) ÷ SUM(数量) 还原。
  12.【账期哨兵】聚合后 [执行时间] 已被消除，但下游维表（如拉链映射）可能需要账期时点
     做半开区间匹配。故在出口携带 BIZ_EPOCH = 次月 1 日 00:00:00（账期右端点哨兵），
     以常量穿越 CTE 链而非污染聚合键；该列不作为业务时点列对外输出。
  13.【字段裁剪·诊疗决策系数】[DECISION_COFF] 属开单侧决策语义，仅服务于
     医疗服务项目开单积分（数量 × RVU_VAL × DECISION_COFF），与执行侧拆算无因果关系。
     为杜绝无关维度污染执行积分链路与冗余 I/O，已从维表抽取（dim_version_scope）、
     维度收敛（dim_collapse）、关联层（joined）、final 及出口契约全量移除；
     维表 A 契约中 [DECISION_COFF] 列保留声明以维持 DDL 血缘可追溯性。
  14.【行转列剪枝】医技护三角色由 CROSS APPLY (VALUES ...) 动态行转列，1 条【科室 × 项目】
      事实行按角色展开为 1~3 行，并强制剪枝：
      u.[EXEC_RATIO] > 0.00000000 且 u.[HPS_DEPT_CODE] IS NOT NULL。
      价值：未配置角色（比例兜底 0）与无核算单元映射的行在出口直接消除，
      下游无需再写角色 IF 分支判定，核算口径天然对齐【唯有效执行才产生积分】。
  15.【执行积分口径】[执行积分] = CAST([数量] × [单项RVU点数] × [执行比例] AS DECIMAL(18,8))，
      在 final 层以行内标量乘法一次性算定，不做二次聚合与精度降级；
      运算三因子已在 joined 层完成 DECIMAL(18,8) 同精度收敛，杜绝低精度截断累积误差。
      该列语义为【科室 × 项目 × 角色】粒度工作量，跨角色求和即该项目全部执行积分。

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份, 4 位数字文本, 默认 '2025'
  '{month}'     : 核算月份, 1-12 文本, 默认 '6'
  {struct_codes}: 科室代码过滤集, 英文逗号分隔; 留空则不过滤
  输出契约   : 核算年份 / 核算月份 / 执行科室代码 / 执行科室 / 项目代码 / 项目名称 / 数量 / 金额
               / 绩效核算大类代码 / 绩效核算大类名称 / 单项RVU点数
               / 执行角色 / 执行比例 / 核算单元编码 / 核算单元名称 / 执行积分
               / 计算过程描述
  落库契约   : 第一区块写入 dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配专用物理表）
               列化核对列: FINAL_VALUE(执行积分) + TOTAL_QTY(执行数量)
               JSON 过程仓: CALC_DETAIL_JSON 全量 7 组节点（基础元数据/执行科室/项目大类/
                            角色比例/计算因子与结果/RVU配置快照/执行比例配置快照）
  粒度定义   : 【核算单元 × 执行科室 × 收费项目 × 执行角色】行转列后粒度
               事实层按 (EXEC_DEPT_ID, EXEC_DEPT_NAME, PROJ_CODE, PROJ_NAME) 完成预聚合后再进入维度关联链；
               医技护三角色经 CROSS APPLY 行转列，每有效角色恰产出一行。
  【EPOCH】  : BIZ_EPOCH 为账期边界哨兵值（次月 1 日 00:00:00），
               仅用于携带账期信息穿越 CTE 链，供下游做半开区间时点匹配，
               严禁作为业务时点列对外输出，严禁参与聚合或分组。

  修改日志：
  2026-09-14 11:00:00 | 持久化与过滤纠偏 | 参照开单积分脚本完成 Envelope Pattern 双区块物理持久化改造，落库 [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]（ITEM_CODE = ITEM_MED_SVC_EXEC_SCORE）；纠偏出口过滤口径由物理执行科室 [EXEC_DEPT_ID] 改为核算单元 [HPS_DEPT_CODE]；追加四段式 [计算过程描述] 与全量 7 组 JSON 过程仓（含 RVU配置快照 / 执行比例配置快照 双子 JSON）。
  2026-09-14 10:30:00 | 架构重构与积分计算 | 引入 CROSS APPLY 实现医技护角色动态行转列与剪枝，直接计算并输出 [执行积分]；出口契约归一化为单列核算单元与执行角色。
  2026-09-14 10:15:00 | 字段裁剪与规范对齐 | 移除平均单价(AVG_UNIT_PRICE)与诊疗决策系数(DECISION_COFF)字段输出与相关计算逻辑；补齐文件相对路径与链路注释。
  2026-09-14 10:05:00 | 粒度收敛聚合 | 移除 [执行时间] 维度与明细输出；事实层按 (执行科室代码, 执行科室, 项目代码, 项目名称) 进行 GROUP BY 聚合，输出 SUM(数量) 与 SUM(金额)，大幅减少物理行数。
  2026-09-14 09:50:00 | 关联修复与裁剪 | 彻底移除开单科室代码/名称输出；通过 sjjk_bmb_2025_06_01 桥接事实层 执行科室代码 (id) 与维表 HIS_DEPT_CODE (编码) 的主键关联。
  2026-09-14 07:00:00 | 重构熵减 | 按系统单版本假设，移除 VERSION_NO 窗口函数收敛逻辑，降低计算熵值与算子开销：
                                 彻底删除 dim_latest_version CTE（含 ROW_NUMBER() OVER (PARTITION BY PROJ_CODE, MEAS_UNIT
                                 ORDER BY VERSION_NO DESC) 开窗排序）与 dim_pick 层 VERSION_RANK = 1 过滤；
                                 维表 A 抽取流简化为 dim_version_scope → dim_collapse 两级直连（保留 ITEM_CAT_CODE NOT IN ('1101','1041') 剪枝）；
                                 dim_collapse 层保留按 PROJ_CODE 的 MAX() 拉平以继续防多计费单位/多机构分支行级放大；
                                 同步清除头部注释与 CTE 中全部 VERSION_NO / VERSION_RANK 引用；
                                 模板占位符、别名规范、DECIMAL(18,8) 类型转换、出口列名契约与物理行数零改动。
  2026-09-14 06:00:00 | 脚本新建 | 创建医疗服务项目执行积分基础数据抽取脚本：
                                 以 PF临时医疗服务项目26A 为主表，INNER JOIN DIM_PRF_ITEM_RVU_VERSION 取绩效大类，
                                 LEFT JOIN DIM_DEPT_ITEM_EXEC_RATIO（IS_ENABLED = 1）取医技护执行比例与三路核算单元映射；
                                 剔除绩效大类 1101/1041；关联键按源类型差异做一次性 VARCHAR(60) 字符串化；
                                 比例列 ISNULL 兜底 0.00000000，维表版本快照收敛防笛卡尔放大；
                                 仅输出 SELECT 结果集，不落库、不改表结构；全局禁 GO 协议、单批分号结束。
                                 【注：本条为 06:00:00 初始版本口径，已由 2026-09-14 11:00:00 持久化改造覆盖——
                                   本脚本现落库 dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG，并落 CALC_PROCESS_TEXT 与 CALC_DETAIL_JSON。】
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

-- 2. 算子计算与持久化落库（dept_dict → fact_raw → dim_version_scope → dim_exec_ratio_raw
--    → dim_collapse → joined → final 计算链路零改动，仅增强过滤口径与 Envelope 包装）
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
    WHERE a.[执行时间] >= DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1)
      AND a.[执行时间] <  DATEADD(MONTH, 1, DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1))
    GROUP BY
        a.[项目代码],
        a.[项目名称],
        a.[执行科室代码],
        a.[执行科室],
        d.[DEPT_CODE]
),

-- ── Import CTE: 绩效大类维表作用域（大类剔除在 JOIN 前完成剪枝；仅抽取计算所需列） ──
dim_version_scope AS (
    SELECT
        b.[PROJ_CODE],
        b.[MEAS_UNIT],
        b.[PROJ_NAME],
        b.[ITEM_CAT_CODE],
        b.[ITEM_CAT_NAME],
        b.[RVU_VAL]
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

-- ── Logical CTE: 维度系数收敛（同一 PROJ_CODE 多计费单位/多机构分支拉平，防最外层输出被维度污染；
--              仅保留执行积分所需 RVU_VAL，DECISION_COFF 属开单侧语义已裁剪） ──
dim_collapse AS (
    SELECT
        d.[PROJ_CODE],
        MAX(d.[PROJ_NAME])                          AS CAT_PROJ_NAME,
        MAX(d.[ITEM_CAT_CODE])                      AS ITEM_CAT_CODE,
        MAX(d.[ITEM_CAT_NAME])                      AS ITEM_CAT_NAME,
        MAX(CAST(d.[RVU_VAL]       AS DECIMAL(18,8))) AS RVU_VAL
    FROM dim_version_scope AS d
    GROUP BY d.[PROJ_CODE]
),

-- ── Logical CTE: 事实(聚合) × 绩效大类 × 医技护执行划分 关联（【执行科室 × 项目】粒度，
--              此层维持宽表三角色并列，供 final 层 CROSS APPLY 行转列消费） ──
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
    INNER JOIN dim_collapse AS c
        ON f.[PROJ_CODE] = c.[PROJ_CODE]
    LEFT JOIN dim_exec_ratio_raw AS x
        ON f.[EXEC_DEPT_CODE_KEY] = x.[HIS_DEPT_CODE]
       AND f.[PROJ_CODE]          = x.[ITEM_CODE]
),

-- ── Final CTE: 出口契约（医技护三角色经 CROSS APPLY 动态行转列，1 行拆为 1~3 行）
--              过滤落位于 final 层，同时完成：科室过滤 + 有效角色剪枝 + 执行积分标量算定 ──
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        j.[BIZ_EPOCH],
        j.[EXEC_DEPT_ID],
        j.[EXEC_DEPT_NAME],
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[QTY],
        j.[AMOUNT],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        u.[ROLE_NAME]                                                                AS EXEC_ROLE,
        CAST(u.[EXEC_RATIO] AS DECIMAL(18,8))                                        AS EXEC_RATIO,
        u.[HPS_DEPT_CODE],
        u.[HPS_DEPT_NAME],
        CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8))                AS EXEC_POINTS,
        '医疗服务执行积分 | 科室项目角色执行积分 = 数量 × 单项RVU点数 × 执行比例 | '
            + CAST(CAST(j.[QTY] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' × '
            + CAST(CAST(j.[RVU_VAL] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' × '
            + CAST(CAST(u.[EXEC_RATIO] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' = '
            + CAST(CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' | '
            + CAST(CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8)) AS VARCHAR(50)) + ' + 0.00000000 = '
            + CAST(CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8)) AS VARCHAR(50)) AS CALC_PROCESS_TEXT
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
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME],
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
            CAST(f.[EXEC_DEPT_ID] AS VARCHAR(20))       AS [执行科室代码],
            f.[EXEC_DEPT_NAME]                          AS [执行科室名称],
            f.[EXEC_DEPT_CODE_KEY]                      AS [执行科室业务编码],
            f.[PROJ_CODE]                               AS [项目代码],
            f.[PROJ_NAME]                               AS [项目名称],
            f.[ITEM_CAT_CODE]                           AS [绩效核算大类代码],
            f.[ITEM_CAT_NAME]                           AS [绩效核算大类名称],
            f.[EXEC_ROLE]                               AS [执行角色],
            CAST(f.[EXEC_RATIO] AS DECIMAL(18,8))       AS [执行比例],
            CAST(f.[QTY]        AS DECIMAL(18,8))       AS [数量],
            CAST(f.[AMOUNT]     AS DECIMAL(18,8))       AS [金额],
            CAST(f.[RVU_VAL]    AS DECIMAL(18,8))       AS [单项RVU点数],
            CAST(f.[EXEC_POINTS] AS DECIMAL(18,8))      AS [执行积分],
            (
                SELECT
                    f.[ITEM_CAT_CODE]                   AS [绩效核算大类代码],
                    f.[ITEM_CAT_NAME]                   AS [绩效核算大类名称],
                    CAST(f.[RVU_VAL] AS DECIMAL(18,8))  AS [单项RVU点数]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )                                           AS [RVU配置快照],
            (
                SELECT
                    f.[EXEC_ROLE]                               AS [执行角色],
                    CAST(f.[EXEC_RATIO] AS DECIMAL(18,8))       AS [执行比例],
                    f.[HPS_DEPT_CODE]                           AS [核算单元编码],
                    f.[HPS_DEPT_NAME]                           AS [核算单元名称]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            )                                           AS [执行比例配置快照],
            f.[CALC_PROCESS_TEXT]                       AS [计算过程描述]
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

