/*
================================================================================
Relative Path : sqlserver/dwd_fin_charge_workload_detail.sql
脚本名称     : dwd_fin_charge_workload_detail.sql
分层归属     : DWD（明细层 / 线下导入工作量事实明细）
业务定义     : 全院通用线下 Excel 导入工作量事实表，承载无 HIS 结构化流水科室（收费处、药剂科等）
               的「细目 + 年月 + 值」线下工作量，作为该类科室一次分配工作量的通用事实源；
               表名沿用历史 charge 前缀仅为物理层在线兼容，严禁理解为收费处专属表。
项目分类     : item_code 承载标准化编码契约，收费类 8 类标准取值与全院追加规则见字段级扩展属性。
粒度         : 自增 id 物理唯一；业务粒度 = 核算年月 × 机构 × 核算单元 × 标准项目编码，
               一个细目一个月仅存一行，重复导入必须先删后插（幂等重跑，见下）。
适用范围     : 全院各科室通用（收费处、药剂科等任意线下工作量科室），非任何单一科室专属，
               新增科室无需变更本表物理结构。
空值语义     : org_code / org_name / unit_code / unit_name / item_code / item_name 全部 NOT NULL
               且无任何物理默认值，机构与核算单元维度一律由导入端显式传入，
               严禁依赖隐式缺省值污染科室归属；batch_no / remark 允许 NULL。
度量口径     : workload_qty 为唯一度量列（线下导入原始值）；单价与结算金额不落本表，
               由下游单价配置与算子层承接。
数值符号约定 : workload_qty 一律录入正数，受内核 CHECK >= 0.00000000 硬约束；退费、退号等
               语义为「正数绝对量」，加减方向由 item_code 决定，严禁录入负数。
数值精度     : 全量 DECIMAL(18,8)，对齐全局精度强制标准。
编码字段语义 : org_code / unit_code / item_code / batch_no 全量 VARCHAR 字符串语义，严禁整型化。
索引策略     : 聚簇主键 pk_dwd_fin_charge_workload_detail（id）保障行级唯一寻址；
               ix_dwd_fin_charge_workload_detail_lookup（calc_year, calc_month, unit_code, item_code）
               INCLUDE (item_name, workload_qty) 实现账期 × 核算单元 × 细目汇总零回表。
幂等重跑     : 本脚本自带 IF EXISTS DROP TABLE 卸载；数据层重导入须先按
               (calc_year, calc_month, unit_code) 或 batch_no 删除历史行再插入。
会话无关性   : 无 DATEFIRST / LANGUAGE 会话依赖。
模板占位符   : 无（纯 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）。
修改日志：
2026-10-14 09:43:24 | 结构剪裁 | 剥离 org_code / org_name 物理 DEFAULT，机构与核算单元四列统一为纯 NOT NULL 显式赋值；头部说明与扩展属性注释大幅熵减。
2026-10-14 09:30:05 | 结构剪裁 | 剥离 unit_code / unit_name 物理 DEFAULT（100031 / 收款处）。
2026-10-14 09:26:54 | 语义泛化 | 泛化为全院通用线下导入工作量明细事实表（收费处、药剂科等）。
2026-10-13 18:10:00 | 文档纠偏 | 说明文案对齐物理默认值（U0101 ➔ 100031、收费处 ➔ 收款处）。
2026-10-13 16:30:00 | 结构剪裁 | 补齐 org_name；剥离冗余度量列 unit_price / calc_amount。
2026-10-13 15:00:00 | 初始建表 | 新建线下导入工作量明细事实表（自增主键 + 覆盖索引 + 非负 CHECK）。
================================================================================
*/

-- 1. 幂等卸载同名物理表
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[dwd_fin_charge_workload_detail]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[dwd_fin_charge_workload_detail];
END;

-- 2. 创建线下导入工作量明细事实表（全院通用）
CREATE TABLE [dbo].[dwd_fin_charge_workload_detail] (
    [id]           BIGINT IDENTITY(1,1) NOT NULL,                       -- 自增代理主键

    [calc_year]    INT              NOT NULL,                           -- 核算年份
    [calc_month]   INT              NOT NULL,                           -- 核算月份

    [org_code]     VARCHAR(50)      NOT NULL,                           -- 机构编码（导入端显式赋值）
    [org_name]     NVARCHAR(100)    NOT NULL,                           -- 机构名称（导入端显式赋值）
    [unit_code]    VARCHAR(50)      NOT NULL,                           -- 核算单元编码（导入端显式赋值）
    [unit_name]    NVARCHAR(100)    NOT NULL,                           -- 核算单元名称（导入端显式赋值）

    [item_code]    VARCHAR(50)      NOT NULL,                           -- 标准项目编码
    [item_name]    NVARCHAR(200)    NOT NULL,                           -- 原始细目名称

    [workload_qty] DECIMAL(18,8)    NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_workload_qty DEFAULT (0.00000000), -- 工作量数值

    [batch_no]     VARCHAR(50)      NULL,                               -- 导入批次号
    [remark]       NVARCHAR(1000)   NULL,                               -- 备注说明
    [create_user]  VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_create_user DEFAULT ('system'),  -- 创建人
    [create_time]  DATETIME         NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_create_time DEFAULT (GETDATE()), -- 创建时间
    [update_user]  VARCHAR(50)      NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_update_user DEFAULT ('system'),  -- 最后修改人
    [update_time]  DATETIME         NOT NULL CONSTRAINT df_dwd_fin_charge_workload_detail_update_time DEFAULT (GETDATE()), -- 最后修改时间

    CONSTRAINT [pk_dwd_fin_charge_workload_detail] PRIMARY KEY CLUSTERED (
        [id] ASC
    ),
    CONSTRAINT [ck_dwd_fin_charge_workload_detail_workload_qty] CHECK ([workload_qty] >= 0.00000000)
);

