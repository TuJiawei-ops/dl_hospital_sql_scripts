-- =================================================================
-- 表实体创建：dim_perf_pool（统筹池定义表）
-- 业务定义：绩效统筹分配的"池"（如护理部、医技部、院级留存）
-- Relative Path : sqlserver/DIM_PERF_POOL.sql
-- =================================================================
-- 设计说明
--   1. 统筹分配 = 科室 → 池（划转/提取）→ 池 → 科室（再分配）。
--      池是"中间账户"，可对应职能部门，也可对应院级留存。
--   2. 池不参与核算单元口径，独立建表，不占用 T_DEPARTMENT。
--   3. 金额明细见 fact_perf_transfer，本表只存池定义。
-- =================================================================
-- 修改日志
-- 2026-11-18 00:00:00 | 初始建表 | 建立统筹池定义表，含启用状态与备注。
-- =================================================================

IF OBJECT_ID(N'[dbo].[dim_perf_pool]', N'U') IS NOT NULL
    DROP TABLE [dbo].[dim_perf_pool];

CREATE TABLE [dbo].[dim_perf_pool] (
    [id]            BIGINT          IDENTITY(1, 1) NOT NULL,   -- 主键
    [pool_code]     VARCHAR(50)     NOT NULL,                  -- 池编码，如 POOL_NURSE
    [pool_name]     VARCHAR(100)    NOT NULL,                  -- 池名称，如 护理部
    [pool_type]     VARCHAR(20)     NULL,                      -- 类型：职能部门/院级留存（仅描述）
    [enabled]       INT             NOT NULL DEFAULT 1,        -- 1启用 0停用
    [remark]        VARCHAR(500)    NULL,                      -- 备注
    [create_time]   DATETIME        NOT NULL DEFAULT (GETDATE()), -- 创建时间

    CONSTRAINT pk_dim_perf_pool PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT uq_dim_perf_pool_code UNIQUE ([pool_code])
);

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'【统筹池定义表】：绩效统筹分配的中间账户（护理部/医技部/院级留存等）；与 fact_perf_transfer 配合完成"科室→池→科室"的额度划转与再分配。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_perf_pool';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'池编码（唯一）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_perf_pool',
    @level2type = N'COLUMN', @level2name = N'pool_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'池名称',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_perf_pool',
    @level2type = N'COLUMN', @level2name = N'pool_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'池类型（职能部门/院级留存，仅描述）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_perf_pool',
    @level2type = N'COLUMN', @level2name = N'pool_type';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'启用状态：1启用 0停用',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'dim_perf_pool',
    @level2type = N'COLUMN', @level2name = N'enabled';
