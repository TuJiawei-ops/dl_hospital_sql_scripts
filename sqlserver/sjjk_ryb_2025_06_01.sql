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

 Date: 16/09/2026 09:10:49
*/


-- ----------------------------
-- Table structure for sjjk_ryb_2025_06_01
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[sjjk_ryb_2025_06_01]') AND type IN ('U'))
	DROP TABLE [dbo].[sjjk_ryb_2025_06_01]
GO

CREATE TABLE [dbo].[sjjk_ryb_2025_06_01] (
  [id] int  NOT NULL,
  [编号] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [姓名] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [简码] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [身份证号] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [出生日期] datetime  NULL,
  [性别] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [民族] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [工作日期] datetime  NULL,
  [办公室电话] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [电子邮件] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [执业类别] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [执业范围] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [执业证号] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [管理职务] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [专业技术职务] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [聘任技术职务] numeric(20,2)  NULL,
  [学历] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [所学专业] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [留学时间] numeric(20,2)  NULL,
  [留学渠道] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [接受培训] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [科研课题] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [建档时间] datetime  NULL,
  [撤档时间] datetime  NULL,
  [撤档原因] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [别名] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [资格证书号] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [执业开始日期] datetime  NULL,
  [处方权标志] numeric(20,2)  NULL,
  [手术等级] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [站点] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [移动电话] numeric(20,2)  NULL,
  [顺序] numeric(20,2)  NULL,
  [最后修改时间] datetime  NULL,
  [门诊特殊医嘱权限] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [住院特殊医嘱权限] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [帐号到期时间] datetime  NULL,
  [资源id] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [国家医师编码] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [create_time] datetime DEFAULT getdate() NOT NULL
)
GO

ALTER TABLE [dbo].[sjjk_ryb_2025_06_01] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'人员表',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_ryb_2025_06_01'
GO


-- ----------------------------
-- Indexes structure for table sjjk_ryb_2025_06_01
-- ----------------------------
CREATE NONCLUSTERED INDEX [idx_ryb_name]
ON [dbo].[sjjk_ryb_2025_06_01] (
  [姓名] ASC
)
INCLUDE ([编号])
GO

CREATE NONCLUSTERED INDEX [IX_ryb_Name]
ON [dbo].[sjjk_ryb_2025_06_01] (
  [姓名] ASC
)
GO


-- ----------------------------
-- Primary Key structure for table sjjk_ryb_2025_06_01
-- ----------------------------
ALTER TABLE [dbo].[sjjk_ryb_2025_06_01] ADD CONSTRAINT [PK__sjjk_ryb__3213E83F60517239] PRIMARY KEY CLUSTERED ([id])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

