/*
  SQL Server 建表脚本 (Oracle 方言转化等效版)

  Source Dialect         : Oracle (Oracle Database 21c Express Edition)
  Target Dialect         : SQL Server (T-SQL)
  Source Schema          : DL_PFM
  Target Schema          : dbo
  Source File            : oracle/PF临时医疗服务项目26A.sql

  修改日志：
  2026-09-11 13:45:19 | 脚本新建 | 由 Oracle DDL 转化生成 SQL Server 等效建表脚本，幂等 DROP + 方括号包裹 + 方言参数剥离 + 数值强制 DECIMAL(18,8)

  Date: 11/09/2026 13:45:19
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
  [来源] NVARCHAR(12) NULL
);
