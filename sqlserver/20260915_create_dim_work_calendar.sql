/*
================================================================================
Relative Path : sqlserver/20260915_create_dim_work_calendar.sql
分层归属     : DIM（维度层）
业务定义     : 绩效核算日历维度表（反范式打平，物理下沉星期维度与 PERF_COEFF 单日绩效系数，支持按类型批量刷新与单日精准微调）
唯一键       : CALC_DATE（自然日历日期，单日唯一粒度）
视图说明     : 本脚本为纯物理表设计，不生成任何面向业务的视图层对象
会话无关性   : 星期维度（WEEKDAY_CODE / WEEKDAY_NAME）已物理下沉，全链路不依赖 DATEFIRST / LANGUAGE 会话设置
模板占位符   : 无（纯维度 DDL，不含 '{year}' / '{month}' / {struct_codes} 动态注入）
修改日志：
2026-09-15 07:00:00 | 结构重构 | 物理下沉星期维度 WEEKDAY_CODE(TINYINT) / WEEKDAY_NAME(NVARCHAR(16))，彻底消除 DATEFIRST / LANGUAGE 会话依赖；同步补齐 2 条字段级扩展属性注释
2026-09-15 06:45:00 | 结构重构 | 剔除 V_DIM_WORK_CALENDAR 视图定义，脚本收敛为纯维度物理单表；补齐表级与 9 个字段级扩展属性注释（幂等可重复执行）
2026-09-15 06:33:00 | 语法修复 | 修复 CREATE TABLE 中 DEFAULT CONSTRAINT 的 FOR 关键字语法错误（FOR 为 ALTER TABLE 专有语法），统一改为列内联 DEFAULT
2026-09-15 06:30:00 | 结构重构 | 物理表直接下沉 PERF_COEFF 系数列(DECIMAL(18,8))，简化视图计算链路
2026-09-15 06:21:00 | 结构新建 | 新建绩效核算日历维度物理表 DIM_WORK_CALENDAR 及面向业务视图 V_DIM_WORK_CALENDAR
================================================================================
*/

-- ================================================================
-- 1. 创建绩效核算日历维度物理表 (DIM_WORK_CALENDAR)
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[DIM_WORK_CALENDAR];
END;

CREATE TABLE [dbo].[DIM_WORK_CALENDAR] (
    -- ===== 日期主键与星期维度（物理下沉，杜绝 DATEFIRST / LANGUAGE 会话依赖）=====
    [CALC_DATE]       DATE          NOT NULL,                         -- 日期（YYYY-MM-DD，单日唯一粒度）
    [WEEKDAY_CODE]    TINYINT       NOT NULL,                         -- 星期编码（ISO 口径：1=星期一 ... 7=星期日）
    [WEEKDAY_NAME]    NVARCHAR(16)  NOT NULL,                         -- 星期名称（星期一/星期二/.../星期日）
    -- ===== 日期类型维度（编码严格字符串语义，严禁整型化）=====
    [DAY_TYPE_CODE]   VARCHAR(16)   NOT NULL,                         -- 日期类型编码（WORKDAY/HOLIDAY/WEEKEND/MAKEUP）
    [DAY_TYPE_NAME]   NVARCHAR(32)  NOT NULL,                         -- 日期类型名称（正常工作日/法定节假日/普通周末/调休补班）
    -- ===== 节假日标识与绩效系数 =====
    [IS_HOLIDAY]      TINYINT       NOT NULL DEFAULT (0),             -- 是否法定节假日（1:是, 0:否）
    [HOLIDAY_NAME]    NVARCHAR(64)  NULL,                             -- 节假日名称（如：清明节）
    [IS_MAKEUP_WORK]  TINYINT       NOT NULL DEFAULT (0),             -- 是否调休补班（1:是, 0:否）
    [PERF_COEFF]      DECIMAL(18,8) NOT NULL DEFAULT (1.00000000),    -- 绩效核算系数（支持单日独立微调）
    -- ===== 审计字段 =====
    [REMARK]          NVARCHAR(255) NULL,                             -- 备注
    [CREATE_TIME]     DATETIME      NOT NULL DEFAULT (GETDATE()),     -- 创建时间
    -- ===== 主键约束 =====
    CONSTRAINT [PK_DIM_WORK_CALENDAR] PRIMARY KEY CLUSTERED ([CALC_DATE] ASC)
);

