-- =================================================================
-- 配置数据变更历史（字段级审计）
-- File : sqlserver/SYS_DATA_CHANGE_LOG.sql
-- =================================================================
-- 目的
--   记录「本地文件导入」关键配置表的每一次变更，精确到字段：
--   谁、在何时、对哪张表、哪条记录、哪个字段、从什么值变成什么值。
-- 与操作日志的关系
--   sys_operation_log    = 动作级（谁做了什么）
--   sys_data_change_*    = 数据级（数据变成了什么），两者用 batch_id 可关联
-- 命名规范
--   全小写 + 下划线（主键沿用 ID 大写的历史例外不做，新表统一用 id）
-- =================================================================

SET NOCOUNT ON;

/* ---------- 1. 变更批次 ---------- */
IF OBJECT_ID('dbo.sys_data_change_batch', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.sys_data_change_batch (
        id               BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        table_name       NVARCHAR(128) NOT NULL,
        table_label      NVARCHAR(128) NULL,
        action           NVARCHAR(16)  NOT NULL,   -- INSERT / UPDATE / DELETE / IMPORT
        row_count        INT           NOT NULL DEFAULT 0,
        field_count      INT           NOT NULL DEFAULT 0,
        operator_id      BIGINT        NULL,
        operator_account NVARCHAR(64)  NULL,
        operator_name    NVARCHAR(64)  NULL,
        source           NVARCHAR(16)  NULL,       -- import / manual / api
        client_ip        NVARCHAR(64)  NULL,
        summary          NVARCHAR(512) NULL,
        change_time      DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );
    CREATE INDEX ix_dcc_batch_time   ON dbo.sys_data_change_batch (change_time DESC);
    CREATE INDEX ix_dcc_batch_table  ON dbo.sys_data_change_batch (table_name, change_time DESC);
    CREATE INDEX ix_dcc_batch_op     ON dbo.sys_data_change_batch (operator_id, change_time DESC);
    PRINT N'[1] 已创建 sys_data_change_batch';
END
ELSE PRINT N'[1] sys_data_change_batch 已存在，跳过';

/* ---------- 2. 变更明细（一行一个字段变化） ---------- */
IF OBJECT_ID('dbo.sys_data_change_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.sys_data_change_log (
        id            BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        batch_id      BIGINT        NOT NULL,
        table_name    NVARCHAR(128) NOT NULL,
        record_id     NVARCHAR(64)  NULL,          -- 业务主键值（如 ID=1164）
        action        NVARCHAR(16)  NOT NULL,      -- INSERT / UPDATE / DELETE
        field_name    NVARCHAR(128) NOT NULL,
        field_label   NVARCHAR(128) NULL,          -- 中文名（取 data_import.param_description）
        old_value     NVARCHAR(MAX) NULL,
        new_value     NVARCHAR(MAX) NULL,
        before_json   NVARCHAR(MAX) NULL,          -- 变更前整行快照（JSON，字段级 diff 的上下文）
        after_json    NVARCHAR(MAX) NULL,          -- 变更后整行快照
        json_truncated INT NOT NULL DEFAULT 0,     -- 1=快照超长被截断，仅保留字段级 diff
        change_time   DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );
    CREATE INDEX ix_dcl_batch   ON dbo.sys_data_change_log (batch_id);
    CREATE INDEX ix_dcl_record  ON dbo.sys_data_change_log (table_name, record_id, change_time DESC);
    CREATE INDEX ix_dcl_field   ON dbo.sys_data_change_log (table_name, field_name, change_time DESC);
    PRINT N'[2] 已创建 sys_data_change_log';
END
ELSE PRINT N'[2] sys_data_change_log 已存在，跳过';

/* ---------- 2b. 已存在表补快照列（幂等） ---------- */
IF COL_LENGTH('dbo.sys_data_change_log', 'before_json') IS NULL
    ALTER TABLE dbo.sys_data_change_log ADD before_json NVARCHAR(MAX) NULL;
IF COL_LENGTH('dbo.sys_data_change_log', 'after_json') IS NULL
    ALTER TABLE dbo.sys_data_change_log ADD after_json NVARCHAR(MAX) NULL;
IF COL_LENGTH('dbo.sys_data_change_log', 'json_truncated') IS NULL
    ALTER TABLE dbo.sys_data_change_log ADD json_truncated INT NOT NULL DEFAULT 0;

/* ---------- 3. 需记录变更的关键表清单 ---------- */
IF OBJECT_ID('dbo.sys_data_change_table_cfg', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.sys_data_change_table_cfg (
        id           BIGINT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        table_name   NVARCHAR(128) NOT NULL,
        table_label  NVARCHAR(128) NULL,
        record_mode  NVARCHAR(16)  NOT NULL DEFAULT 'FIELD',  -- FIELD=仅记变化字段；ALL=整行快照
        enabled      INT           NOT NULL DEFAULT 1,
        remark       NVARCHAR(255) NULL,
        create_time  DATETIME2(3)  NOT NULL DEFAULT SYSDATETIME()
    );
    CREATE UNIQUE INDEX ux_dctc_table ON dbo.sys_data_change_table_cfg (table_name);
    PRINT N'[3] 已创建 sys_data_change_table_cfg';
END
ELSE PRINT N'[3] sys_data_change_table_cfg 已存在，跳过';

/* ---------- 4. 初始纳入（先两张，验证后再铺开） ---------- */
MERGE dbo.sys_data_change_table_cfg AS t
USING (VALUES
    ('sjjk_DEPT_UNIT_MAPPING_2025_11_27', N'科室与核算单元映射表', 'FIELD'),
    ('DIM_PRF_ITEM_RVU_VERSION',          N'医院收费项目绩效点数版本维表', 'FIELD')
) AS s (table_name, table_label, record_mode)
ON t.table_name = s.table_name
WHEN NOT MATCHED THEN
    INSERT (table_name, table_label, record_mode, enabled, remark)
    VALUES (s.table_name, s.table_label, s.record_mode, 1, N'P1 试运行');

/* ---------- 5. 核对 ---------- */
SELECT table_name, table_label, record_mode, enabled FROM dbo.sys_data_change_table_cfg ORDER BY id;
SELECT COUNT(1) AS batch_rows FROM dbo.sys_data_change_batch;
SELECT COUNT(1) AS log_rows FROM dbo.sys_data_change_log;
