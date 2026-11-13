/* ===============================================================================
  报表名称: 月度未配置医技护执行比例明细（月度版）
  业务说明: 按月排查 dbo.[PF临时医疗服务项目26A] 中「执行科室 × 项目」未在
            dbo.[DIM_DEPT_ITEM_EXEC_RATIO] 配置（IS_ENABLED = 1）的组合。
            这类组合在《医疗服务项目执行积分》里会因 LEFT JOIN 落空而使四条执行比例
            全部按 0 处理 → 该月这部分工作量**不计分**（漏算），本报表用于按月发现漏配。
  使用方式: 修改下方 @year / @month 两个变量为目标账期，直接执行即可（只读）。
  输出粒度: HIS科室 × 项目（含发生笔数、金额、金额占比），按金额倒序，优先补大头。
  只读声明: 纯 SELECT，无任何写操作；全链路 WITH (NOLOCK)。
  参数说明: @year 核算年（如 2026）；@month 核算月（1-12）。
            时间口径与计分脚本一致：按 [缴费时间] 落在该自然月内。
  生成日期: 2026-11-13
=============================================================================== */
DECLARE @year  INT = 2026;
DECLARE @month INT = 11;

DECLARE @start_time DATETIME = DATEFROMPARTS(@year, @month, 1);
DECLARE @end_time   DATETIME = DATEADD(MONTH, 1, @start_time);

WITH fact AS (
    SELECT
        b.[HIS_DEPT_CODE]                                   AS HIS_DEPT_CODE,
        src.[执行科室]                                       AS HIS_DEPT_NAME,
        src.[项目代码]                                       AS ITEM_CODE,
        src.[项目名称]                                       AS ITEM_NAME,
        src.[项目大类]                                       AS HIS_CAT_NAME,
        COUNT(1)                                            AS RECORD_COUNT,
        CAST(SUM(CAST(src.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS TOTAL_AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS src WITH (NOLOCK)
    INNER JOIN (
        SELECT b.[id] AS DEPT_ID, b.[编码] AS HIS_DEPT_CODE
        FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    ) AS b
        ON src.[执行科室代码] = b.[DEPT_ID]
    WHERE 1 = 1
      AND src.[缴费时间] >= @start_time
      AND src.[缴费时间] <  @end_time
      AND src.[执行科室代码] IS NOT NULL
      AND src.[项目代码] IS NOT NULL
      -- 非核算项目大类剔除（与全量版一致）
      AND (
          src.[项目大类] NOT IN (N'西药费', N'中草药费', N'中成药费', N'卫生材料费', N'卫生材料')
          OR src.[项目大类] IS NULL
      )
      -- 院外项目剔除
      AND NOT EXISTS (
          SELECT 1 FROM dbo.[DIM_OUT_HOSP_ITEM] AS o WITH (NOLOCK)
          WHERE o.[ITEM_CODE] = src.[项目代码]
      )
    GROUP BY
        b.[HIS_DEPT_CODE], src.[执行科室], src.[项目代码], src.[项目名称], src.[项目大类]
),
ratio AS (
    SELECT r.[HIS_DEPT_CODE], r.[ITEM_CODE]
    FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS r WITH (NOLOCK)
    WHERE r.[IS_ENABLED] = 1
),
miss AS (
    SELECT
        f.*,
        CAST(SUM(f.TOTAL_AMOUNT) OVER () AS DECIMAL(18,8))              AS ALL_AMOUNT,
        CAST(100.0 * f.TOTAL_AMOUNT / NULLIF(SUM(f.TOTAL_AMOUNT) OVER (), 0) AS DECIMAL(18,2)) AS AMOUNT_PCT
    FROM fact AS f
    LEFT JOIN ratio AS r
        ON r.[HIS_DEPT_CODE] = f.[HIS_DEPT_CODE]
       AND r.[ITEM_CODE]     = f.[ITEM_CODE]
    WHERE r.[HIS_DEPT_CODE] IS NULL
)
SELECT
    CAST(@year  AS VARCHAR(10))              AS [核算年份],
    CAST(@month AS VARCHAR(10))              AS [核算月份],
    m.[HIS_DEPT_CODE]                        AS [HIS科室编码],
    m.[HIS_DEPT_NAME]                        AS [HIS科室名称],
    m.[ITEM_CODE]                            AS [项目代码],
    m.[ITEM_NAME]                            AS [项目名称],
    m.[HIS_CAT_NAME]                         AS [HIS类别名称],
    m.[RECORD_COUNT]                         AS [发生笔数],
    m.[TOTAL_AMOUNT]                         AS [金额],
    m.[AMOUNT_PCT]                           AS [金额占比%],
    N'未配置执行比例'                          AS [缺口类型],
    N'该科室+项目在DIM_DEPT_ITEM_EXEC_RATIO中无生效配置，执行积分按0计' AS [说明]
FROM miss AS m
ORDER BY
    m.[TOTAL_AMOUNT] DESC,
    m.[HIS_DEPT_CODE] ASC,
    m.[ITEM_CODE] ASC;