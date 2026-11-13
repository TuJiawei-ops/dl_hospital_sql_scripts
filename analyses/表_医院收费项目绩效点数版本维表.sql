-- =============================================================================
-- 报表：医院收费项目绩效点数版本维表
-- 数据源：dbo.DIM_PRF_ITEM_RVU_VERSION（29 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [VERSION_NO], [VERSION_DESC], [ORG_CODE], [ORG_NAME], [SRC_SYS_CODE], [PROJ_CODE], [PROJ_NAME], [MEAS_UNIT], [RVU_VAL], [ITEM_CAT_CODE], [ITEM_CAT_NAME], [UNIT_PRICE], [OPR_LEVEL_CODE], [OPR_LEVEL_NAME], [CREATE_USER], [CREATE_TIME], [UPDATE_USER], [UPDATE_TIME], [ID], [DECISION_COFF], [EXEC_COFF], [REMARK], [SCORE_REASON], [CLINIC_ORDER_RVU_VAL], [CLINIC_EXEC_RVU_VAL], [TECH_ORDER_RVU_VAL], [TECH_EXEC_RVU_VAL], [NURSE_ORDER_RVU_VAL], [NURSE_EXEC_RVU_VAL] FROM [dbo].[DIM_PRF_ITEM_RVU_VERSION] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [VERSION_NO] AS [版本号],
       [VERSION_DESC] AS [版本方案业务中文描述],
       [ORG_CODE] AS [机构编码],
       [ORG_NAME] AS [机构名称],
       [SRC_SYS_CODE] AS [源系统编码],
       [PROJ_CODE] AS [收费项目编码],
       [PROJ_NAME] AS [收费项目名称],
       [MEAS_UNIT] AS [原始计费单位],
       [RVU_VAL] AS [单项绩效点数],
       [ITEM_CAT_CODE] AS [绩效标准核算分类编码],
       [ITEM_CAT_NAME] AS [绩效标准核算分类名称],
       [UNIT_PRICE] AS [历史参考单价],
       [OPR_LEVEL_CODE] AS [手术等级编码],
       [OPR_LEVEL_NAME] AS [手术等级名称],
       [CREATE_USER] AS [初始化创建人],
       [CREATE_TIME] AS [初始化创建时间],
       [UPDATE_USER] AS [最后修改人],
       [UPDATE_TIME] AS [最后修改时间戳],
       [ID] AS [冗余ID],
       [DECISION_COFF] AS [诊疗决策系数],
       [EXEC_COFF] AS [执行系数],
       [REMARK] AS [备注说明],
       [SCORE_REASON] AS [评分理由依据],
       [CLINIC_ORDER_RVU_VAL] AS [临床开单绩效点数],
       [CLINIC_EXEC_RVU_VAL] AS [临床执行绩效点数],
       [TECH_ORDER_RVU_VAL] AS [医技开单绩效点数],
       [TECH_EXEC_RVU_VAL] AS [医技执行绩效点数],
       [NURSE_ORDER_RVU_VAL] AS [护理开单绩效点数],
       [NURSE_EXEC_RVU_VAL] AS [护理执行绩效点数]
   FROM [dbo].[DIM_PRF_ITEM_RVU_VERSION];
   ============================================================================= */
