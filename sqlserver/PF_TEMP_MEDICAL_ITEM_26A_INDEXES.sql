-- =================================================================
-- 索引重建：PF临时医疗服务项目26A（一次分配事实表）
-- Relative Path : sqlserver/PF_TEMP_MEDICAL_ITEM_26A_INDEXES.sql
-- =================================================================
-- 背景
--   表规模约 1550 万行 / 4.3 GB，且是【堆表（无聚集索引）】，
--   一次分配各脚本均按「缴费时间/接诊时间 + 开单/执行科室 + 项目代码」取数，
--   数据接入页又按 create_time 倒序分页，堆扫描导致查询缓慢。
--
-- 索引设计依据（来自 一次分配/*.sql 的实际访问路径 + 数据接入分页）
--   ① 时间过滤：缴费时间（医疗服务项目开单/执行积分、专项激励）
--   ② 时间过滤：接诊时间（门诊诊察类项目执行积分）
--   ③ 关联列：开单科室代码、执行科室代码、项目代码
--   ④ 分页排序：create_time DESC（数据接入页 order by）
--   ⑤ 分组/输出列：项目名称、项目大类、数量、金额
--
-- 设计要点
--   · 聚集索引建在 [缴费时间]：覆盖绝大多数脚本的区间过滤，同时消除堆表；
--     [接诊时间] 另建非聚集覆盖索引，避免与聚集键重复。
--   · 覆盖索引把常用输出列放进 INCLUDE，减少回表（RID Lookup）。
--   · 保留 create_time 的窄索引，服务数据接入页 order by create_time desc。
--   · 不建「%值%」可用的索引——前缀通配无法走索引，属查询语义问题，非索引可解。
--
-- 执行说明
--   · 必须在维护窗口执行：建聚集索引会重建整表，期间占用大量 IO 且阻塞写入，
--     预计 5~15 分钟（视磁盘），需要约 1 倍表大小的临时空间。
--   · 建议顺序：先备份 → 执行本脚本 → 更新统计信息。
--   · 若为 SQL Server 企业版，可给 CREATE CLUSTERED INDEX 追加 WITH (ONLINE = ON)；
--     标准版不支持 ONLINE，请停机执行。
-- =================================================================
-- 修改日志
-- 2026-11-17 00:00:00 | 初始化 | 删除历史 4 个非聚集索引，建立 1 聚集 + 4 非聚集覆盖索引。
-- =================================================================

SET NOCOUNT ON;
SET XACT_ABORT ON;

-- 前置检查：确认表存在
IF OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]', N'U') IS NULL
BEGIN
    RAISERROR(N'表 dbo.PF临时医疗服务项目26A 不存在，脚本终止。', 16, 1);
    RETURN;
END

/* -----------------------------------------------------------------
   1. 删除现有索引（仅删本表已知的历史索引，避免误删未知索引）
      · IX_PF临时医疗服务项目26A_Opt                 (项目代码, 缴费时间)
      · IX_PF临时医疗服务项目26A_OrderDept_Opt       (项目代码, 开单科室代码, 执行时间)
      · IX_PF26A_create_time                         (create_time)
      · IX_PF26A_kaidan_time                         (开单时间)
   ----------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]') AND name = N'IX_PF临时医疗服务项目26A_Opt')
    DROP INDEX [IX_PF临时医疗服务项目26A_Opt] ON [dbo].[PF临时医疗服务项目26A];

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]') AND name = N'IX_PF临时医疗服务项目26A_OrderDept_Opt')
    DROP INDEX [IX_PF临时医疗服务项目26A_OrderDept_Opt] ON [dbo].[PF临时医疗服务项目26A];

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]') AND name = N'IX_PF26A_create_time')
    DROP INDEX [IX_PF26A_create_time] ON [dbo].[PF临时医疗服务项目26A];

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]') AND name = N'IX_PF26A_kaidan_time')
    DROP INDEX [IX_PF26A_kaidan_time] ON [dbo].[PF临时医疗服务项目26A];

/* -----------------------------------------------------------------
   2. 聚集索引：缴费时间
      覆盖：医疗服务项目开单积分 / 执行积分 / 专项激励金额（按缴费时间区间过滤）
   ----------------------------------------------------------------- */
CREATE CLUSTERED INDEX CIX_PF26A_jiaofei_time
    ON [dbo].[PF临时医疗服务项目26A] ([缴费时间])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   3. 非聚集覆盖索引：开单科室 + 缴费时间
      覆盖：按开单科室统计（开单积分、专项激励），INCLUDE 常用输出列
   ----------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX IX_PF26A_kaidan_dept_time
    ON [dbo].[PF临时医疗服务项目26A] ([开单科室代码], [缴费时间])
    INCLUDE ([项目代码], [项目名称], [项目大类], [数量], [金额], [create_time])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   4. 非聚集覆盖索引：执行科室 + 缴费时间
      覆盖：医疗服务项目执行积分（按执行科室 × 项目聚合）
   ----------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX IX_PF26A_zhixing_dept_time
    ON [dbo].[PF临时医疗服务项目26A] ([执行科室代码], [缴费时间])
    INCLUDE ([项目代码], [项目名称], [项目大类], [数量], [金额], [create_time])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   5. 非聚集覆盖索引：项目代码 + 缴费时间
      覆盖：按项目过滤/关联 RVU 版本表（项目代码是各脚本的主要关联键）
   ----------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX IX_PF26A_project_time
    ON [dbo].[PF临时医疗服务项目26A] ([项目代码], [缴费时间])
    INCLUDE ([项目名称], [项目大类], [数量], [金额])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   6. 非聚集覆盖索引：接诊时间
      覆盖：门诊诊察类项目执行积分（按接诊时间窗口过滤，含"门诊"来源隔离）
   ----------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX IX_PF26A_jiezhen_time
    ON [dbo].[PF临时医疗服务项目26A] ([接诊时间])
    INCLUDE ([项目代码], [项目名称], [项目大类], [数量], [金额], [开单科室代码], [执行科室代码])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   7. 非聚集索引：create_time
      覆盖：数据接入页 order by create_time desc 分页（过滤条件为任意列 LIKE，无法走索引，
      本索引只用于避免排序）
   ----------------------------------------------------------------- */
CREATE NONCLUSTERED INDEX IX_PF26A_create_time
    ON [dbo].[PF临时医疗服务项目26A] ([create_time])
    WITH (DATA_COMPRESSION = PAGE);
GO

/* -----------------------------------------------------------------
   8. 更新统计信息（重建索引后建议执行）
   ----------------------------------------------------------------- */
UPDATE STATISTICS [dbo].[PF临时医疗服务项目26A] WITH FULLSCAN;
GO

/* -----------------------------------------------------------------
   9. 结果核对：列出最终索引结构
   ----------------------------------------------------------------- */
SELECT
     i.name                                                          AS 索引名
    ,i.type_desc                                                     AS 类型
    ,STUFF((SELECT N', ' + c.name
            FROM sys.index_columns ic
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 0
            ORDER BY ic.key_ordinal
            FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'')  AS 键列
    ,STUFF((SELECT N', ' + c.name
            FROM sys.index_columns ic
            JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
            WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND ic.is_included_column = 1
            ORDER BY ic.index_column_id
            FOR XML PATH(N''), TYPE).value(N'.', N'NVARCHAR(MAX)'), 1, 2, N'')  AS 包含列
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'[dbo].[PF临时医疗服务项目26A]')
  AND i.type > 0
ORDER BY i.type DESC, i.name;
GO
