-- =================================================================
-- 表名：ads_perf_dept_user_auth
-- 分层：ADS（应用层/集市层）
-- 业务定义：科室-人员数据权限及填报关联映射表（代替历史的逗号拼接字段）
-- 命名规范：全小写 + 下划线分割（snake_case）
-- 主键策略：代理主键 + 业务唯一索引，保障幂等与检索性能
-- =================================================================

IF OBJECT_ID('[dbo].[ads_perf_dept_user_auth]', 'U') IS NOT NULL
    DROP TABLE [dbo].[ads_perf_dept_user_auth];

CREATE TABLE [dbo].[ads_perf_dept_user_auth] (
    -- 代理主键
    [id]                    BIGINT IDENTITY(1,1) NOT NULL,
    -- 机构与核算单元维度
    [org_code]              NVARCHAR(50)        NOT NULL,   -- 机构编码（如 1001）
    [org_name]              NVARCHAR(200)       NULL,       -- 机构名称
    [unit_code]             NVARCHAR(100)       NOT NULL,   -- 核算单元编码
    [unit_name]             NVARCHAR(200)       NULL,       -- 核算单元名称
    -- 员工权限主体维度
    [staff_code]            NVARCHAR(50)        NOT NULL,   -- 员工编码
    [staff_name]            NVARCHAR(100)       NOT NULL,   -- 员工姓名
    [auth_type]             NVARCHAR(20)        NOT NULL,   -- 权限类型：LEADER-负责人, FILLER-填报人
    -- 通用审计 4 字段
    [create_user]           NVARCHAR(100)       NULL,       -- 创建人
    [create_time]           DATETIME2(3)        NOT NULL
        CONSTRAINT [df_ads_perf_dept_user_auth_create_time] DEFAULT (SYSDATETIME()), -- 创建时间
    [update_user]           NVARCHAR(100)       NULL,       -- 修改人
    [update_time]           DATETIME2(3)        NULL,       -- 修改时间
    -- 聚簇索引主键
    CONSTRAINT [pk_ads_perf_dept_user_auth] PRIMARY KEY CLUSTERED ([id] ASC),
    -- 业务唯一约束（防重：同一机构下，某个核算单元的某个员工不能重复拥有同一种权限角色）
    CONSTRAINT [uq_ads_perf_dept_user_auth_biz] UNIQUE NONCLUSTERED (
        [org_code] ASC, 
        [unit_code] ASC, 
        [staff_code] ASC, 
        [auth_type] ASC
    )
);

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty
    @name = N'MS_Description', @value = N'科室-人员数据权限及填报关联映射表',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_perf_dept_user_auth';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'自增代理主键',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'id';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构编码',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'org_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'org_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码（HPS_DEPT_CODE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工编码',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'staff_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工姓名',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'staff_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'权限类型：LEADER-负责人, FILLER-填报人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'auth_type';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'create_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'create_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'update_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_dept_user_auth', @level2type = N'COLUMN', @level2name = N'update_time';