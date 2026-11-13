-- =============================================================================
-- 报表：核算单元月度岗位系数与在岗状态明细表
-- 数据源：dbo.ads_dept_post_coefficient_m（16 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [year], [month], [unit_code], [unit_name], [staff_code], [staff_name], [staff_sequence], [series_code], [series_name], [post_code], [post_name], [post_coefficient], [on_duty_days], [is_transferred], [remark], [create_time] FROM [dbo].[ads_dept_post_coefficient_m] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [year] AS [核算年份],
       [month] AS [核算月份],
       [unit_code] AS [核算单元编码],
       [unit_name] AS [核算单元名称],
       [staff_code] AS [员工编码],
       [staff_name] AS [员工姓名],
       [staff_sequence] AS [员工序列],
       [series_code] AS [所属职系编码],
       [series_name] AS [所属职系名称],
       [post_code] AS [岗位物理编码],
       [post_name] AS [职务标签名称],
       [post_coefficient] AS [岗位系数],
       [on_duty_days] AS [月度实际在岗天数],
       [is_transferred] AS [是否转科标识],
       [remark] AS [备注],
       [create_time] AS [创建时间]
   FROM [dbo].[ads_dept_post_coefficient_m];
   ============================================================================= */
