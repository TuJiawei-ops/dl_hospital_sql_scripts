/*
================================================================================
Relative Path : sqlserver/ods_tcm_advantage_disease_patient_d.sql
脚本名称     : ods_tcm_advantage_disease_patient_d.sql
分层归属     : ODS（原始数据层 / 明细粒度 _d）
业务定义     : 中医优势病种入组患者明细表（承载日间治疗中心等来源的白疕病、蛇串疮/蛇盘疮病数据）
粒度         : 患者级明细（归属年月 + 病种 + 患者 + 结算时间，天然可重复，不设物理主键）
归属年月切片 : calc_year(INT) + calc_month(INT) 物理下沉，支撑按月切片查询与按月重跑删除
源系统       : 医院信息系统（HIS）/ 日间治疗中心中医优势病种登记
命名规范     : 全小写英文下划线（UPPER_CASE_SNAKE 在中台物理层的小写表述），分层前缀 ods_，后缀 _d 标识日/明细粒度
编码字段语义 : disease_code / patient_no / dept_code 锁定 VARCHAR 字符串语义，严禁整型化（防前导零丢失与关联失配）
金额精度     : total_fee 锁定 DECIMAL(18,8)，对齐全局绩效高精度计算标准
元数据字典   : 表级与全部 11 个字段级 MS_Description 扩展属性已下沉至数据库引擎元数据字典，客户端工具可实时展示
会话无关性   : 全链路无 DATEFIRST / LANGUAGE / COLLATE 会话依赖
模板占位符   : 无（纯 ODS 物理 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）
修改日志：
2026-09-17 10:50:00 | 结构完善 | 追加 calc_year / calc_month 每月切片字段，并增加 sp_addextendedproperty 数据库元数据字段注释。
2026-09-17 10:48:37 | 初始建表 | 新建中医优势病种入组患者 ODS 物理表结构，严格遵守全小写下划线命名与 DECIMAL(18,8) 精度规范。
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表（重跑零脏数据，保障 DDL 脚本可重复执行）
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[ods_tcm_advantage_disease_patient_d];
END;

-- ================================================================
-- 2. 创建中医优势病种入组患者明细物理表
-- ================================================================
CREATE TABLE [dbo].[ods_tcm_advantage_disease_patient_d] (
    -- ===== 归属年月切片维度（物理下沉，支撑按月增量重跑与查询切片）=====
    [calc_year]       INT             NOT NULL,                      -- 归属年份（如：2025）
    [calc_month]      INT             NOT NULL,                      -- 归属月份（如：1）
    -- ===== 病种维度 =====
    [disease_code]    VARCHAR(50)     NOT NULL,                      -- 病种编码（字符串语义，严禁整型化）
    [disease_name]    NVARCHAR(100)   NULL,                          -- 病种名称（如：白疕病 / 蛇串疮 / 蛇盘疮病）
    -- ===== 患者维度 =====
    [patient_name]    NVARCHAR(100)   NULL,                          -- 姓名
    [patient_no]      VARCHAR(50)     NOT NULL,                      -- 门诊号（字符串语义，防前导零丢失）
    -- ===== 科室维度 =====
    [dept_code]       VARCHAR(50)     NULL,                          -- 病人科室ID（字符串语义，对齐 HIS 源编码）
    [dept_name]       NVARCHAR(100)   NULL,                          -- 病人科室名称
    -- ===== 结算时间与金额 =====
    [settle_time]     DATETIME        NOT NULL,                      -- 结算时间
    [total_fee]       DECIMAL(18,8)   NULL,                          -- 医疗费总额（高精度，杜绝低精度截断累积误差）
    -- ===== 审计字段 =====
    [create_time]     DATETIME        NOT NULL DEFAULT (GETDATE())   -- 数据导入/创建时间
);

-- ================================================================
-- 3. 检索索引（支撑按月核算切片与患者级明细回溯）
-- ================================================================
-- 归属年月 + 病种编码复合索引（服务按月切片过滤、按月重跑删除与病种聚合）
CREATE NONCLUSTERED INDEX [ix_ods_tcm_adv_disease_patient_ym_disease]
    ON [dbo].[ods_tcm_advantage_disease_patient_d] ([calc_year] ASC, [calc_month] ASC, [disease_code] ASC);

-- 门诊号索引（支撑患者级明细回溯与跨来源去重比对）
CREATE NONCLUSTERED INDEX [ix_ods_tcm_adv_disease_patient_patient_no]
    ON [dbo].[ods_tcm_advantage_disease_patient_d] ([patient_no] ASC);

-- ================================================================
-- 4. 表级与字段级扩展属性注释（MS_Description 下沉数据库引擎元数据字典）
--    幂等：存在即先删后加，可重复执行；可直接被 Navicat / DBeaver / SSMS 读取展示
-- ================================================================
-- 4.1 表级注释
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = 0 AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'中医优势病种入组患者明细表（ODS 原始数据层；粒度：归属年月 × 病种 × 患者 × 结算时间）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d';

-- 4.2 字段级注释 : calc_year
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'calc_year', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'calc_year';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'归属年份（INT，如 2025；按月切片与重跑删除的主控过滤列）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'calc_year';

-- 4.3 字段级注释 : calc_month
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'calc_month', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'calc_month';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'归属月份（INT，取值 1-12，如 1；与 calc_year 共同构成核算期间切片）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'calc_month';

-- 4.4 字段级注释 : disease_code
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'disease_code', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'disease_code';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'病种编码（VARCHAR(50) 字符串语义，严禁整型化，防前导零丢失与关联失配）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'disease_code';

-- 4.5 字段级注释 : disease_name
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'disease_name', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'disease_name';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'病种名称（NVARCHAR(100)，如：白疕病 / 蛇串疮 / 蛇盘疮病）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'disease_name';

-- 4.6 字段级注释 : patient_name
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'patient_name', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'patient_name';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'患者姓名（NVARCHAR(100)）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'patient_name';

-- 4.7 字段级注释 : patient_no
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'patient_no', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'patient_no';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'门诊号（VARCHAR(50) 字符串语义，严禁整型化，防前导零丢失与关联失配）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'patient_no';

-- 4.8 字段级注释 : dept_code
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'dept_code', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'dept_code';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'病人科室ID（VARCHAR(50) 字符串语义，对齐 HIS 源编码，严禁整型化）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'dept_code';

-- 4.9 字段级注释 : dept_name
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'dept_name', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'dept_name';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'病人科室名称（NVARCHAR(100)）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'dept_name';

-- 4.10 字段级注释 : settle_time
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'settle_time', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'settle_time';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'结算时间（DATETIME，YYYY-MM-DD HH:MM:SS；归属年月的原始判定依据）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'settle_time';

-- 4.11 字段级注释 : total_fee
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'total_fee', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'total_fee';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'医疗费总额（高精度 DECIMAL(18,8)，严禁低精度截断累积误差）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'total_fee';

-- 4.12 字段级注释 : create_time
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]'), N'create_time', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'ods_tcm_advantage_disease_patient_d', N'COLUMN', N'create_time';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'数据导入/创建时间（DATETIME，默认 GETDATE()）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'ods_tcm_advantage_disease_patient_d',
    N'COLUMN', N'create_time';

