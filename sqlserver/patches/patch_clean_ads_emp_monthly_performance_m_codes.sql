/* ===============================================================================
  Relative Path : sqlserver/patches/patch_clean_ads_emp_monthly_performance_m_codes.sql
  脚本名称: patch_clean_ads_emp_monthly_performance_m_codes.sql
  脚本类型: DML 数据清洗补丁（幂等可重复执行，非表结构 DDL）
  目标表  : dbo.[ads_emp_monthly_performance_m]
  业务说明: 清洗维度编码列被误填为对应名称的脏数据：
            · 动作 A：unit_code = unit_name 时，依据 T_DEPARTMENT 映射替换为真实 CODE；
            · 动作 B：series_code = series_name 时，依据标准职系对照表替换为 4 位数字编码。
  -------------------------------------------------------------------------------
  【动作 A 映射依据 —— 唯一性锁死】
  以 a.unit_name = d.NAME 精确匹配 dbo.[T_DEPARTMENT]，
  通过 ROW_NUMBER() OVER (PARTITION BY [NAME] ORDER BY [ID] ASC) 取 rn = 1，
  物理锁死「同名部门取最小 ID」单一行，杜绝 UPDATE ... FROM 多行匹配膨胀。
  过滤 d.[DELETE_FLAG] = 0 剔除逻辑删除部门，并排除 [CODE] 为 NULL / 空串的无效行。
  -------------------------------------------------------------------------------
  【触发条件语义确认 —— 为何可安全前置断言】
  两个动作的触发条件均为「编码列 = 名称列」，属纯自反等值判定，与映射来源表无关。
  因此可完全脱离事务前置断言命中行数：若两列恒不相等则本脚本必然零副作用。
  -------------------------------------------------------------------------------
  【主键防重防御 —— pk_ads_emp_monthly_performance_m】
  联合主键 (year, month, unit_code, staff_code, post_code)。
  更新 unit_code 会抬高主键冲突概率，故 UPDATE 前以 NOT EXISTS 反连接排除
  「目标键已存在」的潜在行：这些行被刻意跳过而非终止，保障已命中的正常行仍可
  单批提交，同时杜绝触发器级 pk_ads_emp_monthly_performance_m 唯一约束异常中断。
  -------------------------------------------------------------------------------
  【编码字段字符串语义】
  unit_code / series_code 均为 VARCHAR 字符串编码，映射常量一律以单引号文本字面量
  写入，严禁 CAST 为 INT/BIGINT（防前导零丢弃与关联失配）。
  -------------------------------------------------------------------------------
  【幂等性说明】
  两处更新均为「绝对值赋值」而非增量计算；其中动作 B 的 UPDATE 以
  [series_code] = [series_name] 作为自身过滤条件，正确行天然免疫。
  故本脚本可重复执行且结果恒等，重复执行影响行数归零。
  -------------------------------------------------------------------------------
  【执行边界声明 —— 不做的事】
  1. 不回溯修正因主键冲突被跳过的 row（仅跳过，不作删除/覆盖/改键）。
  2. 不臆造 T_DEPARTMENT 未收录部门的编码（未命中行保持原值不动）。
  3. 不改动任何金额度量列与审计时间戳列，本补丁更新域严格锁定 2 个编码列。
  -------------------------------------------------------------------------------
  修改日志：
  2026-10-05 00:00:00 | 脚本新建 | 创建个人月度绩效金额明细表维度编码清洗补丁：
                                 动作 A 依据 T_DEPARTMENT 同名最小 ID 映射刷洗 unit_code；
                                 动作 B 依据标准职系对照表刷洗 series_code；
                                 以 NOT EXISTS 反连接防御联合主键冲突；
                                 包裹显式事务与 TRY...CATCH，全局禁 GO 协议、单批分号结束。
=============================================================================== */

SET XACT_ABORT ON;
SET NOCOUNT ON;

