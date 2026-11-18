-- =================================================================
-- 表实体创建：fact_perf_transfer（统筹分配明细表）
-- 业务定义：一次分配"基础结果 → 定稿"之间的额度划转与再分配
-- Relative Path : sqlserver/FACT_PERF_TRANSFER.sql
-- =================================================================
-- 设计说明
--   1. 方向：
--        OUT = 科室 → 池（划转/提取，如护理组 50% 上交护理部）
--        IN  = 池 → 科室（再分配，护理部把额度分回科室）
--   2. 金额由业务手工填写（不内置比例规则），"想填多少填多少"，规则化留待后续。
--   3. 最终结果不落新表：
--        最终 = 基础结果(DWD_FIN_CALC_ALLOC1_DETAIL_LOG) − ΣOUT + ΣIN
--      预览用视图 vw_perf_alloc1_final；期间结账时算好写入现有
--      ads_perf_primary_settlement（定稿表，结构不动）。
--   4. 状态：0草稿（可改可删） 1已提交（锁定，结账前可撤回）。
--   5. 结账前置校验：无草稿单 + 每个池 ΣOUT = ΣIN（平账）。
-- =================================================================
-- 修改日志
-- 2026-11-18 00:00:00 | 初始建表 | 建立统筹分配明细表（OUT/IN 双方向），含状态与操作留痕。
-- =================================================================

IF OBJECT_ID(N'[dbo].[fact_perf_transfer]', N'U') IS NOT NULL
    DROP TABLE [dbo].[fact_perf_transfer];

CREATE TABLE [dbo].[fact_perf_transfer] (
    [id]            BIGINT          IDENTITY(1, 1) NOT NULL,   -- 主键
    [calc_year]     INT             NOT NULL,                  -- 核算年份
    [calc_month]    INT             NOT NULL,                  -- 核算月份
    [pool_code]     VARCHAR(50)     NOT NULL,                  -- 统筹池编码（dim_perf_pool）
    [direction]     VARCHAR(4)      NOT NULL,                  -- OUT=科室→池 / IN=池→科室
    [unit_code]     VARCHAR(50)     NOT NULL,                  -- 对方科室编码（OUT=来源，IN=目标）
    [unit_name]     VARCHAR(100)    NULL,                      -- 科室名称（冗余）
    [amount]        DECIMAL(18,2)   NOT NULL,                  -- 金额（手工填写）
    [remark]        VARCHAR(500)    NULL,                      -- 原因/说明
    [status]        INT             NOT NULL DEFAULT 0,        -- 0草稿 1已提交
    [create_user]   BIGINT          NULL,                      -- 创建人
    [create_time]   DATETIME        NOT NULL DEFAULT (GETDATE()), -- 创建时间
    [submit_user]   BIGINT          NULL,                      -- 提交人
    [submit_time]   DATETIME        NULL,                      -- 提交时间

    CONSTRAINT pk_fact_perf_transfer PRIMARY KEY CLUSTERED ([id]),
    CONSTRAINT ck_fact_perf_transfer_direction CHECK ([direction] IN ('OUT', 'IN')),
    CONSTRAINT ck_fact_perf_transfer_amount CHECK ([amount] >= 0)
);

-- 按期间 + 池查询明细（页面主查询）
CREATE INDEX ix_fact_perf_transfer_period
    ON [dbo].[fact_perf_transfer] ([calc_year], [calc_month], [pool_code]);

-- 按科室追溯（审计/对账）
CREATE INDEX ix_fact_perf_transfer_unit
    ON [dbo].[fact_perf_transfer] ([unit_code], [calc_year], [calc_month]);

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description',
    @value = N'【统筹分配明细表】：一次分配基础结果到定稿之间的额度转移；OUT=科室划转到池，IN=池再分配到科室；金额手工填写，提交后锁定，结账前可撤回。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算年份',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'calc_year';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'核算月份',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'calc_month';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'统筹池编码（dim_perf_pool.pool_code）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'pool_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'方向：OUT=科室→池，IN=池→科室',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'direction';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'科室编码（OUT=来源科室，IN=目标科室）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'unit_code';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'科室名称（冗余字段）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'unit_name';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'金额（手工填写，保留两位小数）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'amount';

EXEC sys.sp_addextendedproperty
    @name = N'MS_Description', @value = N'状态：0草稿 1已提交',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'fact_perf_transfer',
    @level2type = N'COLUMN', @level2name = N'status';