-- 3. 检索索引（账期 × 核算单元 × 细目 覆盖索引）
CREATE NONCLUSTERED INDEX [ix_dwd_fin_charge_workload_detail_lookup]
    ON [dbo].[dwd_fin_charge_workload_detail] ([calc_year] ASC, [calc_month] ASC, [unit_code] ASC, [item_code] ASC)
    INCLUDE ([item_name], [workload_qty]);

-- 4. 表级与字段级扩展属性注释
EXEC sp_addextendedproperty N'MS_Description', N'全院通用线下导入工作量明细事实表：承载无 HIS 结构化流水科室（收费处、药剂科等）的线下 Excel 细目工作量，为一次分配工作量的通用事实源；业务粒度 = 核算年月 × 机构 × 核算单元 × 标准项目编码；org_code / org_name / unit_code / unit_name 均为纯 NOT NULL 无默认值，导入端必须显式传入；workload_qty 为唯一度量列，受 CHECK >= 0 非负硬约束，退费退号类语义为绝对量、方向由 item_code 决定；数值精度 DECIMAL(18,8)', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail';
EXEC sp_addextendedproperty N'MS_Description', N'自增代理主键（聚簇，行级唯一寻址；业务粒度见表级说明）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'id';
EXEC sp_addextendedproperty N'MS_Description', N'核算年份（如 2026）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'calc_year';
EXEC sp_addextendedproperty N'MS_Description', N'核算月份（如 10）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'calc_month';
EXEC sp_addextendedproperty N'MS_Description', N'机构编码（NOT NULL 且无默认值，导入端必须显式传入；字符串语义，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'org_code';
EXEC sp_addextendedproperty N'MS_Description', N'机构名称（NOT NULL 且无默认值，导入端必须显式传入；展示标签，严禁作为关联键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'org_name';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室编码（NOT NULL 且无默认值，导入端必须显式赋真实 HPS_DEPT_CODE；字符串语义，严禁整型化）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'unit_code';
EXEC sp_addextendedproperty N'MS_Description', N'核算单元/科室名称（NOT NULL 且无默认值，导入端必须显式赋真实科室名称）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'unit_name';
EXEC sp_addextendedproperty N'MS_Description', N'标准项目编码（NOT NULL，字符串语义，严禁整型化）；收费类标准取值：PROJ_CHARGE_FEES_PAY 收费服务工作 / PROJ_CHARGE_FEES_REFUND 退费服务工作 / PROJ_CHARGE_REG_CANCEL 挂号退号 / PROJ_CHARGE_INPATIENT_ADM 入院收费 / PROJ_CHARGE_INPATIENT_DIS 出院结算 / PROJ_CHARGE_DEPOSIT_ADJ 押金调整 / PROJ_CHARGE_INSURANCE_SETTLE 医保结算 / PROJ_CHARGE_DAILY_SETTLE 日结；其他科室按同构命名追加自有细目（不施加枚举 CHECK）；加减方向由本列语义决定', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'item_code';
EXEC sp_addextendedproperty N'MS_Description', N'导入原始细目名称（汉字仅作展示与人工核对，严禁作为关联键）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'item_name';
EXEC sp_addextendedproperty N'MS_Description', N'工作量数值（唯一度量列，导入原始值；DECIMAL(18,8)，受 CHECK >= 0 非负约束；退费退号类录入正数绝对量，方向由 item_code 决定）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'workload_qty';
EXEC sp_addextendedproperty N'MS_Description', N'导入批次号（可空，Excel 导入批次唯一标识，支撑按批次回滚与重复导入追责）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'batch_no';
EXEC sp_addextendedproperty N'MS_Description', N'备注说明（导入异常、口径调整、人工修正等追溯信息）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'remark';
EXEC sp_addextendedproperty N'MS_Description', N'创建人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'create_user';
EXEC sp_addextendedproperty N'MS_Description', N'创建时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'create_time';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改人（默认 system）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'update_user';
EXEC sp_addextendedproperty N'MS_Description', N'最后修改时间（默认 GETDATE()）', N'SCHEMA', N'dbo', N'TABLE', N'dwd_fin_charge_workload_detail', N'COLUMN', N'update_time';

