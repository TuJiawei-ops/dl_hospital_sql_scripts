-- =================================================================
-- 表实体创建：ads_dept_monthly_performance_m
-- 业务定义：业务科室月度绩效金额表（大连市皮肤病医院专用 · 线下发放口径）
-- Relative Path : sqlserver/ADS_DEPT_MONTHLY_PERFORMANCE_M.sql
-- =================================================================
-- 设计说明
--   1. 实体定位：本表主体是【业务科室】（如「治疗科」），不是【核算单元】
--      （核算单元是「治疗科医生 / 治疗科护士」这类按职系拆分的考核对象）。
--      因此：列名统一用 dept_code / dept_name；不含职系字段
--      ——职系（临床系列 / 护理系列）是核算单元的属性，不属于业务科室。
--   2. 粒度：业务科室 × 账期（year, month, dept_code），一个科室每月一条。
--   3. 与个人绩效表的关联方式：
--        ads_emp_monthly_performance_m（核算单元 × 员工）
--              │ unit_code
--              ▼
--        dim_unit_dept_relation（核算单元 → 业务科室，带生效区间）
--              │ dept_code
--              ▼
--        ads_dept_monthly_performance_m（业务科室 × 账期）
--      个人绩效按【核算单元】记录，本表按【业务科室】记录，两者经关系表汇总，
--      不能直接用 unit_code = dept_code 关联。
--   4. 本表为「线下核定发放」口径，非全公司通用口径；其他医院按各自口径另建。
-- =================================================================
-- 修改日志
-- 2026-11-16 00:00:00 | 初始建表 | 建立业务科室月度绩效金额表，联合主键 (year, month, dept_code)。
-- 2026-11-16 00:00:00 | 模型修正 | 主体由「核算单元」更正为「业务科室」：unit_code/unit_name 更名
--                      dept_code/dept_name；移除 series_code/series_name（职系属核算单元属性）。
-- =================================================================

-- 删除已存在的表（开发/迭代环境使用，生产环境请谨慎）
IF OBJECT_ID(N'[dbo].[ads_dept_monthly_performance_m]', N'U') IS NOT NULL
    DROP TABLE [dbo].[ads_dept_monthly_performance_m];

-- 创建表
CREATE TABLE [dbo].[ads_dept_monthly_performance_m] (
    -- 1. 账期维度
    [year]                              INT             NOT NULL,       -- 核算年份
    [month]                             INT             NOT NULL,       -- 核算月份

    -- 2. 业务科室维度（科室行见 T_DEPARTMENT 中 CODE 以 UNIT 开头的记录）
    [dept_code]                         VARCHAR(50)     NOT NULL,       -- 业务科室编码
    [dept_name]                         VARCHAR(100)    NOT NULL,       -- 业务科室名称

    -- 3. 金额度量
    [total_performance]                 DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 科室绩效总额（线下核定）
    [distributed_amount]                DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 已分配给个人的合计

    -- 4. 辅助度量
    [staff_count]                       INT             NOT NULL DEFAULT 0,     -- 参与分配人数

    -- 5. 审计与备注
    [remark]                            VARCHAR(1000)   NULL,                        -- 备注
    [create_time]                       DATETIME        NOT NULL CONSTRAINT df_ads_dept_monthly_performance_m_create_time DEFAULT (GETDATE()),  -- 创建时间

    -- 6. 联合主键：同一账期内单个业务科室仅存在一条绩效记录
    CONSTRAINT pk_ads_dept_monthly_performance_m PRIMARY KEY CLUSTERED (
        [year],
        [month],
        [dept_code]
    )
);

-- 索引：按账期批量取数、按科室纵向追溯
CREATE INDEX ix_ads_dept_monthly_performance_m_period
    ON [dbo].[ads_dept_monthly_performance_m] ([year], [month]);

CREATE INDEX ix_ads_dept_monthly_performance_m_dept
    ON [dbo].[ads_dept_monthly_performance_m] ([dept_code], [year], [month]);

-- 注入表级扩展属性注释
EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'【业务科室月度绩效金额表（大连市皮肤病医院专用·线下发放口径）】：主体为业务科室（如治疗科），粒度 科室 × 账期；承载月度科室绩效总额、已分配合计与参与人数。个人绩效按核算单元记录，两者经 dim_unit_dept_relation 汇总关联；不含职系字段（职系属核算单元属性）。',
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
    @name = N'MS_Description', @value = N'业务科室编码（T_DEPARTMENT 中 CODE 以 UNIT 开头的科室行）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'dept_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'业务科室名称',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'dept_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'科室绩效总额（线下核定口径）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_dept_monthly_performance_m',
    @level2type = N'COLUMN', @level2name = N'total_performance';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'已分配给个人的合计金额（经 dim_unit_dept_relation 汇总个人绩效表回算）',
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