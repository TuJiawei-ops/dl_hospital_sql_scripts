-- =================================================================
-- 表名：DWD_FIN_CALC_DETAIL_LOG
-- 分层：DWD（明细层）
-- 业务定义：绩效一次二次分配核算明细统一持久化日志表
-- 架构：EAV-Hybrid（极简公共维度列化 + 全量无损 JSON 过程仓）
-- 唯一键：CALC_YEAR + CALC_MONTH + ITEM_CODE + UNIT_CODE + STAFF_CODE + POST_CODE
-- 修改日志：
-- 2026-08-17 21:45:00 | 架构升级 | 创建 EAV-Hybrid 统一持久化明细日志表 DDL
-- 2026-08-17 22:10:00 | 架构瘦身 | 剔除物理过程列，中间因子全量收敛至 CALC_DETAIL_JSON
-- 2026-08-17 22:45:00 | 规范纠偏 | 引入 ITEM_CODE/ITEM_NAME 标准核算项维度，将 SCRIPT_NAME 降级为运维审计字段，重构唯一索引
-- =================================================================

IF OBJECT_ID('[dbo].[DWD_FIN_CALC_DETAIL_LOG]', 'U') IS NOT NULL
BEGIN
    DROP TABLE [dbo].[DWD_FIN_CALC_DETAIL_LOG];
END;
GO

CREATE TABLE [dbo].[DWD_FIN_CALC_DETAIL_LOG] (
    -- 代理主键
    [ID]                    BIGINT IDENTITY(1,1) NOT NULL,
    -- ===== 账期维度 =====
    [CALC_YEAR]             INT                 NOT NULL,   -- 核算年份
    [CALC_MONTH]            INT                 NOT NULL,   -- 核算月份
    -- ===== 核算项维度 =====
    [ITEM_CODE]             NVARCHAR(50)        NOT NULL,   -- 核算项编码（业务唯一标识，如 ITEM_ENG_MIL_PERF）
    [ITEM_NAME]             NVARCHAR(200)       NULL,       -- 核算项名称（如 '医学工程科军文员工绩效核算'）
    [SCRIPT_NAME]           NVARCHAR(200)       NULL,       -- 执行脚本/算子名称（运维追溯源文件名）
    -- ===== 核算单元维度 =====
    [UNIT_CODE]             NVARCHAR(50)        NOT NULL,   -- 核算单元编码（DEPT_CODE）
    [UNIT_NAME]             NVARCHAR(200)       NULL,       -- 核算单元名称
    -- ===== 员工维度 =====
    [STAFF_CODE]            NVARCHAR(50)        NOT NULL,   -- 员工编码
    [STAFF_NAME]            NVARCHAR(100)       NULL,       -- 员工姓名
    [STAFF_TYPE]            NVARCHAR(20)        NULL,       -- 人员身份（军文/聘用/文职）
    -- ===== 岗位维度 =====
    [POST_CODE]             NVARCHAR(50)        NOT NULL CONSTRAINT [DF_DWD_FIN_CALC_DETAIL_LOG_POST_CODE] DEFAULT ('N/A'), -- 岗位编码（防 NULL 碰撞，默认 N/A）
    [POST_NAME]             NVARCHAR(100)       NULL,       -- 岗位名称
    -- ===== 最终值与审计 =====
    [FINAL_VALUE]           DECIMAL(18,8)       NOT NULL,   -- 最终分配金额/最终积分（result_value 语义）
    [CALC_PROCESS_TEXT]     NVARCHAR(MAX)       NULL,       -- 计算过程描述（三段式/四段式审计文本）
    -- ===== JSON 过程仓（所有系数/出勤/得分/因子全量打包）=====
    [CALC_DETAIL_JSON]      NVARCHAR(MAX)       NULL,       -- FOR JSON PATH 序列化全量过程因子
    -- ===== 审计字段 =====
    [CREATE_TIME]           DATETIME2(3)        NOT NULL
        CONSTRAINT [DF_DWD_FIN_CALC_DETAIL_LOG_CREATE_TIME] DEFAULT (SYSDATETIME()),
    -- 主键
    CONSTRAINT [PK_DWD_FIN_CALC_DETAIL_LOG] PRIMARY KEY CLUSTERED ([ID] ASC),
    -- 业务唯一键（基于 ITEM_CODE 锁死幂等重跑与防重锚点）
    CONSTRAINT [UQ_DWD_FIN_CALC_DETAIL_LOG_BIZ]
        UNIQUE NONCLUSTERED ([CALC_YEAR] ASC, [CALC_MONTH] ASC, [ITEM_CODE] ASC, [UNIT_CODE] ASC, [STAFF_CODE] ASC, [POST_CODE] ASC)
);
GO

-- 账期 + 核算项检索索引
CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_DETAIL_LOG_ACCT]
    ON [dbo].[DWD_FIN_CALC_DETAIL_LOG] ([CALC_YEAR] ASC, [CALC_MONTH] ASC, [ITEM_CODE] ASC);
GO

-- 单位 + 人员检索索引
CREATE NONCLUSTERED INDEX [IX_DWD_FIN_CALC_DETAIL_LOG_STAFF]
    ON [dbo].[DWD_FIN_CALC_DETAIL_LOG] ([UNIT_CODE] ASC, [STAFF_CODE] ASC);
GO

-- =================================================================
-- 扩展属性：表级与字段级注释
-- =================================================================

EXEC sp_addextendedproperty 
    @name = N'MS_Description', @value = N'绩效一次二次分配核算明细统一持久化日志表（EAV-Hybrid 架构：公共维度列化 + JSON 过程仓）',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'DWD_FIN_CALC_DETAIL_LOG';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'自增代理主键',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ID';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份（如 2026）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_YEAR';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份（如 8）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_MONTH';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算项编码（唯一业务标识，如 ITEM_ENG_MIL_PERF）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_CODE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算项名称（如 医学工程科军文员工绩效核算）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'ITEM_NAME';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算脚本/算子名称（用于技术运维排查源代码文件）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'SCRIPT_NAME';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码（DEPT_CODE）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'UNIT_CODE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'UNIT_NAME';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工编码',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'STAFF_CODE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'员工姓名',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'STAFF_NAME';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'人员身份类型（如：军文/聘用/文职）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'STAFF_TYPE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'岗位编码（默认 N/A，防 NULL 碰撞）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'POST_CODE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'岗位名称',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'POST_NAME';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'最终分配金额或最终核算积分（最终结算结果）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'FINAL_VALUE';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'计算过程人类可读描述文本（审计穿透与前端明细弹窗）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_PROCESS_TEXT';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'JSON 过程仓（包含岗位系数/出勤率/考核得分/资金池等全量中间计算因子）',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CALC_DETAIL_JSON';
GO

EXEC sp_addextendedproperty @name = N'MS_Description', @value = N'记录落库生成时间',
    @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'DWD_FIN_CALC_DETAIL_LOG', @level2type = N'COLUMN', @level2name = N'CREATE_TIME';
GO
