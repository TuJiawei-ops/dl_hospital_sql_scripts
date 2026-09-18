/*
  SQL Server 建表脚本 (Oracle 方言转化等效版)

  Relative Path          : sqlserver/PF临时医疗服务项目26A.sql
  Source Dialect         : Oracle (Oracle Database 21c Express Edition)
  Target Dialect         : SQL Server (T-SQL)
  Source Schema          : DL_PFM
  Target Schema          : dbo
  Source File            : oracle/PF临时医疗服务项目26A.sql

  修改日志：
  2026-09-18 14:50:00 | 结构对齐 | 对齐 Oracle 源表最新 DDL（21 → 25 列）：在 [HIS主键] 之后、[来源] 之前新增 4 列，严格保持与 Oracle 物理列序（第 21→24 位）一一对应——[接诊时间] DATETIME NULL / [完成时间] DATETIME NULL / [挂号发生时间] DATETIME NULL / [费用性质] NVARCHAR(36) NULL。类型换算依据既有惯例：Oracle DATE → SQL Server DATETIME；Oracle CHAR(12 BYTE) → NVARCHAR(12×3=36)（UTF-8 三倍膨胀防护，与既有 [开单人] VARCHAR2(41 BYTE)→NVARCHAR(123) 换算惯例一致）。[来源] 为存量列（NVARCHAR(12)），本次不新增、不改宽，避免破坏与 python/sync_oracle_to_sqlserver.py 及 seatunnel/oracle_to_sqlserver.conf 既有的列宽契约。同步补齐头部 Relative Path 标注。
  2026-09-11 13:45:19 | 脚本新建 | 由 Oracle DDL 转化生成 SQL Server 等效建表脚本，幂等 DROP + 方括号包裹 + 方言参数剥离 + 数值强制 DECIMAL(18,8)

  Date: 11/09/2026 13:45:19

  遗留待办（本次未处理，范围外）：
  1. python/sync_oracle_to_sqlserver.py 的 PF临时医疗服务项目26A TableSpec（第 194-216 行）仍为 21 列，
     未纳入本次 4 个新列 → 同步后新列将恒为 NULL。
  2. seatunnel/oracle_to_sqlserver.conf 的 Source query（第 113 行）与 Sink query（第 196 行）
     仍为 21 列显式清单，同样未纳入 4 个新列。
  上述两处须同步补齐后，本表 4 个新列方能真正落数。
*/


-- ----------------------------
-- Table structure for PF临时医疗服务项目26A
-- ----------------------------
IF OBJECT_ID('dbo.[PF临时医疗服务项目26A]', 'U') IS NOT NULL DROP TABLE dbo.[PF临时医疗服务项目26A];

CREATE TABLE dbo.[PF临时医疗服务项目26A] (
  [项目大类] NVARCHAR(60) NULL,
  [项目代码] NVARCHAR(60) NULL,
  [项目名称] NVARCHAR(600) NULL,
  [开单科室代码] BIGINT NULL,
  [开单科室] NVARCHAR(300) NULL,
  [开单人员代码] BIGINT NULL,
  [开单人] NVARCHAR(123) NULL,
  [开单时间] DATETIME NULL,
  [执行科室代码] BIGINT NULL,
  [执行科室] NVARCHAR(300) NULL,
  [执行人员代码] BIGINT NULL,
  [执行人员] NVARCHAR(60) NULL,
  [执行时间] DATETIME NULL,
  [数量] DECIMAL(18,8) NULL,
  [单价] DECIMAL(18,8) NULL,
  [金额] DECIMAL(18,8) NULL,
  [缴费时间] DATETIME NULL,
  [患者ID] BIGINT NULL,
  [挂号ID] NVARCHAR(243) NULL,
  [HIS主键] BIGINT NULL,
  [接诊时间] DATETIME NULL,
  [完成时间] DATETIME NULL,
  [挂号发生时间] DATETIME NULL,
  [费用性质] NVARCHAR(36) NULL,
  [来源] NVARCHAR(12) NULL
);
