/* ===============================================================================
  Relative Path : analyses/核算单元月度绩效测算与实际发放对比表.sql
  脚本名称: 核算单元月度绩效测算与实际发放对比表.sql
  业务说明: 面向业务人员的「核算单元月度绩效测算 vs 实际发放」对比透视报表。
            按【核算年份 + 核算月份 + 核算单元】三维粒度，将测算口径与实际发放口径
            并排对齐，输出两口径总额、绝对差异金额与差异比例，供业务直接核对与导出。
  数据链路: dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] 测算侧事实（一次分配明细持久化 log）
            ──▶ SUM(FINAL_VALUE) 按 (CALC_YEAR, CALC_MONTH, UNIT_CODE) 预汇总
            dbo.[ads_emp_monthly_performance_m] 实际发放侧事实（员工月度绩效金额表）
            ──▶ SUM(performance_after_fixed_deduction) 按 (year, month, unit_code) 预汇总
            两路汇总经 FULL OUTER JOIN 拼接，捕捉「仅测算未发放」与「仅发放未测算」断层。
  只读声明: 纯 SELECT 分析报表，彻底剥离 Envelope Pattern（无 DELETE / INSERT / UPDATE /
            波浪号 ~ 区块 / DWD_* 写入逻辑），零 DDL 副作用、零 DML 副作用。
  查询提示: 全链路 WITH (NOLOCK)，只读核对不加锁，避免影响生产事实表写入。
  模板占位符: 无（本报表为全账期全量透视，不接受 '{year}' / '{month}' / {struct_codes} 注入）

  关键纠偏:
  1. 【阻断级·字段名纠偏】需求描述称实际发放侧账期列为 calc_year / calc_month，
     经核对物理 DDL（sqlserver/ADS_EMP_MONTHLY_PERFORMANCE_M.sql）确认该表账期列
     实际命名为 [year] / [month]（且为保留关键字，必须方括号转义），不存在 calc_ 前缀。
     若照抄 calc_year / calc_month 将触发 Invalid column name 运行时错误，
     故本脚本一律以物理列名 [year] / [month] 裸引用，严禁臆造列名。
  2. 【口径差异声明·业务必读】两侧金额口径非同源，差异率天然非零属预期现象，不是缺陷：
     · 测算侧 SUM(FINAL_VALUE)：覆盖一次分配全量核算项（积分 SCORE / 金额 AMOUNT /
       指数 INDEX 混合口径，含开单积分、执行积分、出入院积分、通知入院积分等），
       且 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 粒度含 ENUF 员工 / 项目 / 执行角色 / 日期类型
       多维展开，属「应发测算口径」。
     · 实际发放侧 SUM(performance_after_fixed_deduction)：「扣除固定部分后绩效」，
       属「实发口径」，已剔除固定部分并与二次分配落地金额对齐。
     本报表职责是「暴露差异」而非「消除差异」，严禁为凑平而对任一侧叠加系数或过滤。
  3. 【金额精度规范】两侧源列分别为 DECIMAL(18,8) 与 DECIMAL(18,2)，汇总前统一
     CAST 至 DECIMAL(18,8)（.clinerules §7 全局精度强制标准），杜绝低精度截断累积误差；
     差异比例以 DECIMAL(18,8) 计算并按百分比展示。注意：差异比例为除零敏感量，
     实际发放总额 = 0 时返回 NULL 而非 0 或报错，避免业务误读为「零差异」。
  4. 【零行丢失保障】FULL OUTER JOIN 双向兜底，仅测算未发放 / 仅发放未测算的核算单元
     均完整保留；编码与名称以 COALESCE(测算侧, 实际发放侧) 双源兜底补全。
  5. 【聚合隔离】两侧各自在独立 CTE 内完成预汇总，严禁将差异计算下推至聚合层内部，
     防止新增维度污染最外层分组粒度（.clinerules §3 隔离多余维度）。
  6. 【零视图策略】全程 CTE 逻辑隔离，不落地任何 VIEW 对象，规避视图嵌套对
     查询优化器并行执行计划的侵蚀。

  修改日志：
  2026-10-05 03:00:00 | 脚本新建 | 建立核算单元月度绩效测算与实际发放对比报表：
                                 测算侧以 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 按
                                 (CALC_YEAR, CALC_MONTH, UNIT_CODE) 预汇总 SUM(FINAL_VALUE)；
                                 实发侧以 ads_emp_monthly_performance_m 按
                                 ([year], [month], [unit_code]) 预汇总 SUM(performance_after_fixed_deduction)；
                                 双侧 FULL OUTER JOIN 拼接并 COALESCE 兜底编码/名称；
                                 输出测算绩效总额、实际发放总额、绝对差异金额、差异比例；
                                 纠偏需求文档中 calc_year / calc_month 臆造列名为物理 [year] / [month]；
                                 全链路 NOLOCK 只读，零 GO、零视图、零 DML/DDL 副作用。
================================================================================ */

