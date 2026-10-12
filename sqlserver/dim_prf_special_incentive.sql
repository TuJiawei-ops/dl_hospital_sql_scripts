/*
================================================================================
Relative Path : sqlserver/dim_prf_special_incentive.sql
脚本名称     : dim_prf_special_incentive.sql
分层归属     : DIM（维度层 / 配置类定制表，独立于全局版本体系）
业务定义     : 专项激励配置表。承载按「机构 × 项目」维度下发的专项激励金额标准，
               作为一次分配/二次分配中独立于 RVU 点数的专项加成数据源。
粒度         : org_code + item_code + effective_date（同一机构同一项目在同一生效日仅允许一条配置）
时效性设计   : effective_date / expire_date 闭区间（含两端）。长期有效直接录入
               2026-01-01 ~ 2099-12-31，业务人员平时零维护；调价时仅新增区间记录，
               历史账期按结算/开单日期回落到当时的生效记录，天然可追溯。
命名规范     : 全小写英文下划线（表名与字段名均为小写形态）
编码字段语义 : org_code / item_code 锁定 VARCHAR 字符串语义，严禁整型化
               （防前导零丢失与跨表 JOIN 关联失配）
展示属性     : org_name / item_name 为业务可读的冗余展示标签（供报表直出与人工辨识，
               免去外联维表），严禁作为关联键；机构/项目更名时须随配置同步维护
金额精度     : incentive_money 锁定 DECIMAL(18,8)，对齐 .clinerules 第 7 节全局精度强制标准
               （参考稿中的 NUMERIC(12,4) 属低精度类型，已按项目规范纠偏；若外部系统需
               12,4 展示口径，应在查询层 CAST，严禁在物理层降精度截断）
排序规则     : 编码列不覆写 COLLATE，继承库默认排序规则，规避跨表 JOIN 排序规则冲突
约束声明     : 主键仅锁死「同一生效日唯一」，跨区间重叠（同机构同项目多段区间交叉）由
               业务录入纪律保障，可在上层查询以 effective_date DESC 收敛最近生效行
会话无关性   : 无 DATEFIRST / LANGUAGE 会话依赖
模板占位符   : 无（纯配置 DDL，不含 '{year}' / '{month}' / '{start_time}' /
               '{end_time}' / {struct_codes} 动态注入）
修改日志：
2026-10-12 11:00:00 | 字段微调 | 新增 org_name(NVARCHAR(100) NULL) 紧随 org_code 之后；item_name 上移与 item_code 并列；组合索引键序对齐为 (org_code, item_code, effective_date) 并更名 ix_dim_prf_special_incentive_org_item_period；扩展属性同步插入 org_name 注释并前移 item_name 注释；示例区补齐 org_name 投影。
2026-10-12 10:00:00 | 初始建表 | 新建专项激励配置物理表：机构×项目×生效日 联合聚簇主键 + 时效闭区间 + 组合覆盖索引 + 全字段中文扩展属性；金额精度按项目规范锁定 DECIMAL(18,8)；全脚本零 GO 单批执行。
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表（重跑零脏数据，保障 DDL 可重复执行）
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[dim_prf_special_incentive]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[dim_prf_special_incentive];
END;

-- ================================================================
-- 2. 创建专项激励配置物理表
-- ================================================================
CREATE TABLE [dbo].[dim_prf_special_incentive] (
    -- ===== 机构维度（联合主键第 1 列）=====
    [org_code]        VARCHAR(50)    NOT NULL,                          -- 机构编码
    [org_name]        NVARCHAR(100)  NULL,                              -- 机构名称

    -- ===== 项目维度与时效（联合主键第 2、3 列）=====
    [item_code]       VARCHAR(50)    NOT NULL,                          -- 项目编码
    [item_name]       NVARCHAR(200)  NULL,                              -- 项目名称
    [effective_date]  DATE           NOT NULL,                          -- 生效日期

    -- ===== 时效与金额 =====
    [expire_date]     DATE           NOT NULL,                          -- 失效日期（闭区间终点）
    [incentive_money] DECIMAL(18,8)  NOT NULL DEFAULT (0.00000000),     -- 专项激励金额

    -- ===== 说明与审计字段 =====
    [remark]          NVARCHAR(500)  NULL,                              -- 备注
    [create_user]     VARCHAR(50)    NOT NULL CONSTRAINT df_dim_prf_special_incentive_create_user DEFAULT ('system'),   -- 创建人
    [create_time]     DATETIME       NOT NULL CONSTRAINT df_dim_prf_special_incentive_create_time DEFAULT (GETDATE()),  -- 创建时间
    [update_user]     VARCHAR(50)    NOT NULL CONSTRAINT df_dim_prf_special_incentive_update_user DEFAULT ('system'),   -- 最后修改人
    [update_time]     DATETIME       NOT NULL CONSTRAINT df_dim_prf_special_incentive_update_time DEFAULT (GETDATE()),  -- 最后修改时间

    -- ===== 主键约束（同一机构同一项目同一生效日唯一）=====
    CONSTRAINT [pk_dim_prf_special_incentive] PRIMARY KEY CLUSTERED (
        [org_code]       ASC,
        [item_code]      ASC,
        [effective_date] ASC
    ),

    -- ===== 时效合法性约束（失效日不得早于生效日）=====
    CONSTRAINT [ck_dim_prf_special_incentive_date_range] CHECK ([expire_date] >= [effective_date])
);

-- ================================================================
-- 3. 检索索引（组合索引支撑 机构 × 项目 × 生效日 的时效命中）
-- ================================================================
-- 时效区间窄覆盖索引：键序 (机构编码, 项目编码, 生效日) 与主键同序且物理行更窄，
-- 承载「机构 × 项目 × 生效日」时效命中与「生效日倒序取最近一段」区间过滤；
-- INCLUDE 覆盖 expire_date / incentive_money 实现零回表，并规避宽行聚簇索引扫描
CREATE NONCLUSTERED INDEX [ix_dim_prf_special_incentive_org_item_period]
    ON [dbo].[dim_prf_special_incentive] ([org_code] ASC, [item_code] ASC, [effective_date] ASC)
    INCLUDE ([expire_date], [incentive_money]);

-- ================================================================
-- 4. 表级与字段级扩展属性注释
--    第 1 区块已 DROP TABLE 重建，表级绑定扩展属性被物理层同步清除，
--    故此处顺序执行 sp_addextendedproperty，无需任何 IF EXISTS 守卫
-- ================================================================
EXEC sp_addextendedproperty N'MS_Description', N'专项激励配置表：承载按「机构 × 项目」下发的专项激励金额标准（时效闭区间 effective_date ~ expire_date，长期有效可录至 2099-12-31，调价仅新增区间记录，历史账期可回溯）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive';
EXEC sp_addextendedproperty N'MS_Description', N'机构编码（字符串语义，取值对齐 ORG_CODE，如 1001，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'org_code';
EXEC sp_addextendedproperty N'MS_Description', N'机构名称（业务可读冗余展示标签，供报表直出与人工辨识，免去外联维表；严禁作为关联键，机构更名时须同步维护）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'org_name';
EXEC sp_addextendedproperty N'MS_Description', N'项目编码（字符串语义，对齐 PROJ_CODE / ITEM_CODE 口径，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'item_code';
EXEC sp_addextendedproperty N'MS_Description', N'项目名称（业务可读冗余展示标签，仅用于展示与排查，严禁作为关联键；项目更名时须同步维护）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'item_name';
EXEC sp_addextendedproperty N'MS_Description', N'生效日期（时效闭区间起点，含当日；与 expire_date 共同构成配置有效期）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'effective_date';
EXEC sp_addextendedproperty N'MS_Description', N'失效日期（时效闭区间终点，含当日；长期有效统一录 2099-12-31，日常免维护）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'expire_date';
EXEC sp_addextendedproperty N'MS_Description', N'专项激励金额（DECIMAL(18,8) 高精度，对齐全局绩效金额精度标准；默认 0，未配置即按 0 参与计算）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'incentive_money';
EXEC sp_addextendedproperty N'MS_Description', N'备注（承载调价依据、批复文号等追溯信息）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'remark';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system，业务录入时写明操作人工号）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dim_prf_special_incentive', N'COLUMN', N'update_time';

-- ================================================================
-- 5. 录入与命中示例（注释态参考，按需解注执行；非脚本必需逻辑）
-- ================================================================
-- 5.1 长期有效配置（一次录入，长期免维护）
-- INSERT INTO [dbo].[dim_prf_special_incentive] ([org_code], [org_name], [item_code], [item_name], [effective_date], [expire_date], [incentive_money], [remark], [create_user])
-- VALUES ('1001', N'大连市皮肤病医院', 'PROJ_DEMO', N'示例项目', '2026-01-01', '2099-12-31', 100.00000000, N'长期有效', 'system');
--
-- 5.2 调价打补丁（仅新增区间记录 + 关闭上段区间，历史账期自动回落旧值）
-- INSERT INTO [dbo].[dim_prf_special_incentive] ([org_code], [org_name], [item_code], [item_name], [effective_date], [expire_date], [incentive_money], [remark], [create_user])
-- VALUES ('1001', N'大连市皮肤病医院', 'PROJ_DEMO', N'示例项目', '2026-07-01', '2099-12-31', 120.00000000, N'7 月调价', 'system');
-- UPDATE [dbo].[dim_prf_special_incentive]
-- SET [expire_date] = '2026-06-30', [update_user] = 'system', [update_time] = GETDATE()
-- WHERE [org_code] = '1001' AND [item_code] = 'PROJ_DEMO' AND [effective_date] = '2026-01-01';
--
-- 5.3 按业务日期命中配置（闭区间过滤，多段区间时以生效日倒序取最近一行）
-- SELECT s.[org_code], s.[org_name], s.[item_code], s.[item_name], s.[effective_date], s.[expire_date], s.[incentive_money]
-- FROM [dbo].[dim_prf_special_incentive] AS s
-- WHERE s.[effective_date] <= '2026-07-15' AND s.[expire_date] >= '2026-07-15'
-- ORDER BY s.[effective_date] DESC;
