-- =================================================================
-- 本地文件导入：审计字段补齐（科室与核算单元映射表）
-- File    : sqlserver/DATA_IMPORT_AUDIT_FIELDS.sql
-- 目标表  : sjjk_DEPT_UNIT_MAPPING_2025_11_27
-- 数据源  : data_connection.table_name = 'sjjk_DEPT_UNIT_MAPPING_2025_11_27'（access_way = 2 本地导入）
-- =================================================================
-- 命名规范（本项目）
--   列名 / 字段名统一 **全小写 + 下划线**；唯一例外是主键 `ID`（历史遗留，暂不改名）。
--   因此审计四字段为：
--     create_user   创建人   （只读，系统写入）
--     create_time   创建时间 （只读，系统写入）
--     update_user   修改人   （只读，系统写入）
--     update_time   修改时间 （只读，系统写入）
-- 现状
--   该表只有 create_time；缺 create_user / update_user / update_time；
--   data_import 里 4 个审计字段均未配置。
-- 幂等
--   1) 若历史上误建为大写（CREATE_USER 等），自动 rename 为小写；
--   2) 列不存在才 ADD；配置不存在才 INSERT；已存在大写配置则 UPDATE 为小写。
-- 执行顺序
--   备份 → 执行本脚本 → 核对输出 → 重启后端 → 数据接入页确认字段只读。
-- =================================================================

SET NOCOUNT ON;

DECLARE @connId DECIMAL(20,0);
DECLARE @tbl SYSNAME = 'sjjk_DEPT_UNIT_MAPPING_2025_11_27';

SELECT @connId = id FROM data_connection
WHERE table_name = @tbl AND ISNULL(deleted, 0) = 0;

IF @connId IS NULL
BEGIN
    PRINT N'[中止] 未找到数据源 ' + @tbl;
    RETURN;
END

/* ---------- 1. 表结构：补审计列（小写命名） ---------- */
IF COL_LENGTH('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27', 'create_user') IS NULL
    ALTER TABLE dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27 ADD create_user NVARCHAR(64) NULL;
IF COL_LENGTH('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27', 'update_user') IS NULL
    ALTER TABLE dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27 ADD update_user NVARCHAR(64) NULL;
IF COL_LENGTH('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27', 'update_time') IS NULL
    ALTER TABLE dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27 ADD update_time DATETIME NULL;
IF COL_LENGTH('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27', 'create_time') IS NULL
    ALTER TABLE dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27 ADD create_time DATETIME NULL;

/* ---------- 2. 规范：把误建的大写列 rename 为小写 ---------- */
DECLARE @old SYSNAME, @new SYSNAME, @sql NVARCHAR(400);

SELECT @old = name FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27') AND name COLLATE Latin1_General_CS_AS = 'CREATE_USER';
IF @old IS NOT NULL
BEGIN
    SET @sql = N'EXEC sp_rename ''dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27.' + @old + N''', ''create_user'', ''COLUMN'';';
    EXEC sp_executesql @sql;
    PRINT N'[2] CREATE_USER -> create_user';
END

SET @old = NULL;
SELECT @old = name FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27') AND name COLLATE Latin1_General_CS_AS = 'UPDATE_USER';
IF @old IS NOT NULL
BEGIN
    SET @sql = N'EXEC sp_rename ''dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27.' + @old + N''', ''update_user'', ''COLUMN'';';
    EXEC sp_executesql @sql;
    PRINT N'[2] UPDATE_USER -> update_user';
END

