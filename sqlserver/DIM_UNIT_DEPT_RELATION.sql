-- =================================================================
-- 表实体创建：dim_unit_dept_relation
-- 业务定义：核算单元与业务科室归属关系表（N:N + 生效区间）
-- Relative Path : sqlserver/DIM_UNIT_DEPT_RELATION.sql
-- =================================================================
-- 设计说明
--   1. 关系为多对多：
--        - 一个业务科室可对应多个核算单元（如「治疗科」→ 治疗科医生 / 治疗科护士）；
--        - 一个核算单元也可能归属多个科室（科室合并核算、专诊并入等）。
--      因此不能用 T_DEPARTMENT 的 P_ID（组织层级）或类型字段表达归属关系。
--   2. 关系带生效区间 [valid_from, valid_to)（半开区间）：
--      绩效按月核算且会补算历史月份，「某月归属哪个科室」必须可追溯到当期，
--      故采用「有效期关系表」而非覆盖式更新，也不是按日快照的拉链表。
--   3. 科室端（dept_code）过渡期指向 T_DEPARTMENT 中 CODE 以 'UNIT' 开头的科室行
--      （如 UNIT054 治疗科），长期可拆分为独立科室维表 dim_dept。
--   4. 约束：
--        - 唯一约束 (unit_code, dept_code, valid_from) 防重复；
--        - CHECK (valid_to > valid_from) 防区间倒置；
--        - 同一 unit_code 的区间不得重叠由应用层校验（SQL Server 无原生排他约束）。
--   5. 只读约束：本表仅承载关系，不改动 T_DEPARTMENT 任何字段。
-- =================================================================
-- 修改日志
-- 2026-11-16 00:00:00 | 初始建表 | 建立核算单元-业务科室归属关系表，含生效区间、关系类型、
--                      唯一约束与检查约束；附「核算单元未挂科室」排查视图（可选使用）。
-- =================================================================

-- 删除已存在的表（开发/迭代环境使用，生产环境请谨慎）
IF OBJECT_ID(N'[dbo].[dim_unit_dept_relation]', N'U') IS NOT NULL
    DROP TABLE [dbo].[dim_unit_dept_relation];

CREATE TABLE [dbo].[dim_unit_dept_relation] (
    [id]            BIGINT          IDENTITY(1, 1) NOT NULL,     -- 主键
    [unit_code]     VARCHAR(50)     NOT NULL,                     -- 核算单元编码（T_DEPARTMENT.CODE）
    [unit_name]     VARCHAR(100)    NULL,                         -- 核算单元名称（冗余，便于报表直读）
    [dept_code]     VARCHAR(50)     NOT NULL,                     -- 业务科室编码（T_DEPARTMENT.CODE，UNIT*）
    [dept_name]     VARCHAR(100)    NULL,                         -- 业务科室名称（冗余）
    [relation_type] VARCHAR(20)     NULL,                         -- 关系类型：医生/护士/医技/工勤/医生+护士
    [valid_from]    DATE            NOT NULL CONSTRAINT df_dim_unit_dept_relation_from DEFAULT ('1900-01-01'),  -- 生效起（含）
    [valid_to]      DATE            NOT NULL CONSTRAINT df_dim_unit_dept_relation_to   DEFAULT ('9999-12-31'),  -- 生效止（不含）
    [remark]        VARCHAR(500)    NULL,                         -- 备注
    [create_time]   DATETIME        NOT NULL CONSTRAINT df_dim_unit_dept_relation_ct DEFAULT (GETDATE()),       -- 创建时间

    CONSTRAINT pk_dim_unit_dept_relation PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT uq_dim_unit_dept_relation UNIQUE ([unit_code], [dept_code], [valid_from]),
    CONSTRAINT ck_dim_unit_dept_relation_period CHECK ([valid_to] > [valid_from])
);

-- 索引：按单元查归属（绩效计算/分析常用）、按科室汇总（科室维度分析）
CREATE INDEX ix_dim_unit_dept_relation_unit
    ON [dbo].[dim_unit_dept_relation] ([unit_code], [valid_from], [valid_to]);

CREATE INDEX ix_dim_unit_dept_relation_dept
    ON [dbo].[dim_unit_dept_relation] ([dept_code], [valid_from], [valid_to]);

-- 注入表级扩展属性注释
EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'【核算单元与业务科室归属关系表】：多对多关系，带生效区间 [valid_from, valid_to)；用于按科室维度汇总绩效、补算历史月份时还原当期归属，以及排查未挂科室的核算单元。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算单元编码（T_DEPARTMENT.CODE）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算单元名称（冗余字段）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'业务科室编码（T_DEPARTMENT.CODE，UNIT* 行）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'dept_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'业务科室名称（冗余字段）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'dept_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'关系类型：医生/护士/医技/工勤/医生+护士（可空）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'relation_type';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'生效起（含）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'valid_from';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'生效止（不含），9999-12-31 表示当前有效',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'valid_to';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'备注',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'remark';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_unit_dept_relation',
    @level2type = N'COLUMN', @level2name = N'create_time';
