-- =============================================================================
-- 报表：专项激励配置表
-- 数据源：dbo.dim_prf_special_incentive（12 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [org_code], [org_name], [item_code], [item_name], [effective_date], [expire_date], [incentive_money], [remark], [create_user], [create_time], [update_user], [update_time] FROM [dbo].[dim_prf_special_incentive] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [org_code] AS [机构编码],
       [org_name] AS [机构名称],
       [item_code] AS [项目编码],
       [item_name] AS [项目名称],
       [effective_date] AS [生效日期],
       [expire_date] AS [失效日期],
       [incentive_money] AS [专项激励金额],
       [remark] AS [备注],
       [create_user] AS [创建人],
       [create_time] AS [创建时间],
       [update_user] AS [最后修改人],
       [update_time] AS [最后修改时间]
   FROM [dbo].[dim_prf_special_incentive];
   ============================================================================= */
