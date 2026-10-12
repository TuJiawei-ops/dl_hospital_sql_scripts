/*
================================================================================
Relative Path : sqlserver/dwd_fin_reward_punish_detail.sql
脚本名称     : dwd_fin_reward_punish_detail.sql
分层归属     : DWD（明细层 / 奖惩事实明细）
业务定义     : 综合奖惩明细事实表。承载一次分配（科室级）与二次分配（个人级）共用的
               奖惩/扣款原始事件明细，作为奖惩资金池切分与个人奖惩分摊的唯一事实源。
粒度         : 自增 id 单行物理唯一；业务粒度 = 核算年月 × 核算单元 ×（可选）员工 ×
               奖惩项目 × 发生日期，同一科室同一天允许存在多笔同类奖惩，故不设业务复合主键。
空值语义     : unit_code / unit_name 强制 NOT NULL（任何奖惩均必有归属科室，保障科室级汇总）；
               staff_code / staff_name 允许 NULL —— NULL 表示「科室整体奖惩」（如科室集体
               行政处罚、科室质控奖），有值表示「个人奖惩」，一张表兼容两级分配。
双重分类体系 : category（方向属性：REWARD 奖励/加分、PUNISH 惩罚/扣款）
               + item_cat_code / item_cat_name（业务大类：QUALITY 医疗质控、SAFETY 生产安全、
               SERVICE 服务投诉、ADMIN 行政政工、RESEARCH 科研教学等），支撑 BI 大类汇总。
金额符号约定 : amount 为最终金额，奖励为正、惩罚为负（符号由录入侧保证，物理层不再二次取反）；
               unit_price / quantity / amount 三列统一 DECIMAL(18,8)，对齐全局精度强制标准。
编码字段语义 : org_code / unit_code / staff_code / item_cat_code / item_code 全量 VARCHAR 字符串语义，
               严禁 CAST 为 INT/BIGINT（防前导零丢失与跨表 JOIN 关联失配）。
索引策略     : 聚簇主键 pk_dwd_fin_reward_punish_detail（id）保障行级唯一寻址；
               ix_dwd_fin_reward_punish_detail_lookup（calc_year, calc_month, unit_code, staff_code）
               INCLUDE (category, item_cat_code, amount) 实现账期×科室×员工奖惩汇总零回表。
会话无关性   : 无 DATEFIRST / LANGUAGE 会话依赖。
模板占位符   : 无（纯 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）。
修改日志：
2026-10-12 16:00:00 | 初始建表 | 新建综合奖惩明细事实表：自增 id 聚簇主键 + (账期,科室,员工) 覆盖检索索引 + staff 维度可空兼容科室/个人两级奖惩 + category 与 item_cat* 双重分类 + 全字段中文扩展属性；金额精度锁定 DECIMAL(18,8)；全脚本零 GO 单批执行。
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表（重跑零脏数据，保障 DDL 可重复执行）
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[dwd_fin_reward_punish_detail]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[dwd_fin_reward_punish_detail];
END;

-- ================================================================
-- 2. 创建综合奖惩明细事实表
-- ================================================================
CREATE TABLE [dbo].[dwd_fin_reward_punish_detail] (
    -- ===== 物理代理主键 =====
    [id]             BIGINT IDENTITY(1,1) NOT NULL,                     -- 自增代理主键

    -- ===== 账期与发生日期 =====
    [calc_year]      INT                  NOT NULL,                     -- 核算年份（如 2026）
    [calc_month]     INT                  NOT NULL,                     -- 核算月份（如 10）
    [record_date]    DATE                 NOT NULL,                     -- 奖惩发生日期

    -- ===== 机构与核算单元（必填，保障科室级汇总）=====
    [org_code]       VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_org_code DEFAULT ('1001'), -- 机构编码
    [org_name]       NVARCHAR(100)  NULL,                               -- 机构名称
    [unit_code]      VARCHAR(50)    NOT NULL,                           -- 核算单元/科室编码
    [unit_name]      NVARCHAR(100)  NOT NULL,                           -- 核算单元/科室名称

    -- ===== 员工维度（选填：NULL 为科室整体奖惩，有值为个人奖惩）=====
    [staff_code]     VARCHAR(50)    NULL,                               -- 员工工号/编码
    [staff_name]     NVARCHAR(100)  NULL,                               -- 员工姓名

    -- ===== 奖惩大类与奖惩项目 =====
    [item_cat_code]  VARCHAR(50)    NULL,                               -- 奖惩大类编码（QUALITY/SAFETY/SERVICE/ADMIN/RESEARCH 等）
    [item_cat_name]  NVARCHAR(100)  NULL,                               -- 奖惩大类名称（医疗质控类/安全生产类等）
    [item_code]      VARCHAR(50)    NOT NULL,                           -- 奖惩项目编码
    [item_name]      NVARCHAR(200)  NOT NULL,                           -- 奖惩项目名称
    [category]       VARCHAR(20)    NOT NULL,                           -- 奖惩方向（REWARD：奖励/加分，PUNISH：惩罚/扣款）

    -- ===== 金额与计量标准 =====
    [unit_price]     DECIMAL(18,8)  NOT NULL DEFAULT (0.00000000),      -- 单价/标准
    [quantity]       DECIMAL(18,8)  NOT NULL DEFAULT (1.00000000),      -- 数量/频次
    [amount]         DECIMAL(18,8)  NOT NULL DEFAULT (0.00000000),      -- 最终金额（奖励为正，惩罚为负）

    -- ===== 说明与审计字段 =====
    [remark]         NVARCHAR(1000) NULL,                               -- 事由与备注说明
    [create_user]    VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_create_user DEFAULT ('system'),  -- 创建人
    [create_time]    DATETIME       NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_create_time DEFAULT (GETDATE()), -- 创建时间
    [update_user]    VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_update_user DEFAULT ('system'),  -- 最后修改人
    [update_time]    DATETIME       NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_update_time DEFAULT (GETDATE()), -- 最后修改时间

    -- ===== 主键约束（自增 id 单列聚簇，兼容 staff_code 为空与同科室同日多笔同类奖惩）=====
    CONSTRAINT [pk_dwd_fin_reward_punish_detail] PRIMARY KEY CLUSTERED (
        [id] ASC
    ),

    -- ===== 方向枚举约束（锁定 REWARD / PUNISH 二值语义）=====
    CONSTRAINT [ck_dwd_fin_reward_punish_detail_category] CHECK ([category] IN ('REWARD', 'PUNISH'))
);

-- ================================================================
-- 3. 检索索引（账期 × 科室 × 员工 奖惩汇总窄覆盖索引）
-- ================================================================
-- 键序对齐奖惩核算主路径（先按账期切片，再按科室/员工下钻）；
-- INCLUDE category / item_cat_code / amount 实现大类汇总与金额合计零回表
CREATE NONCLUSTERED INDEX [ix_dwd_fin_reward_punish_detail_lookup]
    ON [dbo].[dwd_fin_reward_punish_detail] ([calc_year] ASC, [calc_month] ASC, [unit_code] ASC, [staff_code] ASC)
    INCLUDE ([category], [item_cat_code], [amount]);

-- ================================================================
-- 4. 表级与字段级扩展属性注释
--    第 1 区块已 DROP TABLE 重建，表级绑定扩展属性被物理层同步清除，
--    故此处顺序执行 sp_addextendedproperty，无需任何 IF EXISTS 守卫
-- ================================================================
EXEC sp_addextendedproperty N'MS_Description', N'综合奖惩明细事实表：一张表兼容一次分配（科室级，staff 为空）与二次分配（个人级，staff 有值）；双重分类体系 category（奖励/扣款方向）+ item_cat_code（业务大类），金额精度 DECIMAL(18,8)，奖励为正惩罚为负', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail';
EXEC sp_addextendedproperty N'MS_Description', N'自增代理主键（单列聚簇，物理唯一寻址；不使用业务复合主键，因 staff_code 允许为空且同一科室同一天可存在多笔同类奖惩）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'id';
EXEC sp_addextendedproperty N'MS_Description', N'核算年份（如 2026）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'calc_year';
EXEC sp_addextendedproperty N'MS_Description', N'核算月份（如 10）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'calc_month';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩发生日期（业务归属日期，用于跨账期追溯与日粒度明细下钻）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'record_date';
EXEC sp_addextendedproperty N'MS_Description', N'机构编码（字符串语义，默认 1001，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'org_code';
EXEC sp_addextendedproperty N'MS_Description', N'机构名称（业务可读冗余展示标签，可空，严禁作为关联键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'org_name';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室编码（NOT NULL，奖惩必有归属科室；字符串语义，对齐 HPS_DEPT_CODE，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_code';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室名称（NOT NULL，支撑科室级汇总展示）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_name';
EXEC sp_addextendedproperty N'MS_Description', N'员工工号/编码（可空：NULL 表示科室整体奖惩，有值表示个人奖惩；字符串语义，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'staff_code';
EXEC sp_addextendedproperty N'MS_Description', N'员工姓名（可空，与 staff_code 同生共死：科室整体奖惩时留空，个人奖惩时填写）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'staff_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩大类编码（可空；取值如 QUALITY 医疗质控、SAFETY 生产安全、SERVICE 服务投诉、ADMIN 行政政工、RESEARCH 科研教学，供 BI 按大类汇总）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_cat_code';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩大类名称（可空；如 医疗质控类 / 安全生产类 / 服务投诉类 / 行政政工类 / 科研教学类）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_cat_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩项目编码（NOT NULL，奖惩标准/项目唯一标识；字符串语义，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_code';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩项目名称（NOT NULL，业务可读的奖惩事项名称）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩方向（NOT NULL，受 CHECK 约束锁定二值：REWARD 奖励/加分、PUNISH 惩罚/扣款）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'category';
EXEC sp_addextendedproperty N'MS_Description', N'单价/标准（DECIMAL(18,8) 高精度，默认 0.00000000；按次定额或按标准单价录入口径）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_price';
EXEC sp_addextendedproperty N'MS_Description', N'数量/频次（DECIMAL(18,8) 高精度，默认 1.00000000，支持按次/按人次/按天计量）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'quantity';
EXEC sp_addextendedproperty N'MS_Description', N'最终金额（DECIMAL(18,8) 高精度，默认 0.00000000；奖励为正、惩罚为负，符号由录入侧保证，物理层不再二次取反）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'amount';
EXEC sp_addextendedproperty N'MS_Description', N'事由与备注说明（承载处罚文号、投诉工单号、奖励依据等追溯信息）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'remark';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system，业务录入时写明操作人工号）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'update_time';

-- ================================================================
-- 5. 录入示例（注释态参考，按需解注执行；非脚本必需逻辑）
-- ================================================================
-- 5.1 科室级奖惩（一次分配：staff_code / staff_name 留空）
-- INSERT INTO [dbo].[dwd_fin_reward_punish_detail]
--     ([calc_year], [calc_month], [record_date], [org_code], [org_name], [unit_code], [unit_name],
--      [item_cat_code], [item_cat_name], [item_code], [item_name], [category], [unit_price], [quantity], [amount], [remark], [create_user])
-- VALUES
--     (2026, 10, '2026-10-09', '1001', N'大连市皮肤病医院', 'D1002', N'皮肤内科', 'ADMIN', N'行政政工类',
--      'ADM_DEPT_PENALTY', N'科室集体行政处罚', 'PUNISH', 2000.00000000, 1.00000000, -2000.00000000, N'院周会通报批评', 'system');
--
-- 5.2 个人级奖惩（二次分配：staff_code / staff_name 填写工号与姓名）
-- INSERT INTO [dbo].[dwd_fin_reward_punish_detail]
--     ([calc_year], [calc_month], [record_date], [org_code], [org_name], [unit_code], [unit_name], [staff_code], [staff_name],
--      [item_cat_code], [item_cat_name], [item_code], [item_name], [category], [unit_price], [quantity], [amount], [remark], [create_user])
-- VALUES
--     (2026, 10, '2026-10-12', '1001', N'大连市皮肤病医院', 'D1002', N'皮肤内科', '20260001', N'张三',
--      'QUALITY', N'医疗质控类', 'QC_REWARD', N'病历书写质控奖励', 'REWARD', 200.00000000, 1.00000000, 200.00000000, N'三季度病历甲级', 'system');
--
-- 5.3 账期 × 科室奖惩净额汇总（个人级与科室级同池合计，覆盖索引零回表）
-- SELECT f.[calc_year], f.[calc_month], f.[unit_code], f.[unit_name],
--        SUM(CASE WHEN f.[category] = 'REWARD' THEN f.[amount] ELSE 0.00000000 END) AS [reward_amount],
--        SUM(CASE WHEN f.[category] = 'PUNISH' THEN f.[amount] ELSE 0.00000000 END) AS [punish_amount],
--        SUM(f.[amount]) AS [net_amount]
-- FROM [dbo].[dwd_fin_reward_punish_detail] AS f
-- GROUP BY f.[calc_year], f.[calc_month], f.[unit_code], f.[unit_name];
