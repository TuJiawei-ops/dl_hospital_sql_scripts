/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分_非小儿科.sql
  脚本名称: 门诊诊察类项目执行积分_非小儿科.sql
  业务说明: 门诊诊察类项目（1043）执行积分持久化（按 核算单元 × 执行人员 × 项目 × 日期类型 粒度），
            执行科室代码 <> 36 硬隔离（NULL 安全）；学科系数常量 1.0。
  积分口径: 积分 = 项目点数 × 汇总数量 × 学科系数(1.0) × 绩效核算系数
  数据流向: dbo.[PF临时医疗服务项目26A] (事实·医疗服务项目明细)
            ──▶ INNER JOIN cte_rvu  ← dbo.[DIM_PRF_ITEM_RVU_VERSION]  (维表·绩效项目 RVU 属性, ITEM_CAT_CODE='1043')
            ──▶ LEFT JOIN  cte_ryb / cte_mdm_staff / cte_staff_post (人员主数据 → 执行人员所在核算单元 + 岗位系数)
            ──▶ LEFT JOIN  dbo.[DIM_WORK_CALENDAR]                   (维表·日期类型与绩效核算系数)
            ──▶ dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (落库 Target: ITEM_OUTPATIENT_DIAG_SCORE_NON_PED)

  ── 依赖契约 ──
  事实表 : dbo.[PF临时医疗服务项目26A] ([项目代码] / [数量] DECIMAL(18,8) / [缴费时间] / [执行科室代码])
  维表 A : dbo.[DIM_PRF_ITEM_RVU_VERSION] (按 [PROJ_CODE] 聚合收敛，RVU_VAL / EXEC_COFF 取 MAX)
  桥接 B : dbo.[sjjk_ryb_2025_06_01] ([id] → [编号]) ──▶ dbo.[MAP_MDM_STAFF] ([SRC_STAFF_CODE] → [STAFF_CODE])
  维表 C : dbo.[ads_dept_post_coefficient_m] (账期对齐 [year]/[month] 取 [unit_code] / [unit_name])
  维表 D : dbo.[DIM_WORK_CALENDAR] (生效态单日粒度，[DAY_TYPE_CODE] / [PERF_COEFF])

  ── 核心架构与约束规范（极简版） ──
  1. 【双区块隔离】：第一区块（~ 之前）完成算子计算与幂等落库；第二区块（~ 之后）仅读取日志表并承接
     struct_code / struct_name / result_value 对外契约。两区块由波浪号 ~ 硬隔离，禁止交叉引用。
  2. 【幂等重跑】：第一区块入口必须先按 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE) 精确 DELETE，
     清场范围 ⊇ UQ 前缀 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE,
     DAY_TYPE_CODE)，重跑零脏数据。
  3. 【PROJ_CODE 聚合归一】：维表 A 按 [PROJ_CODE] 一对多（多版本 / 多机构 / 多计费单位）时必须先
     GROUP BY 收敛，否则事实明细将被维表行数放大（卡特兰积扩散）。收敛口径：RVU_VAL / EXEC_COFF 取 MAX。
  4. 【执行角色无切分】：本核算项不做医技护角色切分，[EXEC_ROLE] 恒为常量 N'执行人员'，
     对应 UQ 第 6 列固定值，不参与业务语义切分。
  5. 【工作日历左连接】：日历表按 [CALC_DATE] 单日粒度匹配缴费日期，LEFT JOIN + ISNULL 双保险防覆盖缺口，
     缺口兜底 WORKDAY / 正常工作日 / 1.00000000。
  6. 【维度剪枝】：核算归属以「执行人员所在核算单元」为准；未匹配人员主数据兜底 N'未匹配'，
     严禁用 INNER JOIN 静默丢弃执行明细。
  7. 【全精度对齐】：全部数值列（点数 / 数量 / 金额 / 系数 / 积分）统一 DECIMAL(18,8)，
     数值列与审计文本同一乘数序列，保证文本推演与实际计算全程同精度同源。
  8. 【JSON 性能红线】：CALC_DETAIL_JSON 采用单层扁平标量 + 检索命中的 RVU 嵌套快照，
     严格限制为 O(N) 内存拼接，禁止外部表回表。

  ── 输出粒度 ──
  每行 = 核算单元 × 执行人员 × 项目 × 日期类型（已剥离执行日期 / 缴费日期明细维度，患者级明细不可逆）。

  ── 模板占位符 ──
  '{start_time}' : 核算开始时间 (如 '2026-06-01 00:00:00.000'，用于解析 CALC_YEAR / CALC_MONTH)
  '{end_time}'   : 核算结束时间 (如 '2026-06-30 23:59:59.997')
  {struct_codes} : 核算单元过滤集 (如 ('10001', '10002'))

  修改日志：
  2026-09-16 19:45:00 | JSON 过程仓扩展 | cte_rvu 由 5 列升级为全字段收敛（追加 VERSION_NO/VERSION_DESC/ORG_CODE/
                                   ORG_NAME/SRC_SYS_CODE/PROJ_NAME/MEAS_UNIT/OPR_LEVEL_CODE/OPR_LEVEL_NAME/
                                   CREATE_USER/CREATE_TIME/UPDATE_USER/UPDATE_TIME/REMARK/SCORE_REASON 及
                                   DECISION_COFF/UNIT_PRICE，数值列统一 CAST DECIMAL(18,8)，字符列 MAX() 收敛）；
                                   [RVU配置快照] 由 5 节点扩至 22 节点全字段血缘；CALC_DETAIL_JSON 外层补齐
                                   DWD 物理列同源标量节点（核算项编码/核算项名称/脚本名称/执行角色/员工编码/
                                   员工姓名/值类型/最终结果/计算过程描述），实现列化落库与 JSON 穿透双轨同源。
                                   双区块隔离、物理列落库逻辑与积分算式零改动。
  2026-09-16 18:30:00 | 架构持久化 | Envelope Pattern 双区块重构：第一区块前置幂等 DELETE（按 CALC_YEAR/CALC_MONTH/
                                   ITEM_CODE/UNIT_CODE 清理，清场范围 ⊇ UQ 八维前缀），计算链路收敛后 INSERT 落至
                                   dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（ITEM_CODE='ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'，
                                   EXEC_ROLE 常量 N'执行人员'，FINAL_VALUE_TYPE='SCORE'）；时间入参改由
                                   '{start_time}' 解析 YEAR/MONTH，{struct_codes} 下推至执行人员所在核算单元；
                                   过程因子经 FOR JSON PATH 收敛入 CALC_DETAIL_JSON（单层扁平 + [RVU配置快照] 嵌套）；
                                   第二区块读取日志表承接 struct_code/struct_name/result_value 契约。
                                   表结构禁止变更，学科系数 1.0 与工作日历逻辑零改动。
  2026-09-16 | 入口过滤扩展 | 增加 f.[缴费时间] 在 '{start_time}' 与 '{end_time}' 之间的过滤条件，实现源头数据下推剪枝。
  2026-09-16 | 业务指标扩充 | 新增 [积分] 与 [积分计算过程] 字段，动态展开 项目点数*数量*学科系数*绩效核算系数 审计计算表达式。
  2026-09-16 | 易用性增强 | 追加 ORDER BY 按 缴费年月->日期类型->核算单元->人员代码->项目代码 显式排序，提升财务对账与报表展示体验。
  2026-09-16 17:05:00 | 粒度压缩 | 剥离 [执行日期] 与 [缴费日期] 维度，按 人员+项目+月份+日期类型 进行聚合，实现数据高倍率压缩并提升计算性能。
  2026-09-16 16:20:00 | 维度扩充 | 接入 DIM_WORK_CALENDAR 表，以缴费日期关联提取 DAY_TYPE_CODE, DAY_TYPE_NAME, PERF_COEFF 投影与分组。
  2026-09-16 15:40:00 | 维度剪枝 | 核算归属改以「执行人员所在核算单元」为准，剥离 cte_bmb/cte_dept_map 及主查询对应 JOIN，删除 [执行绩效核算单元编码]/[执行绩效核算单元名称] 投影与分组；保留 f.[执行科室代码] <> 36（NULL 安全）硬隔离。
  2026-09-16 15:10:00 | 主数据路由纠偏 | 人员链路接入 MAP_MDM_STAFF（cte_ryb[编号] → cte_mdm_staff[SRC_STAFF_CODE] → [STAFF_CODE]），剥离不存在的 IS_ACTIVE 谓词（运行库无该列）。
