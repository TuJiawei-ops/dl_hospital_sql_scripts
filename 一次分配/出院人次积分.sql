/* ===============================================================================
  Relative Path : 一次分配/出院人次积分.sql
  脚本名称: 出院人次积分.sql
  业务说明: 出院人次积分持久化（核算单元 × 人员类型 粒度），积分 = 出院人次 × RVU 点数。
  数据流向: dbo.[PF临时出院数据26A] (事实层)
            ──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接 出院科室代码 id -> 编码)
            ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (HIS 编码 -> 绩效核算单元 × 人员类型)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (RVU 点数维表)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_DISCHARGE_PERSON_COUNT_SCORE)

  ── 依赖契约 ──
  事实表 : dbo.[PF临时出院数据26A] ([出院科室代码] BIGINT / [出院时间] DATETIME)
  桥接表 : dbo.[sjjk_bmb_2025_06_01] ([id] bigint -> [编码] nvarchar(10))
  维表 A : dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (拉链有效期 [START_DATE, END_DATE] 闭区间)
  维表 B : dbo.[DIM_PRF_ITEM_RVU_VERSION] (单版本快照策略，PROJ_CODE 1:1 直连；
           VERSION_NO / VERSION_DESC 降维为普通备注属性列，严禁作为动态寻址条件)

  ── 模板占位符 ──
  '{year}'      : 核算年份 (如 '2025')
  '{month}'     : 核算月份 (如 '6')
  '{start_time}': 核算开始时间 (如 '2024-01-01 00:00:00.000')
  '{end_time}'  : 核算结束时间 (如 '2024-01-31 23:59:59.997')
  {struct_codes}: 核算单元过滤集 (如 ('10001', '10002'))

  修改日志:
  2026-09-17 10:30:00 | 映射修正 | 纠偏 PROJ_NAME 映射：在 src CTE 中增加 [项目名称] 映射（1001->出院人次-医生，1002->出院人次-护士），替换落库投影 f.[人员类型] 为 f.[项目名称]，实现 PROJ_CODE 与 PROJ_NAME 完全对齐。
  2026-09-16 21:30:00 | 文件重命名 | 脚本由「出入院服务项目积分.sql」正式更名为「出院人次积分.sql」并同步全链元数据：头部 Relative Path 与脚本名称标注对齐新文件名；落库投影 [SCRIPT_NAME] 常量由 N'出入院服务项目积分.sql' 改为 N'出院人次积分.sql'，保证持久化日志与物理脚本文件精准一致；同步修正跨血缘引用文件 analyses/排查_出院服务未映射核算单元科室明细.sql 的口径溯源标注；核算逻辑、ITEM_CODE、占位符契约与双区块结构零改动。
  2026-09-16 18:00:00 | 格式规范对齐 | 依 .clinerules 第 6 节【占位符条件独占行与 AND 开头法则】审计三处 {struct_codes} 过滤点（DELETE 块 / src CTE / CTE_DWD_READ_ALIAS 块），确认均已独占一行且行首带 AND 前缀，SQL 逻辑零改动；三处上方补录格式规范注释锚点，防范后续同行混写回归破坏 `--` 单行注释隔离能力。
  2026-09-16 17:00:00 | 去版本化重构 | 本系统默认单版本快照，彻底移除 cte_rvu 中的 ROW_NUMBER 寻址与 cte_rvu_snap 过滤层，VERSION_NO 降维为普通备注列直接关联。
  2026-09-16 16:00:00 | 架构重构 | 剔除 cte_rvu 过度 MAX 聚合；强制倒数第二层 final 明细层日期时间字段文本化。
  2026-09-16 00:00:00 | 逻辑修正 | 追加出院时间核算范围过滤条件 WHERE f.[出院时间] >= '{start_time}' AND f.[出院时间] <= '{end_time}'，补齐原脚本缺失的核算期间约束（原实现无 WHERE 子句将全量累计出院人次）；同步补齐 Relative Path 标注并拆分核算期间截面与维度期间截面注释语义
  2026-09-16 12:00:00 | 架构持久化 | Envelope Pattern 双区块重构：第一区块前置幂等 DELETE（清场范围 = ITEM_CODE + UNIT_CODE，覆盖 UQ 前缀），计算链路原样封装为 cte_rvu → src → final，出院人次聚合关联与积分算式零改动；INSERT 落至一次分配专用物理表 DWD_FIN_CALC_ALLOC1_DETAIL_LOG（ITEM_CODE='ITEM_DISCHARGE_PERSON_COUNT_SCORE' / FINAL_VALUE_TYPE='SCORE' / ITEM_CAT_CODE='1101'），人员类型经 CASE 下沉至 PROJ_CODE 与 EXEC_ROLE 列，过程因子经 FOR JSON PATH 收敛入 CALC_DETAIL_JSON；第二区块以波浪号隔离，从物理表读取生成 CTE_DWD_READ_ALIAS 并严格承接 struct_code/struct_name/result_value 模板契约；
                                     纠偏 scalar subquery 无 FROM 的 T-SQL 强制语法约束，账期常量统一经 SELECT ... (SELECT ...) 常量投影落库。
  2026-09-16 10:00:00 | 注释极简重构 | 剥离叙事型推演注释，收敛为依赖契约 + 模板占位符原子清单；SQL 逻辑零改动。
=============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 人员类型 粒度专用物理表）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE)
-- =================================================================
~
-- 1. 幂等清理历史数据（清场范围 = ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
-- 【格式规范】占位符条件 [UNIT_CODE] IN {struct_codes} 强制独占一行并以 AND 开头，支持单行 `--` 注释做零副作用隔离
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_DISCHARGE_PERSON_COUNT_SCORE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（cte_rvu 单版本直连 → src 出院人次聚合 → final 审计文本 → INSERT 封装）
WITH
-- ── Import CTE: RVU 维表 1:1 直连（单版本快照策略，PROJ_CODE 唯一，VERSION_NO 降维为普通备注列） ──
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
    WHERE v.[PROJ_CODE] IN ('METRIC_DISCHARGE_DOCTOR', 'METRIC_DISCHARGE_NURSE')
),

-- ── Logical CTE: 出院人次聚合（原主查询逻辑原样保留，仅补 PROJ_CODE 路由列与单元过滤） ──
src AS (
    SELECT
        YEAR(f.[出院时间])                            AS [出院时间年份]
       ,MONTH(f.[出院时间])                           AS [出院时间月份]
       ,ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN')         AS [绩效核算单元编码]
       ,ISNULL(m.[HPS_DEPT_NAME], '未映射核算单元')    AS [绩效核算单元名称]
       ,m.[PERFORM_PERSON_TYPE_CODE]                 AS [人员类型编码]
       ,m.[PERFORM_PERSON_TYPE]                      AS [人员类型]
       ,CASE
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DISCHARGE_DOCTOR'
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DISCHARGE_NURSE'
            ELSE 'UNKNOWN'
        END                                          AS [项目代码]
       ,CASE
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN N'出院人次-医生'
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN N'出院人次-护士'
            ELSE N'UNKNOWN'
        END                                          AS [项目名称]
       ,COUNT(1)                                     AS [出院人次]
       ,ISNULL(rvu.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS [RVU]
       ,CAST(COUNT(1) * ISNULL(rvu.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [积分]
       ,rvu.[PROJ_CODE]                              AS [RVU项目代码]
    FROM dbo.[PF临时出院数据26A] AS f WITH (NOLOCK)
    INNER JOIN dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
        ON f.[出院科室代码] = b.[id]
    LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
        ON b.[编码] = m.[HIS_DEPT_CODE]
       AND f.[出院时间] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR f.[出院时间] <= m.[END_DATE])
    LEFT JOIN cte_rvu AS rvu
        ON rvu.[PROJ_CODE] = CASE
                                WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DISCHARGE_DOCTOR'
                                WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DISCHARGE_NURSE'
                                ELSE NULL
                             END
    -- 【格式规范】核算期间截面与动态单元过滤逐条独立换行，占位符条件独占一行并以 AND 开头
    WHERE f.[出院时间] >= '{start_time}'
      AND f.[出院时间] <= '{end_time}'
      AND ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN') IN {struct_codes}
    GROUP BY
        YEAR(f.[出院时间])
       ,MONTH(f.[出院时间])
       ,m.[HPS_DEPT_CODE]
       ,m.[HPS_DEPT_NAME]
       ,m.[PERFORM_PERSON_TYPE_CODE]
       ,m.[PERFORM_PERSON_TYPE]
       ,CASE
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DISCHARGE_DOCTOR'
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DISCHARGE_NURSE'
            ELSE 'UNKNOWN'
        END
       ,CASE
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN N'出院人次-医生'
            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN N'出院人次-护士'
            ELSE N'UNKNOWN'
        END
       ,rvu.[RVU_VAL]
       ,rvu.[PROJ_CODE]
),
-- ── Final CTE: 出口契约与审计文本打包（三段式：中文逻辑公式 | 纯数学代入算式） ──
-- 【明细层日期时间强制文本化】本层即程序读写倒数第二层，年份/月份必须裸化为纯文本，严禁向持久化/JSON 层抛出 INT 原生长度
final AS (
    SELECT
        CAST(s.[出院时间年份] AS VARCHAR(4))           AS [出院时间年份]
       ,CAST(s.[出院时间月份] AS VARCHAR(2))           AS [出院时间月份]
       ,s.[绩效核算单元编码]                          AS [绩效核算单元编码]
       ,s.[绩效核算单元名称]                          AS [绩效核算单元名称]
       ,s.[项目代码]                                  AS [项目代码]
       ,s.[项目名称]                                  AS [项目名称]
       ,s.[人员类型编码]                              AS [人员类型编码]
       ,s.[人员类型]                                  AS [人员类型]
       ,s.[出院人次]                                  AS [出院人次]
       ,s.[RVU]                                       AS [RVU]
       ,s.[积分]                                      AS [积分]
       ,s.[RVU项目代码]                               AS [RVU项目代码]
       ,CONCAT(
            N'出院人次积分 | 出院人次积分 = 出院人次 × 单项RVU点数 | '
           ,CAST(s.[出院人次] AS VARCHAR(20)), ' × '
           ,CAST(s.[RVU] AS VARCHAR(32)), ' = '
           ,CAST(s.[积分] AS VARCHAR(32))
        )                                             AS [计算过程]
    FROM src AS s
)

INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [EXEC_ROLE],
    [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST('{year}'  AS INT)                      AS [CALC_YEAR],
    CAST('{month}' AS INT)                      AS [CALC_MONTH],
    N'ITEM_DISCHARGE_PERSON_COUNT_SCORE'        AS [ITEM_CODE],
    N'出院人次积分'                              AS [ITEM_NAME],
    N'出院人次积分.sql'                         AS [SCRIPT_NAME],
    f.[绩效核算单元编码]                         AS [UNIT_CODE],
    f.[绩效核算单元名称]                         AS [UNIT_NAME],
    f.[项目代码]                                 AS [PROJ_CODE],
    f.[项目名称]                                 AS [PROJ_NAME],
    '1101'                                      AS [ITEM_CAT_CODE],
    N'出入院服务类'                              AS [ITEM_CAT_NAME],
    CASE
        WHEN f.[人员类型编码] = '1001' THEN N'医生'
        WHEN f.[人员类型编码] = '1002' THEN N'护士'
        ELSE N'NONE'
    END                                         AS [EXEC_ROLE],
    N'NONE'                                     AS [STAFF_CODE],
    N'NONE'                                     AS [STAFF_NAME],
    N'NONE'                                     AS [DAY_TYPE_CODE],
    N'NONE'                                     AS [DAY_TYPE_NAME],
    N'SCORE'                                    AS [FINAL_VALUE_TYPE],
    CAST(f.[积分]     AS DECIMAL(18,8))         AS [FINAL_VALUE],
    CAST(f.[出院人次] AS DECIMAL(18,8))         AS [TOTAL_QTY],
    f.[计算过程]                                 AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[出院时间年份] AS VARCHAR(4))                   AS [核算年份],
            CAST(f.[出院时间月份] AS VARCHAR(2))                   AS [核算月份],
            f.[绩效核算单元编码]                                   AS [核算单元编码],
            f.[绩效核算单元名称]                                   AS [核算单元名称],
            f.[项目代码]                                          AS [项目代码],
            f.[项目名称]                                          AS [项目名称],
            '1101'                                               AS [绩效核算大类代码],
            N'出入院服务类'                                        AS [绩效核算大类名称],
            CASE
                WHEN f.[人员类型编码] = '1001' THEN N'医生'
                WHEN f.[人员类型编码] = '1002' THEN N'护士'
                ELSE N'NONE'
            END                                                  AS [执行角色],
            f.[人员类型编码]                                      AS [人员类型编码],
            f.[人员类型]                                          AS [人员类型],
            CAST(f.[出院人次] AS DECIMAL(18,8))                    AS [出院人次],
            CAST(f.[RVU] AS DECIMAL(18,8))                         AS [单项RVU点数],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [出院人次积分],
            f.[计算过程]                                          AS [计算过程描述],
            -- RVU 配置快照（FOR JSON PATH 纯常量投影，零表回表；按 PROJ_CODE 1:1 直连 cte_rvu）
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
      AND [ITEM_CODE]  = N'ITEM_DISCHARGE_PERSON_COUNT_SCORE'
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

