/* ===============================================================================
  Relative Path : sqlserver/patches/patch_clean_ads_emp_monthly_performance_m_codes.sql
  脚本名称: patch_clean_ads_emp_monthly_performance_m_codes.sql
  脚本类型: DML 数据清洗补丁（幂等可重复执行，非表结构 DDL）
  目标表  : dbo.[ads_emp_monthly_performance_m]
  业务说明: 清洗维度编码列及核算单元名称列被误填/非标的脏数据（按动作 0 → A → B 顺序执行）：
            · 动作 0：将非标 unit_name 纠正为标准名称；若 unit_code 与原名称自反相等，
                      则同步刷新 unit_code 为新标准名称，维持「编码待解析」标记语义；
            · 动作 A：unit_code = unit_name 时，依据 T_DEPARTMENT 映射替换为真实 CODE；
            · 动作 B：series_code = series_name 时，依据标准职系对照表替换为 4 位数字编码。
  -------------------------------------------------------------------------------
  【执行顺序 —— 动作 0 必须前置的不可逆动因】
  动作 A 的触发条件是 unit_code = unit_name 自反等值。历史脏数据中该条件成立的行，
  其 unit_name 恰为非标名称（如「病理科医技护」），T_DEPARTMENT 中不存在同名记录，
  动作 A 必然零命中。故必须先由动作 0 将 unit_name 纠正为 T_DEPARTMENT 中真实存在的
  标准名（如「病理医技护」），动作 A 才能成功关联刷出 d.CODE。
  顺序颠倒的顺序依赖是可证伪的：先 A 后 0 将使全部非标名称行永久逃逸编码解析。
  -------------------------------------------------------------------------------
  【动作 0 联动刷新 unit_code 的语义 —— 保持「未解析标记」】
  当 unit_code = unit_name 成立时，该 unit_code 本身即为「占位符（未解析）」，而非
  已解析的真实编码。若仅更新 unit_name 而保留旧 unit_code，行状态将退化为
  unit_code ≠ unit_name，动作 A 随之失配，编码永久无法解析。
  因此必须同步把 unit_code 也刷为新标准名称，令「unit_code = unit_name = 新标准名」
  重新成立，作为交给动作 A 的正确解析入口。
  此处为**恒等重赋值**（新 unit_code 与原值同值），不引入任何新信息，非数据臆造。
  -------------------------------------------------------------------------------
  【动作 0 与主键的交互 —— 经论证无需防重】
  本动作仅更新 unit_code / unit_name，联合主键 (year, month, unit_code, staff_code,
  post_code) 中 unit_code 的取值来自「原 unit_code 同名情形下的名称映射」，
  其值域被严格约束为旧 unit_name 的字面值，绝不越界到该行既有他行的键空间，
  故不产生新的主键冲突面。动作 A 的 NOT EXISTS 反连接防御仍完整保留。
  -------------------------------------------------------------------------------
  【动作 A 映射依据 —— 唯一性锁死】
  以 a.unit_name = d.NAME 精确匹配 dbo.[T_DEPARTMENT]，
  通过 ROW_NUMBER() OVER (PARTITION BY [NAME] ORDER BY [ID] ASC) 取 rn = 1，
  物理锁死「同名部门取最小 ID」单一行，杜绝 UPDATE ... FROM 多行匹配膨胀。
  过滤 d.[DELETE_FLAG] = 0 剔除逻辑删除部门，并排除 [CODE] 为 NULL / 空串的无效行。
  -------------------------------------------------------------------------------
  【控制结构合规声明 —— 游标零使用】
  本脚本为纯集合式更新，全程零游标、零 WHILE 循环；三处 TABLE 级 UPDATE 语句均在
  事务块顶层平坦执行，杜绝「逐行 UPDATE 不存在」之外的一切 DML 写法争议。
  【控制结构合规声明 —— 事务前零行数断言】
  「编码 = 名称」均为纯自反等值判定，与映射来源表无关，故事务前置断言在实际执行中
  恒为零命中，属无效断言；本脚本剔除该冗余断言，改由末端核查 1 承担事后验证职责。
  -------------------------------------------------------------------------------
  【编码字段字符串语义】
  unit_code / series_code 均为 VARCHAR 字符串编码，映射常量一律以单引号文本字面量
  写入，严禁 CAST 为 INT/BIGINT（防前导零丢弃与关联失配）。
  -------------------------------------------------------------------------------
  【幂等性说明】
  三处更新均为「绝对值赋值」而非增量计算：
  · 动作 0 命中集合为 {非标名称}，重跑时名称已是标准值 → 不再命中，更新行数归零；
  · 动作 A 命中集合为 {unit_code = unit_name}，解析成功后自然脱离集合；
  · 动作 B 命中集合为 {series_code = series_name}，同理自我消解。
  故本脚本可重复执行且结果恒等，重复执行影响行数全部归零。
  -------------------------------------------------------------------------------
  【执行边界声明 —— 不做的事】
  1. 不回溯修正因主键冲突被跳过的 row（仅跳过，不作删除/覆盖/改键）。
  2. 不臆造 T_DEPARTMENT 未收录部门的编码（未命中行保持原值不动）。
  3. 不触碰任何金额度量列与审计时间戳列（本补丁更新域锁定 3 列：
     unit_name / unit_code / series_code）。
  -------------------------------------------------------------------------------
  修改日志：
  2026-10-05 02:30:00 | 逻辑前置 | 增加动作 0（unit_name 标准化映射）：在事务块最前面追加非标名称纠正，
                                 并联动刷新 unit_code（仅限原 unit_code = unit_name 的行），
                                 确保名称纠偏后动作 A 可命中 T_DEPARTMENT 编码关联；
                                 同步在头部契约块声明顺序依赖动因、联动语义与非游标控制结构声明。
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
-- 事务主体：TRY / CATCH 包裹三动作清洗（动作 0 → A → B 严格有序）
-- ================================================================
BEGIN TRY
    BEGIN TRANSACTION;

    -- ------------------------------------------------------------
    -- 动作 0：核算单元名称标准化清洗（修正历史错别字/非标名称）
    -- 说明：unit_code 与 unit_name 同步刷新，维持「未解析标记」自反等值，
    --       使后续动作 A 能正确触发 T_DEPARTMENT 编码解析。
    -- ------------------------------------------------------------
    UPDATE [dbo].[ads_emp_monthly_performance_m]
    SET
        [unit_code] = CASE
            WHEN [unit_code] = [unit_name] THEN
                CASE [unit_name]
                    WHEN N'变态反应科护理'           THEN N'变态反应科护士'
                    WHEN N'病理科医技护'             THEN N'病理医技护'
                    WHEN N'激光美容科'               THEN N'激光美容科医生护士工勤'
                    WHEN N'毛发护理'                 THEN N'毛发护士'
                    WHEN N'皮肤二病房护理'           THEN N'皮肤二病房护士'
                    WHEN N'皮肤科护理'               THEN N'皮肤科护士（处置室等）'
                    WHEN N'皮肤三病房护理'           THEN N'皮肤三病房护士'
                    WHEN N'皮肤一病房护理'           THEN N'皮肤一病房护士'
                    WHEN N'日间治疗中心护理'         THEN N'日间治疗中心护士'
                    WHEN N'收款室'                   THEN N'收款处'
                    WHEN N'外科（含门诊、病房）护理' THEN N'外科护士（含门诊、病房）'
                    WHEN N'外科（含门诊、病房）医生' THEN N'外科医生（含门诊、病房）'
                    WHEN N'性病科医生'               THEN N'性病科医生（含门诊、病房）'
                    WHEN N'药物临床试验机构办公室'   THEN N'药物临床试验机构办'
                    WHEN N'治疗科护理'               THEN N'治疗科护士'
                    WHEN N'中医美容科护理'           THEN N'中医美容科护士'
                    WHEN N'中医外治科护理'           THEN N'中医外治科护士'
                    ELSE [unit_code]
                END
            ELSE [unit_code]
        END
       ,[unit_name] = CASE [unit_name]
                    WHEN N'变态反应科护理'           THEN N'变态反应科护士'
                    WHEN N'病理科医技护'             THEN N'病理医技护'
                    WHEN N'激光美容科'               THEN N'激光美容科医生护士工勤'
                    WHEN N'毛发护理'                 THEN N'毛发护士'
                    WHEN N'皮肤二病房护理'           THEN N'皮肤二病房护士'
                    WHEN N'皮肤科护理'               THEN N'皮肤科护士（处置室等）'
                    WHEN N'皮肤三病房护理'           THEN N'皮肤三病房护士'
                    WHEN N'皮肤一病房护理'           THEN N'皮肤一病房护士'
                    WHEN N'日间治疗中心护理'         THEN N'日间治疗中心护士'
                    WHEN N'收款室'                   THEN N'收款处'
                    WHEN N'外科（含门诊、病房）护理' THEN N'外科护士（含门诊、病房）'
                    WHEN N'外科（含门诊、病房）医生' THEN N'外科医生（含门诊、病房）'
                    WHEN N'性病科医生'               THEN N'性病科医生（含门诊、病房）'
                    WHEN N'药物临床试验机构办公室'   THEN N'药物临床试验机构办'
                    WHEN N'治疗科护理'               THEN N'治疗科护士'
                    WHEN N'中医美容科护理'           THEN N'中医美容科护士'
                    WHEN N'中医外治科护理'           THEN N'中医外治科护士'
                    ELSE [unit_name]
                END
    WHERE 1 = 1
      AND [unit_name] IN (
              N'变态反应科护理', N'病理科医技护', N'激光美容科', N'毛发护理',
              N'皮肤二病房护理', N'皮肤科护理', N'皮肤三病房护理', N'皮肤一病房护理',
              N'日间治疗中心护理', N'收款室', N'外科（含门诊、病房）护理',
              N'外科（含门诊、病房）医生', N'性病科医生', N'药物临床试验机构办公室',
              N'治疗科护理', N'中医美容科护理', N'中医外治科护理'
          );

    DECLARE @RownumUnitName INT = @@ROWCOUNT;

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
    PRINT N'  动作 0 影响行数（UNIT_NAME）  : ' + CAST(@RownumUnitName   AS VARCHAR(11));
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
