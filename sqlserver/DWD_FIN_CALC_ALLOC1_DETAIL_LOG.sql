-- =================================================================
-- 表名：DWD_FIN_CALC_ALLOC1_DETAIL_LOG
-- 分层：DWD（明细层）
-- 业务定义：绩效一次分配（核算单元 × 项目/指标粒度）核算明细持久化日志表
-- 架构：EAV-Hybrid（公共维度列化 + 全量 JSON 过程仓）
-- 唯一键：CALC_YEAR + CALC_MONTH + ITEM_CODE + UNIT_CODE + PROJ_CODE + EXEC_ROLE + STAFF_CODE + DAY_TYPE_CODE
-- 解耦说明：与二次分配表 DWD_FIN_CALC_DETAIL_LOG 物理解耦。
--           本表剥离 STAFF_TYPE / POST_CODE / POST_NAME，
--           显式承载一次分配命脉列 PROJ_CODE / PROJ_NAME / ITEM_CAT_CODE / ITEM_CAT_NAME
--           及执行归因列 STAFF_CODE / STAFF_NAME（员工）与 DAY_TYPE_CODE / DAY_TYPE_NAME（日期类型）；
--           原表 DWD_FIN_CALC_DETAIL_LOG 退守二次分配（核算单元 × 员工 × 岗位）粒度。
-- 修改日志：
-- 2026-09-18 12:35:00 | 字段微调 | 新增 [RVU_VAL] DECIMAL(18,8) NULL 物理列（单项绩效点数快照列）：列位插入于 [ITEM_CAT_NAME] 之后、[EXEC_ROLE] 之前，保持「项目大类 ➔ 单项点数 ➔ 执行归因」的自然血缘流向；提升一次分配列化核对体验，避免前端与 BI 频繁解析 JSON 仓提取基础 RVU 点值；同步追加列级 MS_Description 扩展属性注释。8 维 UQ 唯一键、4 条检索索引、主键约束与其余物理列零改动。
-- 2026-09-16 | 维度扩展 | 追加 STAFF_CODE / STAFF_NAME 与 DAY_TYPE_CODE / DAY_TYPE_NAME 维度物理列，设置默认值 NONE 并将 UQ 扩展为 8 维唯一键。
-- 2026-09-12 22:50:00 | 字段扩展 | 新增 [TOTAL_QTY] DECIMAL(18,8) NULL 物理列（汇总工作量/数量·工分制第一性核对列）：将"工作量/工分"一等公民化，
--                                      使前端与 BI 无需解析 CALC_DETAIL_JSON 即可直接 SUM(TOTAL_QTY) 完成 工作量 × 点值 业务对账；
--                                      同步追加对应字段级扩展属性注释，JSON 过程仓继续承载全量计算链路上下文（列化核对 + JSON 穿透双轨并存）。
-- 2026-09-12 22:10:00 | 架构解耦 | 创建一次分配专用物理表 DDL：剥离人员/岗位杂质列，显式露出 PROJ_CODE/PROJ_NAME/ITEM_CAT_CODE/ITEM_CAT_NAME 项目维度；
--                                      唯一键绑定 (CALC_YEAR, CALC_MONTH, ITEM_CODE, UNIT_CODE, PROJ_CODE)；新增 FINAL_VALUE_TYPE 值类型标识列（SCORE/AMOUNT/INDEX）防口径歧义；
--                                      纠偏草稿 GO 批处理违规为单批分号执行；索引创建增加幂等守卫；
--                                      编码列宽度按源物理类型对齐（PROJ_CODE←PF临时医疗服务项目26A.[项目代码] VARCHAR2(60)、ITEM_CAT_CODE←DIM_PRF_ITEM_RVU_VERSION.ITEM_CAT_CODE、UNIT_CODE←sjjk_DEPT_UNIT_MAPPING.HPS_DEPT_CODE）。
-- =================================================================

IF OBJECT_ID('[dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]', 'U') IS NOT NULL
    DROP TABLE [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG];

