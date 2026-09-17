/* ===============================================================================
  Relative Path : 一次分配/通知入院积分.sql
  脚本名称: 通知入院积分.sql
  业务定义: 通知入院积分(人次数 × RVU 点数)一次分配核算明细持久化。
  数据流向: dbo.[PF临时收入院数据26A] (事实层, 别名 A)
            ──▶ dbo.[sjjk_ryb_2025_06_01] (人员表桥接 [开单人员代码] -> 原始系统工号, 别名 B)
            ──▶ dbo.[MAP_MDM_STAFF] (主数据路由 原始系统工号 -> 绩效标准工号, 别名 C)
            ──▶ dbo.[ads_dept_post_coefficient_m] (月度岗位系数表 -> 开单人所属核算单元, 别名 D)
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (RVU 点数维表 -> 积分因子, 别名 cte_rvu)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_ADM_NOTICE_SCORE)

  ── 依赖契约 ──
  事实层 : dbo.[PF临时收入院数据26A]
           [开单人员代码] BIGINT / [入院登记时间] DATETIME
  人员表 : dbo.[sjjk_ryb_2025_06_01]
           [id] int (主键聚簇) / [编号] varchar(300) —— 事实层数值主键 → 原始系统工号的唯一桥接通道
  映射表 : dbo.[MAP_MDM_STAFF]
           主键 (SRC_ORG_CODE, SRC_SYS_CODE, SRC_STAFF_CODE)；
           [SRC_STAFF_CODE] varchar(50) / [STAFF_CODE] char(6) —— 绩效内核标准人员编码
  系数表 : dbo.[ads_dept_post_coefficient_m]
           主键 (year, month, unit_code, staff_code, post_code)；
           [unit_code] varchar(50) / [unit_name] varchar(100)
  RVU维表: dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)；
           [PROJ_CODE] varchar(50) / [RVU_VAL] numeric(12,4) NOT NULL DEFAULT 0.0000
           单版本快照策略：PROJ_CODE 1:1 直连绩效内核指标编码，VERSION_NO / VERSION_DESC
           降维为普通备注属性列，严禁作为动态寻址条件（恪守零版本寻址法则）。
  落库表 : dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]（一次分配专用 EAV-Hybrid 日志表）
           业务唯一键 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE,
                       PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE) —— 8 维锁死幂等重跑

  ── 关键纠偏（防熵增） ──
  1. 【零聚合收敛】禁用 MAX()/MIN() 黑箱折叠与 ROW_NUMBER() 开窗收敛；
     岗位系数表物理主键含 [post_code]，同一员工同一账期多岗位（兼岗/月中转科）产生多行属业务真实语义，
     以核算单元维度原样透传；同员工多核算单元将落为多条日志行，由 8 维唯一键天然区隔。
  2. 【账期取自事实层】系数表账期 [year]/[month] 直接由事实层 [入院登记时间] 派生，
     严禁引入外部 '{year}' / '{month}' 作为第二套账期口径，避免双账期语义漂移。
  3. 【编码族关联】全链关联键均为字符串编码族，原值裸引用，不做 CAST / 补零等冗余改造。
  4. 【明细层文本化】final CTE 为程序读写倒数第二层，年份/月份强制文本化，
     严禁向 CALC_DETAIL_JSON 与 INSERT 层抛出 INT 原生长度（上层仅透传，不重复叠加 CAST）。
  5. 【未映射单元幂等声明】[UNIT_CODE] 未命中系数表时兜底 'UNKNOWN'；
     该批行的清场同样受 {struct_codes} 占位符约束，若 {struct_codes} 不含 'UNKNOWN'
     则重跑时该批行不参与 DELETE，属本项目既有统一惯例（与 出院人次积分.sql 同源处理）。

  ── 模板占位符（严禁破坏） ──
  '{year}'      : 核算年份 (如 '2025')
  '{month}'     : 核算月份 (如 '6')
  '{start_time}': 核算开始时间 (如 '2024-01-01 00:00:00.000')
  '{end_time}'  : 核算结束时间 (如 '2024-01-31 23:59:59.997')
  {struct_codes}: 核算单元过滤集 (如 ('10001', '10002'))

  修改日志
  2026-09-17 10:15:00 | 细节文本化 | 依 .clinerules 规范，将第二区块 CTE_DWD_READ_ALIAS 中的 [CREATE_TIME] 显式文本化为 CONVERT(VARCHAR(19), [CREATE_TIME], 120) AS [创建时间]。
  2026-09-17 10:00:00 | 架构持久化 | Envelope Pattern 双区块重构：前置幂等 DELETE，计算链路封装落库至 DWD_FIN_CALC_ALLOC1_DETAIL_LOG（ITEM_CODE='ITEM_ADM_NOTICE_SCORE'），明细收敛入 CALC_DETAIL_JSON；第二区块以波浪号隔离，严格承接 struct_code/struct_name/result_value 模板契约。
  2026-09-17 09:55:00 | 指标扩展 | 通过项目编码关联 DIM_PRF_ITEM_RVU_VERSION 维表提取 RVU，计算积分(人次数*RVU)，并依据四段式规范拼接积分详解审计文本。
  2026-09-17 09:45:00 | 映射扩展 | 增设项目编码衍生字段：当项目名称等于'通知入院'时映射为'METRIC_ADM_NOTICE'，保持现有分组粒度不变。
  2026-09-17 09:35:00 | 维度裁剪 | 剔除执行科室代码、执行科室、执行人员代码与执行人员字段，粒度收敛至 [入院登记年月 × 项目名称 × 开单人 × 开单人所属核算单元]，进一步减少结果集行数。
  2026-09-17 09:25:00 | 维度裁剪 | 剔除冗余开单科室代码与开单科室字段，基于开单人所属核算单元归并分组，进一步降低数据粒度并减少行数。
  2026-09-17 09:15:00 | 粒度降维 | 移除开单时间、入院登记时间及患者/挂号标识，新增入院登记年份、入院登记月份及 COUNT(1) AS [人次数]，使用 GROUP BY 按年月与科室人员维度聚合，降低结果集行数。
  2026-09-17 09:05:00 | 脚本新建 | 新建通知入院积分查询脚本；多表关联提取开单人所属核算单元编码与名称，使用标准时间范围占位符过滤，严格恪守零 ROW_NUMBER / 零 MAX-MIN 聚合折叠与时间占位符独占行法则。
=============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 员工 粒度）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)
-- =================================================================
~
-- 1. 幂等清理历史数据（清场范围 = 账期 + ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
-- 【格式规范】占位符条件 [UNIT_CODE] IN {struct_codes} 强制独占一行并以 AND 开头，支持单行 `--` 注释做零副作用隔离
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
  AND [CALC_MONTH] = CAST('{month}' AS INT)
  AND [ITEM_CODE]  = N'ITEM_ADM_NOTICE_SCORE'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（cte_rvu 单版本直连 → src 人次数聚合 → final 审计文本 → INSERT 封装）
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
    WHERE v.[PROJ_CODE] = 'METRIC_ADM_NOTICE'
),

-- ── Logical CTE: 通知入院人次数聚合（原明细逻辑保留，补标准员工工号维度与单元过滤） ──
src AS (
    SELECT
        YEAR(A.[入院登记时间])                         AS [入院登记年份]
       ,MONTH(A.[入院登记时间])                        AS [入院登记月份]
       ,A.[项目名称]                                    AS [项目名称]
       ,'METRIC_ADM_NOTICE'                           AS [项目编码]
       ,A.[开单人员代码]                                AS [开单人员代码]
       ,C.[STAFF_CODE]                                AS [标准员工工号]
       ,A.[开单人]                                      AS [开单人]
       ,ISNULL(D.[unit_code], 'UNKNOWN')              AS [开单人所属核算单元编码]
       ,ISNULL(D.[unit_name], '未映射核算单元')       AS [开单人所属核算单元名称]
       ,COUNT(1)                                        AS [人次数]
       -- 【精度标准】RVU 源列为 numeric(12,4)，空值兜底后统一收敛至全局 DECIMAL(18,8) 强制精度
       ,CAST(ISNULL(rvu.[RVU_VAL], 0) AS DECIMAL(18,8)) AS [RVU]
       ,CAST(COUNT(1) * ISNULL(rvu.[RVU_VAL], 0) AS DECIMAL(18,8)) AS [积分]
    FROM dbo.[PF临时收入院数据26A] AS A WITH (NOLOCK)
    LEFT JOIN dbo.[sjjk_ryb_2025_06_01] AS B WITH (NOLOCK)
        ON A.[开单人员代码] = B.[id]
    LEFT JOIN dbo.[MAP_MDM_STAFF] AS C WITH (NOLOCK)
        ON B.[编号] = C.[SRC_STAFF_CODE]
    LEFT JOIN dbo.[ads_dept_post_coefficient_m] AS D WITH (NOLOCK)
        ON C.[STAFF_CODE]  = D.[staff_code]
       AND D.[year]        = YEAR(A.[入院登记时间])
       AND D.[month]       = MONTH(A.[入院登记时间])
    -- 【零版本寻址】RVU 维表单版本快照，PROJ_CODE 常量直连，严禁 ROW_NUMBER() 动态版本路由
    LEFT JOIN cte_rvu AS rvu
        ON rvu.[PROJ_CODE] = 'METRIC_ADM_NOTICE'
    -- 【格式规范】核算期间截面与动态单元过滤逐条独立换行，占位符条件独占一行并以 AND 开头
    WHERE A.[入院登记时间] >= '{start_time}'
      AND A.[入院登记时间] <= '{end_time}'
      AND ISNULL(D.[unit_code], 'UNKNOWN') IN {struct_codes}
    GROUP BY
        YEAR(A.[入院登记时间])
       ,MONTH(A.[入院登记时间])
       ,A.[项目名称]
       ,A.[开单人员代码]
       ,C.[STAFF_CODE]
       ,A.[开单人]
       ,D.[unit_code]
       ,D.[unit_name]
       ,rvu.[RVU_VAL]
),
-- ── Final CTE: 出口契约与审计文本打包（四段式：元数据 | 中文逻辑公式 | 纯数学代入算式 | 纯数字结算算式） ──
-- 【明细层日期时间强制文本化】本层即程序读写倒数第二层，年份/月份必须裸化为纯文本，严禁向持久化/JSON 层抛出 INT 原生长度
final AS (
    SELECT
        CAST(s.[入院登记年份] AS VARCHAR(4))           AS [入院登记年份]
       ,CAST(s.[入院登记月份] AS VARCHAR(2))           AS [入院登记月份]
       ,s.[项目名称]                                  AS [项目名称]
       ,s.[项目编码]                                  AS [项目编码]
       ,s.[开单人员代码]                              AS [开单人员代码]
       ,s.[标准员工工号]                              AS [标准员工工号]
       ,s.[开单人]                                    AS [开单人]
       ,s.[开单人所属核算单元编码]                    AS [开单人所属核算单元编码]
       ,s.[开单人所属核算单元名称]                    AS [开单人所属核算单元名称]
       ,s.[人次数]                                    AS [人次数]
       ,s.[RVU]                                       AS [RVU]
       ,s.[积分]                                      AS [积分]
       ,CONCAT(
            N'通知入院积分 | 通知入院积分 = 人次数 × 单项RVU点数 | '
           ,CAST(s.[人次数] AS VARCHAR(20)), ' × '
           ,CAST(s.[RVU]    AS VARCHAR(32)), ' = '
           ,CAST(s.[积分]   AS VARCHAR(32))
           ,' | '
           ,CAST(s.[积分]   AS VARCHAR(32))
        )                                             AS [计算过程]
    FROM src AS s
)

-- 3. 投影落库（账期常量经 SELECT 投影；JSON 过程仓承载全量中间因子与 RVU 配置快照）
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [EXEC_ROLE],
    [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST('{year}'  AS INT)                      AS [CALC_YEAR],
    CAST('{month}' AS INT)                      AS [CALC_MONTH],
    N'ITEM_ADM_NOTICE_SCORE'                    AS [ITEM_CODE],
    N'通知入院积分'                              AS [ITEM_NAME],
    N'通知入院积分.sql'                         AS [SCRIPT_NAME],
    f.[开单人所属核算单元编码]                    AS [UNIT_CODE],
    f.[开单人所属核算单元名称]                    AS [UNIT_NAME],
    f.[项目编码]                                 AS [PROJ_CODE],
    f.[项目名称]                                 AS [PROJ_NAME],
    '1101'                                      AS [ITEM_CAT_CODE],
    N'出入院服务类'                              AS [ITEM_CAT_NAME],
    N'医生'                                     AS [EXEC_ROLE],
    ISNULL(f.[标准员工工号], N'NONE')            AS [STAFF_CODE],
    ISNULL(f.[开单人], N'NONE')                  AS [STAFF_NAME],
    N'NONE'                                     AS [DAY_TYPE_CODE],
    N'NONE'                                     AS [DAY_TYPE_NAME],
    N'SCORE'                                    AS [FINAL_VALUE_TYPE],
    CAST(f.[积分]   AS DECIMAL(18,8))           AS [FINAL_VALUE],
    CAST(f.[人次数] AS DECIMAL(18,8))           AS [TOTAL_QTY],
    f.[计算过程]                                 AS [CALC_PROCESS_TEXT],
    (
        SELECT
            -- 【透传原则】年份/月份在 final 层已文本化，此处直接透传，严禁重复叠加 CAST
            f.[入院登记年份]                                       AS [核算年份],
            f.[入院登记月份]                                       AS [核算月份],
            f.[开单人所属核算单元编码]                             AS [核算单元编码],
            f.[开单人所属核算单元名称]                             AS [核算单元名称],
            f.[项目编码]                                          AS [项目代码],
            f.[项目名称]                                          AS [项目名称],
            '1101'                                               AS [绩效核算大类代码],
            N'出入院服务类'                                        AS [绩效核算大类名称],
            N'医生'                                               AS [执行角色],
            ISNULL(f.[标准员工工号], N'NONE')                      AS [员工工号],
            ISNULL(f.[开单人], N'NONE')                            AS [员工姓名],
            CAST(f.[人次数] AS DECIMAL(18,8))                      AS [人次数],
            CAST(f.[RVU] AS DECIMAL(18,8))                         AS [单项RVU点数],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [通知入院积分],
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
                WHERE c.[PROJ_CODE] = f.[项目编码]
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
        -- 【明细层日期时间强制文本化】第二区块为接口读取出口，[CREATE_TIME] 为 DATETIME2 原生类型，必须文本化防原生类型外泄
        CONVERT(VARCHAR(19), [CREATE_TIME], 120) AS [创建时间]
    FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
    -- 【格式规范】占位符条件 [UNIT_CODE] IN {struct_codes} 独占一行并以 AND 开头，便于按单元降维调试
    WHERE [CALC_YEAR]  = CAST('{year}'  AS INT)
      AND [CALC_MONTH] = CAST('{month}' AS INT)
      AND [ITEM_CODE]  = N'ITEM_ADM_NOTICE_SCORE'
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

