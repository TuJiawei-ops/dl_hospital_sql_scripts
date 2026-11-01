/* ===============================================================================
  Relative Path : sqlserver/patches/PATCH_dwd_fin_reward_punish_detail_add_origin.sql
  脚本名称: PATCH_dwd_fin_reward_punish_detail_add_origin.sql
  业务说明: 为存量环境的 dwd_fin_reward_punish_detail 增量追加通用发起方描述列
            （origin_type / origin_name / origin_ref_no），兼容科室、医疗组/护理组等虚拟组
            与会议；同步注册数据接口字段（data_import）并调整排序；不改主键、业务唯一索引、
            CHECK 与既有数据。
  修改日志:
  2026-11-01 21:30:00 | 字段注册 | 追加 data_import 三条字段注册（ID 324-326，排序 20-22），原 remark 起 5 个字段排序整体后移 3 位；按 parent_id + field_name 幂等守卫。
  2026-11-01 21:05:00 | 补丁新建 | 新增三列（均可空）及列级 MS_Description；IF COL_LENGTH / fn_listextendedproperty 幂等守卫，重复执行零报错。
  =============================================================================== */

SET XACT_ABORT ON;

IF OBJECT_ID(N'[dbo].[dwd_fin_reward_punish_detail]', N'U') IS NOT NULL
BEGIN
    -- 1. 增量加列（仅当列不存在）
    IF COL_LENGTH(N'dbo.dwd_fin_reward_punish_detail', N'origin_type') IS NULL
        ALTER TABLE [dbo].[dwd_fin_reward_punish_detail] ADD [origin_type] VARCHAR(20) NULL;

    IF COL_LENGTH(N'dbo.dwd_fin_reward_punish_detail', N'origin_name') IS NULL
        ALTER TABLE [dbo].[dwd_fin_reward_punish_detail] ADD [origin_name] NVARCHAR(200) NULL;

    IF COL_LENGTH(N'dbo.dwd_fin_reward_punish_detail', N'origin_ref_no') IS NULL
        ALTER TABLE [dbo].[dwd_fin_reward_punish_detail] ADD [origin_ref_no] VARCHAR(100) NULL;

    -- 2. 列级注释（仅当扩展属性不存在）
    IF NOT EXISTS (
        SELECT 1
        FROM sys.fn_listextendedproperty(N'MS_Description', N'SCHEMA', N'dbo',
             N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_type')
    )
        EXEC sp_addextendedproperty N'MS_Description',
             N'发起方类型（可空；轻量分类，不做外键校验：DEPT 科室 / GROUP 专项组 / MEETING 会议 / OTHER 其他；与 create_user 的录入人区分）',
             N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_type';

    IF NOT EXISTS (
        SELECT 1
        FROM sys.fn_listextendedproperty(N'MS_Description', N'SCHEMA', N'dbo',
             N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_name')
    )
        EXEC sp_addextendedproperty N'MS_Description',
             N'发起方名称（可空，自由文本：可为科室、医疗组/护理组/专项组等虚拟组、院周会等会议；发起方不是组织架构稳定实体，故不建部门外键）',
             N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_name';

    IF NOT EXISTS (
        SELECT 1
        FROM sys.fn_listextendedproperty(N'MS_Description', N'SCHEMA', N'dbo',
             N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_ref_no')
    )
        EXEC sp_addextendedproperty N'MS_Description',
             N'发起方依据编号（可空：处罚文号 / 会议纪要编号 / 检查批次号等，用于追溯奖惩来源文件）',
             N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'origin_ref_no';
END;

-- ================================================================
-- 3. 数据接口字段注册（data_import）
--    新字段插在 amount(19) 与 remark(20) 之间：占用 20/21/22，
--    原 remark / create_user / create_time / update_user / update_time 整体后移 3 位。
-- ================================================================
IF OBJECT_ID(N'[dbo].[data_import]', N'U') IS NOT NULL
   AND NOT EXISTS (
        SELECT 1
        FROM [dbo].[data_import]
        WHERE [parent_id] = 2115404654015782913
          AND [field_name] = N'origin_type'
          AND [deleted] = 0
   )
BEGIN
    BEGIN TRANSACTION;

    INSERT INTO [dbo].[data_import]
        ([id], [parent_id], [field_name], [field_type], [business_type], [creator_id], [createtime],
         [modifier_id], [modifytime], [deleted], [param_description], [field_query], [sort], [remark], [field_tip])
    VALUES
        (324, 2115404654015782913, N'origin_type', N'varchar', N'无', 1968504173607608321, SYSDATETIME(),
         NULL, NULL, 0, N'发起方类型', 0, 20, NULL,
         N'请选择发起方类型：DEPT（科室）/ GROUP（专项组）/ MEETING（会议）/ OTHER（其他）');

    INSERT INTO [dbo].[data_import]
        ([id], [parent_id], [field_name], [field_type], [business_type], [creator_id], [createtime],
         [modifier_id], [modifytime], [deleted], [param_description], [field_query], [sort], [remark], [field_tip])
    VALUES
        (325, 2115404654015782913, N'origin_name', N'nvarchar', N'无', 1968504173607608321, SYSDATETIME(),
         NULL, NULL, 0, N'发起方名称', 0, 21, NULL,
         N'请输入发起方名称，如：医疗质量专项组、护理组、院周会');

    INSERT INTO [dbo].[data_import]
        ([id], [parent_id], [field_name], [field_type], [business_type], [creator_id], [createtime],
         [modifier_id], [modifytime], [deleted], [param_description], [field_query], [sort], [remark], [field_tip])
    VALUES
        (326, 2115404654015782913, N'origin_ref_no', N'varchar', N'无', 1968504173607608321, SYSDATETIME(),
         NULL, NULL, 0, N'发起方依据编号', 0, 22, NULL,
         N'选填：处罚文号 / 会议纪要编号 / 检查批次号');

    -- 三条注册成功后再后移原字段，避免 ID 冲突时排序被重复推移
    UPDATE [dbo].[data_import]
    SET [sort] = [sort] + 3
    WHERE [parent_id] = 2115404654015782913
      AND [deleted] = 0
      AND [field_name] IN (N'remark', N'create_user', N'create_time', N'update_user', N'update_time');

    COMMIT TRANSACTION;
END;
