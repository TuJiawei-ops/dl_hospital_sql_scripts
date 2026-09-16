-- ============================================================
-- 目录路径：02_DDL_CORE/03_MAP/MAP_MDM_STAFF.sql
-- 物理表名：MAP_MDM_STAFF
-- 核心逻辑：异构人员 (SRC) -> 绩效内核标准人员 (STAFF) 的路由网关
-- 核心哲学：
--   1. [类型收紧] STAFF_CODE: VARCHAR(50) → CHAR(6)
--      6 位纯数字顺序流水号文本，彻底规避前导零丢失的工程风险
--   2. [主键纠偏] PK 锁定原子粒度 (SRC_ORG_CODE, SRC_SYS_CODE, SRC_STAFF_CODE)
--      确保一个外部源人员在同院区同系统下有且仅能路由到一个标准人头
-- ============================================================

CREATE TABLE [dbo].[MAP_MDM_STAFF] (
    -- [1. 来源标识：多源异构拦截]
    [SRC_ORG_CODE]      VARCHAR(50)    NOT NULL, -- 来源机构/院区 (医共体唯一性基础)
    [SRC_SYS_CODE]      VARCHAR(50)    NOT NULL, -- 来源系统 (HIS/OA/HRP/OPER)
    [SRC_STAFF_CODE]    VARCHAR(50)    NOT NULL, -- 原始系统职员工号/工号编码（路由输入侧）
    [SRC_STAFF_NAME]    NVARCHAR(100)  NULL,     -- 原始系统职员姓名（辅助人工核验）

    -- [2. 核算口径：绩效管理唯一口径]
    -- 绝对去业务化：6 位固定长度纯数字顺序流水号文本
    -- CHAR(6) 强类型字符网关，拒绝 INT/VARCHAR，规避前导零在 Excel/Python 传输中被省略
    [STAFF_CODE]        CHAR(6)        NOT NULL, -- 绩效内核标准人员编码 (出口，CHAR(6) 定长纯数字流水号)
    [STAFF_NAME]        NVARCHAR(100)  NOT NULL, -- 绩效内核标准人员姓名 (出口)
    
    -- [3. 管理状态：工程安全垫]
    [IS_ACTIVE]    INT            DEFAULT 1, -- 逻辑开关 (0:停用, 1:启用)
    
    -- [4. 审计追踪：谁在什么时候改了规则]
    [CREATE_USER_CODE]  VARCHAR(50)    NULL,      -- 创建人
    [CREATE_DATE_TIME]  DATETIME       DEFAULT GETDATE(), 
    [UPDATE_DATE_TIME]  DATETIME       DEFAULT GETDATE(), 
    [REMARK_DESC]       NVARCHAR(200)  NULL,      -- 映射调整原因说明

    -- [主键协议：纯净输入原子粒度]
    -- 锁死 (SRC_ORG_CODE, SRC_SYS_CODE, SRC_STAFF_CODE)
    -- 保证路由网关唯一性：同一源人员在同一院区同一系统下，有且仅能路由到一个绩效标准人头
    CONSTRAINT [PK_MAP_MDM_STAFF] PRIMARY KEY CLUSTERED (
        [SRC_ORG_CODE], 
        [SRC_SYS_CODE], 
        [SRC_STAFF_CODE]
    )
);

-- ======================================================================
-- [元数据持久化] - 全字段 MS_Description
-- ======================================================================
-- 表级描述
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'异构人员到绩效内核标准人员的路由映射表（多源异构工号/编码归一化为统一标准人员编码，拦截来自 HIS/OA/HRP/手麻等系统的肮脏、多变工号，降维打击纯数字短号、字母前缀工号、姓名拼音等混乱数据）',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF';

-- 来源标识
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'来源机构/院区编码 (医共体多租户隔离标识，如: H001=九龙坡区人民医院)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'SRC_ORG_CODE';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'来源系统标识 (如: HIS=医院信息系统, OA=办公自动化, HRP=人力资源管理系统, OPER=手麻系统)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'SRC_SYS_CODE';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'原始系统职员工号/工号编码 (外部异构系统的工号原始编码，路由映射的输入侧；可能为纯数字短号、字母前缀工号、姓名拼音等异构格式)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'SRC_STAFF_CODE';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'原始系统职员姓名 (外部异构系统的职员原始姓名，辅助人工核验与排错)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'SRC_STAFF_NAME';

-- 核算口径
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'绩效内核标准人员编码 (CHAR(6) 强类型字符网关，6位固定长度纯数字顺序流水号文本，绝对去业务化，规避前导零在Excel/Python传输中被省略；出口，外键关联 DIM_STAFF 的 6 位定长纯数字流水号文本)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'STAFF_CODE';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'绩效内核标准人员姓名 (如: 张三、李四；绩效系统统一出口人员名称)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'STAFF_NAME';

-- 管理状态
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'逻辑开关 (0=停用, 1=启用；用于映射规则的灰度发布与应急关闭，不停用则始终生效)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'IS_ACTIVE';

-- 审计追踪
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建人工号 (记录映射规则的创建者身份，用于变更追溯)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'CREATE_USER_CODE';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'创建时间 (记录映射规则的创建时刻，默认当前时间)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'CREATE_DATE_TIME';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'更新时间 (记录映射规则的最后修改时刻，默认当前时间，用于变更追踪)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'UPDATE_DATE_TIME';
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'映射调整原因说明 (记录映射规则的变更原因/审批备注，如: 2026年5月外科工号体系升级，旧工号000233映射至新标准编码000456)',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'COLUMN', @level2name=N'REMARK_DESC';
GO

