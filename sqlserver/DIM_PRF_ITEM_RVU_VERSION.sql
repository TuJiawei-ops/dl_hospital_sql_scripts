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

 Date: 12/09/2026 16:54:51
*/


-- ----------------------------
-- Table structure for DIM_PRF_ITEM_RVU_VERSION
-- ----------------------------
IF EXISTS (SELECT * FROM sys.all_objects WHERE object_id = OBJECT_ID(N'[dbo].[DIM_PRF_ITEM_RVU_VERSION]') AND type IN ('U'))
	DROP TABLE [dbo].[DIM_PRF_ITEM_RVU_VERSION]
GO

CREATE TABLE [dbo].[DIM_PRF_ITEM_RVU_VERSION] (
  [VERSION_NO] varchar(20) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [VERSION_DESC] nvarchar(200) COLLATE Chinese_PRC_CI_AS  NULL,
  [ORG_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT '' NOT NULL,
  [ORG_NAME] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NULL,
  [SRC_SYS_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [PROJ_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [PROJ_NAME] nvarchar(200) COLLATE Chinese_PRC_CI_AS  NULL,
  [MEAS_UNIT] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [RVU_VAL] numeric(12,4) DEFAULT 0.0000 NOT NULL,
  [ITEM_CAT_CODE] varchar(50) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [ITEM_CAT_NAME] nvarchar(100) COLLATE Chinese_PRC_CI_AS  NOT NULL,
  [UNIT_PRICE] numeric(18,4) DEFAULT 0.0000 NOT NULL,
  [OPR_LEVEL_CODE] varchar(20) COLLATE Chinese_PRC_CI_AS  NULL,
  [OPR_LEVEL_NAME] nvarchar(50) COLLATE Chinese_PRC_CI_AS  NULL,
  [CREATE_USER] varchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT 'SYSTEM' NOT NULL,
  [CREATE_TIME] datetime DEFAULT getdate() NOT NULL,
  [UPDATE_USER] varchar(50) COLLATE Chinese_PRC_CI_AS DEFAULT 'SYSTEM' NOT NULL,
  [UPDATE_TIME] datetime DEFAULT getdate() NOT NULL,
  [ID] bigint  NULL,
  [DECISION_COFF] decimal(18,4) DEFAULT 1.0000 NOT NULL,
  [EXEC_COFF] decimal(5,4) DEFAULT 1.0000 NOT NULL,
  [REMARK] varchar(255) COLLATE Chinese_PRC_CI_AS  NULL,
  [SCORE_REASON] nvarchar(500) COLLATE Chinese_PRC_CI_AS  NULL
)
GO

ALTER TABLE [dbo].[DIM_PRF_ITEM_RVU_VERSION] SET (LOCK_ESCALATION = TABLE)
GO

EXEC sp_addextendedproperty
'MS_Description', N'版本号（纯顺序流水号文本，如 V1, V2, V3；版本寻址由 MAP_PRF_SCHEME_MASTER 方案调度协议通过 VERSION_NO 显式路由）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'VERSION_NO'
GO

EXEC sp_addextendedproperty
'MS_Description', N'版本方案业务中文描述',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'VERSION_DESC'
GO

EXEC sp_addextendedproperty
'MS_Description', N'机构编码（多租户物理隔离主键）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'ORG_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'机构名称',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'ORG_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'源系统编码（外键参照 DIM_SRC_SYSTEM，如 HIS/OPER）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'SRC_SYS_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'收费项目编码（统一对齐事实层 PROJ_CODE，防止血缘断裂）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'PROJ_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'收费项目名称',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'PROJ_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'原始计费单位/计数方式（如: 次/小时/例/盘，防止同一个项目多单位导致的计算崩盘）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'MEAS_UNIT'
GO

EXEC sp_addextendedproperty
'MS_Description', N'单项绩效点数/相对分值（基于该特定计费单位的无量纲原子客观属性）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'RVU_VAL'
GO

EXEC sp_addextendedproperty
'MS_Description', N'绩效标准核算分类编码（如: CLINIC=临床类, TECH=技术类），随版本动态隔离',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'ITEM_CAT_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'绩效标准核算分类名称',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'ITEM_CAT_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'历史参考单价（仅供财务边界审计与运营测算参考，不参与点数核心计算）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'UNIT_PRICE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'手术等级编码（项目固有客观物理属性，降维拉平自 DWD_OPER_RECORD_DETAIL.OPR_LEVEL_CODE，非手术项目 NULL）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'OPR_LEVEL_CODE'
GO

EXEC sp_addextendedproperty
'MS_Description', N'手术等级名称（项目固有客观物理属性，如: 三级手术，非手术项目 NULL）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'OPR_LEVEL_NAME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'归一化审计：初始化创建人',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'CREATE_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'归一化审计：初始化创建时间',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'CREATE_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'归一化审计：最后修改人',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'UPDATE_USER'
GO

EXEC sp_addextendedproperty
'MS_Description', N'归一化审计：最后修改时间戳',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'UPDATE_TIME'
GO

EXEC sp_addextendedproperty
'MS_Description', N'【系统冗余错误功能】架构妥协：为统一开发接口临时加入的冗余ID字段',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'ID'
GO

EXEC sp_addextendedproperty
'MS_Description', N'诊疗决策系数（用于体现临床医生开单决策的风险与技术含量，未配置默认 1.0000 降维兜底）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'DECISION_COFF'
GO

EXEC sp_addextendedproperty
'MS_Description', N'执行系数（用于技术、护理、手术等实际执行动作的难度/风险技术修正，未配置默认 1.0000 降维兜底）',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'EXEC_COFF'
GO

EXEC sp_addextendedproperty
'MS_Description', N'备注说明',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'REMARK'
GO

EXEC sp_addextendedproperty
'MS_Description', N'分值与系数评估/评分理由依据',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION',
'COLUMN', N'SCORE_REASON'
GO

EXEC sp_addextendedproperty
'MS_Description', N'医院收费项目绩效点数版本维表。核心资产项目点数表，资产无状态，调度控期间。版本寻址由 MAP_PRF_SCHEME_MASTER 方案调度协议通过 VERSION_NO 显式路由，物理表内严禁任何状态位标记。',
'SCHEMA', N'dbo',
'TABLE', N'DIM_PRF_ITEM_RVU_VERSION'
GO


-- ----------------------------
-- Indexes structure for table DIM_PRF_ITEM_RVU_VERSION
-- ----------------------------
CREATE NONCLUSTERED INDEX [IX_DIM_PRF_ITEM_RVU_VERSION_LOOKUP]
ON [dbo].[DIM_PRF_ITEM_RVU_VERSION] (
  [ORG_CODE] ASC,
  [SRC_SYS_CODE] ASC,
  [PROJ_CODE] ASC,
  [MEAS_UNIT] ASC
)
GO


-- ----------------------------
-- Primary Key structure for table DIM_PRF_ITEM_RVU_VERSION
-- ----------------------------
ALTER TABLE [dbo].[DIM_PRF_ITEM_RVU_VERSION] ADD CONSTRAINT [PK_DIM_PRF_ITEM_RVU_VERSION] PRIMARY KEY CLUSTERED ([ORG_CODE], [VERSION_NO], [PROJ_CODE], [MEAS_UNIT])
WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON)  
ON [PRIMARY]
GO

