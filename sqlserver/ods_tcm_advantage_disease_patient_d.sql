/*
================================================================================
Relative Path : sqlserver/ods_tcm_advantage_disease_patient_d.sql
脚本名称     : ods_tcm_advantage_disease_patient_d.sql
分层归属     : ODS（原始数据层 / 明细粒度 _d）
业务定义     : 中医优势病种入组患者明细表（承载日间治疗中心等来源的白疕病、蛇串疮/蛇盘疮病数据）
粒度         : 患者级明细（病种 × 患者 × 结算日期，天然可重复，不设物理主键）
源系统       : 医院信息系统（HIS）/ 日间治疗中心中医优势病种登记
命名规范     : 全小写英文下划线（UPPER_CASE_SNAKE 在中台物理层的小写表述），分层前缀 ods_，后缀 _d 标识日/明细粒度
编码字段语义 : disease_code / patient_no / dept_code 锁定 VARCHAR 字符串语义，严禁整型化（防前导零丢失与关联失配）
金额精度     : total_fee 锁定 DECIMAL(18,8)，对齐全局绩效高精度计算标准
会话无关性   : 全链路无 DATEFIRST / LANGUAGE / COLLATE 会话依赖
模板占位符   : 无（纯 ODS 物理 DDL，不含 '{year}' / '{month}' / '{start_time}' / '{end_time}' / {struct_codes} 动态注入）
修改日志：
2026-09-17 10:48:37 | 初始建表 | 新建中医优势病种入组患者 ODS 物理表结构，严格遵守全小写下划线命名与 DECIMAL(18,8) 精度规范。
================================================================================
*/

-- ================================================================
-- 1. 幂等卸载同名物理表（重跑零脏数据，保障 DDL 脚本可重复执行）
-- ================================================================
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[ods_tcm_advantage_disease_patient_d]') AND type IN (N'U'))
BEGIN
    DROP TABLE [dbo].[ods_tcm_advantage_disease_patient_d];
END;

-- ================================================================
-- 2. 创建中医优势病种入组患者明细物理表
-- ================================================================
CREATE TABLE [dbo].[ods_tcm_advantage_disease_patient_d] (
    -- ===== 病种维度 =====
    [disease_code]    VARCHAR(50)     NOT NULL,                      -- 病种编码（字符串语义，严禁整型化）
    [disease_name]    NVARCHAR(100)   NULL,                          -- 病种名称（如：白疕病 / 蛇串疮 / 蛇盘疮病）
    -- ===== 患者维度 =====
    [patient_name]    NVARCHAR(100)   NULL,                          -- 姓名
    [patient_no]      VARCHAR(50)     NOT NULL,                      -- 门诊号（字符串语义，防前导零丢失）
    -- ===== 科室维度 =====
    [dept_code]       VARCHAR(50)     NULL,                          -- 病人科室ID（字符串语义，对齐 HIS 源编码）
    [dept_name]       NVARCHAR(100)   NULL,                          -- 病人科室名称
    -- ===== 结算时间与金额 =====
    [settle_time]     DATETIME        NOT NULL,                      -- 结算时间
    [total_fee]       DECIMAL(18,8)   NULL,                          -- 医疗费总额（高精度，杜绝低精度截断累积误差）
    -- ===== 审计字段 =====
    [create_time]     DATETIME        NOT NULL DEFAULT (GETDATE())   -- 数据导入/创建时间
);

-- ================================================================
-- 3. 检索索引（支撑核算期间切片与病种/科室降维分析）
-- ================================================================
-- 结算时间 + 病种编码联合索引（服务按月结算区间过滤与病种聚合）
CREATE NONCLUSTERED INDEX [ix_ods_tcm_adv_disease_patient_settle_disease]
    ON [dbo].[ods_tcm_advantage_disease_patient_d] ([settle_time] ASC, [disease_code] ASC);

-- 门诊号索引（支撑患者级明细回溯与跨来源去重比对）
CREATE NONCLUSTERED INDEX [ix_ods_tcm_adv_disease_patient_patient_no]
    ON [dbo].[ods_tcm_advantage_disease_patient_d] ([patient_no] ASC);