-- ======================================================================
-- [物理外键落地前置：孤数据清洗]
-- 在创建 FK 约束前，先清理 MAP_MDM_STAFF 中已在库但未被参照表注册的脏记录，
-- 防止 ALTER TABLE ADD CONSTRAINT 因错误 547 (FOREIGN KEY 冲突) 失败。
-- 本条清理为幂等操作，重复执行不会产生副作用。
-- ======================================================================
-- 清理输入端：MAP_MDM_STAFF 中存在但 DIM_SRC_STAFF 中未注册的源端三元组
DELETE T
FROM [dbo].[MAP_MDM_STAFF] T
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[DIM_SRC_STAFF] R
    WHERE R.[SRC_ORG_CODE]   = T.[SRC_ORG_CODE]
      AND R.[SRC_SYS_CODE]   = T.[SRC_SYS_CODE]
      AND R.[SRC_STAFF_CODE] = T.[SRC_STAFF_CODE]
);
GO

-- 清理输出端：MAP_MDM_STAFF 中存在但 DIM_STAFF 中未注册的标准人员编码
-- 注：MAP_MDM_STAFF.STAFF_CODE 类型为 CHAR(6)，DIM_STAFF.STAFF_CODE 类型为 VARCHAR(50)，
--     两者同属字符族，SQL Server 隐式转换兼容，FK 跨类型参照合法。
DELETE T
FROM [dbo].[MAP_MDM_STAFF] T
WHERE NOT EXISTS (
    SELECT 1 FROM [dbo].[DIM_STAFF] R
    WHERE R.[ORG_CODE]   = T.[SRC_ORG_CODE]
      AND R.[STAFF_CODE] = T.[STAFF_CODE]
);
GO

-- ======================================================================
-- [外键约束 1/2：输入端物理外键 — 多源异构人员注册白名单锁定]
-- 参照 DIM_SRC_STAFF 的联合主键 (SRC_ORG_CODE, SRC_SYS_CODE, SRC_STAFF_CODE)，
-- 确保未经 DIM_SRC_STAFF 注册的外部异构系统人员无法进入映射路由。
-- 注：PK_DIM_SRC_STAFF 列序为 (SRC_ORG_CODE, SRC_SYS_CODE, SRC_STAFF_CODE)，
--     故 FK 列序必须与此严格一致（SQL Server 强制要求 FK 列序匹配参照 PK 列序）。
-- ======================================================================
ALTER TABLE [dbo].[MAP_MDM_STAFF] ADD CONSTRAINT [FK_MAP_MDM_STAFF_SRC_STAFF]
    FOREIGN KEY ([SRC_ORG_CODE], [SRC_SYS_CODE], [SRC_STAFF_CODE])
    REFERENCES [dbo].[DIM_SRC_STAFF] ([SRC_ORG_CODE], [SRC_SYS_CODE], [SRC_STAFF_CODE]);
GO

-- ======================================================================
-- [外键约束 2/2：输出端物理外键 — 标准人员档案核算口径锁定]
-- 参照 DIM_STAFF 的联合静态主键 (ORG_CODE, STAFF_CODE)，
-- 确保映射输出必须指向合法的标准人员档案，杜绝悬空人员编码流入核算引擎。
-- MAP_MDM_STAFF.SRC_ORG_CODE → DIM_STAFF.ORG_CODE（机构维度对齐），
-- MAP_MDM_STAFF.STAFF_CODE   → DIM_STAFF.STAFF_CODE（标准工号对齐）。
-- ======================================================================
ALTER TABLE [dbo].[MAP_MDM_STAFF] ADD CONSTRAINT [FK_MAP_MDM_STAFF_STANDARD_STAFF]
    FOREIGN KEY ([SRC_ORG_CODE], [STAFF_CODE])
    REFERENCES [dbo].[DIM_STAFF] ([ORG_CODE], [STAFF_CODE]);
GO

-- ======================================================================
-- [外键约束元数据持久化] — 输入端防污染隔离 & 输出端核算口径锁定
-- ======================================================================
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'输入端防污染隔离：SRC_ORG_CODE+SRC_SYS_CODE+SRC_STAFF_CODE 强制参照 DIM_SRC_STAFF 联合主键，确保未经注册的外部异构系统人员无法进入映射路由，从物理层拦截肮脏多变工号渗入核算核心',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'CONSTRAINT', @level2name=N'FK_MAP_MDM_STAFF_SRC_STAFF';
GO

EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'输出端核算口径锁定：SRC_ORG_CODE+STAFF_CODE 强制参照 DIM_STAFF 联合静态主键 (ORG_CODE+STAFF_CODE)【注：MAP_MDM_STAFF.STAFF_CODE(CHAR(6))→DIM_STAFF.STAFF_CODE(VARCHAR(50))属字符族内跨类型参照，SQL Server隐式兼容】，确保映射输出必须指向合法的标准人员档案，杜绝悬空/非法人员编码流入绩效核算引擎，保障核算口径的权威一致',
    @level0type=N'SCHEMA', @level0name=N'dbo', @level1type=N'TABLE', @level1name=N'MAP_MDM_STAFF', @level2type=N'CONSTRAINT', @level2name=N'FK_MAP_MDM_STAFF_STANDARD_STAFF';
GO
