/*
================================================================================
Relative Path : sqlserver/dwd_fin_reward_punish_detail.sql
脚本名称     : dwd_fin_reward_punish_detail.sql
分层归属     : DWD（明细层 / 奖惩事实明细）
业务定义     : 综合奖惩明细事实表。承载一次分配（科室级）与二次分配（个人级）共用的
               奖惩/扣款原始事件明细，作为奖惩资金池切分与个人奖惩分摊的唯一事实源。
粒度         : 业务唯一键 = 核算年月 × 机构 × 核算单元 ×（可空）员工 × 奖惩项目 × 发生日期 ×
               奖惩方向 × 度量类型；staff_code 为 NULL 表示「科室整体奖惩」，有值表示个人奖惩；
               业务唯一性由两条过滤唯一索引分别在「个人行」与「科室行」上物理锁定，
               既保留 NULL 语义，又杜绝同键重复录入。
               物理聚簇主键为 [ID] 自增列（单列唯一寻址，适配系统框架与数据接口）；
               【命名例外】该列必须保持大写 ID：数据接口模块（IRawDataServiceImpl）以字面量
               'ID' 作为导出表头、导入/增删改的主键键名（v.get("ID")、buildUpdate(..., "ID", ...)），
               改为小写会导致导入行被误判为新增、导出 ID 列空白；除本列外全部业务列小写。
空值语义     : unit_code / unit_name 强制 NOT NULL（任何奖惩均必有归属科室，保障科室级汇总）；
               staff_code / staff_name 允许 NULL —— NULL 表示「科室整体奖惩」（如科室集体行政处罚、
               科室质控奖），有值表示「个人奖惩」，一张表兼容两级分配；
               注意：科室级必须留 NULL，不可写空串 ''（空串会被当作一个“员工”参与业务唯一约束）。
双重分类体系 : category（方向属性：REWARD 奖励/加分、PUNISH 惩罚/扣款）
               + item_cat_code / item_cat_name（业务大类：QUALITY 医疗质控、SAFETY 生产安全、
               SERVICE 服务投诉、ADMIN 行政政工、RESEARCH 科研教学等），支撑 BI 大类汇总。
单表双模     : metric_type 统一承载两类度量（AMOUNT 金额/元、SCORE 分数/分）：奖励金与罚款、
               加分与扣分共用一张事实表、一套 API、一条二次分配链路，杜绝“分数表 + 金额表”双表冗余；
               下游汇总必须先行按 metric_type 分组，严禁跨量纲直接相加。
数值符号约定 : unit_price / amount 一律录入正数绝对值（物理层 CHECK >= 0 硬约束，严禁负数），
               加减性质完全由 category（REWARD 加 / PUNISH 减）与 metric_type（AMOUNT 元 / SCORE 分）
               决定，从数据库内核根绝“负负得正”与财务加减错乱事故；三列统一 DECIMAL(18,8)，
               对齐全局精度强制标准（AMOUNT 记为元，SCORE 记为分，量纲由 metric_type 唯一决定）。
编码字段语义 : org_code / unit_code / staff_code / item_cat_code / item_code 全量 VARCHAR 字符串语义，
               严禁 CAST 为 INT/BIGINT（防前导零丢失与跨表 JOIN 关联失配）。
索引策略     : 聚簇主键 pk_dwd_fin_reward_punish_detail（[ID]）保障行级唯一寻址与 ORM 单列定位；
               业务唯一性由两条过滤唯一索引承担 —— uq_..._staff（staff_code IS NOT NULL，
               含 staff_code 的 9 列）与 uq_..._dept（staff_code IS NULL，8 列），
               分别锁定个人行与科室行的重复录入；另保留窄覆盖索引 ix_..._lookup
               （calc_year, calc_month, unit_code, staff_code）INCLUDE (category, metric_type,
               item_cat_code, amount)，支撑奖惩大类汇总零回表。
会话无关性   : 无 DATEFIRST / LANGUAGE 会话依赖。
模板占位符   : 无（纯 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）。
修改日志：
2026-10-28 19:40:00 | 主键回调 | 应「科室整体奖惩可为空」语义，staff_code 恢复可空并退出主键；聚簇主键回归 [ID]；业务唯一性改由两条过滤唯一索引（个人行 staff_code IS NOT NULL / 科室行 staff_code IS NULL）保证；表级与列级注释、5.1 示例同步回调。
2026-10-28 19:05:00 | 主键重构 | 撤销自增 id 主键，改为业务复合主键（calc_year, calc_month, org_code, unit_code, staff_code, item_code, record_date, category, metric_type）；新增框架兼容列 [ID] BIGINT IDENTITY 并绑定唯一约束；staff_code 由可空收紧为 NOT NULL DEFAULT 'NONE'（科室整体奖惩哨兵）；扩展属性与 5.1 示例同步改口径。
2026-10-12 18:30:00 | 约束升级 | [unit_price]/[amount] 新增 CHECK >= 0.00000000 非负绝对值硬约束（ck_dwd_fin_reward_punish_detail_unit_price / ck_dwd_fin_reward_punish_detail_amount）；符号口径由「奖励正惩罚负」改为「一律正数绝对值 + category 定加减」；表级与字段级扩展属性、5.1/5.3 示例、5.4 净额汇总算式同步改口径。
2026-10-12 17:00:00 | 架构升级 | 引入单表双模度量字段 [metric_type] VARCHAR(20) NOT NULL（默认 AMOUNT，CHECK 锁定 AMOUNT/SCORE）；[amount]/[unit_price] 语义升格为「金额或分值」通用奖惩值，扩展属性与示例同步补录 SCORE 模式；覆盖索引 INCLUDE 增补 metric_type。
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
    -- ===== 聚簇主键（框架与数据接口单列寻址）=====
    [ID]             BIGINT IDENTITY(1,1) NOT NULL,                     -- 聚簇主键（IDENTITY；业务唯一性另由过滤唯一索引保证）

    -- ===== 账期与发生日期 =====
    [calc_year]      INT                  NOT NULL,                     -- 核算年份（如 2026）
    [calc_month]     INT                  NOT NULL,                     -- 核算月份（如 10）
    [record_date]    DATE                 NOT NULL,                     -- 奖惩发生日期

    -- ===== 机构与核算单元（必填，保障科室级汇总）=====
    [org_code]       VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_org_code DEFAULT ('1001'), -- 机构编码
    [org_name]       NVARCHAR(100)  NULL,                               -- 机构名称
    [unit_code]      VARCHAR(50)    NOT NULL,                           -- 核算单元/科室编码
    [unit_name]      NVARCHAR(100)  NOT NULL,                           -- 核算单元/科室名称

    -- ===== 员工维度（可空：NULL 为科室整体奖惩，有值为个人奖惩）=====
    [staff_code]     VARCHAR(50)    NULL,                               -- 员工工号/编码（NULL=科室整体奖惩）
    [staff_name]     NVARCHAR(100)  NULL,                               -- 员工姓名（科室整体奖惩时留空）

    -- ===== 奖惩大类与奖惩项目 =====
    [item_cat_code]  VARCHAR(50)    NULL,                               -- 奖惩大类编码（QUALITY/SAFETY/SERVICE/ADMIN/RESEARCH 等）
    [item_cat_name]  NVARCHAR(100)  NULL,                               -- 奖惩大类名称（医疗质控类/安全生产类等）
    [item_code]      VARCHAR(50)    NOT NULL,                           -- 奖惩项目编码
    [item_name]      NVARCHAR(200)  NOT NULL,                           -- 奖惩项目名称
    [category]       VARCHAR(20)    NOT NULL,                           -- 奖惩方向（REWARD：奖励/加分，PUNISH：惩罚/扣款）
    [metric_type]    VARCHAR(20)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_metric_type DEFAULT ('AMOUNT'), -- 度量类型（AMOUNT：金额/元，SCORE：分数/分）

    -- ===== 数值与计量标准（单表双模：金额与分值同列承载，量纲由 metric_type 决定；一律正数绝对值）=====
    [unit_price]     DECIMAL(18,8)  NOT NULL DEFAULT (0.00000000),      -- 标准值（AMOUNT：元/次；SCORE：分/次；正数绝对值，严禁负数）
    [quantity]       DECIMAL(18,8)  NOT NULL DEFAULT (1.00000000),      -- 数量/频次
    [amount]         DECIMAL(18,8)  NOT NULL DEFAULT (0.00000000),      -- 最终奖惩值（AMOUNT=金额(元)，SCORE=分值(分)；正数绝对值，加减由 category 决定）

    -- ===== 说明与审计字段 =====
    [remark]         NVARCHAR(1000) NULL,                               -- 事由与备注说明
    [create_user]    VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_create_user DEFAULT ('system'),  -- 创建人
    [create_time]    DATETIME       NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_create_time DEFAULT (GETDATE()), -- 创建时间
    [update_user]    VARCHAR(50)    NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_update_user DEFAULT ('system'),  -- 最后修改人
    [update_time]    DATETIME       NOT NULL CONSTRAINT df_dwd_fin_reward_punish_detail_update_time DEFAULT (GETDATE()), -- 最后修改时间

    -- ===== 主键约束（[ID] 单列聚簇，保障行级唯一寻址；业务唯一性由过滤唯一索引承担）=====
    CONSTRAINT [pk_dwd_fin_reward_punish_detail] PRIMARY KEY CLUSTERED (
        [ID] ASC
    ),

    -- ===== 方向枚举约束（锁定 REWARD / PUNISH 二值语义）=====
    CONSTRAINT [ck_dwd_fin_reward_punish_detail_category] CHECK ([category] IN ('REWARD', 'PUNISH')),

    -- ===== 度量类型枚举约束（单表双模：锁定 AMOUNT 金额 / SCORE 分数二值语义）=====
    CONSTRAINT [ck_dwd_fin_reward_punish_detail_metric_type] CHECK ([metric_type] IN ('AMOUNT', 'SCORE')),

    -- ===== 非负绝对值约束（内核级杜绝负数录入，加减性质交由 category 决定）=====
    CONSTRAINT [ck_dwd_fin_reward_punish_detail_unit_price] CHECK ([unit_price] >= 0.00000000),
    CONSTRAINT [ck_dwd_fin_reward_punish_detail_amount] CHECK ([amount] >= 0.00000000)
);

-- ================================================================
-- 3. 业务唯一约束与检索索引
-- ================================================================
-- 过滤唯一索引要求会话级 ANSI_NULLS / QUOTED_IDENTIFIER 为 ON（显式声明，避免客户端默认值差异）
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;

-- 业务唯一约束（个人行）：staff_code 有值时，九列唯一，杜绝同员工同日同项目同方向重复录入
CREATE UNIQUE NONCLUSTERED INDEX [uq_dwd_fin_reward_punish_detail_staff]
    ON [dbo].[dwd_fin_reward_punish_detail]
       ([calc_year] ASC, [calc_month] ASC, [org_code] ASC, [unit_code] ASC, [staff_code] ASC,
        [item_code] ASC, [record_date] ASC, [category] ASC, [metric_type] ASC)
    WHERE [staff_code] IS NOT NULL;

-- 业务唯一约束（科室行）：staff_code 为 NULL 时，八列唯一，每单元每日每项目每方向每度量仅一条科室级记录
CREATE UNIQUE NONCLUSTERED INDEX [uq_dwd_fin_reward_punish_detail_dept]
    ON [dbo].[dwd_fin_reward_punish_detail]
       ([calc_year] ASC, [calc_month] ASC, [org_code] ASC, [unit_code] ASC,
        [item_code] ASC, [record_date] ASC, [category] ASC, [metric_type] ASC)
    WHERE [staff_code] IS NULL;

-- 奖惩汇总窄覆盖索引（键序对齐账期 → 科室 → 员工，INCLUDE 聚合列实现零回表）
CREATE NONCLUSTERED INDEX [ix_dwd_fin_reward_punish_detail_lookup]
    ON [dbo].[dwd_fin_reward_punish_detail] ([calc_year] ASC, [calc_month] ASC, [unit_code] ASC, [staff_code] ASC)
    INCLUDE ([category], [metric_type], [item_cat_code], [amount]);

-- ================================================================
-- 4. 表级与字段级扩展属性注释
--    第 1 区块已 DROP TABLE 重建，表级绑定扩展属性被物理层同步清除，
--    故此处顺序执行 sp_addextendedproperty，无需任何 IF EXISTS 守卫
-- ================================================================
EXEC sp_addextendedproperty N'MS_Description', N'综合奖惩明细事实表（单表双模）：一张表兼容一次分配（科室级，staff_code IS NULL）与二次分配（个人级，staff_code 有值）；业务唯一键为（账期 × 机构 × 核算单元 × 员工 × 奖惩项目 × 发生日期 × 奖惩方向 × 度量类型），由 uq_..._staff / uq_..._dept 两条过滤唯一索引分别锁定个人行与科室行；[ID] 为聚簇主键（自增，框架与数据接口单列寻址）；category 承载奖惩方向，metric_type 承载度量类型（AMOUNT 金额/元、SCORE 分数/分），item_cat_code 承载业务大类；所有金额与分值统一录入正数绝对值（受 CHECK (unit_price >= 0) 与 CHECK (amount >= 0) 物理约束），严禁录入负数，加减性质由 category 决定；数值精度 DECIMAL(18,8)；下游汇总须先按 metric_type 分组，严禁跨量纲相加', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail';
EXEC sp_addextendedproperty N'MS_Description', N'聚簇主键（IDENTITY 自增，单列唯一寻址；供 MyBatis-Plus 等 ORM 与数据接口按单列定位/回写；业务唯一性不在本列，由两条过滤唯一索引保证）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'ID';
EXEC sp_addextendedproperty N'MS_Description', N'核算年份（如 2026；业务唯一键组成部分）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'calc_year';
EXEC sp_addextendedproperty N'MS_Description', N'核算月份（如 10；业务唯一键组成部分）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'calc_month';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩发生日期（业务归属日期；业务唯一键组成部分；用于跨账期追溯与日粒度明细下钻）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'record_date';
EXEC sp_addextendedproperty N'MS_Description', N'机构编码（字符串语义，默认 1001，严禁整型化；业务唯一键组成部分）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'org_code';
EXEC sp_addextendedproperty N'MS_Description', N'机构名称（业务可读冗余展示标签，可空，严禁作为关联键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'org_name';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室编码（NOT NULL，奖惩必有归属科室；业务唯一键组成部分；字符串语义，对齐 HPS_DEPT_CODE，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_code';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室名称（NOT NULL，支撑科室级汇总展示）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_name';
EXEC sp_addextendedproperty N'MS_Description', N'员工工号/编码（可空：NULL 表示科室整体奖惩，有值表示个人奖惩；业务唯一键组成部分；字符串语义，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'staff_code';
EXEC sp_addextendedproperty N'MS_Description', N'员工姓名（可空，与 staff_code 对应：科室整体奖惩（staff_code IS NULL）时留空，个人奖惩时填写）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'staff_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩大类编码（可空；取值如 QUALITY 医疗质控、SAFETY 生产安全、SERVICE 服务投诉、ADMIN 行政政工、RESEARCH 科研教学，供 BI 按大类汇总）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_cat_code';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩大类名称（可空；如 医疗质控类 / 安全生产类 / 服务投诉类 / 行政政工类 / 科研教学类）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_cat_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩项目编码（NOT NULL，奖惩标准/项目唯一标识；业务唯一键组成部分；字符串语义，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_code';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩项目名称（NOT NULL，业务可读的奖惩事项名称）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'item_name';
EXEC sp_addextendedproperty N'MS_Description', N'奖惩方向（NOT NULL，受 CHECK 约束锁定二值：REWARD 奖励/加分、PUNISH 惩罚/扣款；业务唯一键组成部分）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'category';
EXEC sp_addextendedproperty N'MS_Description', N'度量类型（NOT NULL，默认 AMOUNT，受 CHECK 约束锁定二值：AMOUNT 金额（单位：元）、SCORE 分数（单位：分）；业务唯一键组成部分）；单表双模设计：分数奖惩与金额奖惩共用一张事实表/一套 API/一条二次分配链路，杜绝双表冗余与口径漂移，量纲唯一由本列决定', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'metric_type';
EXEC sp_addextendedproperty N'MS_Description', N'标准值（DECIMAL(18,8) 高精度，默认 0.00000000；量纲由 metric_type 决定：AMOUNT 为元/次，SCORE 为分/次）；所有金额与分值统一录入正数绝对值（受 CHECK ([unit_price] >= 0) 物理约束），严禁录入负数；加减性质由 category 决定', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'unit_price';
EXEC sp_addextendedproperty N'MS_Description', N'数量/频次（DECIMAL(18,8) 高精度，默认 1.00000000，支持按次/按人次/按天计量，与 unit_price 同量纲乘积得 amount）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'quantity';
EXEC sp_addextendedproperty N'MS_Description', N'最终奖惩值（DECIMAL(18,8) 高精度，默认 0.00000000；AMOUNT 时为金额（元），SCORE 时为分值（分））；所有金额与分值统一录入正数绝对值（受 CHECK ([amount] >= 0) 物理约束），严禁录入负数，加减性质由 category 决定（REWARD 计入奖励池、PUNISH 计入惩罚池，下游计算净额时按 category 施加符号）；跨 metric_type 汇总严禁直接相加', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'amount';
EXEC sp_addextendedproperty N'MS_Description', N'事由与备注说明（承载处罚文号、投诉工单号、奖励依据等追溯信息）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'remark';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system，业务录入时写明操作人工号）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_reward_punish_detail', N'COLUMN', N'update_time';

-- ================================================================
-- 5. 录入示例（注释态参考，按需解注执行；非脚本必需逻辑）
--    单表双模：5.1 / 5.2 为 AMOUNT 金额模式（一次分配科室级 + 二次分配个人级），
--    5.3 为 SCORE 分数模式；两类记录物理同表，仅由 metric_type 区分量纲。
--    业务唯一键含（账期, 机构, 单元, 员工, 项目, 日期, 方向, 度量），个人行/科室行分别由过滤唯一索引拒绝重复。
-- ================================================================
-- 5.1 科室级金额奖惩（一次分配：staff_code / staff_name 留空即 NULL，metric_type = AMOUNT；扣款同样录入正值 2000，方向由 category = PUNISH 表达）
-- INSERT INTO [dbo].[dwd_fin_reward_punish_detail]
--     ([calc_year], [calc_month], [record_date], [org_code], [org_name], [unit_code], [unit_name],
--      [item_cat_code], [item_cat_name], [item_code], [item_name], [category], [metric_type], [unit_price], [quantity], [amount], [remark], [create_user])
-- VALUES
--     (2026, 10, '2026-10-09', '1001', N'大连市皮肤病医院', 'D1002', N'皮肤内科', 'ADMIN', N'行政政工类',
--      'ADM_DEPT_PENALTY', N'科室集体行政处罚', 'PUNISH', 'AMOUNT', 2000.00000000, 1.00000000, 2000.00000000, N'院周会通报批评', 'system');
--
-- 5.2 个人级金额奖励（二次分配：staff_code / staff_name 填写工号与姓名，metric_type = AMOUNT）
-- INSERT INTO [dbo].[dwd_fin_reward_punish_detail]
--     ([calc_year], [calc_month], [record_date], [org_code], [org_name], [unit_code], [unit_name], [staff_code], [staff_name],
--      [item_cat_code], [item_cat_name], [item_code], [item_name], [category], [metric_type], [unit_price], [quantity], [amount], [remark], [create_user])
-- VALUES
--     (2026, 10, '2026-10-12', '1001', N'大连市皮肤病医院', 'D1002', N'皮肤内科', '20260001', N'张三',
--      'QUALITY', N'医疗质控类', 'QC_REWARD', N'病历书写质控奖励', 'REWARD', 'AMOUNT', 200.00000000, 1.00000000, 200.00000000, N'三季度病历甲级', 'system');
--
-- 5.3 个人级分数奖惩（metric_type = SCORE：unit_price 为「分/次」，amount 为最终分值；扣分同样录入正值 2，方向由 category = PUNISH 表达）
-- INSERT INTO [dbo].[dwd_fin_reward_punish_detail]
--     ([calc_year], [calc_month], [record_date], [org_code], [org_name], [unit_code], [unit_name], [staff_code], [staff_name],
--      [item_cat_code], [item_cat_name], [item_code], [item_name], [category], [metric_type], [unit_price], [quantity], [amount], [remark], [create_user])
-- VALUES
--     (2026, 10, '2026-10-12', '1001', N'大连市皮肤病医院', 'D1002', N'皮肤内科', '20260001', N'张三',
--      'QUALITY', N'医疗质控类', 'QC_SCORE_DEDUCT', N'病历书写不规范扣分', 'PUNISH', 'SCORE', 2.00000000, 1.00000000, 2.00000000, N'病历首页缺项', 'system');
--
-- 5.4 账期 × 科室奖惩汇总（按 metric_type 分子池合计，严禁跨量纲相加；窄覆盖索引零回表）
--     源列一律正数绝对值，故 net 口径必须按 category 施加符号（PUNISH 取负），严禁裸 SUM(amount) 当净额
-- SELECT f.[calc_year], f.[calc_month], f.[unit_code], f.[unit_name],
--        SUM(CASE WHEN f.[metric_type] = 'AMOUNT' AND f.[category] = 'REWARD' THEN f.[amount] ELSE 0.00000000 END) AS [reward_amount],
--        SUM(CASE WHEN f.[metric_type] = 'AMOUNT' AND f.[category] = 'PUNISH' THEN f.[amount] ELSE 0.00000000 END) AS [punish_amount],
--        SUM(CASE WHEN f.[metric_type] = 'AMOUNT' AND f.[category] = 'PUNISH' THEN -f.[amount] ELSE f.[amount] END) AS [net_amount],
--        SUM(CASE WHEN f.[metric_type] = 'SCORE'  AND f.[category] = 'PUNISH' THEN -f.[amount] ELSE f.[amount] END) AS [net_score]
-- FROM [dbo].[dwd_fin_reward_punish_detail] AS f
-- GROUP BY f.[calc_year], f.[calc_month], f.[unit_code], f.[unit_name];
