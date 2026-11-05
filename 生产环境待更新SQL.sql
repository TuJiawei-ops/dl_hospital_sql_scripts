生产环境 待执行

/* ① 解决排序：页面 ORDER BY create_time DESC */
CREATE NONCLUSTERED INDEX IX_PF26A_create_time
    ON dbo.[PF临时医疗服务项目26A] (create_time DESC)
    WITH (MAXDOP = 4);

/* ② 解决按业务时间筛选 + 拉取前按窗口 DELETE
      列名请替换成第 0 步查到的真实列名，如 [开单时间] */
CREATE NONCLUSTERED INDEX IX_PF26A_kaidan_time
    ON dbo.[PF临时医疗服务项目26A] ([开单时间])
    WITH (MAXDOP = 4);



INSERT INTO [dbo].[data_connection] ([id], [source_id], [org_id], [status], [name], [code], [master], [port], [data_base], [username], [password], [data_driven], [data_view], [sign], [access_way], [creator_id], [createtime], [modifier_id], [modifytime], [deleted], [table_name], [table_name_clean], [value_type], [pull_status], [structural_name], [pull_time], [description], [sticky], [add_pk], [end_date], [is_scheduled], [cron_expression], [date_offset_type], [date_offset_value], [last_window_start], [last_window_end], [last_success_time]) VALUES (2115774905593442305, 123, 2688431883371515906, 1, N'各科室收费项目医技护临执行划分维表', N'DIM_DEPT_ITEM_EXEC_RATIO', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 2, 1688431883371515906, '2026-10-29 19:57:01.3310000', NULL, NULL, 0, 'DIM_DEPT_ITEM_EXEC_RATIO', NULL, 1, NULL, NULL, NULL, '-- 业务定义：各科室收费项目医技护临执行划分维表（HIS 科室 × 收费项目 → 医生/技师/护士/临床 执行比例切分）
', '1', '1', NULL, 0, NULL, NULL, NULL, NULL, NULL, NULL);



INSERT INTO [dbo].[data_import] ([id], [parent_id], [field_name], [field_type], [business_type], [creator_id], [createtime], [modifier_id], [modifytime], [deleted], [param_description], [field_query], [sort], [remark], [field_tip]) VALUES 
(400, 2115774905593442305, N'ID', N'bigint', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'ID', 0, 1, NULL, N'ID'),
(401, 2115774905593442305, N'HIS_DEPT_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'HIS科室编码', 1, 2, NULL, N'请输入或选择HIS系统中的科室编码（字符串语义，注意前导零）'),
(402, 2115774905593442305, N'HIS_DEPT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'HIS科室名称', 1, 3, NULL, N'请输入HIS科室名称进行检索'),
(403, 2115774905593442305, N'ITEM_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'收费项目编码', 1, 4, NULL, N'请输入收费项目编码（字符串语义，严禁丢前导零）'),
(404, 2115774905593442305, N'ITEM_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'收费项目名称', 1, 5, NULL, N'请输入收费项目名称'),
(405, 2115774905593442305, N'HIS_CAT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'HIS类别名称', 1, 6, NULL, N'请输入HIS医疗服务类别名称'),
(406, 2115774905593442305, N'DOC_EXEC_RATIO', N'decimal', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'医生执行比例', 0, 7, NULL, N'请输入医生角色的执行比例（范围 0~1，默认 0.00000000）'),
(407, 2115774905593442305, N'TECH_EXEC_RATIO', N'decimal', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'技师执行比例', 0, 8, NULL, N'请输入技师角色的执行比例（范围 0~1，默认 0.00000000）'),
(408, 2115774905593442305, N'NURSE_EXEC_RATIO', N'decimal', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'护士执行比例', 0, 9, NULL, N'请输入护士角色的执行比例（范围 0~1，默认 0.00000000）'),
(409, 2115774905593442305, N'CLINICAL_EXEC_RATIO', N'decimal', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'临床执行比例', 0, 10, NULL, N'请输入临床角色的执行比例（用于不区分医护的通用/科室整体核算单元）'),
(410, 2115774905593442305, N'DOC_HPS_DEPT_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'医生对应核算单元编码', 1, 11, NULL, N'请选择或输入医生对应的绩效核算单元编码'),
(411, 2115774905593442305, N'DOC_HPS_DEPT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'医生对应核算单元名称', 1, 12, NULL, N'请输入医生对应核算单元名称'),
(412, 2115774905593442305, N'TECH_HPS_DEPT_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'技师对应核算单元编码', 1, 13, NULL, N'请选择或输入技师对应的绩效核算单元编码'),
(413, 2115774905593442305, N'TECH_HPS_DEPT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'技师对应核算单元名称', 1, 14, NULL, N'请输入技师对应核算单元名称'),
(414, 2115774905593442305, N'NURSE_HPS_DEPT_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'护士对应核算单元编码', 1, 15, NULL, N'请选择或输入护士对应的绩效核算单元编码'),
(415, 2115774905593442305, N'NURSE_HPS_DEPT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'护士对应核算单元名称', 1, 16, NULL, N'请输入护士对应核算单元名称'),
(416, 2115774905593442305, N'CLINICAL_HPS_DEPT_CODE', N'varchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'临床对应核算单元编码', 1, 17, NULL, N'请选择或输入临床对应的绩效核算单元编码'),
(417, 2115774905593442305, N'CLINICAL_HPS_DEPT_NAME', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'临床对应核算单元名称', 1, 18, NULL, N'请输入临床对应核算单元名称'),
(418, 2115774905593442305, N'PROVIDE_DATE', N'datetime', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'提供日期', 1, 19, NULL, N'请选择规则生效的提供日期（SCD Type 2 左端点）'),
(419, 2115774905593442305, N'ITEM_ADD_DATE', N'datetime', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'项目新增日期', 1, 20, NULL, N'请选择收费项目在源系统中的新增日期'),
(420, 2115774905593442305, N'DISABLE_DATE', N'datetime', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'停用日期', 1, 21, NULL, N'请选择规则被标记为停用时的业务终止时间（生效区间右端点）'),
(421, 2115774905593442305, N'REMARK', N'nvarchar', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'备注', 0, 22, NULL, N'请输入相关的业务备注说明信息（可选）'),
(422, 2115774905593442305, N'VERSION_NO', N'int', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'版本号', 0, 23, NULL, N'请输入当前规则的版本号（仅做留痕记录）'),
(423, 2115774905593442305, N'IS_ENABLED', N'tinyint', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'是否启用', 1, 24, NULL, N'请选择启用状态（1:启用, 0:停用）'),
(424, 2115774905593442305, N'CREATE_TIME', N'datetime2', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'创建时间', 1, 25, NULL, N'系统自动记录的创建时间'),
(425, 2115774905593442305, N'UPDATE_TIME', N'datetime2', N'无', 1688431883371515906, '2026-10-29 19:57:01.3740000', NULL, NULL, 0, N'更新时间', 1, 26, NULL, N'系统自动记录的最后更新时间');


-- 2026年10月30日 13点09分
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116034743696445441, NULL, NULL, NULL, NULL, N'撤回', 1942402761383583745, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-30 13:09:31.5910000', 1688431883371515906, '2026-10-30 13:09:31.5910000', 0, 'kscalculateSave:withdraw', NULL, '科室核算表确认');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116034136650633217, NULL, NULL, NULL, NULL, N'确认', 1942402761383583745, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-30 13:07:06.8200000', 1688431883371515906, '2026-10-30 13:07:06.8200000', 0, 'kscalculateSave:confirm', NULL, '科室核算表确认');


UPDATE [dbo].[ads_dept_post_coefficient_m]
SET [unit_code] = N'UNIT021'
WHERE [unit_code] = N'100045';


-- 2026年10月31日09点07分 
-- 人员表 ID 显示出来给
UPDATE [dbo].[data_middle_base] SET [parent_id] = 1928880610526322690, [field_name] = N'id', [param_description] = N'ID', [field_type] = N'int', [business_type] = N'无', [creator_id] = 1688431883371515906, [createtime] = '2025-06-01 02:25:49.0880000', [modifier_id] = 1688431883371515906, [modifytime] = '2025-12-29 09:58:10.2810000', [deleted] = 0, [field_query] = 0, [sort] = 1, [field_sort] = 1 WHERE [id] = 1928880610526322691;
UPDATE [dbo].[data_middle_base] SET [parent_id] = 1928879755068661761, [field_name] = N'id', [param_description] = N'ID', [field_type] = N'numeric', [business_type] = N'无', [creator_id] = 1688431883371515906, [createtime] = '2025-06-01 02:22:25.1200000', [modifier_id] = 1688431883371515906, [modifytime] = '2025-12-29 10:13:34.7860000', [deleted] = 0, [field_query] = 0, [sort] = 1, [field_sort] = 1 WHERE [id] = 1928879755068661762;



INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116382088786026497, NULL, NULL, NULL, NULL, N'全院汇总视图', 2116381841997373441, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 12:09:45.1020000', 1688431883371515906, '2026-10-31 12:09:45.1020000', 0, 'primarySignSheet:summary', NULL, '一次分配签认表');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116382010113466370, NULL, NULL, NULL, NULL, N'导出签认表', 2116381841997373441, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 12:09:26.3590000', 1688431883371515906, '2026-10-31 12:09:26.3590000', 0, 'primarySignSheet:export', NULL, '一次分配签认表');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116381949015040002, NULL, NULL, NULL, NULL, N'查看', 2116381841997373441, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 12:09:11.7830000', 1688431883371515906, '2026-10-31 12:09:11.7830000', 0, 'primarySignSheet:list', NULL, '一次分配签认表');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116381841997373441, NULL, NULL, NULL, NULL, N'一次分配签认表', 2116349842989486082, N'/primarySignSheet/index', NULL, 1, N'primarySignSheet', 1, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 12:08:45.8330000', 1688431883371515906, '2026-10-31 12:08:45.8330000', 0, NULL, NULL, '绩效签认');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116352209856204802, NULL, NULL, NULL, NULL, N'查看', 2116351739347570690, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 10:11:01.4120000', 1688431883371515906, '2026-10-31 10:11:01.4120000', 0, 'unitSignSheet:list', NULL, '核算单元签认表');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116352101500555266, NULL, NULL, NULL, NULL, N'导出签字表', 2116351739347570690, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 10:10:35.5830000', 1688431883371515906, '2026-10-31 10:16:37.0962237', 0, 'unitSignSheet:export', NULL, '核算单元签认表');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116351739347570690, NULL, NULL, NULL, NULL, N'核算单元签认表', 2116349842989486082, N'/unitSignSheet/index', NULL, 1, N'unitSignSheet', 1, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 10:09:09.2430000', 1688431883371515906, '2026-10-31 10:09:09.2430000', 0, NULL, NULL, '绩效签认');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116349842989486082, NULL, NULL, NULL, NULL, N'绩效签认', NULL, N'/perfSign', NULL, 86, N'perfSign', 1, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-10-31 10:01:37.0690000', 1688431883371515906, '2026-10-31 10:05:32.7202830', 0, NULL, NULL, NULL);



-- 1) 加列（可重复执行需先判断）
ALTER TABLE data_connection ADD
  scope_enabled      tinyint      NOT NULL CONSTRAINT DF_dc_scope_enabled DEFAULT 0,
  scope_unit_column  varchar(128) NULL,
  scope_staff_column varchar(128) NULL;

-- 2) 初始化：全部保持"不启用"（= 上线零行为变化）
UPDATE data_connection SET scope_enabled = 0 WHERE scope_enabled IS NULL;

-- 3) 建议：给已确认的接口批量初始化（示例，执行前请核对列名）
UPDATE [dbo].[data_connection] SET [source_id] = 123, [org_id] = 2688431883371515906, [status] = 1, [name] = N'科室岗位系数月度明细表', [code] = N'ads_dept_post_coefficient_m', [master] = NULL, [port] = NULL, [data_base] = NULL, [username] = NULL, [password] = NULL, [data_driven] = NULL, [data_view] = NULL, [sign] = NULL, [access_way] = 2, [creator_id] = 1688431883371515906, [createtime] = '2026-09-20 13:30:07.3210000', [modifier_id] = NULL, [modifytime] = NULL, [deleted] = 0, [table_name] = 'ads_dept_post_coefficient_m', [table_name_clean] = NULL, [value_type] = 3, [pull_status] = NULL, [structural_name] = NULL, [pull_time] = NULL, [description] = '新版本 每月都需要维护', [sticky] = '1', [add_pk] = '0', [end_date] = NULL, [is_scheduled] = 0, [cron_expression] = NULL, [date_offset_type] = NULL, [date_offset_value] = NULL, [last_window_start] = NULL, [last_window_end] = NULL, [last_success_time] = NULL, [scope_enabled] = 1, [scope_unit_column] = 'unit_code', [scope_staff_column] = NULL WHERE [id] = 2101544412156755970;
UPDATE [dbo].[data_connection] SET [source_id] = 123, [org_id] = 2688431883371515906, [status] = 1, [name] = N'线下工作量明细事实表', [code] = N'dwd_fin_charge_workload_detail', [master] = NULL, [port] = NULL, [data_base] = NULL, [username] = NULL, [password] = NULL, [data_driven] = NULL, [data_view] = NULL, [sign] = NULL, [access_way] = 2, [creator_id] = 1688431883371515906, [createtime] = '2026-10-13 17:14:33.0000000', [modifier_id] = NULL, [modifytime] = NULL, [deleted] = 0, [table_name] = 'dwd_fin_charge_workload_detail', [table_name_clean] = NULL, [value_type] = 3, [pull_status] = NULL, [structural_name] = NULL, [pull_time] = NULL, [description] = '新版本', [sticky] = '1', [add_pk] = '0', [end_date] = NULL, [is_scheduled] = 0, [cron_expression] = NULL, [date_offset_type] = NULL, [date_offset_value] = NULL, [last_window_start] = NULL, [last_window_end] = NULL, [last_success_time] = NULL, [scope_enabled] = 1, [scope_unit_column] = 'unit_code', [scope_staff_column] = NULL WHERE [id] = 2109935812166496257;
UPDATE [dbo].[data_connection] SET [source_id] = 123, [org_id] = 2688431883371515906, [status] = 1, [name] = N'综合奖惩明细事实表', [code] = N'dwd_fin_reward_punish_detail', [master] = NULL, [port] = NULL, [data_base] = NULL, [username] = NULL, [password] = NULL, [data_driven] = NULL, [data_view] = NULL, [sign] = NULL, [access_way] = 2, [creator_id] = 1968504173607608321, [createtime] = '2026-10-28 19:25:46.4590000', [modifier_id] = NULL, [modifytime] = NULL, [deleted] = 0, [table_name] = 'dwd_fin_reward_punish_detail', [table_name_clean] = NULL, [value_type] = 1, [pull_status] = NULL, [structural_name] = NULL, [pull_time] = NULL, [description] = NULL, [sticky] = '1', [add_pk] = '1', [end_date] = NULL, [is_scheduled] = 0, [cron_expression] = NULL, [date_offset_type] = NULL, [date_offset_value] = NULL, [last_window_start] = NULL, [last_window_end] = NULL, [last_success_time] = NULL, [scope_enabled] = 1, [scope_unit_column] = 'unit_code', [scope_staff_column] = NULL WHERE [id] = 2115404654015782913;


SET NOCOUNT ON;
IF OBJECT_ID(N'dbo.data_connection_acl', N'U') IS NULL
BEGIN
  CREATE TABLE dbo.data_connection_acl (
    id bigint IDENTITY (1, 1) NOT NULL CONSTRAINT pk_data_connection_acl PRIMARY KEY,
    -- 主体：角色
    role_id bigint NOT NULL,
    role_code VARCHAR (50) NOT NULL, -- 冗余快照
    role_name nvarchar (100) NULL, -- 冗余快照
    -- 资源：数据接口
    connection_id bigint NOT NULL,
    connection_code VARCHAR (100) NOT NULL, -- 冗余快照
    connection_name nvarchar (200) NULL, -- 冗余快照
    -- 预留：可见之外是否允许导出（先不启用）
    can_export tinyint NOT NULL CONSTRAINT df_dca_can_export DEFAULT 0,
    create_user bigint NULL,
    create_time datetime2 NULL,
    CONSTRAINT uk_dca_role_conn UNIQUE (role_id, connection_id)
  );
  CREATE INDEX ix_dca_role ON dbo.data_connection_acl (role_id);
  CREATE INDEX ix_dca_conn ON dbo.data_connection_acl (connection_id);
  PRINT N'[新建] dbo.data_connection_acl';
END
ELSE
  PRINT N'[已存在] dbo.data_connection_acl，跳过建表';


    ALTER TABLE dbo.T_USER_INFO ADD PWD_UPDATE_TIME datetime2(7) NULL;
    PRINT N'[新增] T_USER_INFO.PWD_UPDATE_TIME';




ALTER TABLE data_import ADD
    ui_type        varchar(20)  NOT NULL
                   CONSTRAINT df_data_import_ui_type DEFAULT 'text',
    ui_source      varchar(64)  NULL,   -- 字典: sys_dict_type.code；资源: staff/department/position
    ui_pair_field  varchar(128) NULL;   -- 同表名称列，选中后自动写入


ALTER TABLE data_import ADD
    ui_required BIT NOT NULL CONSTRAINT df_data_import_ui_required DEFAULT 0,
    ui_readonly BIT NOT NULL CONSTRAINT df_data_import_ui_readonly DEFAULT 0;



-- =============================================================================
-- 日志审计：登录日志 + 操作日志
-- -----------------------------------------------------------------------------
-- 设计原则：
--   1) 只追加，不提供删除/修改接口（合规要求：审计日志不可篡改）；
--   2) 敏感信息不入库（密码、身份证、银行卡一律不记录）；
--   3) 按时间建索引，配合保留策略（默认保留 6 个月，可配置）。
-- =============================================================================

SET NOCOUNT ON;

/* ---------------- 1. 登录日志 ---------------- */
IF OBJECT_ID(N'dbo.sys_login_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.sys_login_log (
        id            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_sys_login_log PRIMARY KEY,
        account_no    NVARCHAR(64)  NULL,          -- 登录账号（失败时也记录，便于排查撞库）
        user_name     NVARCHAR(64)  NULL,          -- 姓名（成功时回填）
        user_id       DECIMAL(19,0) NULL,          -- 账号ID（成功时回填）
        result        VARCHAR(10)   NOT NULL,      -- SUCCESS / FAIL
        fail_reason   NVARCHAR(200) NULL,          -- 失败原因（如密码错误、账号停用）
        client_ip     VARCHAR(64)   NULL,
        user_agent    NVARCHAR(500) NULL,
        login_time    DATETIME      NOT NULL CONSTRAINT df_sys_login_log_time DEFAULT GETDATE()
    );
    CREATE NONCLUSTERED INDEX ix_sys_login_log_time ON dbo.sys_login_log (login_time DESC);
    CREATE NONCLUSTERED INDEX ix_sys_login_log_account ON dbo.sys_login_log (account_no, login_time DESC);
    PRINT N'[新增] sys_login_log';
END
ELSE PRINT N'[已存在] sys_login_log';

/* ---------------- 2. 操作日志 ---------------- */
IF OBJECT_ID(N'dbo.sys_operation_log', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.sys_operation_log (
        id            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT pk_sys_operation_log PRIMARY KEY,
        module        NVARCHAR(64)  NOT NULL,      -- 模块（如 员工管理 / 数据接口）
        action        NVARCHAR(32)  NOT NULL,      -- 动作（CREATE/UPDATE/DELETE/IMPORT/EXPORT/APPROVE）
        target_type   NVARCHAR(64)  NULL,          -- 对象类型（表名或业务名）
        target_id     NVARCHAR(128) NULL,          -- 对象主键（可为空）
        summary       NVARCHAR(500) NULL,          -- 摘要（人可读）
        detail        NVARCHAR(MAX) NULL,          -- 变更前后（JSON，敏感字段已脱敏）
        result        VARCHAR(10)   NOT NULL,      -- SUCCESS / FAIL
        fail_reason   NVARCHAR(500) NULL,
        operator_id   DECIMAL(19,0) NULL,
        operator_no   NVARCHAR(64)  NULL,
        operator_name NVARCHAR(64)  NULL,
        client_ip     VARCHAR(64)   NULL,
        cost_ms       INT           NULL,
        operate_time  DATETIME      NOT NULL CONSTRAINT df_sys_operation_log_time DEFAULT GETDATE()
    );
    CREATE NONCLUSTERED INDEX ix_sys_operation_log_time ON dbo.sys_operation_log (operate_time DESC);
    CREATE NONCLUSTERED INDEX ix_sys_operation_log_module ON dbo.sys_operation_log (module, operate_time DESC);
    CREATE NONCLUSTERED INDEX ix_sys_operation_log_operator ON dbo.sys_operation_log (operator_no, operate_time DESC);
    PRINT N'[新增] sys_operation_log';
END
ELSE PRINT N'[已存在] sys_operation_log';

/* ---------------- 3. 菜单（示例：按现有 T_RESOURCE_INFO 结构插入后人工调整） ---------------- */
-- 说明：菜单/权限请按你们现有资源表结构与前端路由 name 配置，避免脚本硬编码 ID 造成冲突。
-- 需要插入两条 MENU_TYPE=1 的资源：登录日志 logAuditLogin、操作日志 logAuditOperation，
-- 母菜单建议挂在「基础设置」下（parent_id 取基础设置节点 ID）。

/* ---------------- 4. 保留策略（可选，按月清理） ---------------- */
-- DELETE FROM sys_login_log WHERE login_time < DATEADD(MONTH, -6, GETDATE());
-- DELETE FROM sys_operation_log WHERE operate_time < DATEADD(MONTH, -6, GETDATE());



INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2117862847233536002, NULL, NULL, NULL, NULL, N'查看', 2116382088786026498, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1968504173607608321, '2026-11-04 14:13:45.4310000', 1968504173607608321, '2026-11-04 14:13:45.4310000', 0, 'logAuditLogin:list', NULL, '登录日志');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2117862789469581314, NULL, NULL, NULL, NULL, N'查看', 2116382088786026499, NULL, NULL, NULL, NULL, 2, 1, NULL, 0, NULL, NULL, 1, 1968504173607608321, '2026-11-04 14:13:31.6460000', 1968504173607608321, '2026-11-04 14:13:31.6460000', 0, 'logAuditOperation:list', NULL, '操作日志');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116382088786026499, NULL, NULL, NULL, NULL, N'操作日志', 1915645779515166721, N'/logAuditOperation/index', NULL, 41, N'logAuditOperation', 1, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-11-04 14:12:02.1730000', 1688431883371515906, '2026-11-04 14:12:02.1730000', 0, NULL, NULL, '基础设置');
INSERT INTO [dbo].[T_RESOURCE_INFO] ([ID], [SYSTEM_ID], [FUN_NODE], [LABEL], [COMPONENT_NAME], [NAME], [PARENT_ID], [PATH], [SERVER_URL], [SORT_NUMBER], [COMPONENT], [MENU_TYPE], [EQUIPMENT_TYPE], [IS_KEEP_ALIVE], [IS_HIDE], [ICON], [PERMS], [STATUS], [CREATE_USER], [CREATE_TIME], [MODIFY_USER], [MODIFY_TIME], [DELETE_FLAG], [BTN_CODE], [micro_name], [PARENT_NAME]) VALUES (2116382088786026498, NULL, NULL, NULL, NULL, N'登录日志', 1915645779515166721, N'/logAuditLogin/index', NULL, 40, N'logAuditLogin', 1, 1, NULL, 0, NULL, NULL, 1, 1688431883371515906, '2026-11-04 14:12:02.1700000', 1688431883371515906, '2026-11-04 14:12:02.1700000', 0, NULL, NULL, '基础设置');
