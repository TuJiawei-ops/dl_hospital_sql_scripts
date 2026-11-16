/* ===============================================================================
  报表名称: 业务科室月度绩效新旧方案对比
  业务说明: 以「业务科室」为口径，对比
              · 老方案：ads_dept_monthly_performance_m（线下核定发放，科室维度）
              · 新方案：DWD_FIN_CALC_ALLOC1_DETAIL_LOG 中
                        ITEM_CODE = 'ITEM_ALLOC1_FINAL_PERF_AMOUNT'（一次分配最终绩效金额）
                        按核算单元记录 → 经 dim_unit_dept_relation 汇总到业务科室。
  口径说明: ① 新方案是「核算单元 × 项目」行，先按 UNIT_CODE 汇总金额，再按关系表折算到科室；
            ② 关系表取当前有效记录（valid_to = 9999-12-31）；
            ③ 老方案只有科室总额，无法拆到核算单元，故不能做核算单元维度对比；
            ④ 以科室名称做全外连接，两侧任一侧缺失都会列出，便于发现口径/编码不一致。
  使用方式: 修改 @year / @month 后执行（只读）。
  生成日期: 2026-11-16
=============================================================================== */
DECLARE @year  INT = 2026;
DECLARE @month INT = 10;

WITH new_unit AS (
    SELECT
        l.UNIT_CODE,
        l.UNIT_NAME,
        CAST(SUM(CAST(l.FINAL_VALUE AS DECIMAL(18, 2))) AS DECIMAL(18, 2)) AS AMOUNT
    FROM dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] AS l WITH (NOLOCK)
    WHERE l.CALC_YEAR = @year
      AND l.CALC_MONTH = @month
      AND l.ITEM_CODE = N'ITEM_ALLOC1_FINAL_PERF_AMOUNT'
    GROUP BY l.UNIT_CODE, l.UNIT_NAME
),
new_dept AS (
    SELECT
        r.dept_code,
        r.dept_name,
        COUNT(DISTINCT u.UNIT_CODE)                                         AS UNIT_CNT,
        CAST(SUM(u.AMOUNT) AS DECIMAL(18, 2))                                AS NEW_AMOUNT
    FROM new_unit AS u
    INNER JOIN dbo.[dim_unit_dept_relation] AS r WITH (NOLOCK)
        ON r.unit_code = u.UNIT_CODE
       AND r.valid_to = '9999-12-31'
    GROUP BY r.dept_code, r.dept_name
),
new_unmapped AS (
    SELECT
        u.UNIT_CODE,
        u.UNIT_NAME,
        u.AMOUNT
    FROM new_unit AS u
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.[dim_unit_dept_relation] AS r WITH (NOLOCK)
        WHERE r.unit_code = u.UNIT_CODE AND r.valid_to = '9999-12-31'
    )
),
old_dept AS (
    SELECT
        o.dept_code,
        o.dept_name,
        o.total_performance                                             AS OLD_AMOUNT,
        o.staff_count                                                   AS OLD_STAFF
    FROM dbo.[ads_dept_monthly_performance_m] AS o WITH (NOLOCK)
    WHERE o.[year] = @year AND o.[month] = @month
)
SELECT
    CAST(@year AS VARCHAR(10))                                          AS [核算年份]
   ,CAST(@month AS VARCHAR(10))                                         AS [核算月份]
   ,ISNULL(n.dept_name, o.dept_name)                                    AS [业务科室]
   ,o.dept_name                                                         AS [老方案科室名称]
   ,n.dept_name                                                         AS [新方案科室名称]
   ,o.dept_code                                                         AS [老方案科室编码]
   ,n.dept_code                                                         AS [新方案科室编码]
   ,o.OLD_AMOUNT                                                        AS [老方案绩效金额]
   ,n.NEW_AMOUNT                                                        AS [新方案绩效金额]
   ,CAST(ISNULL(n.NEW_AMOUNT, 0) - ISNULL(o.OLD_AMOUNT, 0) AS DECIMAL(18, 2)) AS [差额（新-老）]
   ,CAST(
        CASE WHEN ISNULL(o.OLD_AMOUNT, 0) = 0 THEN NULL
             ELSE 100.0 * (ISNULL(n.NEW_AMOUNT, 0) - o.OLD_AMOUNT) / o.OLD_AMOUNT
        END AS DECIMAL(18, 2))                                          AS [变动率%]
   ,n.UNIT_CNT                                                          AS [新方案涉及核算单元数]
   ,o.OLD_STAFF                                                         AS [老方案人数]
   ,CASE WHEN o.dept_name IS NULL THEN N'仅新方案'
         WHEN n.dept_name IS NULL THEN N'仅老方案'
         ELSE N'两侧均有' END                                            AS [匹配情况]
FROM new_dept AS n
FULL OUTER JOIN old_dept AS o
    ON o.dept_code = n.dept_code
UNION ALL
SELECT
    CAST(@year AS VARCHAR(10))
   ,CAST(@month AS VARCHAR(10))
   ,N'【未映射到业务科室】'
   ,NULL
   ,NULL
   ,NULL
   ,u.UNIT_CODE
   ,NULL
   ,CAST(u.AMOUNT AS DECIMAL(18, 2))
   ,CAST(u.AMOUNT AS DECIMAL(18, 2))
   ,NULL
   ,1
   ,NULL
   ,N'新方案-单元未挂科室'
FROM new_unmapped AS u
ORDER BY [匹配情况], [差额（新-老）] DESC;