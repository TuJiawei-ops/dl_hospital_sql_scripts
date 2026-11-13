-- =============================================================================
-- 报表：核算单元
-- 数据源：dbo.T_DEPARTMENT（32 列，列序与脚本列契约严格对齐）
-- 对应脚本：export_performance_data.py（ExportTask.build_sql 路径 B：显式列清单 + WITH (NOLOCK)）
-- 说明：表头在脚本端由 Python 映射为中文；本文件保持与脚本 SQL 文本一致（物理列名）。
--       文件末尾附“中文别名版”（默认注释），供导出中心直接得到中文表头。
-- 生成时间：2026-11-13（由脚本列契约 1:1 生成，勿手改列序）
-- =============================================================================
SELECT [ID], [NAME], [CODE], [ABBREVIATION], [PERSON_LIABLE], [COST_CENTRE], [IS_FICTITIOU], [PINYIN_CODE], [TYPE_ID], [P_ID], [COMPANY_ID], [IS_GK_DEPT], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [DEPTTYPE], [CREATEDATE], [OWN_ALL_PRODUCT], [IS_FUNCTIONAL_DEPT], [IS_NURSING_UNIT], [sfhsdy], [TYPE_NAME], [children_ids], [temp], [director_ids], [deputy_director_ids], [is_clinical_dept], [series_code], [series_name] FROM [dbo].[T_DEPARTMENT] WITH (NOLOCK);

/* =============================================================================
   中文别名版（供导出中心使用，表头即中文；列序与上面完全一致）

   SELECT
       [ID] AS [主键ID],
       [NAME] AS [部门名称],
       [CODE] AS [部门编码],
       [ABBREVIATION] AS [部门简称],
       [PERSON_LIABLE] AS [责任人ids],
       [COST_CENTRE] AS [成本中心],
       [IS_FICTITIOU] AS [是否虚拟部门],
       [PINYIN_CODE] AS [拼音编码],
       [TYPE_ID] AS [部门类型],
       [P_ID] AS [上级部门],
       [COMPANY_ID] AS [关联公司],
       [IS_GK_DEPT] AS [是否归口科室],
       [STATUS] AS [状态 1.启用 0.禁用],
       [CREATE_USER] AS [创建者],
       [CREATE_TIME] AS [创建时间],
       [MODIFY_USER] AS [修改者],
       [MODIFY_TIME] AS [修改时间],
       [DELETE_FLAG] AS [删除标识(0:未删除,1:已删除)],
       [DEPTTYPE] AS [部门类型(医院 0 行政后勤1 医疗技术 2 临床服务3 医疗辅助4 乡村卫生院 5)],
       [CREATEDATE] AS [部门成立时间],
       [OWN_ALL_PRODUCT] AS [OWN_ALL_PRODUCT],
       [IS_FUNCTIONAL_DEPT] AS [是否为职能科室],
       [IS_NURSING_UNIT] AS [是否为护理单元],
       [sfhsdy] AS [是否核算单元],
       [TYPE_NAME] AS [部门类型名称],
       [children_ids] AS [下级科室id],
       [temp] AS [是否缓存科室 0-是 1-否],
       [director_ids] AS [科室主任],
       [deputy_director_ids] AS [科室副主任],
       [is_clinical_dept] AS [是否临床科室0否1是],
       [series_code] AS [所属职系编码],
       [series_name] AS [所属职系名称]
   FROM [dbo].[T_DEPARTMENT];
   ============================================================================= */
