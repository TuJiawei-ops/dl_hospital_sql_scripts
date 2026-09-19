/* ===============================================================================
  Relative Path : analyses/医疗服务项目开单积分_核查报表.sql
  脚本名称: 医疗服务项目开单积分_核查报表.sql
  业务说明: 医疗服务项目开单积分的「全量明细链路核对报表」。以事实表物理明细为唯一粒度，
            原样透传 原始科室 → 字典桥接 → 绩效核算单元拉链映射 → RVU 维度配置 的完整血缘，
            并输出逐行中间计算算式，供业务人员一键导出核对（业务可自行 SUM 对账汇总态）。
  数据流向: dbo.[PF临时医疗服务项目26A]                    (事实层, 唯一粒度基准)
            ──▶ dbo.[sjjk_bmb_2025_06_01]                  (字典桥接: [开单科室代码] = [id] ➔ [编码])
            ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27]    (HIS 编码 ➔ 绩效核算单元, 拉链区间原始透传)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION]             (维度层, 单版本 1:1 直连)

  粒度定义: 事实表物理明细粒度，零聚合、零压缩、零 GROUP BY。
            核算单元 / 项目 汇总态 = 业务侧对本报表 [单项开单积分] 直接 SUM 得到，
            严禁在脚本内做聚合导致过程字段（原始科室、映射区间、RVU 系数）不可逆丢失。

  ── 与计算脚本（一次分配/医疗服务项目开单积分.sql）的口径差异声明 ──
  本报表 = 计算脚本的「展开态反证视图」，关联链路、字典桥接键、维度剪枝口径完全同源，
  但下列三处为「核查口径显式差异」，业务对账时务必知悉（属有意设计，非缺陷）：
  1. 【无聚合】计算脚本按 (UNIT_CODE × PROJ_CODE) 汇总后落库，本报表保留事实明细，
     故行数远大于日志表，仅 [单项开单积分] 的全表 SUM 才与日志表 [FINAL_VALUE] 可比。
  2. 【区间边界口径】本报表采用半开区间 [START_DATE, END_DATE) 判定拉链映射命中，
     计算脚本为闭区间 (>= START_DATE AND (END_DATE IS NULL OR <= END_DATE))；
     仅当映射行 END_DATE 恰等于事实时间时才产生差异，若对账出现该边界差属预期。
  3. 【过滤位置纠偏】计算脚本在 agg 层以 UNIT_CODE IN {struct_codes} 过滤，会静默丢弃
     ISNULL 兜底前的 NULL 行；本报表将 {struct_codes} 置于 [HPS_DEPT_CODE] 兜底为
     'UNKNOWN' 之后的最外层，保证「未映射核算单元」记录可被显式核查（防隐性漏计）。

  只读声明: 纯 SELECT 分析报表，彻底剥离 Envelope Pattern（无 DELETE / INSERT /
            波浪号 ~ 区块 / DWD_FIN_CALC_ALLOC1_DETAIL_LOG 写入逻辑），零副作用。
  查询提示: 全链路 WITH (NOLOCK)，只读核对不加锁，避免影响生产事实表写入。

  依赖契约:
  事实表 : dbo.[PF临时医疗服务项目26A] —— [开单科室代码] BIGINT / [患者ID] BIGINT /
           [挂号ID] NVARCHAR(243) / [HIS主键] BIGINT / [数量·单价·金额] DECIMAL(18,8)
  桥接表 : dbo.[sjjk_bmb_2025_06_01] —— [id] BIGINT 主键聚簇 / [编码] NVARCHAR(10)
  拉链表 : dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] —— [ID] INT IDENTITY /
           [HIS_DEPT_CODE] VARCHAR(300) / [HPS_DEPT_CODE] VARCHAR(300) /
           [START_DATE|END_DATE] DATETIME2(7) / [PERFORM_PERSON_TYPE_CODE] VARCHAR(100)
  维表   : dbo.[DIM_PRF_ITEM_RVU_VERSION] —— 主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)

  ── 关键纠偏（防熵增） ──
  1. 【零折叠】拉链维表严禁 ROW_NUMBER()/MAX() 人工去重，原样透传物理映射颗粒度；
     区间内多对多映射按业务预期行级扩散，折叠将导致合法映射静默丢失、积分偏小。
  2. 【单版本直连】RVU 维表 1:1 直连，VERSION_NO / VERSION_DESC 仅作备注属性，
     严禁作为动态寻址主控条件（.clinerules §9 零版本寻址与 VERSION_NO 备注化法则）。
  3. 【源列零改造】事实层 [开单科室代码] 与所有编码类字段裸引用，不做 CAST 整形/补零/去空格。
  4. 【类型文本化】倒数第二层输出的时间字段统一文本化（VARCHAR），杜绝 DATETIME 外泄。
  5. 【精度统一】全部数值计算与 CAST 统一 DECIMAL(18,8)，审计文本同精度同源。

  模板占位符（严禁破坏）:
  '{start_time}' / '{end_time}' : 事实层时间窗，按 [来源] 动态路由
                                  （门诊走 [缴费时间]，非门诊走 [执行时间]）
  '{year}' / '{month}'          : 账期标签，仅作输出列展示，不参与过滤
  {struct_codes}                : 绩效核算单元过滤集，作用于最外层 [HPS_DEPT_CODE] 兜底之后

  修改日志：
  2026-09-19 00:30:00 | 缺陷修复 | 修复 [42S22] 列名 'PROJ_NAME' 无效：joined CTE 补齐事实表 f.[PROJ_NAME] 投影
                                 （与维表 d.[PROJ_NAME] AS RVU_PROJ_NAME 并存不冲突），detail CTE 同步透传
                                 j.[PROJ_NAME]，贯通 fact_raw → fact_keyed → joined → detail → final 项目名称血缘；
                                 final 层 ISNULL(ISNULL(RVU_PROJ_NAME, PROJ_NAME), N'') 双保险回退逻辑零改动，
                                 计算公式、占位符契约与过滤条件全程冻结。
  2026-09-19 00:00:00 | 脚本新建 | 依据 一次分配/医疗服务项目开单积分.sql 生成纯只读核查报表：剥离 Envelope
                                 持久化区块（DELETE/INSERT/~ 分隔符）与 agg 聚合压缩，事实明细粒度全量透传
                                 原始科室、字典桥接编码、拉链映射区间、RVU 全系数与逐行积分算式；{struct_codes}
                                 过滤位由 UNIT_CODE 修正为 ISNULL(HPS_DEPT_CODE,'UNKNOWN')，杜绝未映射行被静默丢弃。
=============================================================================== */