-- ================================================================
-- 前置守卫：目标表存在性校验
-- ================================================================
IF OBJECT_ID(N'[dbo].[ads_emp_monthly_performance_m]', N'U') IS NULL
BEGIN
    RAISERROR(N'目标表 [dbo].[ads_emp_monthly_performance_m] 不存在，补丁终止。', 16, 1);
    RETURN;
END;

-- ================================================================
-- 清洗前基线快照：待修复脏数据计数（执行日志留痕，便于前后比对）
-- ================================================================
SELECT
    SUM(CASE WHEN [unit_code]   = [unit_name]   THEN 1 ELSE 0 END)                      AS [待清洗_UNIT_CODE]
   ,SUM(CASE WHEN [series_code] = [series_name] THEN 1 ELSE 0 END)                      AS [待清洗_SERIES_CODE]
   ,COUNT(*)                                                                            AS [目标表总行数]
FROM [dbo].[ads_emp_monthly_performance_m];

-- ================================================================
-- 事务主体：TRY / CATCH 包裹双动作清洗
-- ================================================================
BEGIN TRY
    BEGIN TRANSACTION;

    -- ------------------------------------------------------------
    -- 动作 A：清洗 unit_code（依据 T_DEPARTMENT 同名最小 ID 映射）
    -- ------------------------------------------------------------
    WITH [UniqueDept] AS (
        SELECT
            [NAME],
            [CODE],
            ROW_NUMBER() OVER (PARTITION BY [NAME] ORDER BY [ID] ASC) AS [RN]
        FROM [dbo].[T_DEPARTMENT]
        WHERE [DELETE_FLAG] = 0
          AND [CODE] IS NOT NULL
          AND [CODE] <> ''
    )
    UPDATE [a]
    SET [a].[unit_code] = [d].[CODE]
    FROM [dbo].[ads_emp_monthly_performance_m] AS [a]
    INNER JOIN [UniqueDept] AS [d]
        ON [a].[unit_name] = [d].[NAME]
       AND [d].[RN] = 1
    WHERE 1 = 1
      AND [a].[unit_code] = [a].[unit_name]
      -- 核心防御：排除更新后与既有行主键冲突的潜在行，避免唯一约束异常中断
      AND NOT EXISTS (
          SELECT 1
          FROM [dbo].[ads_emp_monthly_performance_m] AS [target_pk]
          WHERE 1 = 1
            AND [target_pk].[year]       = [a].[year]
            AND [target_pk].[month]      = [a].[month]
            AND [target_pk].[unit_code]  = [d].[CODE]
            AND [target_pk].[staff_code] = [a].[staff_code]
            AND [target_pk].[post_code]  = [a].[post_code]
      );

    DECLARE @RownumUnitCode INT = @@ROWCOUNT;

    -- ------------------------------------------------------------
    -- 动作 B：清洗 series_code（依据标准职系对照表硬编码映射）
    -- ------------------------------------------------------------
    UPDATE [dbo].[ads_emp_monthly_performance_m]
    SET [series_code] = CASE [series_name]
            WHEN N'护理系列'   THEN '1001'
            WHEN N'科研'       THEN '1006'
            WHEN N'临床系列'   THEN '1011'
            WHEN N'麻风住院部' THEN '1016'
            WHEN N'行后系列'   THEN '1021'
            WHEN N'药剂'       THEN '1026'
            WHEN N'医辅系列'   THEN '1031'
            WHEN N'医技系列'   THEN '1036'
            ELSE [series_code]
        END
    WHERE 1 = 1
      AND [series_code] = [series_name]
      AND [series_name] IN (
              N'护理系列', N'科研', N'临床系列', N'麻风住院部',
              N'行后系列', N'药剂', N'医辅系列', N'医技系列'
          );

    DECLARE @RownumSeriesCode INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    PRINT N'SUCCESS: ads_emp_monthly_performance_m 维度编码清洗完成。';
    PRINT N'  动作 A 影响行数（UNIT_CODE）  : ' + CAST(@RownumUnitCode   AS VARCHAR(11));
    PRINT N'  动作 B 影响行数（SERIES_CODE）: ' + CAST(@RownumSeriesCode AS VARCHAR(11));
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    DECLARE @ErrorMessage NVARCHAR(4000) = ERROR_MESSAGE();
    DECLARE @ErrorSeverity INT = ERROR_SEVERITY();
    DECLARE @ErrorState    INT = ERROR_STATE();

    RAISERROR(@ErrorMessage, @ErrorSeverity, @ErrorState);