SET @old = NULL;
SELECT @old = name FROM sys.columns
WHERE object_id = OBJECT_ID('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27') AND name COLLATE Latin1_General_CS_AS = 'UPDATE_TIME';
IF @old IS NOT NULL
BEGIN
    SET @sql = N'EXEC sp_rename ''dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27.' + @old + N''', ''update_time'', ''COLUMN'';';
    EXEC sp_executesql @sql;
    PRINT N'[2] UPDATE_TIME -> update_time';
END

/* ---------- 3. data_import：历史大写配置改为小写 ---------- */
UPDATE data_import SET field_name = 'create_user'
WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0 AND field_name = 'CREATE_USER';

UPDATE data_import SET field_name = 'create_time'
WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0 AND field_name = 'CREATE_TIME';

UPDATE data_import SET field_name = 'update_user'
WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0 AND field_name = 'UPDATE_USER';

UPDATE data_import SET field_name = 'update_time'
WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0 AND field_name = 'UPDATE_TIME';

/* ---------- 4. data_import：补审计字段配置（只读） ---------- */
DECLARE @newId DECIMAL(20,0);
DECLARE @sort INT = (SELECT ISNULL(MAX(sort), 0) FROM data_import WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0);

IF NOT EXISTS (SELECT 1 FROM data_import WHERE parent_id = @connId AND field_name = 'create_user' AND ISNULL(deleted, 0) = 0)
BEGIN
    SET @sort = @sort + 1;
    SET @newId = (SELECT ISNULL(MAX(id), 0) + 1 FROM data_import);
    INSERT INTO data_import (id, parent_id, field_name, field_type, business_type, creator_id, createtime,
                             deleted, param_description, field_query, sort, remark, field_tip,
                             ui_type, ui_source, ui_pair_field, ui_required, ui_readonly)
    VALUES (@newId, @connId, 'create_user', 'nvarchar', '无', 1688431883371515906, GETDATE(),
            0, N'创建人', 0, @sort, NULL, NULL, 'text', NULL, NULL, '0', '1');
END

IF NOT EXISTS (SELECT 1 FROM data_import WHERE parent_id = @connId AND field_name = 'create_time' AND ISNULL(deleted, 0) = 0)
BEGIN
    SET @sort = @sort + 1;
    SET @newId = (SELECT ISNULL(MAX(id), 0) + 1 FROM data_import);
    INSERT INTO data_import (id, parent_id, field_name, field_type, business_type, creator_id, createtime,
                             deleted, param_description, field_query, sort, remark, field_tip,
                             ui_type, ui_source, ui_pair_field, ui_required, ui_readonly)
    VALUES (@newId, @connId, 'create_time', 'datetime', '无', 1688431883371515906, GETDATE(),
            0, N'创建时间', 0, @sort, NULL, NULL, 'text', NULL, NULL, '0', '1');
END

IF NOT EXISTS (SELECT 1 FROM data_import WHERE parent_id = @connId AND field_name = 'update_user' AND ISNULL(deleted, 0) = 0)
BEGIN
    SET @sort = @sort + 1;
    SET @newId = (SELECT ISNULL(MAX(id), 0) + 1 FROM data_import);
    INSERT INTO data_import (id, parent_id, field_name, field_type, business_type, creator_id, createtime,
                             deleted, param_description, field_query, sort, remark, field_tip,
                             ui_type, ui_source, ui_pair_field, ui_required, ui_readonly)
    VALUES (@newId, @connId, 'update_user', 'nvarchar', '无', 1688431883371515906, GETDATE(),
            0, N'修改人', 0, @sort, NULL, NULL, 'text', NULL, NULL, '0', '1');
END

IF NOT EXISTS (SELECT 1 FROM data_import WHERE parent_id = @connId AND field_name = 'update_time' AND ISNULL(deleted, 0) = 0)
BEGIN
    SET @sort = @sort + 1;
    SET @newId = (SELECT ISNULL(MAX(id), 0) + 1 FROM data_import);
    INSERT INTO data_import (id, parent_id, field_name, field_type, business_type, creator_id, createtime,
                             deleted, param_description, field_query, sort, remark, field_tip,
                             ui_type, ui_source, ui_pair_field, ui_required, ui_readonly)
    VALUES (@newId, @connId, 'update_time', 'datetime', '无', 1688431883371515906, GETDATE(),
            0, N'修改时间', 0, @sort, NULL, NULL, 'text', NULL, NULL, '0', '1');
END

/* ---------- 5. 核对结果 ---------- */
SELECT c.name AS column_name, t.name AS data_type, c.is_nullable
FROM sys.columns c
JOIN sys.types t ON t.user_type_id = c.user_type_id
WHERE c.object_id = OBJECT_ID('dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27')
  AND c.name IN ('ID', 'create_user', 'create_time', 'update_user', 'update_time')
ORDER BY c.name;

SELECT field_name, param_description, ui_readonly, sort
FROM data_import
WHERE parent_id = @connId AND ISNULL(deleted, 0) = 0
ORDER BY sort;