WITH bmb_bridge AS (
    -- ── Import CTE: 部门字典桥接层（事实层数值主键 [开单科室代码] → HIS 业务编码 [编码]） ──
    -- [id] 为物理主键聚簇，粒度 1:1；[编码] 裸引用，不做 CAST/补零/去空格加工（§7.1 源列零改造优先）
    SELECT
        b.[id]                                          AS DEPT_ID
       ,b.[编码]                                        AS HIS_DEPT_CODE
       ,b.[名称]                                        AS HIS_DEPT_NAME
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
)
,fact_raw AS (
    -- ── Import CTE: 事实层明细开口（全字段透传，严禁为持久化裁剪过程列） ──
    -- 时间路由：门诊来源以 [缴费时间] 为业务发生锚点，非门诊来源以 [执行时间] 为锚点；
    -- 占位符条件独占行书写，保障 -- 单行零副作用注释隔离。
    SELECT
        a.[来源]                                        AS SRC_TYPE
       ,a.[HIS主键]                                     AS HIS_PK
       ,a.[患者ID]                                      AS PATIENT_ID
       ,a.[挂号ID]                                      AS REG_ID
       ,a.[开单科室代码]                                AS DEPT_ID
       ,a.[开单科室]                                    AS DEPT_NAME
       ,a.[执行时间]                                    AS ORDER_TIME
       ,a.[缴费时间]                                    AS PAY_TIME
       ,a.[项目代码]                                    AS PROJ_CODE
       ,a.[项目名称]                                    AS PROJ_NAME
       ,CAST(a.[数量] AS DECIMAL(18,8))                 AS QTY
       ,CAST(a.[单价] AS DECIMAL(18,8))                 AS UNIT_PRICE
       ,CAST(a.[金额] AS DECIMAL(18,8))                 AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    WHERE 1=1
      AND (
              (a.[来源] = N'门诊' AND a.[缴费时间] >= CAST('{start_time}' AS DATETIME) AND a.[缴费时间] <= CAST('{end_time}' AS DATETIME))
           OR (ISNULL(a.[来源], '') <> N'门诊' AND a.[执行时间] >= CAST('{start_time}' AS DATETIME) AND a.[执行时间] <= CAST('{end_time}' AS DATETIME))
          )
)
,fact_keyed AS (
    -- ── Logical CTE: 事实明细 × 字典桥接（INNER JOIN，与计算脚本同源：字典缺收即无核算单元归属） ──
    SELECT
        f.[SRC_TYPE]
       ,f.[HIS_PK]
       ,f.[PATIENT_ID]
       ,f.[REG_ID]
       ,f.[DEPT_ID]
       ,f.[DEPT_NAME]
       ,f.[ORDER_TIME]
       ,f.[PAY_TIME]
       ,f.[PROJ_CODE]
       ,f.[PROJ_NAME]
       ,f.[QTY]
       ,f.[UNIT_PRICE]
       ,f.[AMOUNT]
       ,b.[HIS_DEPT_CODE]
       ,b.[HIS_DEPT_NAME]
    FROM fact_raw AS f
    INNER JOIN bmb_bridge AS b
        ON f.[DEPT_ID] = b.[DEPT_ID]
)


