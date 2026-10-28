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

 Date: 28/10/2026 10:59:21
*/


-- ----------------------------
-- Table structure for T_STAFF
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[T_STAFF]') AND type IN ('U'))
	DROP TABLE [dbo].[T_STAFF]
GO

CREATE TABLE [dbo].[T_STAFF] (
  [ID] decimal(20)  NOT NULL,
  [NAME] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [USER_URL] nvarchar(max) COLLATE Chinese_PRC_CI_AS  NULL,
  [USER_CODE] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [DEPARTMENT_ID] decimal(20)  NULL,
  [HOSPITAL] decimal(20)  NULL,
  [DELETE_FLAG] decimal(4)  NOT NULL,
  [CREATE_USER] decimal(20)  NULL,
  [CREATE_TIME] datetime  NULL,
  [MODIFY_USER] decimal(20)  NULL,
  [MODIFY_TIME] datetime  NULL,
  [PER_BIRTH_DATE] datetime  NULL,
  [PER_GENDER] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [PER_ID_CARD] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [PER_BANK_CARD] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [PER_WORK_PHONE] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [PER_PHONE] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [PER_WORKING_TIME] datetime  NULL,
  [PER_JOINING_TIME] datetime  NULL,
  [PER_STATUS] nvarchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [OCCUPATION] decimal(20)  NULL,
  [USER_STATE] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [ADD_COMPANY_TIME] datetime  NULL,
  [highest_education] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [position_id] numeric(20)  NULL,
  [user_type_id] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [title_id] numeric(20)  NULL,
  [classify] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [electronic_signature_paths] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [bank_card_property] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [gz_bank_card_type] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [gz_bank_card_line_number] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [gz_bank_card_username] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [staff_sequence] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [is_nurse] numeric(18)  NULL,
  [occupation_id] numeric(20)  NULL,
  [dept_id] numeric(20)  NULL,
  [DEPARTMENT_NAME] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [is_add_account] decimal(10)  NULL,
  [is_setup_posts] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [setup_posts_date] date  NULL,
  [departure_time] date  NULL,
  [rehiring_time] date  NULL,
  [DEPT_NAME] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NULL,
  [RISK_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [RISK_TYPE_NAME] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NULL,
  [USER_TYPE_NAME] AS (case [user_type_id] when 'fanpin' then '返聘' when 'jicai' then '集才' when 'pinyong' then '聘用' when 'zhengshi' then '正式' else [user_type_id] end),
  [retire_date] date  NULL,
  [retire_remark] nvarchar(200) COLLATE Chinese_PRC_CI_AS  NULL,
  [is_retired] AS (case when [retire_date] IS NOT NULL AND [retire_date]<=getdate() then (1) else (0) end) NOT NULL,
  [setup_formal_date] date  NULL,
  [setup_formal_remark] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL,
  [is_setup_formal] AS (case when [setup_formal_date] IS NOT NULL AND [setup_formal_date]<=getdate() then (1) else (0) end) NOT NULL,
  [salary_fixed_date] date  NULL,
  [salary_non_fixed_date] date  NULL,
  [salary_type_remark] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL,
  [salary_type] nvarchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [exit_setup_posts_date] date  NULL,
  [exit_setup_posts_remark] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL,
  [setup_posts_remark] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL,
  [job_id] bigint  NULL,
  [temp] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL
)
GO

ALTER TABLE [dbo].[T_STAFF] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'主键ID',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'员工名称',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'头像地址',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'USER_URL'
GO

EXEC sp_addextendedproperty
'MS_Description', N'用户编号',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'USER_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'人事部门ID',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'DEPARTMENT_ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'医院',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'HOSPITAL'
GO

EXEC sp_addextendedproperty
'MS_Description', N'删除标识(0:未删除,1:已删除)',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'DELETE_FLAG'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建者',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'CREATE_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'创建时间',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'CREATE_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改者',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'MODIFY_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'修改时间',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'MODIFY_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'出生日期',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_BIRTH_DATE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'性别',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_GENDER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'身份证号',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_ID_CARD'
GO

EXEC sp_addextendedproperty
'MS_Description', N'银行卡号',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_BANK_CARD'
GO

EXEC sp_addextendedproperty
'MS_Description', N'手机',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_WORK_PHONE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'电话',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_PHONE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'参与工作时间',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_WORKING_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'加入公司时间',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_JOINING_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'员工状态',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'PER_STATUS'
GO

EXEC sp_addextendedproperty
'MS_Description', N'职称',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'OCCUPATION'
GO

EXEC sp_addextendedproperty
'MS_Description', N'员工状态',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'USER_STATE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'加入公司时间',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'ADD_COMPANY_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'人员类别',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'user_type_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'人员分类',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'classify'
GO

EXEC sp_addextendedproperty
'MS_Description', N'电子签名地址',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'electronic_signature_paths'
GO

EXEC sp_addextendedproperty
'MS_Description', N'账户性质',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'bank_card_property'
GO

EXEC sp_addextendedproperty
'MS_Description', N'工资银行卡类型',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'gz_bank_card_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'工资卡行联号',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'gz_bank_card_line_number'
GO

EXEC sp_addextendedproperty
'MS_Description', N'工资卡户名',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'gz_bank_card_username'
GO

EXEC sp_addextendedproperty
'MS_Description', N'职工序列',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'staff_sequence'
GO

EXEC sp_addextendedproperty
'MS_Description', N'职称id',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'occupation_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'岗位',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'dept_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否创建人员 1.是 0否',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'is_add_account'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否参加岗位设置',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'is_setup_posts'
GO

EXEC sp_addextendedproperty
'MS_Description', N'参加岗位设置日期',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'setup_posts_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'退休日期：行政生效日期，用于十三薪与绩效截断核算',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'retire_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'退休变更原因',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'retire_remark'
GO

EXEC sp_addextendedproperty
'MS_Description', N'退休状态计算列：1为已退休，0为在职。由系统根据退休日期动态判定',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'is_retired'
GO

EXEC sp_addextendedproperty
'MS_Description', N'入编日期：正式进入编制的行政生效日期',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'setup_formal_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'入编备注：记录入编相关的特殊说明',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'setup_formal_remark'
GO

EXEC sp_addextendedproperty
'MS_Description', N'是否入编计算列：1为已入编，0为非在编。基于入编日期动态判定',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'is_setup_formal'
GO

EXEC sp_addextendedproperty
'MS_Description', N'转为固薪的生效日期',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'salary_fixed_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'转为非固薪的生效日期',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'salary_non_fixed_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'固薪原因',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'salary_type_remark'
GO

EXEC sp_addextendedproperty
'MS_Description', N'当前薪酬类别：固薪、非固薪。由用户手动维护，为业务核算的核心依据',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'salary_type'
GO

EXEC sp_addextendedproperty
'MS_Description', N'退出岗位设置日期：行政生效日期，用于绩效结算截断',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'exit_setup_posts_date'
GO

EXEC sp_addextendedproperty
'MS_Description', N'退出岗位设置原因：记录员工退出岗设的具体政策或行政依据',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'exit_setup_posts_remark'
GO

EXEC sp_addextendedproperty
'MS_Description', N'参加岗位设置原因',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'setup_posts_remark'
GO

EXEC sp_addextendedproperty
'MS_Description', N'职务主键ID',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF',
'COLUMN', N'job_id'
GO

EXEC sp_addextendedproperty
'MS_Description', N'用户',
'SCHEMA', N'dbo',
'TABLE', N'T_STAFF'
GO


-- ----------------------------
-- Primary Key structure for table T_STAFF
-- ----------------------------
ALTER TABLE [dbo].[T_STAFF] ADD CONSTRAINT [SYS_C0011357] PRIMARY KEY CLUSTERED ([ID])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

