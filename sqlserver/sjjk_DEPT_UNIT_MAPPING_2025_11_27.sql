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

 Date: 12/09/2026 17:29:10
*/


-- ----------------------------
-- Table structure for sjjk_DEPT_UNIT_MAPPING_2025_11_27
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27]') AND type IN ('U'))
	DROP TABLE [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27]
GO

CREATE TABLE [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (
  [ID] int  IDENTITY(1,1) NOT NULL,
  [HIS_DEPT_CODE] varchar(300) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [HIS_DEPT_NAME] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [PERFORM_PERSON_TYPE] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [HPS_DEPT_CODE] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [HPS_DEPT_NAME] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [START_DATE] datetime2(7)  NULL,
  [END_DATE] datetime2(7)  NULL,
  [REMARK] varchar(300) COLLATE Chinese_PRC_CI_AS  NULL,
  [create_time] datetime DEFAULT getdate() NOT NULL,
  [PERFORM_PERSON_TYPE_CODE] varchar(100) COLLATE Chinese_PRC_CI_AS  NULL
)
GO

ALTER TABLE [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'主键ID',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'HIS科室编码',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'HIS_DEPT_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'HIS科室名称',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'HIS_DEPT_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'执行人员类型名称',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'PERFORM_PERSON_TYPE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'HPS绩效科室编码',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'HPS_DEPT_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'HPS绩效科室名称',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'HPS_DEPT_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'映射开始时间',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'START_DATE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'映射结束时间',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'END_DATE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'备注',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'REMARK'
GO

EXEC sp_addextendedproperty
'MS_Description', N'记录创建时间',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'create_time'
GO

EXEC sp_addextendedproperty
'MS_Description', N'执行人员类型编码',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27',
'COLUMN', N'PERFORM_PERSON_TYPE_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'科室与核算单元映射表',
'SCHEMA', N'dbo',
'TABLE', N'sjjk_DEPT_UNIT_MAPPING_2025_11_27'
GO


-- ----------------------------
-- Auto increment value for sjjk_DEPT_UNIT_MAPPING_2025_11_27
-- ----------------------------
DBCC CHECKIDENT ('[dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27]', RESEED, 286)
GO


-- ----------------------------
-- Primary Key structure for table sjjk_DEPT_UNIT_MAPPING_2025_11_27
-- ----------------------------
ALTER TABLE [dbo].[sjjk_DEPT_UNIT_MAPPING_2025_11_27] ADD CONSTRAINT [PK__sjjk_DEP__3214EC275BE38077] PRIMARY KEY CLUSTERED ([ID], [HIS_DEPT_CODE])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

