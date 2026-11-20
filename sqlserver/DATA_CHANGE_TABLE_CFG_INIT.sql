-- =================================================================
-- 配置变更记录：初始化关键表清单
-- File : sqlserver/DATA_CHANGE_TABLE_CFG_INIT.sql
-- =================================================================
-- 目的
--   把「数据管理 / 数据接入 → 本地文件导入」的全部数据源表（access_way = 2）
--   一次性纳入变更记录清单（enabled = 1），中文名取数据源名称。
-- 幂等
--   已存在的表跳过（不覆盖已有开关与模式），可重复执行。
-- 说明
--   后续如需关闭某张表的记录：UPDATE sys_data_change_table_cfg SET enabled=0 WHERE table_name='xxx'
-- =================================================================

SET NOCOUNT ON;

INSERT INTO sys_data_change_table_cfg (table_name, table_label, record_mode, enabled, remark)
SELECT dc.table_name,
       dc.name,
       'FIELD',
       1,
       N'本地导入数据源初始纳入'
FROM data_connection dc
WHERE dc.access_way = 2
  AND ISNULL(dc.deleted, 0) = 0
  AND dc.table_name IS NOT NULL
  AND dc.table_name <> ''
  AND NOT EXISTS (
      SELECT 1 FROM sys_data_change_table_cfg c WHERE c.table_name = dc.table_name
  );

/* 核对 */
SELECT COUNT(1) AS 已纳入表数, SUM(enabled) AS 已开启数 FROM sys_data_change_table_cfg;
SELECT TOP 20 table_name, table_label, enabled FROM sys_data_change_table_cfg ORDER BY id;
