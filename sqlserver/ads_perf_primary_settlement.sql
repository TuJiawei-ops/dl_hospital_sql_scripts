-- =================================================================
-- 表名：ads_perf_primary_settlement
-- 分层：ADS（应用层/集市层）
-- 业务定义：一次分配结算底账（一次分配与二次分配之间的防腐层、快照契约中间件）
-- 命名规范：全小写 + 下划线分割（snake_case）
-- 主键策略：采用业务复合主键作为聚簇索引（纯最终结算事实表，无状态冗余）
-- Relative Path : sqlserver/ads_perf_primary_settlement.sql
-- 修改日志：
-- 2026-10-28 09:40:10 | 注释补全 | 追加表级与 12 个字段级 MS_Description 扩展属性，单批分号执行。
-- =================================================================

IF OBJECT_ID('[dbo].[ads_perf_primary_settlement]', 'U') IS NOT NULL
    DROP TABLE [dbo].[ads_perf_primary_settlement];

CREATE TABLE [dbo].[ads_perf_primary_settlement] (
    -- 账期维度（复合主键组成部分）
    [calc_year]             INT                 NOT NULL,   -- 核算年份
    [calc_month]            INT                 NOT NULL,   -- 核算月份
    -- 机构维度（复合主键组成部分）
    [org_code]              NVARCHAR(50)        NOT NULL,   -- 机构编码
    [org_name]              NVARCHAR(200)       NULL,       -- 机构名称
    -- 核算单元维度（复合主键组成部分）
    [unit_code]             NVARCHAR(100)       NOT NULL,   -- 核算单元编码
    [unit_name]             NVARCHAR(200)       NULL,       -- 核算单元名称
    -- 最终结算金额
    [primary_amount]        DECIMAL(18,8)       NOT NULL,   -- 一次分配最终结算总额（核定额上限）
    [final_time]            DATETIME2(3)        NULL,       -- 期间结账定稿时间
    -- 通用审计 4 字段
    [create_user]           NVARCHAR(100)       NULL,       -- 创建人
    [create_time]           DATETIME2(3)        NOT NULL
        CONSTRAINT [df_ads_perf_primary_settlement_create_time] DEFAULT (SYSDATETIME()), -- 创建时间
    [update_user]           NVARCHAR(100)       NULL,       -- 修改人
    [update_time]           DATETIME2(3)        NULL,       -- 修改时间
    -- 业务复合主键（聚簇索引，天然保障幂等防重及前缀检索性能）
    CONSTRAINT [pk_ads_perf_primary_settlement] PRIMARY KEY CLUSTERED (
        [calc_year] ASC, 
        [calc_month] ASC, 
        [org_code] ASC, 
        [unit_code] ASC
    )
);

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty
    @name = N'MS_Description', @value = N'一次分配结算底账（一次分配与二次分配之间的防腐层、快照契约中间件，纯最终结算事实表）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_perf_primary_settlement';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'calc_year';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'calc_month';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构编码',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'org_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'机构名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'org_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码（HPS_DEPT_CODE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称（HPS_DEPT_NAME）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'一次分配最终结算总额（二次分配填报的核定额上限）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'primary_amount';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'期间结账定稿时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'final_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'create_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'create_time';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改人',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'update_user';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'修改时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_perf_primary_settlement', @level2type = N'COLUMN', @level2name = N'update_time';