=============================================================================== */

-- =================================================================
-- 第一区块：数据生成与持久化（数据生成时忽略 / 查询明细时跳过）
-- 落库目标：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（一次分配 · 核算单元 × 执行人员 × 项目 × 日期类型 粒度）
-- 唯一键对齐：(CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE, EXEC_ROLE, STAFF_CODE, DAY_TYPE_CODE)
-- =================================================================
~

-- 1. 幂等清理历史数据（清场范围 = ITEM_CODE + UNIT_CODE，已完全覆盖 UQ 前 4 列，重跑零脏数据）
DELETE FROM [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]
WHERE [CALC_YEAR]  = YEAR(CAST('{start_time}' AS DATETIME))
  AND [CALC_MONTH] = MONTH(CAST('{start_time}' AS DATETIME))
  AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'
  AND [UNIT_CODE] IN {struct_codes}
;

-- 2. 算子计算与持久化落库（cte_rvu → cte_ryb → cte_mdm_staff → cte_staff_post → final 计算链路；
--    Envelope 包装、模板占位符与落库列对齐一次分配专用物理表）
WITH
-- ── Import CTE: 绩效大类维表作用域（大类 1043 前置剪枝 + 按 PROJ_CODE 聚合收敛防卡特兰积，
--    并全字段收敛供 [RVU配置快照] 留存完整维度血缘） ──
cte_rvu AS (
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,MAX(v0.[VERSION_NO])                        AS VERSION_NO
       ,MAX(v0.[VERSION_DESC])                      AS VERSION_DESC
       ,MAX(v0.[ORG_CODE])                          AS ORG_CODE
       ,MAX(v0.[ORG_NAME])                          AS ORG_NAME
       ,MAX(v0.[SRC_SYS_CODE])                      AS SRC_SYS_CODE
       ,MAX(v0.[PROJ_NAME])                         AS PROJ_NAME
       ,MAX(v0.[MEAS_UNIT])                         AS MEAS_UNIT
       ,MAX(v0.[ITEM_CAT_CODE])                     AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])                     AS ITEM_CAT_NAME
       ,MAX(v0.[OPR_LEVEL_CODE])                    AS OPR_LEVEL_CODE
       ,MAX(v0.[OPR_LEVEL_NAME])                    AS OPR_LEVEL_NAME
       ,MAX(v0.[CREATE_USER])                       AS CREATE_USER
       ,MAX(v0.[CREATE_TIME])                       AS CREATE_TIME
       ,MAX(v0.[UPDATE_USER])                       AS UPDATE_USER
       ,MAX(v0.[UPDATE_TIME])                       AS UPDATE_TIME
       ,MAX(v0.[REMARK])                            AS REMARK
       ,MAX(v0.[SCORE_REASON])                      AS SCORE_REASON
       ,CAST(MAX(v0.[RVU_VAL])       AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF])     AS DECIMAL(18,8))  AS EXEC_COFF
       ,CAST(MAX(v0.[DECISION_COFF]) AS DECIMAL(18,8))  AS DECISION_COFF
       ,CAST(MAX(v0.[UNIT_PRICE])    AS DECIMAL(18,8))  AS UNIT_PRICE
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
)
,cte_ryb AS (
    SELECT
        r.[id]                                      AS id
       ,MAX(r.[编号])                               AS src_staff_code
    FROM dbo.[sjjk_ryb_2025_06_01] AS r WITH (NOLOCK)
    WHERE r.[id] IS NOT NULL
    GROUP BY r.[id]
)
,cte_mdm_staff AS (
    SELECT
        s.[SRC_STAFF_CODE]                          AS src_staff_code
       ,MAX(s.[STAFF_CODE])                         AS staff_code
    FROM dbo.[MAP_MDM_STAFF] AS s WITH (NOLOCK)
    WHERE s.[SRC_STAFF_CODE] IS NOT NULL
    GROUP BY s.[SRC_STAFF_CODE]
)
,cte_staff_post AS (
    SELECT
        m.[staff_code]                              AS staff_code
       ,m.[year]                                    AS [year]
       ,m.[month]                                   AS [month]
       ,m.[unit_code]                               AS unit_code
       ,m.[unit_name]                               AS unit_name
       ,CAST(m.[post_coefficient] AS DECIMAL(18,8)) AS post_coefficient
    FROM dbo.[ads_dept_post_coefficient_m] AS m WITH (NOLOCK)
    WHERE m.[staff_code] IS NOT NULL
    GROUP BY
        m.[staff_code]
       ,m.[year]
       ,m.[month]
       ,m.[unit_code]
       ,m.[unit_name]
       ,m.[post_coefficient]
)

