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
            dbo.[T_DEPARTMENT]（经 CODE 收敛后左连）──▶ 补全 [所属职系编码] / [所属职系名称]

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
  7. 【阻断级·行倍增防御】补职系属性时若直接 LEFT JOIN dbo.[T_DEPARTMENT]，将因
     [CODE] 可空且无唯一约束（物理主键为 [ID]，唯一索引建在 [NAME] 上）而命中多行，
     静默放大结果行数并导致「测算绩效总额 / 实际发放总额」被虚假重复计列。
     故必须先以 ROW_NUMBER() OVER (PARTITION BY [CODE] ORDER BY [DELETE_FLAG] ASC,
     [ID] DESC) 显式收敛至 RANK = 1（cte_dept_rank → cte_dept），再与汇总结果集
     做 1:1 左连。严禁 MAX() 黑箱折叠（.clinerules §6 禁用滥用 MAX/MIN 聚合规则），
     排序键严禁包含 VERSION_NO（.clinerules §9 零版本寻址法则）。
     与 analyses/01_报表_一次分配明细业务视图.sql 的部门收敛策略保持全项目一致。
  8. 【零行丢失保障·职系侧】职系两列走 ISNULL(..., N'') 空串兜底而非 N'未分配职系'：
     本报表核算单元基数含大量非科室型单元，职系缺失属常态，空串可避免业务侧误读为
     「未分配职系」的待办事项；如需视觉区分可改为 N'未分配职系'。
  9. 【排序键扩展】ORDER BY 在原 (核算年份 DESC, 核算月份 DESC) 之后插入
     [所属职系编码] ASC，形成「先归口职系、再落核算单元」的业务透视层次。

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
  2026-10-05 17:20:00 | 字段扩展 | 补齐职系属性两列并调整输出列序：新增 cte_dept_rank / cte_dept
                                 两级部门维表收敛层（ROW_NUMBER 按 [CODE] 分组、[DELETE_FLAG] ASC +
                                 [ID] DESC 排序取 RANK=1），根治 T_DEPARTMENT.[CODE] 无唯一约束导致的
                                 LEFT JOIN 行倍增与金额虚假重复计列；final CTE 左连收敛后维表补
                                 [所属职系编码] / [所属职系名称]（插于核算单元两列之前，ISNULL 空串兜底）；
                                 ORDER BY 在账期键之后插入 [所属职系编码] ASC；
                                 双侧预汇总、FULL OUTER JOIN 与除零保护逻辑零改动；输出 10 列。
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
,cte_dept_rank AS (
    -- ── Logical CTE: 部门维表按 [CODE] 显式收敛，根治 1:N 行倍增（.clinerules §6） ──
    -- T_DEPARTMENT 物理主键为 [ID]，[CODE] 可空且无唯一约束（唯一索引建在 [NAME] 上），
    -- 一条 UNIT_CODE 可能命中多行部门记录；若直接 LEFT JOIN 将静默放大结果行数，
    -- 导致「测算绩效总额 / 实际发放总额」被虚假重复计列。故必须以 ROW_NUMBER 显式排序
    -- 收敛至 RANK = 1 后左连，严禁 MAX() 黑箱折叠（.clinerules §6 禁用滥用 MAX/MIN）。
    -- 排序优先级：[DELETE_FLAG] ASC（有效部门优先）→ [ID] DESC（确定性 tie-breaker）
    SELECT
        d.[CODE]                                                         AS [CODE]
       ,d.[series_code]                                                  AS [series_code]
       ,d.[series_name]                                                  AS [series_name]
       ,ROW_NUMBER() OVER (
            PARTITION BY d.[CODE]
            ORDER BY d.[DELETE_FLAG] ASC, d.[ID] DESC
        )                                                                AS [RN]
    FROM dbo.[T_DEPARTMENT] AS d WITH (NOLOCK)
    WHERE d.[CODE] IS NOT NULL
)
,cte_dept AS (
    -- ── Logical CTE: 仅保留每个 [CODE] 的唯一胜出行，确保与汇总结果集 1:1 关联 ──
    SELECT
        r.[CODE]                                                         AS [CODE]
       ,r.[series_code]                                                  AS [series_code]
       ,r.[series_name]                                                  AS [series_name]
    FROM cte_dept_rank AS r
    WHERE r.[RN] = 1
)
,final AS (
    -- ── Final CTE: 业务可读中文别名出口，左连收敛后部门维表补职系属性（1:1，零行倍增） ──
    SELECT
        CAST(j.[CALC_YEAR]  AS NVARCHAR(4))                              AS [核算年份]
       ,CAST(j.[CALC_MONTH] AS NVARCHAR(2))                              AS [核算月份]
       ,ISNULL(CAST(dept.[series_code] AS NVARCHAR(50)), N'')            AS [所属职系编码]
       ,ISNULL(CAST(dept.[series_name] AS NVARCHAR(100)), N'')           AS [所属职系名称]
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
    LEFT JOIN cte_dept AS dept
        ON j.[UNIT_CODE] = dept.[CODE]
)
SELECT *
FROM final
ORDER BY
    [核算年份] DESC
   ,[核算月份] DESC
   ,[所属职系编码] ASC
   ,[核算单元编码] ASC;