WITH cte_calc_summary AS (
    -- ── Logical CTE: 测算侧预汇总（一次分配明细事实 → 核算单元月度粒度） ──
    -- 粒度收敛：(CALC_YEAR, CALC_MONTH, UNIT_CODE)
    -- 口径声明：SUM(FINAL_VALUE) 不区分 FINAL_VALUE_TYPE，覆盖 SCORE / AMOUNT / INDEX 混合值域，
    --           属「应发测算口径」，与实发侧不构成同源可比口径（详见头部关键纠偏第 2 条）。
    SELECT
        log.[CALC_YEAR]                                                  AS [CALC_YEAR]
       ,log.[CALC_MONTH]                                                 AS [CALC_MONTH]
       ,log.[UNIT_CODE]                                                  AS [UNIT_CODE]
       ,MAX(log.[UNIT_NAME])                                             AS [UNIT_NAME]
       ,CAST(SUM(ISNULL(log.[FINAL_VALUE], CAST(0 AS DECIMAL(18,8))))
                AS DECIMAL(18,8))                                        AS [CALC_TOTAL]
    FROM dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] AS log WITH (NOLOCK)
    GROUP BY
        log.[CALC_YEAR]
       ,log.[CALC_MONTH]
       ,log.[UNIT_CODE]
)
,cte_actual_summary AS (
    -- ── Logical CTE: 实发侧预汇总（员工月度绩效金额表 → 核算单元月度粒度） ──
    -- 粒度收敛：([year], [month], [unit_code])，跨员工维度折叠求和。
    -- 列名纠偏：[year] / [month] 为物理列真名（保留关键字，必须方括号转义），
    --           需求文档所述 calc_year / calc_month 在物理库中不存在。
    SELECT
        act.[year]                                                       AS [CALC_YEAR]
       ,act.[month]                                                      AS [CALC_MONTH]
       ,act.[unit_code]                                                  AS [UNIT_CODE]
       ,MAX(act.[unit_name])                                             AS [UNIT_NAME]
       ,CAST(SUM(ISNULL(act.[performance_after_fixed_deduction], CAST(0 AS DECIMAL(18,8))))
                AS DECIMAL(18,8))                                        AS [ACTUAL_TOTAL]
    FROM dbo.[ads_emp_monthly_performance_m] AS act WITH (NOLOCK)
    GROUP BY
        act.[year]
       ,act.[month]
       ,act.[unit_code]
)
,cte_joined AS (
    -- ── Logical CTE: 双口径全外连接，捕捉数据断层（仅测算 / 仅发放） ──
    -- 编码与名称以 COALESCE(测算侧, 实发侧) 双源兜底，确保任一侧缺失时报表无空洞。
    SELECT
        COALESCE(c.[CALC_YEAR],  a.[CALC_YEAR])                          AS [CALC_YEAR]
       ,COALESCE(c.[CALC_MONTH], a.[CALC_MONTH])                         AS [CALC_MONTH]
       ,COALESCE(c.[UNIT_CODE],  a.[UNIT_CODE])                          AS [UNIT_CODE]
       ,COALESCE(c.[UNIT_NAME],  a.[UNIT_NAME])                          AS [UNIT_NAME]
       ,ISNULL(c.[CALC_TOTAL],   CAST(0 AS DECIMAL(18,8)))               AS [CALC_TOTAL]
       ,ISNULL(a.[ACTUAL_TOTAL], CAST(0 AS DECIMAL(18,8)))               AS [ACTUAL_TOTAL]
    FROM cte_calc_summary   AS c
    FULL OUTER JOIN cte_actual_summary AS a
        ON  c.[CALC_YEAR]  = a.[CALC_YEAR]
        AND c.[CALC_MONTH] = a.[CALC_MONTH]
        AND c.[UNIT_CODE]  = a.[UNIT_CODE]
)
,final AS (
    -- ── Final CTE: 业务可读中文别名出口，差异指标在聚合层之上单点计算 ──
    SELECT
        CAST(j.[CALC_YEAR]  AS NVARCHAR(4))                              AS [核算年份]
       ,CAST(j.[CALC_MONTH] AS NVARCHAR(2))                              AS [核算月份]
       ,CAST(j.[UNIT_CODE]  AS NVARCHAR(100))                            AS [核算单元编码]
       ,ISNULL(CAST(j.[UNIT_NAME] AS NVARCHAR(200)), N'')                AS [核算单元名称]
       ,CAST(j.[CALC_TOTAL]   AS DECIMAL(18,8))                          AS [测算绩效总额]
       ,CAST(j.[ACTUAL_TOTAL] AS DECIMAL(18,8))                          AS [实际发放总额]
       -- 绝对差异金额 = 测算绩效总额 - 实际发放总额（正值 = 测算高于实发，负值 = 实发高于测算）
       ,CAST(j.[CALC_TOTAL] - j.[ACTUAL_TOTAL] AS DECIMAL(18,8))         AS [绝对差异金额]
       -- 差异比例 = (测算总额 - 实发总额) / 实发总额；实发为 0 时返回 NULL（除零保护，严禁返回 0）
       ,CAST(CASE
                 WHEN j.[ACTUAL_TOTAL] = CAST(0 AS DECIMAL(18,8)) THEN NULL
                 ELSE (j.[CALC_TOTAL] - j.[ACTUAL_TOTAL]) / j.[ACTUAL_TOTAL]
             END AS DECIMAL(18,8))                                       AS [差异比例_百分比]
    FROM cte_joined AS j
)
SELECT *
FROM final
ORDER BY
    [核算年份] DESC
   ,[核算月份] DESC
   ,[核算单元编码] ASC;

