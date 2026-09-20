-- =================================================================
-- 表名：DIM_DEPT_ITEM_EXEC_RATIO
-- 分层：DIM（维度层）
-- 业务定义：各科室收费项目医技护临执行划分维表（HIS 科室 × 收费项目 → 医生/技师/护士/临床 执行比例切分）
-- 主键策略：物理代理主键 [ID] BIGINT IDENTITY(1,1) 单列聚簇，保证主键轻量、行级唯一寻址与主从同步稳定；
--           业务唯一性通过 IS_ENABLED = 1 过滤唯一索引在逻辑层强制约束（启用态下 (HIS_DEPT_CODE, ITEM_CODE) 唯一）。
-- 架构说明：不采用 (HIS_DEPT_CODE, ITEM_CODE) 纯复合主键——版本变更或停用重建时复合主键会阻塞历史废弃行保留；
--           亦不引入 (…, VERSION_NO) 复合主键——徒增外键关联与 ORM 映射复杂度，版本变更仅由 VERSION_NO 记录留痕。
-- 精度规范：四类执行比例物理精度锁死 DECIMAL(18,8)，默认 0.00000000 兜底；
--           编码类字段（HIS_DEPT_CODE / ITEM_CODE / DOC_HPS_DEPT_CODE / TECH_HPS_DEPT_CODE / NURSE_HPS_DEPT_CODE / CLINICAL_HPS_DEPT_CODE）全量 VARCHAR 字符串语义，严禁 CAST 为数值型防前导零丢失。
-- 索引策略：唯一性由 IS_ENABLED = 1 过滤唯一索引在逻辑层强制约束；检索路径另设项目维度索引与医技护临四元联合索引。
-- 修改日志：
-- 2026-09-20 14:30:00 | 角色扩展 | 在医技护三类执行角色基础上追加第四类【临床】执行角色（Slot 扩充模式，单行记录内部直接扩充列，
--                                    严格维持 (HIS_DEPT_CODE, ITEM_CODE) 在 IS_ENABLED = 1 时的单行唯一映射架构，零破坏存量 UQ 索引策略）：
--                                    【医技护执行比例】块 NURSE_EXEC_RATIO 之后追加 [CLINICAL_EXEC_RATIO] DECIMAL(18,8) NOT NULL
--                                    CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_CLINICAL] DEFAULT (0.00000000)（临床执行比例，用于不区分医护的通用/科室整体核算单元）；
--                                    【医技护核算单元映射】块 NURSE_HPS_DEPT_NAME 之后追加 [CLINICAL_HPS_DEPT_CODE] VARCHAR(60) NULL
--                                    与 [CLINICAL_HPS_DEPT_NAME] NVARCHAR(300) NULL 两列（临床对应核算单元编码/名称，编码列强制字符串语义）；
--                                    索引 [IX_DIM_DEPT_ITEM_EXEC_RATIO_HPS] 由三元联合升级为四元联合检索索引
--                                    (DOC_HPS_DEPT_CODE, TECH_HPS_DEPT_CODE, NURSE_HPS_DEPT_CODE, CLINICAL_HPS_DEPT_CODE)；
--                                    追加 3 个字段级扩展属性注释，并同步更新表级注释、头部精度规范编码字段枚举与索引策略说明。
-- 2026-09-14 03:00:00 | 结构重构 | 执行比例列聚合与医技护核算单元列集中重构：
--                                    移除原单列 [HPS_DEPT_CODE] / [HPS_DEPT_NAME]（单一核算单元兜底映射），
--                                    按医技护三类执行角色展开为 6 个独立核算单元映射列
--                                    （DOC_HPS_DEPT_CODE/NAME、TECH_HPS_DEPT_CODE/NAME、NURSE_HPS_DEPT_CODE/NAME）；
--                                    结构遵循高内聚原则划分为【执行比例块】与【医技护核算单元映射块】两个连续物理逻辑块，
--                                    分别保持数值计算域与维度关联域的物理连续性，便于 ORM 实体类映射与 SELECT 提取可读性；
--                                    索引 [IX_DIM_DEPT_ITEM_EXEC_RATIO_HPS] 同步升级为 (DOC_HPS_DEPT_CODE, TECH_HPS_DEPT_CODE, NURSE_HPS_DEPT_CODE) 三编码联合检索索引；
--                                    追加 6 个字段级扩展属性注释，并同步更新头部编码字段枚举与表级注释。
-- 2026-09-14 02:00:00 | 字段扩展 | 业务时间与留痕区域新增 [DISABLE_DATE] DATETIME NULL 停用日期列（置于 [ITEM_ADD_DATE] 之后），
--                                    补齐 SCD Type 2 版本保留模型的生效区间右端点，使 (PROVIDE_DATE → DISABLE_DATE) 构成完整业务生效区间；
--                                    纠偏仅凭 IS_ENABLED + UPDATE_TIME 的半失真停用标记：避免运维侧对废弃行做任何更新（如改备注）
--                                    覆盖 UPDATE_TIME 后，历史核算周期回溯无法判定规则真实停用日期；
--                                    追加字段级扩展属性注释，并同步更新表级与 IS_ENABLED 字段注释的生效区间语义说明。
-- 2026-09-14 01:00:00 | 字段扩展 | 核算单元映射区域新增 [HPS_DEPT_CODE] VARCHAR(60) NULL 编码列（置于 [HPS_DEPT_NAME] 之前），
--                                    表示对应核算单元编码，遵循第 7.1 节编码字段强制字符串规范（严禁 CAST 为数值型防前导零丢失）；
--                                    原 HPS_DEPT_NAME 单列检索索引升级为 (HPS_DEPT_CODE, HPS_DEPT_NAME) 联合检索索引并同步更名，
--                                    追加字段级扩展属性注释与表级索引策略说明。
-- 2026-09-14 00:00:00 | 脚本新建 | 创建各科室收费项目医技护执行划分维表 DDL；保留 ID 自增代理主键，
--                                    创建 (HIS_DEPT_CODE, ITEM_CODE) 在 IS_ENABLED = 1 时的过滤唯一索引；
--                                    数据编码全量 VARCHAR 语义，比例物理精度锁死 DECIMAL(18,8)；
--                                    全局禁 GO 协议、单批分号结束、索引创建幂等守卫、补全表级与字段级扩展属性注释。
-- =================================================================

