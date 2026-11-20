-- =================================================================
-- 绩效期间表规范化改造（performance_period）
-- Relative Path : sqlserver/PERFORMANCE_PERIOD_FIX.sql
-- =================================================================
-- 改动内容
--   1. 新增 calc_year / calc_period（核算年、核算期 1~13）
--   2. 回填存量：从 code 解析（前4位年、5-6位期）
--   3. 唯一约束：同一频次下 (calc_year, calc_period, frequency) 唯一
--   4. 起止时间 date → datetime2，约定半开区间 [start, end)
--        开始：原日期 00:00:00
--        结束：原日期次日 00:00:00（即“含当天”）
--   5. code 统一为纯数字 YYYYMM（含13期则 YYYY13）
-- 执行注意
--   · 本脚本分步执行、可重复执行（幂等）；建议先备份表。
--   · 第 5 步改 code 前，请确认外部引用（导出、报表、接口）按 code 取值处可兼容。
--   · 第 4 步改类型为破坏性变更，生产请在维护窗口执行。
-- =================================================================

SET NOCOUNT ON;

/* ---------- 1. 新增核算年/核算期 ---------- */
IF COL_LENGTH('dbo.performance_period', 'calc_year') IS NULL
    ALTER TABLE dbo.performance_period ADD calc_year INT NULL;
IF COL_LENGTH('dbo.performance_period', 'calc_period') IS NULL
    ALTER TABLE dbo.performance_period ADD calc_period INT NULL;

/* ---------- 2. 回填（code 形如 202712M / 202712） ---------- */
UPDATE dbo.performance_period
SET calc_year = TRY_CAST(LEFT(code, 4) AS INT),
    calc_period = TRY_CAST(SUBSTRING(code, 5, 2) AS INT)
WHERE calc_year IS NULL AND ISNULL(delete_flag, 0) = 0;

/* ---------- 3. 唯一约束（先查重，重复则跳过并提示） ---------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes
               WHERE object_id = OBJECT_ID('dbo.performance_period')
                 AND name = 'uq_performance_period_year_period')
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM dbo.performance_period
        WHERE ISNULL(delete_flag, 0) = 0
        GROUP BY calc_year, calc_period, frequency
        HAVING COUNT(1) > 1
    )
    BEGIN
        CREATE UNIQUE INDEX uq_performance_period_year_period
            ON dbo.performance_period (calc_year, calc_period, frequency)
            WHERE delete_flag = 0;
        PRINT N'[3] 已创建唯一索引 uq_performance_period_year_period';
    END
    ELSE
        PRINT N'[3] 存在重复的(年,期,频次)，请先清理后再创建唯一索引';
END

/* ---------- 4. 起止时间改 datetime2（半开区间） ---------- */
IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_NAME = 'performance_period' AND COLUMN_NAME = 'start_date' AND DATA_TYPE = 'date')
BEGIN
    ALTER TABLE dbo.performance_period ALTER COLUMN start_date DATETIME2(3) NULL;
    UPDATE dbo.performance_period
    SET start_date = CAST(CAST(start_date AS DATE) AS DATETIME2(3))
    WHERE start_date IS NOT NULL;

    ALTER TABLE dbo.performance_period ALTER COLUMN end_date DATETIME2(3) NULL;
    -- 结束时间改为“次日 00:00:00”，形成 [start, end) 半开区间
    UPDATE dbo.performance_period
    SET end_date = DATEADD(DAY, 1, CAST(CAST(end_date AS DATE) AS DATETIME2(3)))
    WHERE end_date IS NOT NULL;
    PRINT N'[4] start_date/end_date 已改为 datetime2（结束为次日 00:00:00）';
END

IF EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
           WHERE TABLE_NAME = 'performance_period' AND COLUMN_NAME = 'fi_start_date' AND DATA_TYPE = 'date')
BEGIN
    ALTER TABLE dbo.performance_period ALTER COLUMN fi_start_date DATETIME2(3) NULL;
    UPDATE dbo.performance_period
    SET fi_start_date = CAST(CAST(fi_start_date AS DATE) AS DATETIME2(3))
    WHERE fi_start_date IS NOT NULL;

    ALTER TABLE dbo.performance_period ALTER COLUMN fi_end_date DATETIME2(3) NULL;
    UPDATE dbo.performance_period
    SET fi_end_date = DATEADD(DAY, 1, CAST(CAST(fi_end_date AS DATE) AS DATETIME2(3)))
    WHERE fi_end_date IS NOT NULL;
    PRINT N'[4] 财务起止时间已改为 datetime2';
END

/* ---------- 5. code 改纯数字 YYYYMM ---------- */
UPDATE dbo.performance_period
SET code = CONCAT(CAST(calc_year AS VARCHAR(4)),
                  RIGHT('0' + CAST(calc_period AS VARCHAR(2)), 2))
WHERE ISNULL(delete_flag, 0) = 0
  AND calc_year IS NOT NULL
  AND calc_period IS NOT NULL
  AND code <> CONCAT(CAST(calc_year AS VARCHAR(4)),
                     RIGHT('0' + CAST(calc_period AS VARCHAR(2)), 2));

/* ---------- 6. 旧表标记（不删） ---------- */
IF OBJECT_ID('dbo.t_accounting_period', 'U') IS NOT NULL
BEGIN
    IF EXISTS (SELECT 1 FROM sys.extended_properties
               WHERE name = N'MS_Description' AND major_id = OBJECT_ID('dbo.t_accounting_period') AND minor_id = 0)
        EXEC sys.sp_updateextendedproperty
            @name = N'MS_Description',
            @value = N'【历史/未使用】绩效期间旧表，业务已改用 performance_period，保留仅供追溯，勿新增数据。',
            @level0type = N'SCHEMA', @level0name = N'dbo',
            @level1type = N'TABLE',  @level1name = N't_accounting_period';
    ELSE
        EXEC sys.sp_addextendedproperty
            @name = N'MS_Description',
            @value = N'【历史/未使用】绩效期间旧表，业务已改用 performance_period，保留仅供追溯，勿新增数据。',
            @level0type = N'SCHEMA', @level0name = N'dbo',
            @level1type = N'TABLE',  @level1name = N't_accounting_period';
    PRINT N'[6] t_accounting_period 已标注为历史表';
END

/* ---------- 7. 结果核对 ---------- */
SELECT TOP 10 id, code, name, frequency, calc_year, calc_period, start_date, end_date
FROM dbo.performance_period
WHERE ISNULL(delete_flag, 0) = 0
ORDER BY calc_year DESC, calc_period DESC;