,dept_unit_mapping AS (
    -- ── Import CTE: HIS 科室 → 绩效核算单元 拉链维表（原始透传，严禁开窗去重折叠） ──
    -- 物理主键 (ID, HIS_DEPT_CODE)，允许同时段一对多映射并存，此为业务预期颗粒度；
    -- 任何 ROW_NUMBER()/MAX() 收敛都会静默丢弃合法核算单元映射并导致积分偏小。
    SELECT
        m.[ID]                                          AS MAPPING_ID
       ,m.[HIS_DEPT_CODE]
       ,m.[HIS_DEPT_NAME]
       ,m.[HPS_DEPT_CODE]
       ,m.[HPS_DEPT_NAME]
       ,m.[START_DATE]
       ,m.[END_DATE]
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] = '1001'
)
,dim_version_scope AS (
    -- ── Import CTE: RVU 项目点数维表作用域（单版本 1:1 直连，绩效大类剪枝前置） ──
    -- VERSION_NO / VERSION_DESC 降级为普通备注属性列，严禁作为动态寻址主控条件（§9 零版本寻址法则）。
    -- [EXEC_COFF] 为核对参考列：开单积分算式不含执行系数，执行侧积分见 医疗服务项目执行积分.sql。
    SELECT
        v.[VERSION_NO]
       ,v.[VERSION_DESC]
       ,v.[ORG_CODE]
       ,v.[ORG_NAME]
       ,v.[SRC_SYS_CODE]
       ,v.[PROJ_CODE]
       ,v.[PROJ_NAME]
       ,v.[ITEM_CAT_CODE]
       ,v.[ITEM_CAT_NAME]
       ,CAST(v.[RVU_VAL] AS DECIMAL(18,8))              AS RVU_VAL
       ,CAST(v.[DECISION_COFF] AS DECIMAL(18,8))        AS DECISION_COFF
       ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))            AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v WITH (NOLOCK)
    WHERE v.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND v.[PROJ_CODE] IS NOT NULL
)
,joined AS (
    -- ── Logical CTE: 事实 × RVU 维度 × 拉链映射 宽表（明细粒度，零聚合零压缩） ──
    -- 拉链匹配采用半开区间 [START_DATE, END_DATE)；END_DATE 为 NULL 视为长期有效。
    SELECT
        f.[SRC_TYPE]
       ,f.[HIS_PK]
       ,f.[PATIENT_ID]
       ,f.[REG_ID]
       ,f.[DEPT_ID]
       ,f.[DEPT_NAME]
       ,f.[ORDER_TIME]
       ,f.[PAY_TIME]
       ,f.[HIS_DEPT_CODE]
       ,f.[HIS_DEPT_NAME]
       ,m.[MAPPING_ID]
       ,m.[HPS_DEPT_CODE]
       ,m.[HPS_DEPT_NAME]
       ,m.[START_DATE]
       ,m.[END_DATE]
       ,f.[PROJ_CODE]
       ,f.[PROJ_NAME]
       ,d.[PROJ_NAME]                                   AS RVU_PROJ_NAME
       ,d.[ITEM_CAT_CODE]
       ,d.[ITEM_CAT_NAME]
       ,d.[RVU_VAL]
       ,d.[DECISION_COFF]
       ,d.[EXEC_COFF]
       ,f.[QTY]
       ,f.[UNIT_PRICE]
       ,f.[AMOUNT]
    FROM fact_keyed AS f
    INNER JOIN dim_version_scope AS d
        ON f.[PROJ_CODE] = d.[PROJ_CODE]
    LEFT JOIN dept_unit_mapping AS m
        ON f.[HIS_DEPT_CODE] = m.[HIS_DEPT_CODE]
       AND f.[ORDER_TIME] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR f.[ORDER_TIME] < m.[END_DATE])
)
,detail AS (
    -- ── Logical CTE: 逐行积分计算与过程字段落地（事实明细粒度，行数 = joined 行数） ──
    -- 核算单元兜底：未命中任何拉链映射的行显式标记 UNKNOWN / 未映射核算单元，供业务定位映射缺口。
    -- [EXEC_COFF] 与 [金额]/[单价] 仅为核对参考，不参与开单积分算式。
    SELECT
        j.[SRC_TYPE]
       ,j.[HIS_PK]
       ,j.[PATIENT_ID]
       ,j.[REG_ID]
       ,j.[DEPT_ID]
       ,j.[DEPT_NAME]
       ,j.[ORDER_TIME]
       ,j.[PAY_TIME]
       ,j.[HIS_DEPT_CODE]
       ,j.[HIS_DEPT_NAME]
       ,j.[MAPPING_ID]
       ,ISNULL(j.[HPS_DEPT_CODE], 'UNKNOWN')            AS UNIT_CODE
       ,ISNULL(j.[HPS_DEPT_NAME], N'未映射核算单元')     AS UNIT_NAME
       ,j.[START_DATE]
       ,j.[END_DATE]
       ,j.[PROJ_CODE]
       ,j.[PROJ_NAME]
       ,j.[RVU_PROJ_NAME]
       ,j.[ITEM_CAT_CODE]
       ,j.[ITEM_CAT_NAME]
       ,j.[RVU_VAL]
       ,j.[DECISION_COFF]
       ,j.[EXEC_COFF]
       ,j.[QTY]
       ,j.[UNIT_PRICE]
       ,j.[AMOUNT]
       ,CAST(j.[QTY] * j.[RVU_VAL] * j.[DECISION_COFF] AS DECIMAL(18,8)) AS ITEM_SCORE
    FROM joined AS j
)


