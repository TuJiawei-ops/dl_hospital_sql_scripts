-- =================================================================
-- 表实体创建：ads_dept_post_coefficient_m
-- 业务定义：全院/核算单元月度岗位系数与在岗状态明细表（支持干部病房特殊系数动态提取）
-- Relative Path : sqlserver/ADS_DEPT_POST_COEFFICIENT_M.sql
-- =================================================================
-- 修改日志
-- 2026-09-15 15:00:00 | 维度补全 | 在员工身份维度区块增补 [series_code] (所属职系编码) 与 [series_name] (所属职系名称) 字段及对应元数据注释。
-- 2026-09-15 14:45:00 | 规范重构 | 遵循新表规范将表名及全量字段重构为全小写下划线；将 [DEPT_CODE]/[DEPT_NAME] 抽象重构为 [unit_code]/[unit_name] (核算单元编码/名称)。
-- 2026-09-15 14:39:00 | 项目适配重构 | 移除 [STAFF_TYPE] (军文/聘用) 字段与相关注释；合并历史增量 Patch 至建表基线（IS_TRANSFERRED 与五元联合主键）。
-- 2026-08-17 11:13:46 | 主键升级：将联合主键由 (YEAR, MONTH, DEPT_CODE, STAFF_CODE) 升维为 (YEAR, MONTH, DEPT_CODE, STAFF_CODE, POST_CODE)，支持同一员工同一账期多岗位天数拆分。
-- 2026-08-11 | 增量追加：新增 [IS_TRANSFERRED] 是否转科标识字段及列级扩展属性注释。
-- 2026-07-19 | 创建表结构，包含 STAFF_TYPE / STAFF_SEQUENCE 双切片键及 POST_CODE / POST_NAME 双重职务标签
-- 2026-07-19 | 逻辑纠偏重构：根据第一性原理，彻底移除 [ACTUAL_WORK_DAYS] 动态考勤字段，使资产表回归高聚合、低耦合的准入数据规范。
-- 2026-07-22 | 增量追加：新增 [ON_DUTY_DAYS] 月度实际在岗天数字段及对应列级元数据注释
-- =================================================================

-- 删除已存在的表（开发/迭代环境使用，生产环境请谨慎）
IF OBJECT_ID(N'[dbo].[ads_dept_post_coefficient_m]', N'U') IS NOT NULL
    DROP TABLE [dbo].[ads_dept_post_coefficient_m];

-- 创建表
CREATE TABLE [dbo].[ads_dept_post_coefficient_m] (
    -- 1. 账期维度
    [year]              INT             NOT NULL,       -- 核算年份
    [month]             INT             NOT NULL,       -- 核算月份

    -- 2. 核算单元维度
    [unit_code]         VARCHAR(50)     NOT NULL,       -- 核算单元编码
    [unit_name]         VARCHAR(100)    NOT NULL,       -- 核算单元名称

    -- 3. 员工身份维度
    [staff_code]        VARCHAR(50)     NOT NULL,       -- 员工编码
    [staff_name]        VARCHAR(100)    NOT NULL,       -- 员工姓名
    [staff_sequence]    VARCHAR(50)     NOT NULL,       -- 联合切片键：对齐考核表，区分 医疗 / 护理
    [series_code]       VARCHAR(50)     NOT NULL,       -- 所属职系编码
    [series_name]       VARCHAR(100)    NOT NULL,       -- 所属职系名称

    -- 4. 职务标签（双重锁定：编码驱动系统逻辑，名称还原前端展示）
    [post_code]         VARCHAR(50)     NOT NULL,       -- 核心防御：岗位物理编码（如 DIR_01, NUR_01）
    [post_name]         VARCHAR(100)    NOT NULL,       -- 职务标签：科主任、护士长、护理组长、普通医生、普通护士

    -- 5. 系数与考勤度量
    [post_coefficient]  DECIMAL(18, 8)  NOT NULL DEFAULT 1.0000,  -- 岗位系数
    [on_duty_days]      DECIMAL(18, 8)  NOT NULL DEFAULT 0.00,    -- 月度实际在岗天数

    -- 6. 月中转科标识（原 2026-08-11 增量 Patch，已并入建表基线）
    [is_transferred]    VARCHAR(10)     NOT NULL CONSTRAINT df_ads_dept_post_coefficient_m_is_transferred DEFAULT '否',

    -- 7. 审计字段
    [remark]            VARCHAR(1000)   NULL,                       -- 备注
    [create_time]       DATETIME        NOT NULL CONSTRAINT df_ads_dept_post_coefficient_m_create_time DEFAULT GETDATE(),

    -- 8. 联合主键：物理层锁死同一账期内单个员工在单一岗位上仅存在一条岗位系数记录，支撑兼岗与月中换岗的天数拆分
    CONSTRAINT pk_ads_dept_post_coefficient_m PRIMARY KEY CLUSTERED (
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
    @value = N'【科室岗位系数月度明细表】：承载月度员工岗位、职务编码及基础系数的物理明细表。通过岗位编码（POST_CODE）与岗位名称（POST_NAME）双重锁定干部病房等科室二次分配中所需的管理层和特殊岗位标签，作为核心系数输入的基石。', 
    @level0type = N'SCHEMA', @level0name = N'dbo', 
    @level1type = N'TABLE',  @level1name = N'ads_dept_post_coefficient_m';

-- =================================================================
-- 列级扩展属性注释
-- =================================================================
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算年份，如 2026', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'year';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算月份，如 7', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'month';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'unit_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'核算单元名称', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'unit_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'staff_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工姓名', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'staff_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工序列：联合切片键，对齐考核表区分医疗/护理', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'staff_sequence';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'所属职系编码', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'series_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'所属职系名称', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'series_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'岗位物理编码：系统级逻辑锁定键，如 DIR_01 主任岗、NUR_01 护士长岗', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'post_code';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'职务标签名称：前端展示还原科主任、护士长、护理组长、普通医生、普通护士', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'post_name';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'岗位系数，默认 1.0000', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'post_coefficient';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'员工当月实际在岗/在位考勤天数', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'on_duty_days';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'是否转科标识：用于区分月中是否发生跨科室调动（是/否），默认 否', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'is_transferred';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'备注', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'remark';
EXEC sys.sp_addextendedproperty @name = N'MS_Description', @value = N'创建时间', @level0type = N'SCHEMA', @level0name = N'dbo', @level1type = N'TABLE', @level1name = N'ads_dept_post_coefficient_m', @level2type = N'COLUMN', @level2name = N'create_time';

