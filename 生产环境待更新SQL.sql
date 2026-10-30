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