,final AS (
    -- ── Final CTE: 业务可读中文别名出口（含日期文本化与 {struct_codes} 最外层过滤） ──
    -- [行号] 为人工核对定位辅助列，非业务度量，导出前可按需剔除。
    SELECT
        CAST('{year}' AS VARCHAR(4))                                   AS [核算年份]
       ,CAST('{month}' AS VARCHAR(2))                                  AS [核算月份]
       ,CONVERT(VARCHAR(19), d.[ORDER_TIME], 120)                      AS [执行时间]
       ,CONVERT(VARCHAR(19), d.[PAY_TIME], 120)                        AS [缴费时间]
       ,ISNULL(d.[SRC_TYPE], N'')                                      AS [来源]
       ,ISNULL(CAST(d.[HIS_PK] AS VARCHAR(20)), N'')                   AS [HIS主键]
       ,ISNULL(CAST(d.[PATIENT_ID] AS VARCHAR(20)), N'')               AS [患者ID]
       ,ISNULL(d.[REG_ID], N'')                                        AS [挂号ID]
       ,ISNULL(CAST(d.[DEPT_ID] AS VARCHAR(20)), N'')                  AS [原始开单科室代码]
       ,ISNULL(d.[DEPT_NAME], N'')                                     AS [原始开单科室名称]
       ,ISNULL(d.[HIS_DEPT_CODE], N'')                                 AS [HIS部门映射编码]
       ,ISNULL(CAST(d.[MAPPING_ID] AS VARCHAR(11)), N'')               AS [映射ID]
       ,d.[UNIT_CODE]                                                  AS [绩效核算单元编码]
       ,d.[UNIT_NAME]                                                  AS [绩效核算单元名称]
       ,CONVERT(VARCHAR(19), d.[START_DATE], 120)                      AS [映射生效开始时间]
       ,CONVERT(VARCHAR(19), d.[END_DATE], 120)                        AS [映射生效结束时间]
       ,ISNULL(d.[PROJ_CODE], N'')                                     AS [项目代码]
       ,ISNULL(ISNULL(d.[RVU_PROJ_NAME], d.[PROJ_NAME]), N'')          AS [项目名称]
       ,ISNULL(d.[ITEM_CAT_CODE], N'')                                 AS [绩效大类代码]
       ,ISNULL(d.[ITEM_CAT_NAME], N'')                                 AS [绩效大类名称]
       ,CAST(ISNULL(d.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))       AS [单项RVU点数]
       ,CAST(ISNULL(d.[DECISION_COFF], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [诊疗决策系数]
       ,CAST(ISNULL(d.[EXEC_COFF], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))     AS [执行系数]
       ,CAST(ISNULL(d.[QTY], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))           AS [数量]
       ,CAST(ISNULL(d.[UNIT_PRICE], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))    AS [单价]
       ,CAST(ISNULL(d.[AMOUNT], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))        AS [金额]
       ,CAST(ISNULL(d.[ITEM_SCORE], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))    AS [单项开单积分]
       -- 三段式审计文本：[元数据段] | [中文逻辑公式段] | [纯数学代入算式段 = 最终积分]
       -- 数学段零汉字，运算符两侧保留 1 个半角空格；末段直接收敛至最终积分，不做恒等零加增熵。
       ,N'医疗服务开单积分 | 单项开单积分 = 数量 × 单项RVU点数 × 诊疗决策系数 | '
            + CAST(CAST(ISNULL(d.[QTY], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(50)) + N' × '
            + CAST(CAST(ISNULL(d.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(50)) + N' × '
            + CAST(CAST(ISNULL(d.[DECISION_COFF], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(50)) + N' = '
            + CAST(CAST(ISNULL(d.[ITEM_SCORE], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(50))      AS [计算过程描述]
       ,ROW_NUMBER() OVER (ORDER BY d.[ORDER_TIME] ASC, d.[HIS_PK] ASC, d.[PROJ_CODE] ASC)                     AS [行号]
    FROM detail AS d
    WHERE 1=1
      AND ISNULL(d.[UNIT_CODE], 'UNKNOWN') IN {struct_codes}
)
SELECT * FROM final
ORDER BY
    [核算年份] ASC
   ,[核算月份] ASC
   ,[绩效核算单元编码] ASC
   ,[项目代码] ASC
   ,[行号] ASC
;
