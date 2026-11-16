-- =================================================================
-- 表实体创建：ads_dept_monthly_performance_m
-- 业务定义：核算单元月度绩效金额表（大连市皮肤病医院专用 · 线下发放口径）
-- Relative Path : sqlserver/ADS_DEPT_MONTHLY_PERFORMANCE_M.sql
-- =================================================================
-- 设计说明
--   1. 粒度：核算单元 × 账期（year, month, unit_code），与个人表
--      ads_emp_monthly_performance_m（人 × 岗位 × 单元 × 月）形成 1:N 拆分关系。
--   2. 两表通过 (year, month, unit_code) 关联，可做勾稽校验：
--      SUM(个人合计绩效) 不应超过本表 [total_performance]。
--   3. 本表为「线下核定发放」口径，非全公司通用口径；其他医院按各自口径另建。
--   4. 若后续需要「按职系拆分单元额度」，请将 [series_code] 纳入联合主键
--      （当前设计允许为空，不参与主键）。
-- =================================================================
-- 修改日志
-- 2026-11-16 00:00:00 | 初始建表 | 建立核算单元月度绩效金额表，承载线下发放口径的单元总额、
--                      已分配合计与参与人数；联合主键 (year, month, unit_code)，含表级与列级扩展属性注释。
-- =================================================================

-- 删除已存在的表（开发/迭代环境使用，生产环境请谨慎）
IF OBJECT_ID(N'[dbo].[ads_dept_monthly_performance_m]', N'U') IS NOT NULL
    DROP TABLE [dbo].[ads_dept_monthly_performance_m];

-- 创建表
CREATE TABLE [dbo].[ads_dept_monthly_performance_m] (
    -- 1. 账期维度
    [year]                              INT             NOT NULL,       -- 核算年份
    [month]                             INT             NOT NULL,       -- 核算月份

    -- 2. 核算单元维度
    [unit_code]                         VARCHAR(50)     NOT NULL,       -- 核算单元编码
    [unit_name]                         VARCHAR(100)    NOT NULL,       -- 核算单元名称

    -- 3. 职系维度（可空：不按职系拆分单元额度时留空）
    [series_code]                       VARCHAR(50)     NULL,           -- 所属职系编码
    [series_name]                       VARCHAR(100)    NULL,           -- 所属职系名称

    -- 4. 金额度量
    [total_performance]                 DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 单元绩效总额（线下核定）
    [distributed_amount]                DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 已分配给个人的合计

    -- 5. 辅助度量
    [staff_count]                       INT             NOT NULL DEFAULT 0,     -- 参与分配人数

    -- 6. 审计与备注
    [remark]                            VARCHAR(1000)   NULL,                        -- 备注
    [create_time]                       DATETIME        NOT NULL CONSTRAINT df_ads_dept_monthly_performance_m_create_time DEFAULT (GETDATE()),  -- 创建时间

    -- 7. 联合主键：同一账期内单个核算单元仅存在一条单元绩效记录
    CONSTRAINT pk_ads_dept_monthly_performance_m PRIMARY KEY CLUSTERED (
        [year],
        [month],
        [unit_code]
    )
);

-- 索引：按账期批量取数、按单元纵向追溯
CREATE INDEX ix_ads_dept_monthly_performance_m_period
    ON [dbo].[ads_dept_monthly_performance_m] ([year], [month]);

CREATE INDEX ix_ads_dept_monthly_performance_m_unit
    ON [dbo].[ads_dept_monthly_performance_m] ([unit_code], [year], [month]);

-- 注入表级扩展属性注释
EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'【核算单元月度绩效金额表（大连市皮肤病医院专用·线下发放口径）】：承载月度核算单元的绩效总额、已分配合计与参与人数；与个人月度绩效表按 (year, month, unit_code) 形成总额与拆分关系，支持勾稽校验。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m';

-- 注入列级扩展属性注释
EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算年份',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'year';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算月份',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'month';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算单元编码',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'所属职系编码（不按职系拆分额度时为空）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'series_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'所属职系名称（不按职系拆分额度时为空）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'series_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'单元绩效总额（线下核定口径）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'total_performance';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'已分配给个人的合计金额（可由个人月度绩效表按单元汇总回算）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'distributed_amount';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'参与分配人数',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'staff_count';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'备注',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'remark';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'create_time';