CREATE TABLE [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (
    -- 代理主键
    [ID]                    BIGINT IDENTITY(1,1) NOT NULL,
    -- ===== 账期维度 =====
    [CALC_YEAR]             INT                 NOT NULL,   -- 核算年份
    [CALC_MONTH]            INT                 NOT NULL,   -- 核算月份
    -- ===== 核算项维度 =====
    [ITEM_CODE]             NVARCHAR(50)        NOT NULL,   -- 核算项编码（如 ITEM_MED_SVC_ORDER_SCORE）
    [ITEM_NAME]             NVARCHAR(200)       NULL,       -- 核算项名称（如 '医疗服务项目开单积分'）
    [SCRIPT_NAME]           NVARCHAR(200)       NULL,       -- 执行脚本/算子名称（运维追溯源文件名）
    -- ===== 核算单元维度 =====
    [UNIT_CODE]             NVARCHAR(100)       NOT NULL,   -- 核算单元编码（HPS_DEPT_CODE，未映射兜底 'UNKNOWN'）
    [UNIT_NAME]             NVARCHAR(200)       NULL,       -- 核算单元名称（HPS_DEPT_NAME）
    -- ===== 项目/指标维度（一次分配核心列） =====
    [PROJ_CODE]             NVARCHAR(60)        NOT NULL,   -- 医疗项目/考核指标编码（一次分配核心粒度，防 NULL 碰撞）
    [PROJ_NAME]             NVARCHAR(600)       NULL,       -- 医疗项目/考核指标名称
    [ITEM_CAT_CODE]         NVARCHAR(60)        NULL,       -- 绩效核算大类代码（如 1101/1041 等）
    [ITEM_CAT_NAME]         NVARCHAR(200)       NULL,       -- 绩效核算大类名称
    [RVU_VAL]               DECIMAL(18,8)       NULL,       -- 单项绩效点数/RVU点值（物理属性快照列，便于前端直拉对比，非主键）
    -- ===== 执行角色维度 =====
    [EXEC_ROLE]             NVARCHAR(20)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_EXEC_ROLE] DEFAULT (N'NONE'), -- 执行角色（医生/技师/护士，非角色切分项默认 'NONE'）
    -- ===== 执行员工维度（一次分配执行归因 + 明细检索锚点） =====
    [STAFF_CODE]            NVARCHAR(50)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_STAFF_CODE] DEFAULT (N'NONE'), -- 员工编码（非人员粒度核算项默认 'NONE'）
    [STAFF_NAME]            NVARCHAR(100)       NULL,       -- 员工姓名
    -- ===== 日期类型维度（工作日历投影） =====
    [DAY_TYPE_CODE]         NVARCHAR(30)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_DAY_TYPE_CODE] DEFAULT (N'NONE'), -- 日期类型编码（工作日/节假日等，非日历粒度核算项默认 'NONE'）
    [DAY_TYPE_NAME]         NVARCHAR(50)        NULL,       -- 日期类型名称
    -- ===== 最终值与审计 =====
    [FINAL_VALUE_TYPE]      NVARCHAR(20)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_VALUE_TYPE] DEFAULT (N'SCORE'), -- 最终值口径：SCORE 积分 / AMOUNT 金额 / INDEX 指数
    [FINAL_VALUE]           DECIMAL(18,8)       NOT NULL,   -- 最终项目积分/分配金额（result_value 语义）
    [TOTAL_QTY]             DECIMAL(18,8)       NULL,       -- 汇总工作量/数量（工分制第一性核对列）
    [CALC_PROCESS_TEXT]     NVARCHAR(MAX)       NULL,       -- 计算过程描述（三段式/四段式审计文本）
    -- ===== JSON 过程仓（单项RVU、决策系数、原始数量、费别等全量打包）=====
    [CALC_DETAIL_JSON]      NVARCHAR(MAX)       NULL,       -- FOR JSON PATH 序列化全量过程因子
    -- ===== 审计字段 =====
    [CREATE_TIME]           DATETIME2(3)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_CREATE_TIME] DEFAULT (SYSDATETIME()),
    -- 主键
    CONSTRAINT [PK_DWD_FIN_CALC_ALLOC1_DETAIL_LOG] PRIMARY KEY CLUSTERED ([ID] ASC),
    -- 一次分配业务唯一键（基于 核算单元 + 项目 + 执行角色 + 员工 + 日期类型 锁死幂等重跑与防重锚点）
    CONSTRAINT [UQ_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_BIZ]
        UNIQUE NONCLUSTERED ([CALC_YEAR] ASC, [CALC_MONTH] ASC, [ITEM_CODE] ASC, [UNIT_CODE] ASC, [PROJ_CODE] ASC, [EXEC_ROLE] ASC, [STAFF_CODE] ASC, [DAY_TYPE_CODE] ASC)
);