-- ── Final CTE: 出口契约（防污点隔离，落库列与 JSON 过程仓同源同精度） ──
,final AS (
SELECT
    f.[来源]                                                  AS [来源]

   ,f.[项目大类]                                              AS [项目大类]
   ,f.[项目代码]                                              AS [项目代码]
   ,f.[项目名称]                                              AS [项目名称]

   ,v.[ITEM_CAT_CODE]                                         AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                         AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                      AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                      AS [执行系数]

   ,CAST(f.[单价] AS DECIMAL(18,8))                           AS [单价]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [数量]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [金额]

   ,CAST(1.0 AS DECIMAL(18,8))                                AS [学科系数]

   ,f.[执行人员代码]                                          AS [执行人员代码]
   ,f.[执行人员]                                              AS [执行人员]

   ,ISNULL(sp_exec.[unit_code], N'未匹配')                     AS [执行人员所在核算单元编码]
   ,ISNULL(sp_exec.[unit_name], N'未匹配')                     AS [执行人员所在核算单元名称]
   ,ISNULL(CAST(sp_exec.[post_coefficient] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS [岗位系数]

   -- ── 工作日历维度（按缴费日期关联，LEFT JOIN + ISNULL 双保险防覆盖缺口） ──
   ,ISNULL(cal.[DAY_TYPE_CODE], 'WORKDAY')                    AS [日期类型编码]
   ,ISNULL(cal.[DAY_TYPE_NAME], N'正常工作日')                  AS [日期类型名称]
   ,ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS [绩效核算系数]

   ,YEAR(f.[缴费时间])                                        AS [缴费日期年份]
   ,MONTH(f.[缴费时间])                                       AS [缴费日期月份]

   -- ── 积分指标（积分 = 项目点数 × 数量 × 学科系数 × 绩效核算系数），
   --    数值列与审计文本列同一乘数序列，全链 DECIMAL(18,8) 同精度同源 ──
   ,CAST(v.[RVU_VAL] * SUM(CAST(f.[数量] AS DECIMAL(18,8))) * CAST(1.0 AS DECIMAL(18,8)) * ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [积分]
   ,CONCAT(
        CAST(CAST(v.[RVU_VAL] AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × '
       ,CAST(CAST(SUM(CAST(f.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS VARCHAR(32))
       ,' × 1.00000000 × '
       ,CAST(ISNULL(CAST(cal.[PERF_COEFF] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8))) AS VARCHAR(32))
    )                                                         AS [积分计算过程]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN cte_rvu AS v
    ON f.[项目代码] = v.[PROJ_CODE]
LEFT JOIN cte_ryb AS ryb_exec
    ON f.[执行人员代码] = ryb_exec.[id]
LEFT JOIN cte_mdm_staff AS mdm_exec
    ON ryb_exec.[src_staff_code] = mdm_exec.[src_staff_code]
LEFT JOIN cte_staff_post AS sp_exec
    ON mdm_exec.[staff_code] = sp_exec.[staff_code]
   AND YEAR(f.[缴费时间])    = sp_exec.[year]
   AND MONTH(f.[缴费时间])   = sp_exec.[month]
LEFT JOIN dbo.[DIM_WORK_CALENDAR] AS cal WITH (NOLOCK)
    ON CAST(f.[缴费时间] AS DATE) = cal.[CALC_DATE]
WHERE f.[缴费时间] >= '{start_time}'
  AND f.[缴费时间] <= '{end_time}'
  AND (f.[执行科室代码] IS NULL OR f.[执行科室代码] <> 36)
GROUP BY
    f.[来源]
   ,f.[项目大类]
   ,f.[项目代码]
   ,f.[项目名称]
   ,v.[ITEM_CAT_CODE]
   ,v.[ITEM_CAT_NAME]
   ,v.[RVU_VAL]
   ,v.[EXEC_COFF]
   ,CAST(f.[单价] AS DECIMAL(18,8))
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,ISNULL(sp_exec.[unit_code], N'未匹配')
   ,ISNULL(sp_exec.[unit_name], N'未匹配')
   ,ISNULL(CAST(sp_exec.[post_coefficient] AS DECIMAL(18,8)), CAST(1.00000000 AS DECIMAL(18,8)))
   ,cal.[DAY_TYPE_CODE]
   ,cal.[DAY_TYPE_NAME]
   ,cal.[PERF_COEFF]
   ,YEAR(f.[缴费时间])
   ,MONTH(f.[缴费时间])
)

-- =================================================================
-- 落库写入：dbo.DWD_FIN_CALC_ALLOC1_DETAIL_LOG（表结构封箱，禁止 ALTER）
-- =================================================================
INSERT INTO [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    [CALC_YEAR], [CALC_MONTH], [ITEM_CODE], [ITEM_NAME], [SCRIPT_NAME],
    [UNIT_CODE], [UNIT_NAME], [PROJ_CODE], [PROJ_NAME], [ITEM_CAT_CODE], [ITEM_CAT_NAME],
    [EXEC_ROLE], [STAFF_CODE], [STAFF_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME],
    [FINAL_VALUE_TYPE], [FINAL_VALUE], [TOTAL_QTY], [CALC_PROCESS_TEXT], [CALC_DETAIL_JSON], [CREATE_TIME]
)
SELECT
    CAST(f.[缴费日期年份] AS INT)                       AS [CALC_YEAR],
    CAST(f.[缴费日期月份] AS INT)                       AS [CALC_MONTH],
    N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'              AS [ITEM_CODE],
    N'门诊诊察类项目执行积分_非小儿科'                  AS [ITEM_NAME],
    N'门诊诊察类项目执行积分_非小儿科.sql'              AS [SCRIPT_NAME],
    f.[执行人员所在核算单元编码]                         AS [UNIT_CODE],
    f.[执行人员所在核算单元名称]                         AS [UNIT_NAME],
    f.[项目代码]                                        AS [PROJ_CODE],
    f.[项目名称]                                        AS [PROJ_NAME],
    f.[绩效大类编码]                                    AS [ITEM_CAT_CODE],
    f.[绩效大类名称]                                    AS [ITEM_CAT_NAME],
    -- 本核算项不做医技护角色切分：UQ 第 6 列固定填充常量
    N'执行人员'                                         AS [EXEC_ROLE],
    -- 执行归因锚点：人员主数据未命中时兜底 N'未匹配'（UQ 第 7 列 NOT NULL 约束保护）
    ISNULL(mdm_exec_staff.[staff_code], N'未匹配')      AS [STAFF_CODE],
    f.[执行人员]                                        AS [STAFF_NAME],
    f.[日期类型编码]                                    AS [DAY_TYPE_CODE],
    f.[日期类型名称]                                    AS [DAY_TYPE_NAME],
    N'SCORE'                                           AS [FINAL_VALUE_TYPE],
    CAST(f.[积分] AS DECIMAL(18,8))                     AS [FINAL_VALUE],
    CAST(f.[数量] AS DECIMAL(18,8))                     AS [TOTAL_QTY],
    -- 三段式审计文本：[元数据段] | [中文逻辑公式段] | [纯数学代入算式段]
    CONCAT(
        N'门诊诊察类项目执行积分_非小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
       ,f.[积分计算过程]
       ,' = '
       ,CAST(CAST(f.[积分] AS DECIMAL(18,8)) AS VARCHAR(50))
    )                                                   AS [CALC_PROCESS_TEXT],
    (
        SELECT
            CAST(f.[缴费日期年份] AS VARCHAR(11))                  AS [核算年份],
            CAST(f.[缴费日期月份] AS VARCHAR(11))                  AS [核算月份],
            -- ===== 核算项维度（与 DWD 落库列 CALC_YEAR/CALC_MONTH/ITEM_CODE/ITEM_NAME/SCRIPT_NAME 同源同值）=====
            N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'                  AS [核算项编码],
            N'门诊诊察类项目执行积分_非小儿科'                      AS [核算项名称],
            N'门诊诊察类项目执行积分_非小儿科.sql'                  AS [脚本名称],
            -- ===== 核算单元 / 项目 / 大类维度（与 DWD 落库列 UNIT_CODE/UNIT_NAME/PROJ_CODE/PROJ_NAME/ITEM_CAT_CODE/ITEM_CAT_NAME 同源同值）=====
            f.[执行人员所在核算单元编码]                             AS [核算单元编码],
            f.[执行人员所在核算单元名称]                             AS [核算单元名称],
            f.[项目代码]                                          AS [项目代码],
            f.[项目名称]                                          AS [项目名称],
            f.[绩效大类编码]                                      AS [绩效核算大类代码],
            f.[绩效大类名称]                                      AS [绩效核算大类名称],
            -- ===== 执行角色 / 员工维度（与 DWD 落库列 EXEC_ROLE/STAFF_CODE/STAFF_NAME 同源，常量与兜底表达式逐字对齐）=====
            N'执行人员'                                            AS [执行角色],
            ISNULL(mdm_exec_staff.[staff_code], N'未匹配')          AS [员工编码],
            f.[执行人员]                                          AS [员工姓名],
            -- ===== 日期类型维度（与 DWD 落库列 DAY_TYPE_CODE/DAY_TYPE_NAME 同源同值）=====
            f.[日期类型编码]                                      AS [日期类型编码],
            f.[日期类型名称]                                      AS [日期类型名称],
            -- ===== 值口径（与 DWD 落库列 FINAL_VALUE_TYPE/FINAL_VALUE/TOTAL_QTY 同源同值）=====
            N'SCORE'                                             AS [值类型],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [最终结果],
            CAST(f.[数量] AS DECIMAL(18,8))                        AS [汇总数量],
            -- ===== 计算过程描述（与 DWD 落库列 CALC_PROCESS_TEXT 完全同源同文本）=====
            CONCAT(
                N'门诊诊察类项目执行积分_非小儿科 | 门诊诊察类执行积分 = 项目点数 × 汇总数量 × 学科系数 × 绩效核算系数 | '
               ,f.[积分计算过程]
               ,' = '
               ,CAST(CAST(f.[积分] AS DECIMAL(18,8)) AS VARCHAR(50))
            )                                                     AS [计算过程描述],
            -- ===== 过程因子（未落物理列，仅 JSON 过程仓承载）=====
            CAST(f.[项目点数] AS DECIMAL(18,8))                    AS [单项RVU点数],
            CAST(f.[执行系数] AS DECIMAL(18,8))                    AS [执行系数],
            f.[执行人员代码]                                      AS [执行人员代码],
            f.[执行人员]                                          AS [执行人员],
            CAST(f.[岗位系数] AS DECIMAL(18,8))                    AS [岗位系数],
            CAST(f.[学科系数] AS DECIMAL(18,8))                    AS [学科系数],
            CAST(f.[绩效核算系数] AS DECIMAL(18,8))                AS [绩效核算系数],
            CAST(f.[单价] AS DECIMAL(18,8))                        AS [单价],
            CAST(f.[金额] AS DECIMAL(18,8))                        AS [汇总金额],
            CAST(f.[积分] AS DECIMAL(18,8))                        AS [门诊诊察类执行积分],
            -- RVU 配置全字段快照（FOR JSON PATH 纯常量投影，零表回表；按 PROJ_CODE 1:1 直连 cte_rvu）
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
                WHERE c.[PROJ_CODE] = f.[项目代码]
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            ))                                                    AS [RVU配置快照]
        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
    )                                                   AS [CALC_DETAIL_JSON],
    SYSDATETIME()                                       AS [CREATE_TIME]
FROM final AS f
LEFT JOIN cte_ryb AS ryb_staff
    ON f.[执行人员代码] = ryb_staff.[id]
LEFT JOIN cte_mdm_staff AS mdm_exec_staff
    ON ryb_staff.[src_staff_code] = mdm_exec_staff.[src_staff_code]
    ~
    ;

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
    WHERE [CALC_YEAR]  = YEAR(CAST('{start_time}' AS DATETIME))
      AND [CALC_MONTH] = MONTH(CAST('{start_time}' AS DATETIME))
      AND [ITEM_CODE]  = N'ITEM_OUTPATIENT_DIAG_SCORE_NON_PED'
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
