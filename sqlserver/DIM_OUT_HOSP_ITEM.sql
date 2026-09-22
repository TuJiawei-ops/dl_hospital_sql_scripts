/*
 Navicat Premium Dump SQL

 Source Server         : 127.0.0.1
 Source Server Type    : SQL Server
 Source Server Version : 16001200 (16.00.1200)
 Source Host           : 127.0.0.1:1433
 Source Catalog        : hospital_performance_dalian_derma
 Source Schema         : dbo

 Target Server Type    : SQL Server
 Target Server Version : 16001200 (16.00.1200)
 File Encoding         : 65001

 Date: 22/09/2026 17:17:33
*/


-- ----------------------------
-- Table structure for DIM_OUT_HOSP_ITEM
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[DIM_OUT_HOSP_ITEM]') AND type IN ('U'))
	DROP TABLE [dbo].[DIM_OUT_HOSP_ITEM]
GO

CREATE TABLE [dbo].[DIM_OUT_HOSP_ITEM] (
  [ITEM_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [ITEM_NAME] nvarchar(200) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [MEAS_UNIT] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [REMARK] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL,
  [CREATE_USER] varchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT 'SYSTEM' NOT NULL,
  [CREATE_TIME] datetime DEFAULT getdate() NOT NULL,
  [UPDATE_USER] varchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT 'SYSTEM' NOT NULL,
  [UPDATE_TIME] datetime DEFAULT getdate() NOT NULL
)
GO

ALTER TABLE [dbo].[DIM_OUT_HOSP_ITEM] SET (LOCK_ESCALATION = TABLE)
GO


-- ----------------------------
-- Primary Key structure for table DIM_OUT_HOSP_ITEM
-- ----------------------------
ALTER TABLE [dbo].[DIM_OUT_HOSP_ITEM] ADD CONSTRAINT [PK_DIM_OUT_HOSP_ITEM] PRIMARY KEY CLUSTERED ([ITEM_CODE])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

