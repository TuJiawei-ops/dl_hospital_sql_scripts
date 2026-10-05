-- =================================================================
-- 表实体创建：ads_emp_monthly_performance_m
-- 业务定义：个人月度绩效金额明细表（绩效奖 / 管理绩效 / 合计绩效 / 固定部分绩效 / 扣除固定部分后绩效）
-- Relative Path : sqlserver/ADS_EMP_MONTHLY_PERFORMANCE_M.sql
-- =================================================================
-- 修改日志
-- 2026-10-05 00:00:00 | 冗余裁剪 | 依据架构职责分离原则（上游参入表 ads_dept_post_coefficient_m 承载考勤/系数，本表作为结果核算表仅承载金额度量），裁剪 [on_duty_days] 与 [is_transferred] 两个考勤过程变量字段及对应列级扩展属性注释，消除双表数据冗余与一致性隐患（溯源时经五元联合主键 LEFT JOIN 上游系数表动态提取）；审计字段区块序号由 7 收敛为 6，联合主键区块序号由 8 收敛为 7。
-- 2026-10-05 00:00:00 | 初始建表 | 参考 ads_dept_post_coefficient_m 结构衍生创建个人月度绩效金额明细表，包含绩效奖、管理绩效、合计绩效、固定部分绩效、扣除固定部分后绩效五项金额度量；五元联合主键 (year, month, unit_code, staff_code, post_code) 支撑跨岗位/跨科室调动拆分；全量 sys.sp_addextendedproperty 表级及列级元数据注释。
-- =================================================================

-- 删除已存在的表（开发/迭代环境使用，生产环境请谨慎）
IF OBJECT_ID(N'[dbo].[ads_emp_monthly_performance_m]', N'U') IS NOT NULL
    DROP TABLE [dbo].[ads_emp_monthly_performance_m];

-- 创建表
CREATE TABLE [dbo].[ads_emp_monthly_performance_m] (
    -- 1. 账期维度
    [year]                              INT             NOT NULL,       -- 核算年份
    [month]                             INT             NOT NULL,       -- 核算月份

    -- 2. 核算单元维度
    [unit_code]                         VARCHAR(50)     NOT NULL,       -- 核算单元编码
    [unit_name]                         VARCHAR(100)    NOT NULL,       -- 核算单元名称

    -- 3. 员工身份维度
    [staff_code]                        VARCHAR(50)     NOT NULL,       -- 员工编码
    [staff_name]                        VARCHAR(100)    NOT NULL,       -- 员工姓名
    [staff_sequence]                    VARCHAR(50)     NOT NULL,       -- 联合切片键：区分 医疗 / 护理
    [series_code]                       VARCHAR(50)     NOT NULL,       -- 所属职系编码
    [series_name]                       VARCHAR(100)    NOT NULL,       -- 所属职系名称

    -- 4. 职务标签（双重锁定：编码驱动系统逻辑，名称还原前端展示）
    [post_code]                         VARCHAR(50)     NOT NULL,       -- 核心防御：岗位物理编码（如 DIR_01, NUR_01）
    [post_name]                         VARCHAR(100)    NOT NULL,       -- 职务标签：科主任、护士长、护理组长、普通医生、普通护士

    -- 5. 绩效金额度量（两位小数）
    [performance_bonus]                 DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 绩效奖
    [management_performance]            DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 管理绩效
    [total_performance]                 DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 合计绩效
    [fixed_performance]                 DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 固定部分绩效
    [performance_after_fixed_deduction] DECIMAL(18, 2)  NOT NULL DEFAULT 0.00,  -- 扣除固定部分后绩效

    -- 6. 审计字段
    [remark]                            VARCHAR(1000)   NULL,                       -- 备注
    [create_time]                       DATETIME        NOT NULL CONSTRAINT df_ads_emp_monthly_performance_m_create_time DEFAULT GETDATE(),

    -- 7. 联合主键：物理层锁死同一账期内单个员工在单一核算单元单一岗位上仅存在一条绩效金额记录，支撑兼岗与月中换岗的金额拆分
    CONSTRAINT pk_ads_emp_monthly_performance_m PRIMARY KEY CLUSTERED (
        [year],
        [month],
        [unit_code],
        [staff_code],
        [post_code]
    )
);

-- 注入表级扩展属性注释
EXEC sys.sp_addextendedproperty 
    @name = N'MS_Description', 
    @value = N'【个人月度绩效金额明细表】：承载月度员工个人绩效奖、管理绩效、合计绩效、固定部分绩效及扣除固定部分后绩效等核心金额指标的明细资产表。', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'ads_emp_monthly_performance_m';

-- =================================================================
-- 列级扩展属性注释
-- =================================================================
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份，如 2026', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'year';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份，如 7', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'month';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'unit_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'unit_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'staff_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工姓名', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'staff_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工序列：联合切片键，对齐考核表区分医疗/护理', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'staff_sequence';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'所属职系编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'series_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'所属职系名称', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'series_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'岗位物理编码：系统级逻辑锁定键，如 DIR_01 主任岗、NUR_01 护士长岗', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'post_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'职务标签名称：前端展示还原科主任、护士长、护理组长、普通医生、普通护士', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'post_name';

EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'绩效奖（元），保留两位小数，默认 0.00', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'performance_bonus';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'管理绩效（元），保留两位小数，默认 0.00', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'management_performance';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'合计绩效（元），保留两位小数，默认 0.00', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'total_performance';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'固定部分绩效（元），保留两位小数，默认 0.00', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'fixed_performance';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'扣除固定部分后绩效（元），保留两位小数，默认 0.00', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'performance_after_fixed_deduction';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'备注', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'remark';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'创建时间', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_emp_monthly_performance_m', @level2type = N'COLUMN', @level2name = N'create_time';
