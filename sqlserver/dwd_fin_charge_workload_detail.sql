/*
================================================================================
Relative Path : sqlserver/dwd_fin_charge_workload_detail.sql
脚本名称     : dwd_fin_charge_workload_detail.sql
分层归属     : DWD（明细层 / 线下导入工作量事实明细）
业务定义     : 全院通用线下 Excel 导入工作量明细事实表。院内无 HIS 结构化流水的科室（收费处、
               药剂科等）业务仅有「细目 + 年月 + 值」三要素（如收费服务工作、退费服务工作、
               挂号退号、入院收费、出院结算、押金调整、医保结算、日结等），故以本表统一承载
               线下导入原始工作量，作为该类科室一次分配工作量的通用事实源；表名沿用历史
               charge 前缀仅为物理层在线兼容，语义已泛化为全院共用，严禁理解为收费处专属表。
粒度         : 自增 id 单行物理唯一；业务粒度 = 核算年月 × 核算单元 × 标准化项目编码，
               一个细目一个月应仅存一行，重复导入必须先删后插（幂等重跑，见下）。
适用范围     : 全院各科室通用，核算单元维度自由赋值（收费处、药剂科等任意线下工作量科室）；
               非任何单一科室专属，新增科室无需变更本表物理结构。
空值语义     : unit_code / unit_name 强制 NOT NULL，保障下游可直接按核算单元映射汇总；
               unit_code / unit_name 物理 DEFAULT（100031 / 收款处）系历史在线兼容残留，
               仅作缺省兜底，不构成业务默认绑定，严禁依赖其表达科室归属，
               多科室导入必须显式赋值真实核算单元；
               org_code / org_name 带 DEFAULT（1001 / 大连市皮肤病医院），导入端可省略机构列；
               batch_no 允许 NULL（历史补录数据可无批次号），remark 允许 NULL。
项目分类     : item_code 承载标准化编码（字符串语义，严禁整型化），收费类标准取值集合：
               PROJ_CHARGE_FEES_PAY / PROJ_CHARGE_FEES_REFUND / PROJ_CHARGE_REG_CANCEL /
               PROJ_CHARGE_INPATIENT_ADM / PROJ_CHARGE_INPATIENT_DIS / PROJ_CHARGE_DEPOSIT_ADJ /
               PROJ_CHARGE_INSURANCE_SETTLE / PROJ_CHARGE_DAILY_SETTLE，明细见字段级扩展属性；
               其他科室（药剂科等）按同构编码契约追加自有细目，不施加枚举 CHECK 硬锁；
               item_name 保留导入原始汉字名称，仅供展示与人工核对，严禁作为关联键。
度量口径     : workload_qty 为导入原始值（唯一度量列，未结算工作量）；
               单价（unit_price）与结算金额（calc_amount）已按最新契约剥离至下游，
               不再落本表，本表回归纯原始工作量事实（一次分配唯读 workload_qty）。
数值符号约定 : workload_qty 一律录入正数，受内核 CHECK >= 0.00000000 硬约束；
               退费、退号等工作量语义为「正数绝对量」，加减方向由 item_code 决定，
               严禁录入负数，从根绝财务加减错乱事故。
数值精度     : 全量 DECIMAL(18,8)，对齐全局精度强制标准。
编码字段语义 : org_code / unit_code / item_code / batch_no 全量 VARCHAR 字符串语义，
               严禁 CAST 为 INT/BIGINT（防前导零丢失与跨表 JOIN 关联失配）。
索引策略     : 聚簇主键 pk_dwd_fin_charge_workload_detail（id）保障行级唯一寻址；
               ix_dwd_fin_charge_workload_detail_lookup（calc_year, calc_month, unit_code, item_code）
               INCLUDE (item_name, workload_qty) 实现
               账期 × 核算单元 × 细目工作量汇总零回表。
幂等重跑     : 本脚本自带 IF EXISTS DROP TABLE 卸载；数据层重导入须先按
               (calc_year, calc_month, unit_code) 或 batch_no 删除历史行再插入，杜绝重复累加。
会话无关性   : 无 DATEFIRST / LANGUAGE 会话依赖。
模板占位符   : 无（纯 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）。
修改日志：
2026-10-14 09:26:54 | 语义泛化 | 表说明、字段注释与扩展属性彻底剥离「收费处专属 / 默认收款处」绑定表述，正式泛化为全院通用线下导入工作量明细事实表（收费处、药剂科等）；物理列、DEFAULT 约束、主键、CHECK 与索引零变更。
2026-10-13 18:10:00 | 文档纠偏 | 说明文案对齐物理 DEFAULT：unit_code 默认值 U0101 ➔ 100031（原注释笔误），unit_name 默认值 收费处 ➔ 收款处；零结构变更。
2026-10-13 16:30:00 | 结构剪裁 | 补齐 org_name（默认 大连市皮肤病医院）；剥离冗余度量列 unit_price / calc_amount（连同其 DEFAULT、CHECK 与索引 INCLUDE），本表收敛为纯原始工作量事实（仅 workload_qty）；表级与字段级扩展属性同步改口径。
2026-10-13 15:00:00 | 初始建表 | 新建收费处线下导入工作量明细事实表：自增 id 聚簇主键 + (账期,核算单元,项目) 覆盖检索索引 + unit_code/unit_name 默认 U0101/收费处 + 三列度量(原值/单价/结算金额) + batch_no 导入批次审计 + 8 类标准项目编码契约 + workload_qty/calc_amount 非负 CHECK；精度锁定 DECIMAL(18,8)；全脚本零 GO 单批分号执行。
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[dwd_fin_charge_workload_detail]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[dwd_fin_charge_workload_detail];
END;

-- ================================================================
-- 2. 创建线下导入工作量明细事实表（全院通用）
-- ================================================================
CREATE TABLE [dbo].[dwd_fin_charge_workload_detail] (
    -- ===== 物理代理主键 =====
    [id]           BIGINT IDENTITY(1,1) NOT NULL,                       -- 自增代理主键

    -- ===== 账期维度 =====
    [calc_year]    INT              NOT NULL,                           -- 核算年份
    [calc_month]   INT              NOT NULL,                           -- 核算月份

    -- ===== 机构与核算单元 =====
    [org_code]     VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_org_code   DEFAULT ('1001'),   -- 机构编码
    [org_name]     NVARCHAR(100)    NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_org_name   DEFAULT (N'大连市皮肤病医院'), -- 机构名称
    [unit_code]    VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_unit_code  DEFAULT ('100031'),  -- 核算单元编码
    [unit_name]    NVARCHAR(100)    NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_unit_name  DEFAULT (N'收款处'), -- 核算单元名称

    -- ===== 项目分类（细目）=====
    [item_code]    VARCHAR(50)      NOT NULL,                           -- 标准项目编码
    [item_name]    NVARCHAR(200)    NOT NULL,                           -- 原始细目名称

    -- ===== 度量指标（唯一度量：原始工作量）=====
    [workload_qty] DECIMAL(18,8)    NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_workload_qty DEFAULT (0.00000000), -- 工作量数值

    -- ===== 导入批次与审计 =====
    [batch_no]     VARCHAR(50)      NULL,                               -- 导入批次号
    [remark]       NVARCHAR(1000)   NULL,                               -- 备注说明
    [create_user]  VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_create_user DEFAULT ('system'),  -- 创建人
    [create_time]  DATETIME         NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_create_time DEFAULT (GETDATE()), -- 创建时间
    [update_user]  VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_update_user DEFAULT ('system'),  -- 最后修改人
    [update_time]  DATETIME         NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_update_time DEFAULT (GETDATE()), -- 最后修改时间

    -- ===== 主键约束 =====
    CONSTRAINT [pk_dwd_fin_charge_workload_detail] PRIMARY KEY CLUSTERED (
        [id] ASC
    ),

    -- ===== 非负约束（内核级杜绝负数录入）=====
    CONSTRAINT [ck_dwd_fin_charge_workload_detail_workload_qty] CHECK ([workload_qty] >= 0.00000000)
);

-- ================================================================
-- 3. 检索索引（账期 × 核算单元 × 项目 覆盖索引）
-- ================================================================
-- 键序对齐一次分配主路径：先按账期切片，再按核算单元与细目下钻
CREATE NONCLUSTERED INDEX [ix_dwd_fin_charge_workload_detail_lookup]
    ON [dbo].[dwd_fin_charge_workload_detail] ([calc_year] ASC, [calc_month] ASC, [unit_code] ASC, [item_code] ASC)
    INCLUDE ([item_name], [workload_qty]);

-- ================================================================
-- 4. 表级与字段级扩展属性注释
--    第 1 区块已 DROP TABLE 重建，表级扩展属性被物理层同步清除，
--    故此处顺序执行，无需 IF EXISTS 守卫
-- ================================================================
EXEC sp_addextendedproperty N'MS_Description', N'全院通用线下导入工作量明细事实表：承载院内无 HIS 结构化流水科室（收费处、药剂科等）的线下 Excel 细目工作量，为该类科室一次分配工作量的通用事实源；表名保留历史 charge 前缀仅为在线物理兼容，语义不限收费处；粒度 = 核算年月 × 核算单元 × 标准项目编码，核算单元维度自由赋值；unit_code / unit_name 物理 DEFAULT（100031 / 收款处）仅为存量兼容兜底、非业务默认绑定，导入端必须显式赋真实核算单元；org_code / org_name 带机构默认值（1001 / 大连市皮肤病医院）；workload_qty 为唯一度量列（线下导入原值），单价与结算金额不落本表、由下游单价配置与算子层承接；workload_qty 受 CHECK >= 0 非负硬约束，退费退号类语义为绝对量、方向由 item_code 决定；数值精度 DECIMAL(18,8)', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail';
EXEC sp_addextendedproperty N'MS_Description', N'自增代理主键（单列聚簇，物理唯一寻址；业务行由 账期 × 核算单元 × 项目编码 逻辑定位，故不设业务复合主键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'id';
EXEC sp_addextendedproperty N'MS_Description', N'核算年份（如 2026）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'calc_year';
EXEC sp_addextendedproperty N'MS_Description', N'核算月份（如 10）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'calc_month';
EXEC sp_addextendedproperty N'MS_Description', N'机构编码（字符串语义，默认 1001，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'org_code';
EXEC sp_addextendedproperty N'MS_Description', N'机构名称（默认 大连市皮肤病医院；业务可读冗余展示标签，严禁作为关联键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'org_name';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室编码（NOT NULL；物理 DEFAULT 100031 系历史在线兼容残留、非业务默认值，导入端必须显式赋真实 HPS_DEPT_CODE，严禁依赖缺省值表达科室归属；字符串语义，严禁整型化防前导零丢失）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'unit_code';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室名称（NOT NULL；物理 DEFAULT 收款处 系历史在线兼容残留、非业务默认值，导入端必须显式赋真实科室名称；支撑科室级汇总展示）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'unit_name';
EXEC sp_addextendedproperty N'MS_Description', N'标准项目编码（NOT NULL，字符串语义，严禁整型化）；收费类标准取值（示例集合，非全院枚举）：PROJ_CHARGE_FEES_PAY 收费服务工作 / PROJ_CHARGE_FEES_REFUND 退费服务工作 / PROJ_CHARGE_REG_CANCEL 挂号退号 / PROJ_CHARGE_INPATIENT_ADM 入院收费 / PROJ_CHARGE_INPATIENT_DIS 出院结算 / PROJ_CHARGE_DEPOSIT_ADJ 押金调整 / PROJ_CHARGE_INSURANCE_SETTLE 医保结算 / PROJ_CHARGE_DAILY_SETTLE 日结；全院各科室共用同一编码契约，其他科室（药剂科等）按同构命名追加自有细目；该集合属业务细目台账，新增细目不施加枚举 CHECK 硬锁；加减方向由本列语义决定，严禁依赖 workload_qty 正负号', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'item_code';
EXEC sp_addextendedproperty N'MS_Description', N'导入原始细目名称（如 收费服务工作 / 退费服务工作 / 药剂科线下工作量；汉字仅作展示与人工核对，严禁作为关联键或 JOIN 条件）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'item_name';
EXEC sp_addextendedproperty N'MS_Description', N'工作量数值（DECIMAL(18,8) 高精度，默认 0.00000000；本表唯一度量列，线下导入原始值；受 CHECK >= 0 非负硬约束，退费退号类录入正数绝对量，方向由 item_code 决定；单价与结算金额不落本表，由下游单价配置与算子层承接）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'workload_qty';
EXEC sp_addextendedproperty N'MS_Description', N'导入批次号（可空，Excel 导入批次唯一标识；支撑按批次整体回滚与重复导入追责）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'batch_no';
EXEC sp_addextendedproperty N'MS_Description', N'备注说明（承载导入异常、口径调整、人工修正依据等追溯信息）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'remark';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system，线下导入时写明操作人工号）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'update_time';