IF OBJECT_ID('[dbo].[DIM_DEPT_ITEM_EXEC_RATIO]', 'U') IS NOT NULL
    DROP TABLE [dbo].[DIM_DEPT_ITEM_EXEC_RATIO];

CREATE TABLE [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] (
    -- 物理代理主键
    [ID]                    BIGINT IDENTITY(1,1) NOT NULL,   -- 自增代理主键（物理唯一寻址）
    -- ===== HIS 科室维度 =====
    [HIS_DEPT_CODE]         VARCHAR(60)         NOT NULL,   -- HIS 科室编码（字符串语义，防前导零丢失）
    [HIS_DEPT_NAME]         NVARCHAR(300)       NULL,       -- HIS 科室名称
    -- ===== 收费项目维度 =====
    [ITEM_CODE]             VARCHAR(60)         NOT NULL,   -- 收费项目编码（字符串语义，防前导零丢失）
    [ITEM_NAME]             NVARCHAR(600)       NULL,       -- 收费项目名称
    [HIS_CAT_NAME]          NVARCHAR(300)       NULL,       -- HIS 类别名称
    -- ===== 医技护执行比例 =====
    [DOC_EXEC_RATIO]        DECIMAL(18,8)       NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_DOC]   DEFAULT (0.00000000), -- 医生执行比例
    [TECH_EXEC_RATIO]       DECIMAL(18,8)       NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_TECH]  DEFAULT (0.00000000), -- 技师执行比例
    [NURSE_EXEC_RATIO]      DECIMAL(18,8)       NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_NURSE] DEFAULT (0.00000000), -- 护士执行比例
    [CLINICAL_EXEC_RATIO]   DECIMAL(18,8)       NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_CLINICAL] DEFAULT (0.00000000), -- 临床执行比例（不区分医护的通用/科室整体核算单元）
    -- ===== 医技护核算单元映射 =====
    [DOC_HPS_DEPT_CODE]     VARCHAR(60)         NULL,       -- 医生对应核算单元编码（字符串语义，防前导零丢失）
    [DOC_HPS_DEPT_NAME]     NVARCHAR(300)       NULL,       -- 医生对应核算单元名称
    [TECH_HPS_DEPT_CODE]    VARCHAR(60)         NULL,       -- 技师对应核算单元编码（字符串语义，防前导零丢失）
    [TECH_HPS_DEPT_NAME]    NVARCHAR(300)       NULL,       -- 技师对应核算单元名称
    [NURSE_HPS_DEPT_CODE]   VARCHAR(60)         NULL,       -- 护士对应核算单元编码（字符串语义，防前导零丢失）
    [NURSE_HPS_DEPT_NAME]   NVARCHAR(300)       NULL,       -- 护士对应核算单元名称
    [CLINICAL_HPS_DEPT_CODE] VARCHAR(60)        NULL,       -- 临床对应核算单元编码（字符串语义，防前导零丢失）
    [CLINICAL_HPS_DEPT_NAME] NVARCHAR(300)      NULL,       -- 临床对应核算单元名称
    -- ===== 业务时间与留痕 =====
    [PROVIDE_DATE]          DATETIME            NULL,       -- 提供日期
    [ITEM_ADD_DATE]         DATETIME            NULL,       -- 项目新增日期
    [DISABLE_DATE]          DATETIME            NULL,       -- 停用日期（规则被标记为停用时的业务终止时间）
    [REMARK]                NVARCHAR(1000)      NULL,       -- 备注
    [VERSION_NO]            INT                 NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_VER]   DEFAULT (1),          -- 版本号（仅做记录，不参与主键寻址）
    [IS_ENABLED]            TINYINT             NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_EN]    DEFAULT (1),          -- 是否启用（1:启用, 0:停用）
    -- ===== 审计字段 =====
    [CREATE_TIME]           DATETIME2           NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_CT]    DEFAULT (SYSDATETIME()), -- 创建时间
    [UPDATE_TIME]           DATETIME2           NOT NULL
        CONSTRAINT [DF_DIM_DEPT_ITEM_EXEC_RATIO_UT]    DEFAULT (SYSDATETIME()), -- 更新时间
    -- 物理主键（单列自增聚簇，主键轻量）
    CONSTRAINT [PK_DIM_DEPT_ITEM_EXEC_RATIO] PRIMARY KEY CLUSTERED ([ID] ASC)
);