-- 日期类型检索索引（支撑按日期范围 + 类型编码的绩效系数批量关联）
CREATE NONCLUSTERED INDEX [IX_DIM_WORK_CALENDAR_DAY_TYPE] ON [dbo].[DIM_WORK_CALENDAR] (
    [DAY_TYPE_CODE] ASC,
    [CALC_DATE]     ASC
);

-- ================================================================
-- 2. 表级与字段级扩展属性注释（幂等：存在即先删后加，可重复执行）
-- ================================================================
-- 2.1 表级注释
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = 0 AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'绩效核算日历维度表（粒度：CALC_DATE 单日唯一；承载日期类型、节假日标识与单日绩效系数）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR';

-- 2.2 字段级注释 : CALC_DATE
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'CALC_DATE', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'CALC_DATE';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'日期（YYYY-MM-DD，单日唯一粒度，物理主键）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'CALC_DATE';

-- 2.3 字段级注释 : WEEKDAY_CODE
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'WEEKDAY_CODE', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'WEEKDAY_CODE';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'星期编码（TINYINT，ISO 口径固定为 1=星期一 ... 7=星期日；物理下沉，严禁改用 DATEPART(WEEKDAY, ...) 实时推导）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'WEEKDAY_CODE';

-- 2.4 字段级注释 : WEEKDAY_NAME
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'WEEKDAY_NAME', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'WEEKDAY_NAME';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'星期名称（NVARCHAR(16)，取值：星期一 / 星期二 / 星期三 / 星期四 / 星期五 / 星期六 / 星期日；与 WEEKDAY_CODE 严格一一对应）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'WEEKDAY_NAME';

-- 2.5 字段级注释 : DAY_TYPE_CODE
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'DAY_TYPE_CODE', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'DAY_TYPE_CODE';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'日期类型编码（字符串语义，严禁整型化；取值：WORKDAY 正常工作日 / HOLIDAY 法定节假日 / WEEKEND 普通周末 / MAKEUP 调休补班）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'DAY_TYPE_CODE';

-- 2.6 字段级注释 : DAY_TYPE_NAME
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'DAY_TYPE_NAME', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'DAY_TYPE_NAME';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'日期类型名称（正常工作日 / 法定节假日 / 普通周末 / 调休补班）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'DAY_TYPE_NAME';

-- 2.7 字段级注释 : IS_HOLIDAY
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'IS_HOLIDAY', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'IS_HOLIDAY';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'是否法定节假日（1:是, 0:否，默认 0）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'IS_HOLIDAY';

-- 2.8 字段级注释 : HOLIDAY_NAME
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'HOLIDAY_NAME', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'HOLIDAY_NAME';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'节假日名称（如：清明节；仅 IS_HOLIDAY = 1 时填充，其余为空）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'HOLIDAY_NAME';

-- 2.9 字段级注释 : IS_MAKEUP_WORK
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'IS_MAKEUP_WORK', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'IS_MAKEUP_WORK';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'是否调休补班（1:是, 0:否，默认 0；为 1 时按正常工作日口径计发）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'IS_MAKEUP_WORK';

-- 2.10 字段级注释 : PERF_COEFF
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'PERF_COEFF', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'PERF_COEFF';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'绩效核算系数（DECIMAL(18,8)，默认 1.00000000；物理下沉支持按 DAY_TYPE_CODE 批量刷新与按 CALC_DATE 单日精准微调）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'PERF_COEFF';

-- 2.11 字段级注释 : REMARK
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'REMARK', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'REMARK';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'备注（承载假日办放假通知编号、系数调整说明等追溯信息）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'REMARK';

-- 2.12 字段级注释 : CREATE_TIME
IF EXISTS (SELECT 1 FROM sys.extended_properties WHERE class = 1 AND major_id = OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]') AND minor_id = COLUMNPROPERTY(OBJECT_ID(N'[dbo].[DIM_WORK_CALENDAR]'), N'CREATE_TIME', 'ColumnId') AND name = N'MS_Description')
BEGIN
    EXEC sp_dropextendedproperty N'MS_Description', N'SCHEMA', N'dbo', N'TABLE', N'DIM_WORK_CALENDAR', N'COLUMN', N'CREATE_TIME';
END;

EXEC sp_addextendedproperty
    N'MS_Description', N'创建时间（默认 GETDATE()）',
    N'SCHEMA', N'dbo',
    N'TABLE', N'DIM_WORK_CALENDAR',
    N'COLUMN', N'CREATE_TIME';

