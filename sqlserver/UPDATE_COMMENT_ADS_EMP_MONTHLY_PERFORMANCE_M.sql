-- =================================================================
-- 注释修订：ads_emp_monthly_performance_m（仅改表级注释，不改结构/数据）
-- 目的：明确该表为「大连市皮肤病医院专用 · 线下发放口径」，避免被误用为通用表
-- Relative Path : sqlserver/UPDATE_COMMENT_ADS_EMP_MONTHLY_PERFORMANCE_M.sql
-- =================================================================
EXEC sys.sp_updateextendedproperty
    @name = N'MS_Description',
    @value = N'【个人月度绩效金额明细表（大连市皮肤病医院专用·线下发放口径）】：承载该院线下核定发放的员工个人绩效奖、管理绩效、合计绩效、固定部分绩效及扣除固定部分后绩效等核心金额指标的明细资产表；非通用口径，其他医院不适用。',
    @level0type = N'SCHEMA', @level0name = N'dbo',
    @level1type = N'TABLE',  @level1name = N'ads_emp_monthly_performance_m';