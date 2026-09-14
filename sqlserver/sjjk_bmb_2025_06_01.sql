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

 Date: 14/09/2026 14:47:07
*/


-- ----------------------------
-- Table structure for sjjk_bmb_2025_06_01
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[sjjk_bmb_2025_06_01]') AND type IN ('U'))
	DROP TABLE [dbo].[sjjk_bmb_2025_06_01]
GO

CREATE TABLE [dbo].[sjjk_bmb_2025_06_01] (
  [id] bigint  NOT NULL,
  [上级id] bigint  NULL,
  [编码] nvarchar(10) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [名称] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [简码] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NULL,
  [位置] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [末级] tinyint  NULL,
  [建档时间] datetime  NULL,
  [撤档时间] datetime  NULL,
  [环境类别] nvarchar(10) COLLATE Chinese_PRC_CI_AS  NULL,
  [部门负责人] bigint  NULL,
  [站点] nvarchar(3) COLLATE Chinese_PRC_CI_AS  NULL,
  [顺序] smallint  NULL,
  [最后修改时间] datetime  NULL,
  [别名] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NULL,
  [位置编码] nvarchar(4) COLLATE Chinese_PRC_CI_AS  NULL,
  [资源id] nvarchar(36) COLLATE Chinese_PRC_CI_AS  NULL,
  [create_time] datetime DEFAULT getdate() NOT NULL
)
GO

ALTER TABLE [dbo].[sjjk_bmb_2025_06_01] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门表',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_bmb_2025_06_01'
GO


-- ----------------------------
-- Indexes structure for table sjjk_bmb_2025_06_01
-- ----------------------------
CREATE NONCLUSTERED INDEX [idx_bmb_name_id]
ON [dbo].[sjjk_bmb_2025_06_01] (
  [名称] ASC
)
GO

CREATE NONCLUSTERED INDEX [IX_bmb_Name]
ON [dbo].[sjjk_bmb_2025_06_01] (
  [名称] ASC
)
GO


-- ----------------------------
-- Primary Key structure for table sjjk_bmb_2025_06_01
-- ----------------------------
ALTER TABLE [dbo].[sjjk_bmb_2025_06_01] ADD CONSTRAINT [PK__sjjk_bmb__3213E83F63567086] PRIMARY KEY CLUSTERED ([id])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

