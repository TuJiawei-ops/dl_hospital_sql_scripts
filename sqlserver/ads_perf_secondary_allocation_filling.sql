-- =================================================================
-- 表名：ads_perf_secondary_allocation_filling
-- 分层：ADS（应用层/集市层）
-- 业务定义：二次分配额度填报底账（二次分配人员明细填报事实表：科室总额受控于一次分配上限，明细落实到具体员工）
-- 命名规范：全小写 + 下划线分割（snake_case）
-- 主键策略：采用业务复合主键作为聚簇索引，天然保障幂等防重及前缀检索性能
-- Relative Path : sqlserver/ads_perf_secondary_allocation_filling.sql
-- 修改日志：
-- 2026-10-28 10:43:19 | 脚本新建 | 新建二次分配额度填报底账 DDL：业务复合主键、核定额快照与填报/审核时点，含表级与列级 MS_Description。
-- 2026-10-28 11:30:00 | 结构升级 | 粒度下沉至员工层：新增 unit_name/staff_code/staff_name，主键追加 staff_code，注释同步补列。
-- 2026-10-28 11:55:00 | 字段扩展 | 追加 remark(NVARCHAR(500)) 备注/调整说明列及列级 MS_Description，主键与粒度零改动。
-- =================================================================

IF OBJECT_ID('[dbo].[ads_perf_secondary_allocation_filling]', 'U') IS NOT NULL
    DROP TABLE [dbo].[ads_perf_secondary_allocation_filling];

CREATE TABLE [dbo].[ads_perf_secondary_allocation_filling] (
    -- 账期维度（复合主键组成部分）
    [calc_year]             INT                 NOT NULL,   -- 核算年份
    [calc_month]            INT                 NOT NULL,   -- 核算月份
    -- 机构维度（复合主键组成部分）
    [org_code]              NVARCHAR(50)        NOT NULL,   -- 机构编码（系统固定配置，如 1001）
    [org_name]              NVARCHAR(200)       NULL,       -- 机构名称
    -- 核算单元维度（复合主键组成部分）
    [unit_code]             NVARCHAR(100)       NOT NULL,   -- 核算单元编码
    [unit_name]             NVARCHAR(200)       NULL,       -- 核算单元名称
    -- 员工维度（复合主键组成部分：二次分配明细落脚点）
    [staff_code]            NVARCHAR(50)        NOT NULL,   -- 员工编码
    [staff_name]            NVARCHAR(100)       NOT NULL,   -- 员工姓名
    -- 填报业务指标
    [upper_limit_amount]    DECIMAL(18,8)       NOT NULL,   -- 一次分配核定额上限（科室级总额上限快照）
    [filled_amount]         DECIMAL(18,8)       NOT NULL,   -- 二次分配员工填报/核定金额
    [remark]                NVARCHAR(500)       NULL,       -- 备注/调整说明
    [fill_status]           INT                 NOT NULL
        CONSTRAINT [df_ads_perf_secondary_allocation_filling_fill_status] DEFAULT (0), -- 填报状态：0-未填报/草稿 1-已提交 2-已审核/已发布
    [submit_time]           DATETIME2(3)        NULL,       -- 提交填报时间
    [audit_time]            DATETIME2(3)        NULL,       -- 审核定稿时间
    -- 通用审计 4 字段
    [create_user]           NVARCHAR(100)       NULL,       -- 创建人
    [create_time]           DATETIME2(3)        NOT NULL
        CONSTRAINT [df_ads_perf_secondary_allocation_filling_create_time] DEFAULT (SYSDATETIME()), -- 创建时间
    [update_user]           NVARCHAR(100)       NULL,       -- 修改人
    [update_time]           DATETIME2(3)        NULL,       -- 修改时间
    -- 业务复合主键（聚簇索引：账期 + 机构 + 核算单元 + 员工）
    CONSTRAINT [pk_ads_perf_secondary_allocation_filling] PRIMARY KEY CLUSTERED (
        [calc_year] ASC,
        [calc_month] ASC,
        [org_code] ASC,
        [unit_code] ASC,
        [staff_code] ASC
    ),
    -- 填报状态域约束
    CONSTRAINT [ck_ads_perf_secondary_allocation_filling_fill_status] CHECK ([fill_status] IN (0, 1, 2))
);

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty
    @name = N'MS_Description', @value = N'二次分配额度填报底账（二次分配人员明细填报事实表）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_perf_secondary_allocation_filling';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'calc_year';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'calc_month';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构编码（系统固定配置，如 1001）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'org_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'org_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码（HPS_DEPT_CODE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工编码',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'staff_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工姓名',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'staff_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'一次分配核定额上限（科室级总额上限快照）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'upper_limit_amount';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'二次分配员工填报/核定金额',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'filled_amount';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'备注/调整说明',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'remark';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'填报状态标识（0-未填报/草稿，1-已提交，2-已审核/已发布）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'fill_status';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'提交填报时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'submit_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'审核定稿时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'audit_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'create_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'create_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'update_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_secondary_allocation_filling', @level2type = N'COLUMN', @level2name = N'update_time';