-- 账期 + 核算项检索索引
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_ACCT' AND [object_id] = OBJECT_ID(N'[dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]'))
    CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_ACCT]
        ON [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] ([CALC_YEAR] ASC, [CALC_MONTH] ASC, [ITEM_CODE] ASC);

-- 核算单元 + 项目检索索引（一次分配命脉查询路径）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_PROJ' AND [object_id] = OBJECT_ID(N'[dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]'))
    CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_PROJ]
        ON [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] ([UNIT_CODE] ASC, [PROJ_CODE] ASC);

-- 绩效核算大类检索索引（按大类下钻）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_CAT' AND [object_id] = OBJECT_ID(N'[dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]'))
    CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_CAT]
        ON [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] ([ITEM_CAT_CODE] ASC);

-- 员工 + 日期类型检索索引（按执行人员与日历类型下钻加速）
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE [name] = N'IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_STAFF' AND [object_id] = OBJECT_ID(N'[dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG]'))
    CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_ALLOC1_DETAIL_LOG_STAFF]
        ON [dbo].[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] ([STAFF_CODE] ASC, [DAY_TYPE_CODE] ASC);

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty
    @name = N'MS_Description', @value = N'绩效一次分配（核算单元 × 项目/指标粒度）核算明细持久化日志表（EAV-Hybrid 架构：公共维度列化 + JSON 过程仓）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'自增代理主键',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ID';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_YEAR';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_MONTH';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算项编码（唯一业务标识，如 ITEM_MED_SVC_ORDER_SCORE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算项名称（如 医疗服务项目开单积分）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算脚本/算子名称（用于技术运维排查源代码文件）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'SCRIPT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码（HPS_DEPT_CODE，未映射兜底 UNKNOWN）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'UNIT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称（HPS_DEPT_NAME）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'UNIT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'医疗项目/考核指标编码（一次分配核心粒度，物理 NOT NULL，防 NULL 碰撞）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'PROJ_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'医疗项目/考核指标名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'PROJ_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'绩效核算大类代码（如 1101 出入院服务类 / 1041 诊察类）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_CAT_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'绩效核算大类名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_CAT_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'执行角色（医生/技师/护士，非角色切分核算项默认 NONE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'EXEC_ROLE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'执行员工编码（一次分配执行归因与人员明细检索锚点，非人员粒度核算项默认 NONE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'STAFF_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'执行员工姓名',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'STAFF_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'日期类型编码（工作日历投影，如 WORKDAY/HOLIDAY，非日历粒度核算项默认 NONE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'DAY_TYPE_CODE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'日期类型名称（如 正常工作日/节假日）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'DAY_TYPE_NAME';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'最终值口径：SCORE 积分 / AMOUNT 金额 / INDEX 指数（防口径歧义）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'FINAL_VALUE_TYPE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'最终项目积分或分配金额（最终结算结果，result_value 语义）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'FINAL_VALUE';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'汇总工作量/数量（工分制第一性核对列，前端与 BI 可直接 SUM 做业务对账，无需解析 JSON）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'TOTAL_QTY';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'单项绩效点数/RVU点值（物理属性快照列，便于前端直拉对比，非主键）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'RVU_VAL';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'计算过程人类可读描述文本（审计穿透与前端明细弹窗）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_PROCESS_TEXT';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'JSON 过程仓（包含单项RVU点数/诊疗决策系数/汇总数量/单价/费别等全量中间计算因子）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_DETAIL_JSON';

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'记录落库生成时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_ALLOC1_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CREATE_TIME';


