-- =============================================================================
-- 报表：各科室收费项目医技护执行划分维表
-- 数据源：dbo.DIM_DEPT_ITEM_EXEC_RATIO（26 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [ID], [HIS_DEPT_CODE], [HIS_DEPT_NAME], [ITEM_CODE], [ITEM_NAME], [HIS_CAT_NAME], [DOC_EXEC_RATIO], [TECH_EXEC_RATIO], [NURSE_EXEC_RATIO], [CLINICAL_EXEC_RATIO], [DOC_HPS_DEPT_CODE], [DOC_HPS_DEPT_NAME], [TECH_HPS_DEPT_CODE], [TECH_HPS_DEPT_NAME], [NURSE_HPS_DEPT_CODE], [NURSE_HPS_DEPT_NAME], [CLINICAL_HPS_DEPT_CODE], [CLINICAL_HPS_DEPT_NAME], [PROVIDE_DATE], [ITEM_ADD_DATE], [DISABLE_DATE], [REMARK], [VERSION_NO], [IS_ENABLED], [CREATE_TIME], [UPDATE_TIME] FROM [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [ID] AS [自增代理主键],
       [HIS_DEPT_CODE] AS [HIS科室编码],
       [HIS_DEPT_NAME] AS [HIS科室名称],
       [ITEM_CODE] AS [收费项目编码],
       [ITEM_NAME] AS [收费项目名称],
       [HIS_CAT_NAME] AS [HIS类别名称],
       [DOC_EXEC_RATIO] AS [医生执行比例],
       [TECH_EXEC_RATIO] AS [技师执行比例],
       [NURSE_EXEC_RATIO] AS [护士执行比例],
       [CLINICAL_EXEC_RATIO] AS [临床执行比例],
       [DOC_HPS_DEPT_CODE] AS [医生对应核算单元编码],
       [DOC_HPS_DEPT_NAME] AS [医生对应核算单元名称],
       [TECH_HPS_DEPT_CODE] AS [技师对应核算单元编码],
       [TECH_HPS_DEPT_NAME] AS [技师对应核算单元名称],
       [NURSE_HPS_DEPT_CODE] AS [护士对应核算单元编码],
       [NURSE_HPS_DEPT_NAME] AS [护士对应核算单元名称],
       [CLINICAL_HPS_DEPT_CODE] AS [临床对应核算单元编码],
       [CLINICAL_HPS_DEPT_NAME] AS [临床对应核算单元名称],
       [PROVIDE_DATE] AS [提供日期],
       [ITEM_ADD_DATE] AS [项目新增日期],
       [DISABLE_DATE] AS [停用日期],
       [REMARK] AS [备注],
       [VERSION_NO] AS [版本号],
       [IS_ENABLED] AS [是否启用],
       [CREATE_TIME] AS [创建时间],
       [UPDATE_TIME] AS [更新时间]
   FROM [dbo].[DIM_DEPT_ITEM_EXEC_RATIO];
   ============================================================================= */
