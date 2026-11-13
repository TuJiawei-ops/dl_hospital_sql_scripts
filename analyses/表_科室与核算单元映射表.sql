-- =============================================================================
-- 报表：科室与核算单元映射表
-- 数据源：dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27（11 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [ID], [HIS_DEPT_CODE], [HIS_DEPT_NAME], [PERFORM_PERSON_TYPE], [HPS_DEPT_CODE], [HPS_DEPT_NAME], [START_DATE], [END_DATE], [REMARK], [create_time], [PERFORM_PERSON_TYPE_CODE] FROM [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [ID] AS [主键ID],
       [HIS_DEPT_CODE] AS [HIS科室编码],
       [HIS_DEPT_NAME] AS [HIS科室名称],
       [PERFORM_PERSON_TYPE] AS [执行人员类型名称],
       [HPS_DEPT_CODE] AS [HPS绩效科室编码],
       [HPS_DEPT_NAME] AS [HPS绩效科室名称],
       [START_DATE] AS [映射开始时间],
       [END_DATE] AS [映射结束时间],
       [REMARK] AS [备注],
       [create_time] AS [记录创建时间],
       [PERFORM_PERSON_TYPE_CODE] AS [执行人员类型编码]
   FROM [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27];
   ============================================================================= */
