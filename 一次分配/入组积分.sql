/* ===============================================================================
  Relative Path : 一次分配/入组积分.sql
  脚本名称     : 入组积分.sql
  分层归属     : 一次分配业务查询层
  业务定义     : 中医优势病种（白疕病 / 蛇串疮 / 蛇盘疮病）入组患者人次与积分核算，
                 按结算年月 × 病种 × 绩效核算单元 × 执行人员类型 × 衍生项目编码 聚合计数与积分。
                 入组积分 = 入组人次 × 单项 RVU 点数。
  数据流向     : dbo.[ods_tcm_advantage_disease_patient_d] (事实层 · 中医优势病种入组患者明细)
                 ──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接 病人科室ID dept_code -> [编码])
                 ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (HIS 编码 -> 绩效核算单元 × 执行人员类型)
                 ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (RVU 点数维表 -> 单项点数与入组积分)
                 ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_TCM_ADVANTAGE_DISEASE_SCORE)

  ── 依赖契约 ──
  事实表 : dbo.[ods_tcm_advantage_disease_patient_d]
           [disease_code] VARCHAR(50) / [disease_name] NVARCHAR(100)
           [dept_code]    VARCHAR(50) / [settle_time]  DATETIME
  桥接表 : dbo.[sjjk_bmb_2025_06_01] ([id] bigint -> [编码] nvarchar(10))
  映射表 : dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27]（渐变维拉链表 SCD Type 2）
           [HIS_DEPT_CODE] varchar(300) / [HPS_DEPT_CODE] / [HPS_DEPT_NAME] varchar(300)
           [PERFORM_PERSON_TYPE_CODE] varchar(100) / [PERFORM_PERSON_TYPE] varchar(300)
           [START_DATE] datetime2(7) / [END_DATE] datetime2(7) —— 映射生效区间 [START_DATE, END_DATE]
  RVU维表: dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)；
           [ORG_CODE] varchar(50) / [PROJ_CODE] varchar(50) / [RVU_VAL] numeric(12,4) NOT NULL DEFAULT 0.0000
           [VERSION_NO] varchar(20) / [VERSION_DESC] nvarchar(200) —— 降维为普通备注属性列

  ── 关键纠偏（防熵增） ──
  1. 【类型安全桥接】事实层 [dept_code] 为 VARCHAR(50) 字符串语义，桥接表 [id] 为 BIGINT，
     关联时必须单侧显式 CAST(bmb.[id] AS VARCHAR(50)) 对齐字符串域，
     严禁反向将 [dept_code] 整型化（防前导零丢失与索引失配）。
  2. 【维度降维切片】剔除 settle_time 物理列，仅派生 [结算年份] / [结算月份] 文本列，
     并按 .clinerules 第 7.2 节【明细层日期时间强制文本化】强制 CAST 为 VARCHAR。
  3. 【零黑箱收敛】禁用 MAX() / MIN() 折叠与 ROW_NUMBER() 开窗；两级映射 1:N 展开属业务真实语义，
     由 GROUP BY 全维度收敛，COUNT(1) 如实反映展开后的人次口径。
  4. 【拉链表时效闭环】映射表为渐变维拉链表（SCD Type 2），同一 [HIS_DEPT_CODE] 在多个映射版本
     下存在多条物理行。关联时必须将事实层 [settle_time] 锁定于映射生效区间之内（起点容忍空值、
     终点容忍空值），确保单时间点精准命中唯一有效切片；缺失该时序边界将导致旧版本历史映射与
     当期数据交叉匹配，引发 1:N 行级膨胀与人次计数翻倍。
  5. 【零版本寻址】RVU 维表 `DIM_PRF_ITEM_RVU_VERSION` 与衍生项目编码 1:1 直连读取，严禁使用
     ROW_NUMBER() OVER (PARTITION BY ... ORDER BY VERSION_NO DESC) 动态版本路由；
     [VERSION_NO] / [VERSION_DESC] 仅作普通备注属性列，不得作为主控过滤条件。
  6. 【积分口径】入组积分 = 入组人次 × 单项 RVU 点数，RVU 未配置时以 0 兜底（LEFT JOIN 保基数）。
     单项点数与积分全程锁定 DECIMAL(18,8) 精度（.clinerules 第 7 节）。
  7. 【持久化粒度对齐】落库唯一键 UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ 为
     (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)，
     不含病种维度，故：PROJ_CODE 取衍生项目编码（METRIC_DRG_*）保持键前缀语义，
     EXEC_ROLE 落人员类型名称承担人员类型切分，病种明细（病种编码/名称/人次/RVU）全量收敛入 CALC_DETAIL_JSON。

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份 (如 '2025')
  '{month}'     : 核算月份 (如 '6')
  '{start_time}': 核算开始时间 (如 '2024-01-01 00:00:00.000')
  '{end_time}'  : 核算结束时间 (如 '2024-01-31 23:59:59.997')
  {struct_codes}: 核算单元过滤集 (如 ('10001', '10002'))

  修改日志：
  2026-09-18 13:00:00 | 字段微调 | 第一区块持久化 INSERT/SELECT 补齐 [RVU_VAL] 物理列投影，与 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 新增属性列 1:1 对齐（投影源 = final 层已透传的 [RVU] 单项点数，经 CAST(... AS DECIMAL(18,8)) 收敛至全局强制精度；INSERT 列位插入于 [ITEM_CAT_NAME] 之后、[EXEC_ROLE] 之前）。
  2026-09-17 16:00:00 | 架构持久化 | Envelope Pattern 双区块重构：新增第一区块（波浪号隔离前）前置幂等 DELETE（按 CALC_YEAR/CALC_MONTH/ITEM_CODE='ITEM_TCM_ADVANTAGE_DISEASE_SCORE'/UNIT_CODE 清场，覆盖 UQ 前 4 列故语义安全），计算链路封装为 cte_rvu → src → final（final 层年份/月份强制文本化并生成四段式审计文本），INSERT 落至 DWD_FIN_CALC_ALLOC1_DETAIL_LOG（FINAL_VALUE=入组积分 / TOTAL_QTY=入组人次 / EXEC_ROLE=执行人员类型，病种与 RVU 配置快照经 FOR JSON PATH 收敛入 CALC_DETAIL_JSON）；第二区块以波浪号隔离，CTE_DWD_READ_ALIAS 读取物理表并严格承接 struct_code/struct_name/result_value 模板契约；头部业务定义、依赖契约、关键纠偏与占位符清单同步对齐落库口径。
  2026-09-17 15:00:00 | 指标扩展 | 引入 RVU 关联与入组积分计算：SELECT 投影新增 CASE WHEN 衍生项目编码映射（A08.01.02×1001→'METRIC_DRG_DZHZ_DOCTOR'、A08.01.02×1002→'METRIC_DRG_DZHZ_NURSE'、A08.01.15×1001→'METRIC_DRG_YXB_DOCTOR'、A08.01.15×1002→'METRIC_DRG_YXB_NURSE'），并 LEFT JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION]（限定 ORG_CODE='1001'，零版本寻址 1:1 直连）取 [RVU_VAL]；新增导出 [衍生项目编码] / [RVU] / [入组积分]（= COUNT(1) × ISNULL(RVU_VAL,0)，DECIMAL(18,8) 精度），GROUP BY 同步纳入衍生项目编码表达式与 rvu.[RVU_VAL]；头部依赖契约与关键纠偏补录 RVU 维表血缘、零版本寻址与积分口径锚点；时间/占位符过滤与拉链时效边界零改动。
  2026-09-17 14:10:00 | 拉链时效闭环 | 映射表关联补全渐变维（SCD Type 2）时效边界：[settle_time] >= [START_DATE]（容忍 [START_DATE] 空值）且 [settle_time] <= [END_DATE]（容忍 [END_DATE] 空值）双条件下沉至 ON 子句，消除跨版本重叠匹配导致的行级膨胀与人次翻倍；同步在头部依赖契约与关键纠偏块补录拉链表时效闭环规范锚点。输出字段、降维粒度、占位符契约与 WHERE 过滤逻辑零改动。
  2026-09-17 13:40:00 | 脚本创建 | 初始创建入组积分查询脚本，实现时间降维切片（结算年份/结算月份文本化）、科室两级桥接映射（dept_code -> id -> [编码] -> HIS_DEPT_CODE）与人次统计（COUNT(1) AS [入组人次]）。
=============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 衍生项目 × 执行角色 粒度专用物理表）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)
-- =================================================================
~
-- 1. 幂等清理历史数据（清场范围 = ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
-- 【格式规范】占位符条件 [UNIT_CODE] IN {struct_codes} 强制独占一行并以 AND 开头，支持单行 `--` 注释做零副作用隔离
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（cte_rvu 单版本直连 → src 入组人次与积分聚合 → final 审计文本 → INSERT 封装）
WITH
-- ── Import CTE: RVU 维表 1:1 直连（零版本寻址，VERSION_NO 降维为普通备注列，严禁 ROW_NUMBER 动态路由） ──
cte_rvu AS (
    SELECT
        v.[PROJ_CODE]                                 AS PROJ_CODE
       ,v.[VERSION_NO]                                AS VERSION_NO
       ,v.[VERSION_DESC]                              AS VERSION_DESC
       ,v.[ORG_CODE]                                  AS ORG_CODE
       ,v.[ORG_NAME]                                  AS ORG_NAME
       ,v.[SRC_SYS_CODE]                              AS SRC_SYS_CODE
       ,v.[PROJ_NAME]                                 AS PROJ_NAME
       ,v.[MEAS_UNIT]                                 AS MEAS_UNIT
       ,v.[ITEM_CAT_CODE]                             AS ITEM_CAT_CODE
       ,v.[ITEM_CAT_NAME]                             AS ITEM_CAT_NAME
       ,v.[OPR_LEVEL_CODE]                            AS OPR_LEVEL_CODE
       ,v.[OPR_LEVEL_NAME]                            AS OPR_LEVEL_NAME
       ,v.[CREATE_USER]                               AS CREATE_USER
       ,v.[CREATE_TIME]                               AS CREATE_TIME
       ,v.[UPDATE_USER]                               AS UPDATE_USER
       ,v.[UPDATE_TIME]                               AS UPDATE_TIME
       ,v.[REMARK]                                    AS REMARK
       ,v.[SCORE_REASON]                              AS SCORE_REASON
       ,CAST(v.[RVU_VAL]       AS DECIMAL(18,8))      AS RVU_VAL
       ,CAST(v.[EXEC_COFF]     AS DECIMAL(18,8))      AS EXEC_COFF
       ,CAST(v.[DECISION_COFF] AS DECIMAL(18,8))      AS DECISION_COFF
       ,CAST(v.[UNIT_PRICE]    AS DECIMAL(18,8))      AS UNIT_PRICE
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v WITH (NOLOCK)
    WHERE v.[ORG_CODE] = '1001'
      AND v.[PROJ_CODE] IN (
              'METRIC_DRG_DZHZ_DOCTOR'
             ,'METRIC_DRG_DZHZ_NURSE'
             ,'METRIC_DRG_YXB_DOCTOR'
             ,'METRIC_DRG_YXB_NURSE'
          )
),

-- ── Logical CTE: 入组人次与入组积分聚合（原查询关联链路与占位符契约原样保留，仅补 RVU 关联与衍生项目编码） ──
src AS (
    SELECT
        CAST(YEAR(ods.[settle_time]) AS VARCHAR(4))     AS [结算年份]
       ,CAST(MONTH(ods.[settle_time]) AS VARCHAR(2))    AS [结算月份]
       ,ods.[disease_code]                              AS [病种编码]
       ,ods.[disease_name]                              AS [病种名称]
       ,m.[HPS_DEPT_CODE]                               AS [核算单元编码]
       ,m.[HPS_DEPT_NAME]                               AS [核算单元名称]
       ,m.[PERFORM_PERSON_TYPE_CODE]                    AS [执行人员类型编码]
       ,m.[PERFORM_PERSON_TYPE]                         AS [执行人员类型名称]
       -- 【衍生项目编码】病种 × 执行人员类型 条件分支映射，对齐 RVU 维表 PROJ_CODE 血统
       ,CASE
            WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_DZHZ_DOCTOR' AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_DZHZ_NURSE'  AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_YXB_DOCTOR'  AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_YXB_NURSE'   AS VARCHAR(50))
            ELSE CAST('UNKNOWN' AS VARCHAR(50))
        END                                              AS [衍生项目编码]
       ,COUNT(1)                                        AS [入组人次]
       -- 【单项点数】自 RVU 维表取值，未配置时以 0 兜底，全程锁定 DECIMAL(18,8) 精度
       ,ISNULL(CAST(rvu.[RVU_VAL] AS DECIMAL(18,8)), CAST(0 AS DECIMAL(18,8))) AS [RVU]
       -- 【入组积分】入组积分 = 入组人次 × 单项点数
       ,CAST(COUNT(1) * ISNULL(CAST(rvu.[RVU_VAL] AS DECIMAL(18,8)), CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [入组积分]
       ,rvu.[PROJ_CODE]                                 AS [RVU项目代码]
    FROM dbo.[ods_tcm_advantage_disease_patient_d] AS ods WITH (NOLOCK)
    INNER JOIN dbo.[sjjk_bmb_2025_06_01] AS bmb WITH (NOLOCK)
        ON ods.[dept_code] = CAST(bmb.[id] AS VARCHAR(50))
    INNER JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
        ON bmb.[编码] = m.[HIS_DEPT_CODE]
        -- 【拉链表时效闭环】渐变维 SCD Type 2 映射生效区间截面：结算时间必须落入 [START_DATE, END_DATE]
        -- 起点/终点均容忍空值（空值视为该侧无界），确保单结算时间点精准命中唯一有效映射切片
        AND (ods.[settle_time] >= m.[START_DATE] OR m.[START_DATE] IS NULL)
        AND (ods.[settle_time] <= m.[END_DATE] OR m.[END_DATE] IS NULL)
    -- 【零版本寻址】RVU 维表 1:1 直连，严禁 ROW_NUMBER() OVER (... ORDER BY VERSION_NO DESC) 动态版本路由；
    -- [VERSION_NO] / [VERSION_DESC] 降维为普通备注属性列，不作为主控过滤条件。
    -- 使用 LEFT JOIN 保基数：衍生项目编码未配置 RVU 时不丢失入组人次事实行。
    LEFT JOIN cte_rvu AS rvu
        ON rvu.[PROJ_CODE] = CASE
                                 WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DRG_DZHZ_DOCTOR'
                                 WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DRG_DZHZ_NURSE'
                                 WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DRG_YXB_DOCTOR'
                                 WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DRG_YXB_NURSE'
                                 ELSE NULL
                             END
    -- 【格式规范】核算期间截面与动态单元过滤逐条独立换行，占位符条件独占一行并以 AND 开头
    WHERE 1 = 1
        AND ods.[settle_time] >= '{start_time}'
        AND ods.[settle_time] <= '{end_time}'
        AND m.[HPS_DEPT_CODE] IN {struct_codes}
    GROUP BY
        CAST(YEAR(ods.[settle_time]) AS VARCHAR(4))
       ,CAST(MONTH(ods.[settle_time]) AS VARCHAR(2))
       ,ods.[disease_code]
       ,ods.[disease_name]
       ,m.[HPS_DEPT_CODE]
       ,m.[HPS_DEPT_NAME]
       ,m.[PERFORM_PERSON_TYPE_CODE]
       ,m.[PERFORM_PERSON_TYPE]
       -- 【聚合收敛】衍生项目编码表达式必须完整纳入 GROUP BY，确保 COUNT(1) 按衍生维度正确聚合
       ,CASE
            WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_DZHZ_DOCTOR' AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_DZHZ_NURSE'  AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_YXB_DOCTOR'  AS VARCHAR(50))
            WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_YXB_NURSE'   AS VARCHAR(50))
            ELSE CAST('UNKNOWN' AS VARCHAR(50))
        END
       ,rvu.[RVU_VAL]
       ,rvu.[PROJ_CODE]
),

-- ── Final CTE: 出口契约与审计文本打包（四段式：元数据段 | 中文逻辑公式段 | 纯数学代入算式段 | 纯数字结算算式段） ──
-- 【明细层日期时间强制文本化】本层即程序读写倒数第二层，年份/月份必须裸化为纯文本，严禁向持久化/JSON 层抛出 INT 原生长度
final AS (
    SELECT
        CAST(s.[结算年份] AS VARCHAR(4))               AS [结算年份]
       ,CAST(s.[结算月份] AS VARCHAR(2))               AS [结算月份]
       ,s.[病种编码]                                   AS [病种编码]
       ,s.[病种名称]                                   AS [病种名称]
       ,s.[核算单元编码]                               AS [核算单元编码]
       ,s.[核算单元名称]                               AS [核算单元名称]
       ,s.[执行人员类型编码]                           AS [执行人员类型编码]
       ,s.[执行人员类型名称]                           AS [执行人员类型名称]
       ,s.[衍生项目编码]                               AS [衍生项目编码]
       ,s.[入组人次]                                   AS [入组人次]
       ,s.[RVU]                                        AS [RVU]
       ,s.[入组积分]                                   AS [入组积分]
       ,s.[RVU项目代码]                                AS [RVU项目代码]
       ,CONCAT(
            N'中医优势病种入组积分 | 入组积分 = 入组人次 × 单项RVU点数 | '
           ,CAST(s.[入组人次] AS VARCHAR(20)), ' × '
           ,CAST(s.[RVU] AS VARCHAR(32)), ' = '
           ,CAST(s.[入组积分] AS VARCHAR(32))
        )                                              AS [计算过程]
    FROM src AS s
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [RVU_VAL], [EXEC_ROLE],
    [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST('{year}'  AS INT)                      AS [CALC_YEAR],
    CAST('{month}' AS INT)                      AS [CALC_MONTH],
    N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE'         AS [ITEM_CODE],
    N'中医优势病种入组积分'                       AS [ITEM_NAME],
    N'入组积分.sql'                              AS [SCRIPT_NAME],
    f.[核算单元编码]                             AS [UNIT_CODE],
    f.[核算单元名称]                             AS [UNIT_NAME],
    f.[衍生项目编码]                             AS [PROJ_CODE],
    f.[病种名称]                                 AS [PROJ_NAME],
    '1101'                                      AS [ITEM_CAT_CODE],
    N'出入院服务类'                              AS [ITEM_CAT_NAME],
    CAST(f.[RVU] AS DECIMAL(18,8))              AS [RVU_VAL],
    -- 执行角色承担人员类型切分（UQ 第 6 列），严禁退化为常量 NONE
    ISNULL(CAST(f.[执行人员类型名称] AS NVARCHAR(20)), N'NONE') AS [EXEC_ROLE],
    N'NONE'                                     AS [STAFF_CODE],
    N'NONE'                                     AS [STAFF_NAME],
    N'NONE'                                     AS [DAY_TYPE_CODE],
    N'NONE'                                     AS [DAY_TYPE_NAME],
    N'SCORE'                                    AS [FINAL_VALUE_TYPE],
    CAST(f.[入组积分] AS DECIMAL(18,8))          AS [FINAL_VALUE],
    CAST(f.[入组人次] AS DECIMAL(18,8))          AS [TOTAL_QTY],
    f.[计算过程]                                 AS [CALC_PROCESS_TEXT],

    (
        SELECT
            CAST(f.[结算年份] AS VARCHAR(4))                       AS [核算年份],
            CAST(f.[结算月份] AS VARCHAR(2))                       AS [核算月份],
            f.[病种编码]                                           AS [病种编码],
            f.[病种名称]                                           AS [病种名称],
            f.[核算单元编码]                                       AS [核算单元编码],
            f.[核算单元名称]                                       AS [核算单元名称],
            f.[执行人员类型编码]                                   AS [人员类型编码],
            f.[执行人员类型名称]                                   AS [人员类型],
            f.[衍生项目编码]                                       AS [项目代码],
            f.[RVU项目代码]                                        AS [RVU项目代码],
            '1101'                                               AS [绩效核算大类代码],
            N'出入院服务类'                                        AS [绩效核算大类名称],
            CAST(f.[入组人次] AS DECIMAL(18,8))                    AS [入组人次],
            CAST(f.[RVU] AS DECIMAL(18,8))                         AS [单项RVU点数],
            CAST(f.[入组积分] AS DECIMAL(18,8))                    AS [入组积分],
            f.[计算过程]                                          AS [计算过程描述],

            -- RVU 配置快照（FOR JSON PATH 纯常量投影，零回表；按 PROJ_CODE 1:1 直连 cte_rvu）
            JSON_QUERY((
                SELECT
                    c.[VERSION_NO]       AS [版本号],
                    c.[VERSION_DESC]     AS [版本描述],
                    c.[ORG_CODE]         AS [机构编码],
                    c.[ORG_NAME]         AS [机构名称],
                    c.[SRC_SYS_CODE]     AS [源系统编码],
                    c.[PROJ_CODE]        AS [项目代码],
                    c.[PROJ_NAME]        AS [项目名称],
                    c.[MEAS_UNIT]        AS [原始计费单位],
                    CAST(c.[RVU_VAL] AS DECIMAL(18,8))       AS [单项绩效点数],
                    c.[ITEM_CAT_CODE]    AS [绩效核算大类编码],
                    c.[ITEM_CAT_NAME]    AS [绩效核算大类名称],
                    CAST(c.[UNIT_PRICE] AS DECIMAL(18,8))    AS [历史参考单价],
                    c.[OPR_LEVEL_CODE]   AS [手术等级编码],
                    c.[OPR_LEVEL_NAME]   AS [手术等级名称],
                    c.[CREATE_USER]      AS [创建人],
                    CONVERT(VARCHAR(19), c.[CREATE_TIME], 120) AS [创建时间],
                    c.[UPDATE_USER]      AS [修改人],
                    CONVERT(VARCHAR(19), c.[UPDATE_TIME], 120) AS [修改时间],
                    CAST(c.[DECISION_COFF] AS DECIMAL(18,8)) AS [诊疗决策系数],
                    CAST(c.[EXEC_COFF] AS DECIMAL(18,8))     AS [执行系数],
                    c.[REMARK]           AS [备注说明],
                    c.[SCORE_REASON]     AS [评分理由依据]
                FROM cte_rvu AS c
                WHERE c.[PROJ_CODE] = f.[RVU项目代码]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ))                                          AS [RVU配置快照]
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
        [CREATE_TIME]           AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    -- 【格式规范】占位符条件 [UNIT_CODE] IN {struct_codes} 独占一行并以 AND 开头，便于按单元降维调试
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_TCM_ADVANTAGE_DISEASE_SCORE'
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