-- 启用状态下的业务逻辑唯一索引（过滤唯一索引，防重复配置；停用历史行不参与唯一性校验，可保留废弃数据）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'UQ_DIM_DEPT_ITEM_EXEC_RATIO_ACTIVE' AND [object_id] = OBJECT_ID(N'[dbo].[DIM_DEPT_ITEM_EXEC_RATIO]'))
    CREATE UNIQUE NONCLUSTERED INDEX [UQ_DIM_DEPT_ITEM_EXEC_RATIO_ACTIVE]
        ON [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] ([HIS_DEPT_CODE] ASC, [ITEM_CODE] ASC)
        WHERE [IS_ENABLED] = 1;

-- 停用历史行追溯检索索引（版本/停用留痕查询路径）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DIM_DEPT_ITEM_EXEC_RATIO_ITEM' AND [object_id] = OBJECT_ID(N'[dbo].[DIM_DEPT_ITEM_EXEC_RATIO]'))
    CREATE NONCLUSTERED INDEX [IX_DIM_DEPT_ITEM_EXEC_RATIO_ITEM]
        ON [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] ([ITEM_CODE] ASC, [IS_ENABLED] ASC);

-- 医技护临核算单元映射检索索引（按 医生/技师/护士/临床 四路核算单元编码 下钻）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DIM_DEPT_ITEM_EXEC_RATIO_HPS' AND [object_id] = OBJECT_ID(N'[dbo].[DIM_DEPT_ITEM_EXEC_RATIO]'))
    CREATE NONCLUSTERED INDEX [IX_DIM_DEPT_ITEM_EXEC_RATIO_HPS]
        ON [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] ([DOC_HPS_DEPT_CODE] ASC, [TECH_HPS_DEPT_CODE] ASC, [NURSE_HPS_DEPT_CODE] ASC, [CLINICAL_HPS_DEPT_CODE] ASC);

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty
    @name = N'MS_Description', @value = N'各科室收费项目医技护临执行划分维表（HIS 科室 × 收费项目 → 医生/技师/护士/临床 四类执行角色比例切分及对应核算单元映射）。采用 Slot 扩充模式：单行记录内部直接扩充角色列组，严格维持 (HIS_DEPT_CODE, ITEM_CODE) 在 IS_ENABLED = 1 时的单行唯一映射架构；【临床】角色用于不区分医护的通用/科室整体核算单元。主键为 ID 自增代理列，业务唯一性由 IS_ENABLED = 1 过滤唯一索引在逻辑层强制约束。业务生效区间由 PROVIDE_DATE → DISABLE_DATE 表达（SCD Type 2 版本保留模型），IS_ENABLED 为该区间的当前逻辑状态投影。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'自增代理主键（BIGINT IDENTITY，物理单列聚簇唯一寻址）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'ID';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'HIS 科室编码（字符串语义，严禁 CAST 为数值型防前导零丢失）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'HIS_DEPT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'HIS 科室名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'HIS_DEPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'收费项目编码（字符串语义，严禁 CAST 为数值型防前导零丢失）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'ITEM_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'收费项目名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'ITEM_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'HIS 类别名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'HIS_CAT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'医生执行比例（DECIMAL(18,8)，未配置默认 0.00000000）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'DOC_EXEC_RATIO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'技师执行比例（DECIMAL(18,8)，未配置默认 0.00000000）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'TECH_EXEC_RATIO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'护士执行比例（DECIMAL(18,8)，未配置默认 0.00000000）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'NURSE_EXEC_RATIO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'临床执行比例（DECIMAL(18,8)，未配置默认 0.00000000；用于不区分医护的通用/科室整体核算单元，与医技护三类角色并列切分）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'CLINICAL_EXEC_RATIO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'医生对应核算单元编码（字符串语义，严禁 CAST 为数值型防前导零丢失；未映射兜底 NULL）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'DOC_HPS_DEPT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'医生对应核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'DOC_HPS_DEPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'技师对应核算单元编码（字符串语义，严禁 CAST 为数值型防前导零丢失；未映射兜底 NULL）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'TECH_HPS_DEPT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'技师对应核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'TECH_HPS_DEPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'护士对应核算单元编码（字符串语义，严禁 CAST 为数值型防前导零丢失；未映射兜底 NULL）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'NURSE_HPS_DEPT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'护士对应核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'NURSE_HPS_DEPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'临床对应核算单元编码（字符串语义，严禁 CAST 为数值型防前导零丢失；未映射兜底 NULL；用于不区分医护的通用/科室整体核算单元）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'CLINICAL_HPS_DEPT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'临床对应核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'CLINICAL_HPS_DEPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'提供日期',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'PROVIDE_DATE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'项目新增日期',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'ITEM_ADD_DATE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'停用日期（规则被标记为停用时的业务终止时间，SCD Type 2 生效区间的右端点；启用中为 NULL，与 IS_ENABLED = 0 严格联动）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'DISABLE_DATE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'备注',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'REMARK';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'版本号（仅做记录留痕，不参与主键寻址与物理唯一约束）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'VERSION_NO';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'是否启用（1:启用, 0:停用；当前逻辑状态投影，与 DISABLE_DATE 严格联动：IS_ENABLED = 0 时 DISABLE_DATE 必须非空；仅在 IS_ENABLED = 1 时参与 (HIS_DEPT_CODE, ITEM_CODE) 过滤唯一性校验）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'IS_ENABLED';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'记录创建时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'CREATE_TIME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'记录最后更新时间（由应用层显式维护）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DIM_DEPT_ITEM_EXEC_RATIO', @level2type = N'COLUMN', @level2name = N'UPDATE_TIME';
