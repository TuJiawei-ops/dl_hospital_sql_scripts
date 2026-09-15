/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分_非小儿科.sql
  脚本名称: 门诊诊察类项目执行积分_非小儿科.sql
  业务说明: 门诊诊察类项目（1043）按日汇总执行数据。
            依据开单科室代码 (36) 进行源头硬隔离（排除 36，NULL 安全），供下游按执行核算单元汇总消费。
            投影粒度已剥离开单环节（科室/人员/日期 7 维）与对应映射链路，仅保留执行环节维度。
  学科系数: 恒定 1.0（源头已隔离，投影层常量化）

  ── 硬约束（禁止回退） ──
  开单科室判定仅允许使用唯一主键编码 [开单科室代码]，严禁引入 [开单科室] 中文名称比较
  （如 <> N'小儿科'）。名称属前端/HIS 可维护文案，一旦改名即静默失效且不报错。

  修改日志：
  2026-09-15 17:50:00 | 维度剪枝 | 剥离开单环节 7 维投影与分组（开单科室代码/开单科室/开单绩效核算单元编码/
                                 名称/开单人员代码/开单人/开单日期），同步移除 bmb_open+map_open 映射链路，
                                 聚合粒度收敛至纯执行清单维度；cte_rvu/cte_bmb/cte_dept_map 定义零改动，
                                 WHERE 仍以基表列 f.[开单科室代码] 硬隔离，GROUP BY 零常量。
  2026-09-15 17:20:00 | 语法修复 | 剔除 GROUP BY 子句中的纯常量表达式 CAST(1.0 AS DECIMAL(18,8))
                                 （触发 42000/164 每个 GROUP BY 表达式必须至少包含一个不是外部引用的列）；
                                 SELECT 投影层常量定义原样保留，CTE/关联/精度零变动。
  2026-09-15 17:00:00 | 编码唯一性审计 | 全文件复核确认 SQL 区零 N'小儿科' 文本判定（WHERE 仅
                                   f.[开单科室代码] IS NULL OR <> 36），头部追加硬约束条款锁定该口径防回退。
  2026-09-15 16:40:00 | 语法修复与精简 | 清除文件尾部遗留的孤立 WITH cte_rvu AS ( 语法碎片，确保单语句严格闭合；
                                  头部 17 条规范说明压缩为极简说明块；开单科室判定废除中文名称匹配，
                                  收敛为仅编码 [开单科室代码] <> 36（NULL 安全）。
  2026-09-15 16:20:00 | 脚本拆分 | 由 门诊诊察类项目执行积分.sql 派生【非小儿科分支】独立脚本，
                                 [学科系数] 简化为 CAST(1.0 AS DECIMAL(18,8)) 常量。
=============================================================================== */


WITH cte_rvu AS (
    -- ── 维表作用域：编码硬匹配 1043 + 按 PROJ_CODE 聚合归一，消除多版本一对多放大风险 ──
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,MAX(v0.[ITEM_CAT_CODE])                     AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])                     AS ITEM_CAT_NAME
       ,CAST(MAX(v0.[RVU_VAL])   AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF]) AS DECIMAL(18,8))  AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
)
,cte_bmb AS (
    -- ── 桥接层：事实层数值主键 id → HIS 业务编码（原值直连，零格式化加工） ──
    SELECT
        b.[id]                                      AS id
       ,MAX(b.[编码])                               AS dept_code
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    WHERE b.[id] IS NOT NULL
    GROUP BY b.[id]
)
,cte_dept_map AS (
    -- ── 映射层：HIS 部门编码 → 绩效核算单元（'1001' 前置硬剪枝 + 编码分组收敛） ──
    SELECT
        m.[HIS_DEPT_CODE]                           AS HIS_DEPT_CODE
       ,MAX(m.[HPS_DEPT_CODE])                      AS HPS_DEPT_CODE
       ,MAX(m.[HPS_DEPT_NAME])                      AS HPS_DEPT_NAME
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] = '1001'
      AND m.[HIS_DEPT_CODE] IS NOT NULL
    GROUP BY m.[HIS_DEPT_CODE]
)
SELECT
    -- ── 来源标识 ──
    f.[来源]                                                  AS [来源]

    -- ── 项目基础信息（事实层口径） ──
   ,f.[项目大类]                                              AS [项目大类]
   ,f.[项目代码]                                              AS [项目代码]
   ,f.[项目名称]                                              AS [项目名称]

    -- ── 绩效属性（维表层：大类归属 / 点数 / 执行系数） ──
   ,v.[ITEM_CAT_CODE]                                         AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                         AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                      AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                      AS [执行系数]

    -- ── 收费计量（尺度：单价为维度，数量/金额为度量） ──
   ,CAST(f.[单价] AS DECIMAL(18,8))                           AS [单价]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [数量]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [金额]

    -- ── 绩效调整因子（学科系数：源头已隔离为非小儿科，退化为常量 1.0） ──
   ,CAST(1.0 AS DECIMAL(18,8))                                AS [学科系数]

    -- ── 执行环节（门诊诊察类绩效归属的核心维度；id → 编码 → 绩效核算单元） ──
   ,f.[执行科室代码]                                          AS [执行科室代码]
   ,f.[执行科室]                                              AS [执行科室]
   ,map_exec.[HPS_DEPT_CODE]                                  AS [执行绩效核算单元编码]
   ,map_exec.[HPS_DEPT_NAME]                                  AS [执行绩效核算单元名称]
   ,f.[执行人员代码]                                          AS [执行人员代码]
   ,f.[执行人员]                                              AS [执行人员]
   ,CAST(f.[执行时间] AS DATE)                                 AS [执行日期]

    -- ── 结算环节（时间为按日截断） ──
   ,CAST(f.[缴费时间] AS DATE)                                 AS [缴费日期]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN cte_rvu AS v
    ON f.[项目代码] = v.[PROJ_CODE]
-- 执行科室链路：id → 部门编码 → 绩效核算单元（全程 LEFT JOIN，未配置映射不收缩事实行）
LEFT JOIN cte_bmb AS bmb_exec
    ON f.[执行科室代码] = bmb_exec.[id]
LEFT JOIN cte_dept_map AS map_exec
    ON bmb_exec.[dept_code] = map_exec.[HIS_DEPT_CODE]
-- 源头物理隔离：仅以主键编码剔除开单科室 36（NULL 安全，与姊妹脚本严格互补）
WHERE f.[开单科室代码] IS NULL
   OR f.[开单科室代码] <> 36
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
   ,f.[执行科室代码]
   ,f.[执行科室]
   ,map_exec.[HPS_DEPT_CODE]
   ,map_exec.[HPS_DEPT_NAME]
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,CAST(f.[执行时间] AS DATE)
   ,CAST(f.[缴费时间] AS DATE)
;
