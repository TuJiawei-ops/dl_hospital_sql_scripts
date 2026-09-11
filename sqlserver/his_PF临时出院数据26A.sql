/*
  SQL Server 建表脚本 (Oracle 方言转化等效版)

  Source Dialect         : Oracle (Oracle Database 21c Express Edition)
  Target Dialect         : SQL Server (T-SQL)
  Source Schema          : DL_PFM
  Target Schema          : dbo
  Source File            : oracle/PF临时出院数据26A.sql

  修改日志：
  2026-09-11 13:47:51 | 脚本新建 | 由 Oracle DDL 转化生成 SQL Server 等效建表脚本，幂等 DROP + 方括号包裹 + 方言参数剥离

  Date: 11/09/2026 13:47:51
*/


-- ----------------------------
-- Table structure for PF临时出院数据26A
-- ----------------------------
IF OBJECT_ID('dbo.[PF临时出院数据26A]', 'U') IS NOT NULL DROP TABLE dbo.[PF临时出院数据26A];

CREATE TABLE dbo.[PF临时出院数据26A] (
  [住院ID] NVARCHAR(243) NULL,
  [出院科室代码] BIGINT NULL,
  [出院科室] NVARCHAR(300) NULL,
  [出院时间] DATETIME NULL
);
