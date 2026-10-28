/*
 Navicat Premium Dump SQL

 Source Server         : 127.0.0.1
 Source Server Type    : SQL Server
 Source Server Version : 16001210 (16.00.1210)
 Source Host           : 127.0.0.1:1433
 Source Catalog        : hospital_performance_dalian_derma
 Source Schema         : dbo

 Target Server Type    : SQL Server
 Target Server Version : 16001210 (16.00.1210)
 File Encoding         : 65001

 Date: 28/10/2026 11:14:03
*/


-- ----------------------------
-- Table structure for T_USER_INFO
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[T_USER_INFO]') AND type IN ('U'))
	DROP TABLE [dbo].[T_USER_INFO]
GO

CREATE TABLE [dbo].[T_USER_INFO] (
  [ID] decimal(20)  NOT NULL,
  [NAME] nvarchar(128) COLLATE Chinese_PRC_CI_AI  NULL,
  [DEPT_ID] decimal(20)  NULL,
  [STAFF_ID] decimal(20)  NULL,
  [HEAD_IMG] nvarchar(200) COLLATE Chinese_PRC_CI_AS  NULL,
  [SEX] nvarchar(32) COLLATE Chinese_PRC_CI_AS  NULL,
  [ID_CARD] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [IS_SYS] decimal(4)  NULL,
  [ACCOUNT_NO] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [PASSWORD] nvarchar(60) COLLATE Chinese_PRC_CI_AS  NULL,
  [STATUS] decimal(11)  NULL,
  [DELETE_FLAG] decimal(4)  NULL,
  [CREATE_USER] decimal(20)  NULL,
  [CREATE_TIME] datetime  NULL,
  [MODIFY_TIME] datetime  NULL,
  [MODIFY_USER] decimal(20)  NULL,
  [user_type] decimal(4) DEFAULT 1 NULL,
  [supplier_id] decimal(20)  NULL,
  [hospital_id] numeric(20)  NULL,
  [dept_scope_type] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [depot_scope_type] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [user_scope_type] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [supplier_scope_type] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [data_scope] decimal(4)  NULL,
  [last_access_system_code] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [last_access_time] datetime  NULL,
  [company_id] bigint  NULL
)
GO

ALTER TABLE [dbo].[T_USER_INFO] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'主键id',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'姓名',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门ID',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'DEPT_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'员工ID',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'STAFF_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'头像',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'HEAD_IMG'
GO

EXEC sp_addextendedproperty
'MS_Description', N'性别',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'SEX'
GO

EXEC sp_addextendedproperty
'MS_Description', N'身份证号',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'ID_CARD'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否管理员，1：管理员，2：非管理员',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'IS_SYS'
GO

EXEC sp_addextendedproperty
'MS_Description', N'手机号（账号）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'ACCOUNT_NO'
GO

EXEC sp_addextendedproperty
'MS_Description', N'登录密码',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'PASSWORD'
GO

EXEC sp_addextendedproperty
'MS_Description', N'状态 1.启用 0.禁用',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'STATUS'
GO

EXEC sp_addextendedproperty
'MS_Description', N'删除标识(0:未删除,1:已删除)',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'DELETE_FLAG'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建人',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'CREATE_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建时间',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'CREATE_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改时间',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'MODIFY_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改人',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'MODIFY_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'用户类型  0 外部单位 1 内部单位  （必传）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'user_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'供应商id',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'supplier_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'医院id',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'hospital_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'部门权限类型（1：全部部门；2：自定义权限；3：任职科室）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'dept_scope_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'仓库权限类型（1：全部仓库；2：自定义权限）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'depot_scope_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'人员权限类型（1：全部人员；2：自定义权限；3：任职科室人员；4：仅自己）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'user_scope_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'供应商权限类型（1：全部供应商；2：自定义权限）',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'supplier_scope_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'数据权限：1：所有数据权限，2：自定义数据权限，3 任职科室权限   4：仅自己查看',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'data_scope'
GO

EXEC sp_addextendedproperty
'MS_Description', N'最后一次访问系统编码',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'last_access_system_code'
GO

EXEC sp_addextendedproperty
'MS_Description', N'最后一次访问系统时间',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO',
'COLUMN', N'last_access_time'
GO

EXEC sp_addextendedproperty
'MS_Description', N'用户表',
'SCHEMA', N'dbo',
'TABLE', N'T_USER_INFO'
GO

