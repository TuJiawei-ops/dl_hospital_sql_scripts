-- =============================================================================
-- 报表：绩效核算日历维度表
-- 数据源：dbo.DIM_WORK_CALENDAR（11 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [CALC_DATE], [WEEKDAY_CODE], [WEEKDAY_NAME], [DAY_TYPE_CODE], [DAY_TYPE_NAME], [IS_HOLIDAY], [HOLIDAY_NAME], [IS_MAKEUP_WORK], [PERF_COEFF], [REMARK], [CREATE_TIME] FROM [dbo].[DIM_WORK_CALENDAR] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [CALC_DATE] AS [日期],
       [WEEKDAY_CODE] AS [星期编码],
       [WEEKDAY_NAME] AS [星期名称],
       [DAY_TYPE_CODE] AS [日期类型编码],
       [DAY_TYPE_NAME] AS [日期类型名称],
       [IS_HOLIDAY] AS [是否法定节假日],
       [HOLIDAY_NAME] AS [节假日名称],
       [IS_MAKEUP_WORK] AS [是否调休补班],
       [PERF_COEFF] AS [绩效核算系数],
       [REMARK] AS [备注],
       [CREATE_TIME] AS [创建时间]
   FROM [dbo].[DIM_WORK_CALENDAR];
   ============================================================================= */
