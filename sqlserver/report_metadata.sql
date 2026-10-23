/*
================================================================================
Relative Path : sqlserver/report_metadata.sql
脚本名称      : report_metadata.sql
分层归属      : DIM（配置层 / UReport2 报表业务元数据补充表）
业务定义      : 报表业务元数据表。作为 UReport2 底层表 ureport_file 的补充，按
                report_name = ureport_file.name 一对一挂接，维护报表分类、解释说明
                与前端展示排序，支撑「报表中心」分类检索与展示。
关联契约      : report_name ◀──1:1──▶ ureport_file.name（仅补业务元数据，不复制模板内容）
                若模板表 name 为 VARCHAR，比对时发生 VARCHAR→NVARCHAR 隐式转换，
                模板表体量小可忽略；元数据侧索引仍可正常命中
唯一性        : report_name 唯一索引，防同一报表重复挂接
排序规则      : 字符列显式 Chinese_PRC_CI_AS；若 ureport_file.name 排序规则不同，
                JOIN 时须双侧显式 COLLATE 对齐，否则触发排序规则冲突错误
幂等策略      : sys.all_objects 判定表存在即 DROP TABLE 重建，脚本可重复执行
数据安全告警  : DROP 重建会清空已维护的业务元数据，生产库重跑前必须先备份
模板占位符    : 无（纯 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes}）
修改日志：
2026-10-23 19:01:17 | 初始建表 | 新建 report_metadata（UReport2 报表业务元数据补充表）：report_name 唯一索引 + 分类排序索引 + 全字段中文注释
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表（重跑零脏数据，保障 DDL 可重复执行）
--    注意：本表承载人工维护的业务元数据，生产环境重跑前先备份：
--    SELECT * INTO dbo.report_metadata_bak_YYYYMMDD FROM dbo.report_metadata;
-- ================================================================
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[report_metadata]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[report_metadata];
END;

-- ================================================================
-- 2. 创建报表业务元数据物理表
-- ================================================================
CREATE TABLE [dbo].[report_metadata] (
    -- ===== 主键 =====
    [id]          BIGINT         IDENTITY(1,1) NOT NULL,                  -- 自增主键

    -- ===== 报表挂接键（对齐 ureport_file.name）=====
    [report_name] NVARCHAR(255)  COLLATE Chinese_PRC_CI_AS NOT NULL,      -- 报表名称

    -- ===== 业务元数据 =====
    [report_type] NVARCHAR(100)  COLLATE Chinese_PRC_CI_AS NULL,          -- 报表分类/类型
    [report_desc] NVARCHAR(500)  COLLATE Chinese_PRC_CI_AS NULL,          -- 报表解释与业务说明
    [sort]        INT            NOT NULL CONSTRAINT df_report_metadata_sort DEFAULT (0),  -- 展示排序号

    -- ===== 审计字段 =====
    [create_user] VARCHAR(50)    COLLATE Chinese_PRC_CI_AS NOT NULL CONSTRAINT df_report_metadata_create_user DEFAULT ('system'),  -- 创建人
    [create_time] DATETIME       NOT NULL CONSTRAINT df_report_metadata_create_time DEFAULT (GETDATE()),                          -- 创建时间
    [update_user] VARCHAR(50)    COLLATE Chinese_PRC_CI_AS NOT NULL CONSTRAINT df_report_metadata_update_user DEFAULT ('system'),  -- 最后修改人
    [update_time] DATETIME       NOT NULL CONSTRAINT df_report_metadata_update_time DEFAULT (GETDATE()),                          -- 最后修改时间

    -- ===== 主键约束 =====
    CONSTRAINT [pk_report_metadata] PRIMARY KEY CLUSTERED ([id] ASC)
);

-- ================================================================
-- 3. 检索索引
-- ================================================================
-- 3.1 报表名称唯一索引：锁定 report_name 与 ureport_file.name 的 1:1 挂接，
--     同时支撑「按报表名回查元数据」与 INNER/LEFT JOIN 的索引命中
CREATE UNIQUE NONCLUSTERED INDEX [uk_report_metadata_report_name]
    ON [dbo].[report_metadata] ([report_name] ASC);

-- 3.2 报表中心分类展示索引：键序 (分类, 排序号) 直接覆盖前端按类目分页取数，
--     INCLUDE 覆盖描述文本，避免分类列表页回表
CREATE NONCLUSTERED INDEX [ix_report_metadata_type_sort]
    ON [dbo].[report_metadata] ([report_type] ASC, [sort] ASC)
    INCLUDE ([report_name], [report_desc]);

-- ================================================================
-- 4. 表级与字段级扩展属性注释
--    第 1 区块已 DROP TABLE 重建，历史扩展属性随对象物理清除，
--    故此处顺序执行 sp_addextendedproperty，无需 IF EXISTS 守卫
-- ================================================================
EXEC sp_addextendedproperty N'MS_Description', N'报表业务元数据表：UReport2 底层表 ureport_file 的补充表，按 report_name = ureport_file.name 一对一挂接，维护报表分类、解释说明与展示排序号，供前端「报表中心」分类检索与展示', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata';
EXEC sp_addextendedproperty N'MS_Description', N'自增主键（BIGINT IDENTITY(1,1)，物理唯一标识，无业务含义，严禁作为报表挂接键使用）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'id';
EXEC sp_addextendedproperty N'MS_Description', N'报表名称（唯一，对应 ureport_file.name，是业务元数据与报表模板的唯一挂接键；报表更名时须同步维护本表，否则元数据在报表中心失联）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'report_name';
EXEC sp_addextendedproperty N'MS_Description', N'报表分类/类型（例如：绩效类、门诊类、住院类、质控类；前端报表中心按此字段分组归类，为空则归入「未分类」）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'report_type';
EXEC sp_addextendedproperty N'MS_Description', N'报表解释与业务说明（面向业务人员的口径说明：统计范围、数据来源、取数周期、指标含义与使用注意事项，供报表中心悬浮提示与帮助页展示）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'report_desc';
EXEC sp_addextendedproperty N'MS_Description', N'展示排序号（INT，默认 0；同一分类内按升序展示，数值越小越靠前，相同值按 report_name 兜底排序）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'sort';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system，业务录入时写明操作人工号）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system；维护脚本或业务人员更新元数据时同步写入）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()；更新语句须显式写 update_time = GETDATE()，本表不含触发器自动刷新）', N'SCHEMA', N'dbo', N'TABLE', N'report_metadata', N'COLUMN', N'update_time';

-- ================================================================
-- 5. 使用参考（注释态，按需解注执行；非脚本必需逻辑）
-- ================================================================
-- 5.1 登记一条报表元数据（report_name 必须与 ureport_file.name 完全一致）
-- INSERT INTO [dbo].[report_metadata] ([report_name], [report_type], [report_desc], [sort], [create_user], [update_user])
-- VALUES (N'未配置RVU点数的医疗服务项目排查清单', N'质控类',
--         N'排查有业务发生但未配置 RVU 点数的医疗服务项目；未配置将无法参与绩效核算，请及时补录。',
--         10, 'system', 'system');
--
-- 5.2 已登记则更新、未登记则新增（report_name 唯一索引天然作为自然键）
-- UPDATE [dbo].[report_metadata]
-- SET [report_type] = N'质控类', [report_desc] = N'排查未配置 RVU 点数的项目，未配置将无法参与绩效核算。',
--     [sort] = 10, [update_user] = 'system', [update_time] = GETDATE()
-- WHERE [report_name] = N'未配置RVU点数的医疗服务项目排查清单';
-- IF @@ROWCOUNT = 0
--     INSERT INTO [dbo].[report_metadata] ([report_name], [report_type], [report_desc], [sort], [create_user], [update_user])
--     VALUES (N'未配置RVU点数的医疗服务项目排查清单', N'质控类', N'排查未配置 RVU 点数的项目，未配置将无法参与绩效核算。', 10, 'system', 'system');
--
-- 5.3 报表中心取数视图口径（左连接：元数据缺失时回落模板名并标记「未分类」）
-- SELECT f.[name]                                                        AS [报表名称]
--       ,ISNULL(m.[report_type], N'未分类')                               AS [报表分类]
--       ,ISNULL(m.[report_desc], N'')                                     AS [报表说明]
--       ,ISNULL(m.[sort], 2147483647)                                     AS [排序号]
-- FROM [dbo].[ureport_file] AS f WITH (NOLOCK)
-- LEFT JOIN [dbo].[report_metadata] AS m WITH (NOLOCK)
--        ON m.[report_name] = f.[name]
-- ORDER BY [报表分类] ASC, [排序号] ASC, [报表名称] ASC;
--
-- 5.4 元数据治理核查：已上传模板但漏登记业务元数据，或本表登记了已删除的报表
-- SELECT N'模板未登记元数据' AS [异常类型], f.[name] AS [报表名称]
-- FROM [dbo].[ureport_file] AS f WITH (NOLOCK)
-- LEFT JOIN [dbo].[report_metadata] AS m WITH (NOLOCK)
--        ON m.[report_name] = f.[name]
-- WHERE m.[id] IS NULL
-- UNION ALL
-- SELECT N'元数据指向已删除报表' AS [异常类型], m.[report_name] AS [报表名称]
-- FROM [dbo].[report_metadata] AS m WITH (NOLOCK)
-- LEFT JOIN [dbo].[ureport_file] AS f WITH (NOLOCK)
--        ON f.[name] = m.[report_name]
-- WHERE f.[name] IS NULL;
