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

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份, 4 位数字文本, 默认 '2025'
  '{month}'     : 核算月份, 1-12 文本, 默认 '6'
  {struct_codes}: 科室代码过滤集, 英文逗号分隔; 留空则不过滤
  输出契约   : 执行科室代码 / 执行科室 / 项目代码 / 项目名称 / 数量 / 单价 / 金额
               / 绩效核算大类代码 / 绩效核算大类名称 / 单项RVU点数 / 诊疗决策系数
               / 医生执行比例 / 技师执行比例 / 护士执行比例
               / 医生核算单元编码 / 医生核算单元名称
               / 技师核算单元编码 / 技师核算单元名称
               / 护士核算单元编码 / 护士核算单元名称
  粒度定义   : 事实层收费明细行（执行科室 × 项目代码）

  修改日志：
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
=============================================================================== */

WITH
-- ── Import CTE: 部门字典桥接层（事实层数值主键 id → 维表业务编码 编码） ──
dept_dict AS (
    SELECT
        b.[id]                                        AS DEPT_ID,
        CAST(b.[编码] AS VARCHAR(60))                 AS DEPT_CODE
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
),

-- ── Import CTE: 事实层收费明细（执行科室通过字典桥接取得业务编码，半开区间 月初 至 次月初） ──
fact_raw AS (
    SELECT
        a.[项目代码]                                  AS PROJ_CODE,
        a.[项目名称]                                  AS PROJ_NAME,
        a.[执行科室代码]                              AS EXEC_DEPT_ID,
        a.[执行科室]                                  AS EXEC_DEPT_NAME,
        d.[DEPT_CODE]                                 AS EXEC_DEPT_CODE_KEY,
        a.[执行时间]                                  AS EXEC_TIME,
        CAST(a.[数量] AS DECIMAL(18,8))               AS QTY,
        CAST(a.[单价] AS DECIMAL(18,8))               AS UNIT_PRICE,
        CAST(a.[金额] AS DECIMAL(18,8))               AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    INNER JOIN dept_dict AS d
        ON a.[执行科室代码] = d.[DEPT_ID]
    WHERE a.[执行时间] >= DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1)
      AND a.[执行时间] <  DATEADD(MONTH, 1, DATEFROMPARTS(CAST('{year}' AS INT), CAST('{month}' AS INT), 1))
),

-- ── Import CTE: 绩效大类维表作用域（大类剔除在 JOIN 前完成剪枝） ──
dim_version_scope AS (
    SELECT
        b.[PROJ_CODE],
        b.[MEAS_UNIT],
        b.[PROJ_NAME],
        b.[ITEM_CAT_CODE],
        b.[ITEM_CAT_NAME],
        b.[RVU_VAL],
        b.[DECISION_COFF]
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

-- ── Logical CTE: 维度系数收敛（同一 PROJ_CODE 多计费单位/多机构分支拉平，防最外层输出被维度污染） ──
dim_collapse AS (
    SELECT
        d.[PROJ_CODE],
        MAX(d.[PROJ_NAME])                          AS CAT_PROJ_NAME,
        MAX(d.[ITEM_CAT_CODE])                      AS ITEM_CAT_CODE,
        MAX(d.[ITEM_CAT_NAME])                      AS ITEM_CAT_NAME,
        MAX(CAST(d.[RVU_VAL]       AS DECIMAL(18,8))) AS RVU_VAL,
        MAX(CAST(d.[DECISION_COFF] AS DECIMAL(18,8))) AS DECISION_COFF
    FROM dim_version_scope AS d
    GROUP BY d.[PROJ_CODE]
),

-- ── Logical CTE: 事实 × 绩效大类 × 医技护执行划分 三表关联（明细粒度，不聚合） ──
joined AS (
    SELECT
        f.[EXEC_DEPT_ID],
        f.[EXEC_DEPT_NAME],
        f.[EXEC_DEPT_CODE_KEY],
        f.[EXEC_TIME],
        f.[PROJ_CODE],
        f.[PROJ_NAME],
        f.[QTY],
        f.[UNIT_PRICE],
        f.[AMOUNT],
        c.[ITEM_CAT_CODE],
        c.[ITEM_CAT_NAME],
        c.[RVU_VAL],
        c.[DECISION_COFF],
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

-- ── Final CTE: 出口契约（执行科室过滤落位于最外层，隔离过滤维度不污染关联链路） ──
final AS (
    SELECT
        CAST('{year}'  AS VARCHAR(10)) AS CALC_YEAR,
        CAST('{month}' AS VARCHAR(10)) AS CALC_MONTH,
        j.[EXEC_DEPT_ID],
        j.[EXEC_DEPT_NAME],
        j.[PROJ_CODE],
        j.[PROJ_NAME],
        j.[EXEC_TIME],
        j.[QTY],
        j.[UNIT_PRICE],
        j.[AMOUNT],
        j.[ITEM_CAT_CODE],
        j.[ITEM_CAT_NAME],
        j.[RVU_VAL],
        j.[DECISION_COFF],
        j.[DOC_EXEC_RATIO],
        j.[TECH_EXEC_RATIO],
        j.[NURSE_EXEC_RATIO],
        j.[DOC_HPS_DEPT_CODE],
        j.[DOC_HPS_DEPT_NAME],
        j.[TECH_HPS_DEPT_CODE],
        j.[TECH_HPS_DEPT_NAME],
        j.[NURSE_HPS_DEPT_CODE],
        j.[NURSE_HPS_DEPT_NAME]
    FROM joined AS j
    WHERE j.[EXEC_DEPT_ID] IN {struct_codes}
)

SELECT
    f.[CALC_YEAR]                AS [核算年份]
   ,f.[CALC_MONTH]               AS [核算月份]
   ,f.[EXEC_DEPT_ID]             AS [执行科室代码]
   ,f.[EXEC_DEPT_NAME]           AS [执行科室]
   ,f.[PROJ_CODE]                AS [项目代码]
   ,f.[PROJ_NAME]                AS [项目名称]
   ,f.[EXEC_TIME]                AS [执行时间]
   ,f.[QTY]                      AS [数量]
   ,f.[UNIT_PRICE]               AS [单价]
   ,f.[AMOUNT]                   AS [金额]
   ,f.[ITEM_CAT_CODE]            AS [绩效核算大类代码]
   ,f.[ITEM_CAT_NAME]            AS [绩效核算大类名称]
   ,f.[RVU_VAL]                  AS [单项RVU点数]
   ,f.[DECISION_COFF]            AS [诊疗决策系数]
   ,f.[DOC_EXEC_RATIO]           AS [医生执行比例]
   ,f.[TECH_EXEC_RATIO]          AS [技师执行比例]
   ,f.[NURSE_EXEC_RATIO]         AS [护士执行比例]
   ,f.[DOC_HPS_DEPT_CODE]        AS [医生核算单元编码]
   ,f.[DOC_HPS_DEPT_NAME]        AS [医生核算单元名称]
   ,f.[TECH_HPS_DEPT_CODE]       AS [技师核算单元编码]
   ,f.[TECH_HPS_DEPT_NAME]       AS [技师核算单元名称]
   ,f.[NURSE_HPS_DEPT_CODE]      AS [护士核算单元编码]
   ,f.[NURSE_HPS_DEPT_NAME]      AS [护士核算单元名称]
FROM final AS f;

