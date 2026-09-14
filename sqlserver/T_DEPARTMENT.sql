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

 Date: 14/09/2026 11:16:10
*/


-- ----------------------------
-- Table structure for T_DEPARTMENT
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[T_DEPARTMENT]') AND type IN ('U'))
	DROP TABLE [dbo].[T_DEPARTMENT]
GO

CREATE TABLE [dbo].[T_DEPARTMENT] (
  [ID] decimal(20)  NOT NULL,
  [NAME] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [CODE] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [ABBREVIATION] nvarchar(20) COLLATE Chinese_PRC_CI_AI DEFAULT '' NULL,
  [PERSON_LIABLE] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [COST_CENTRE] decimal(20)  NULL,
  [IS_FICTITIOU] decimal(4)  NULL,
  [PINYIN_CODE] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [TYPE_ID] decimal(20)  NULL,
  [P_ID] decimal(20)  NULL,
  [COMPANY_ID] decimal(20)  NULL,
  [IS_GK_DEPT] decimal(4)  NULL,
  [STATUS] decimal(4)  NULL,
  [CREATE_USER] decimal(20)  NULL,
  [CREATE_TIME] datetime2(7)  NULL,
  [MODIFY_USER] decimal(20)  NULL,
  [MODIFY_TIME] datetime2(7)  NULL,
  [DELETE_FLAG] decimal(4)  NOT NULL,
  [DEPTTYPE] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [CREATEDATE] datetime2(7)  NULL,
  [OWN_ALL_PRODUCT] nvarchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT 1 NULL,
  [IS_FUNCTIONAL_DEPT] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [IS_NURSING_UNIT] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [sfhsdy] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [TYPE_NAME] AS (case [DEPTTYPE] when '0' then N'医院' when '1' then N'行政后勤' when '2' then N'医疗技术' when '3' then N'临床服务' when '4' then N'医疗辅助' when '5' then N'乡村卫生院' when '6' then N'院领导' when '7' then N'医生' when '8' then N'医技' when '9' then N'护理' when '10' then N'药剂' when '11' then N'行后' when '12' then N'医' when '13' then N'供应' when '14' then N'护' when '91' then N'中医科' when '92' then N'手术麻醉科' else N'未知' end) PERSISTED NOT NULL,
  [children_ids] varchar(255) COLLATE Chinese_PRC_CI_AS DEFAULT 0 NULL,
  [temp] bit  NULL,
  [director_ids] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [deputy_director_ids] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [is_clinical_dept] bit DEFAULT 0 NULL
)
GO

ALTER TABLE [dbo].[T_DEPARTMENT] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'主键ID',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门名称',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门编码',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门简称',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'ABBREVIATION'
GO

EXEC sp_addextendedproperty
'MS_Description', N'责任人ids',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'PERSON_LIABLE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'成本中心',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'COST_CENTRE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否虚拟部门',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'IS_FICTITIOU'
GO

EXEC sp_addextendedproperty
'MS_Description', N'拼音编码',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'PINYIN_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门类型',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'TYPE_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'上级部门',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'P_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'关联公司',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'COMPANY_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否归口科室',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'IS_GK_DEPT'
GO

EXEC sp_addextendedproperty
'MS_Description', N'状态 1.启用 0.禁用',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'STATUS'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建者',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'CREATE_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建时间',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'CREATE_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改者',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'MODIFY_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改时间',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'MODIFY_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'删除标识(0:未删除,1:已删除)',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'DELETE_FLAG'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门类型(医院 0  行政后勤1 医疗技术 2 临床服务3 医疗辅助4 乡村卫生院 5)',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'DEPTTYPE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门成立时间',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'CREATEDATE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否为职能科室',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'IS_FUNCTIONAL_DEPT'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否为护理单元',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'IS_NURSING_UNIT'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否核算单元',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'sfhsdy'
GO

EXEC sp_addextendedproperty
'MS_Description', N'下级科室id',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'children_ids'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否缓存科室 0-是 1-否',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'temp'
GO

EXEC sp_addextendedproperty
'MS_Description', N'科室主任',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'director_ids'
GO

EXEC sp_addextendedproperty
'MS_Description', N'科室副主任',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'deputy_director_ids'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否临床科室0否1是',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT',
'COLUMN', N'is_clinical_dept'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门信息',
'SCHEMA', N'dbo',
'TABLE', N'T_DEPARTMENT'
GO


-- ----------------------------
-- Indexes structure for table T_DEPARTMENT
-- ----------------------------
CREATE NONCLUSTERED INDEX [idx_tdepartment_name_copy1_copy1_copy5_copy1]
ON [dbo].[T_DEPARTMENT] (
  [NAME] ASC
)
INCLUDE ([ID], [CODE])
GO


-- ----------------------------
-- Primary Key structure for table T_DEPARTMENT
-- ----------------------------
ALTER TABLE [dbo].[T_DEPARTMENT] ADD CONSTRAINT [PK__T_DEPART__3214EC272D3D5388] PRIMARY KEY CLUSTERED ([ID])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