END CATCH;

-- ================================================================
-- 核查 1：残留异常计数（期望 [待清洗_UNIT_CODE] = 0，[待清洗_SERIES_CODE] = 0）
-- ================================================================
SELECT
    SUM(CASE WHEN [unit_code]   = [unit_name]   THEN 1 ELSE 0 END)                      AS [待清洗_UNIT_CODE]
   ,SUM(CASE WHEN [series_code] = [series_name] THEN 1 ELSE 0 END)                      AS [待清洗_SERIES_CODE]
   ,COUNT(*)                                                                            AS [目标表总行数]
FROM [dbo].[ads_emp_monthly_performance_m];

-- ================================================================
-- 核查 2：主键冲突被跳过的行明细（动作 A 未覆盖的脏数据，需人工复核）
-- ================================================================
WITH [UniqueDept] AS (
    SELECT
        [NAME],
        [CODE],
        ROW_NUMBER() OVER (PARTITION BY [NAME] ORDER BY [ID] ASC) AS [RN]
    FROM [dbo].[T_DEPARTMENT]
    WHERE [DELETE_FLAG] = 0
      AND [CODE] IS NOT NULL
      AND [CODE] <> ''
)
SELECT
    [a].[year]                                                                          AS [年份]
   ,[a].[month]                                                                         AS [月份]
   ,[a].[unit_code]                                                                     AS [异常_单元编码]
   ,[a].[unit_name]                                                                     AS [单元名称]
   ,[d].[CODE]                                                                          AS [映射目标编码]
   ,[a].[staff_code]                                                                    AS [员工编码]
   ,[a].[post_code]                                                                     AS [岗位编码]
   ,N'目标主键已存在，更新被跳过'                                                        AS [跳过原因]
FROM [dbo].[ads_emp_monthly_performance_m] AS [a]
INNER JOIN [UniqueDept] AS [d]
    ON [a].[unit_name] = [d].[NAME]
   AND [d].[RN] = 1
WHERE 1 = 1
  AND [a].[unit_code] = [a].[unit_name]
  AND EXISTS (
      SELECT 1
      FROM [dbo].[ads_emp_monthly_performance_m] AS [target_pk]
      WHERE 1 = 1
        AND [target_pk].[year]       = [a].[year]
        AND [target_pk].[month]      = [a].[month]
        AND [target_pk].[unit_code]  = [d].[CODE]
        AND [target_pk].[staff_code] = [a].[staff_code]
        AND [target_pk].[post_code]  = [a].[post_code]
  );

-- ================================================================
-- 核查 3：unit_code 映射覆盖率核查（T_DEPARTMENT 未命中项，保持原值）
-- ================================================================
WITH [UniqueDept] AS (
    SELECT
        [NAME],
        [CODE],
        ROW_NUMBER() OVER (PARTITION BY [NAME] ORDER BY [ID] ASC) AS [RN]
    FROM [dbo].[T_DEPARTMENT]
    WHERE [DELETE_FLAG] = 0
      AND [CODE] IS NOT NULL
      AND [CODE] <> ''
)
SELECT
    [a].[unit_name]                                                                     AS [未命中_单元名称]
   ,COUNT(*)                                                                            AS [涉及行数]
   ,MIN([a].[unit_code])                                                                AS [当前编码]
FROM [dbo].[ads_emp_monthly_performance_m] AS [a]
LEFT JOIN [UniqueDept] AS [d]
    ON [a].[unit_name] = [d].[NAME]
   AND [d].[RN] = 1
WHERE 1 = 1
  AND [a].[unit_code] = [a].[unit_name]
  AND [d].[CODE] IS NULL
GROUP BY [a].[unit_name]
ORDER BY [涉及行数] DESC;
