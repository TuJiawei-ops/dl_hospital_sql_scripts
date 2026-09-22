/* ===============================================================================
  Relative Path : sqlserver/patches/PATCH_UPDATE_DEPT_ITEM_EXEC_RATIO_OUT_HOSP.sql
  脚本名称: PATCH_UPDATE_DEPT_ITEM_EXEC_RATIO_OUT_HOSP.sql
  脚本类型: DML 数据刷洗补丁（一次性执行，非表结构 DDL）
  目标表  : dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
  业务说明: 将院外项目表 dbo.[DIM_OUT_HOSP_ITEM] 中收录的项目，在科室项目执行比例
            维表中对应记录的四类执行比例全部清零，并追加备注标记，确保院外项目不参与
            医技护临执行划分核算。
  关联键  : ratio.[ITEM_CODE] = out_item.[ITEM_CODE]（编码字符串裸引用，零 CAST）
  -------------------------------------------------------------------------------
  【生效态作用域声明 —— 执行前必读】
  本表 [IS_ENABLED] 为 SCD Type 2 生效区间的当前逻辑状态投影，IS_ENABLED = 0 表示
  已停用历史废弃行。本脚本严格限定 IS_ENABLED = 1（仅清当前生效规则），避免对废弃行
  更新 [REMARK] / [UPDATE_TIME] 导致历史核算周期回溯无法判定规则真实停用日期。
  如需一并处理停用历史行，请显式移除 WHERE 中的 IS_ENABLED 条件。
  -------------------------------------------------------------------------------
  【影响面声明】
  业务唯一性由过滤唯一索引 (HIS_DEPT_CODE, ITEM_CODE) WHERE IS_ENABLED = 1 约束，
  [ITEM_CODE] 可对应多个 [HIS_DEPT_CODE] 多行，故单个院外项目将命中该项目的全部
  科室生效规则并全部清零，此为本需求预期行为（院外项目在任何科室均不核算）。
  -------------------------------------------------------------------------------
  【类型安全声明】
  1. 四类比例列物理类型均为 DECIMAL(18,8) NOT NULL，字面量 0.00000000 精度精确匹配。
  2. [UPDATE_TIME] 物理类型为 DATETIME2，与 SYSDATETIME() 返回类型一致，无需 GETDATE() 转换。
  -------------------------------------------------------------------------------
  【备注追加口径 —— 严禁覆盖存量】
  · 存量 [REMARK] 为 NULL 或全空格  → 写入 N'院外项目，不核算'
  · 存量已含 N'院外项目，不核算'     → 恒等保留原值（幂等性保证，防重复追加）
  · 存量有其他文本                   → 后缀追加 N'；院外项目，不核算'
  -------------------------------------------------------------------------------
  【幂等性说明】
  比例为绝对值赋值、备注为「含标记即跳过」的幂等追加，可重复执行且结果一致。
  重复执行会刷新 [UPDATE_TIME]；如需区分首跑与重跑，请比对影响行数。
  -------------------------------------------------------------------------------
  修改日志：
  2026-09-22 17:35:00 | 初始化 | 建立院外项目科室执行比例清零与备注追加补丁
  2026-09-22 17:35:00 | 纠偏 | 追加 IS_ENABLED = 1 生效态限定，防污染已停用历史行审计
=============================================================================== */

SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE ratio
SET
    ratio.[DOC_EXEC_RATIO]      = 0.00000000
   ,ratio.[TECH_EXEC_RATIO]     = 0.00000000
   ,ratio.[NURSE_EXEC_RATIO]    = 0.00000000
   ,ratio.[CLINICAL_EXEC_RATIO] = 0.00000000
   ,ratio.[REMARK]              = CASE
                                      WHEN ratio.[REMARK] IS NULL OR LTRIM(RTRIM(ratio.[REMARK])) = N'' THEN N'院外项目，不核算'
                                      WHEN ratio.[REMARK] LIKE N'%院外项目，不核算%'                  THEN ratio.[REMARK]
                                      ELSE ratio.[REMARK] + N'；院外项目，不核算'
                                  END
   ,ratio.[UPDATE_USER]        = N'SYSTEM'
   ,ratio.[UPDATE_TIME]        = SYSDATETIME()
FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS ratio
INNER JOIN dbo.[DIM_OUT_HOSP_ITEM] AS out_item
    ON ratio.[ITEM_CODE] = out_item.[ITEM_CODE]
WHERE ratio.[IS_ENABLED] = 1
  AND (
      ratio.[REMARK] IS NULL
      OR ratio.[REMARK] NOT LIKE N'%院外项目，不核算%'
  );

PRINT N'院外项目执行比例清零影响行数: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

COMMIT TRANSACTION;

-- 复核：清零结果明细（已生效且含标记）
SELECT
    ratio.[ID]                                                           AS [主键ID]
   ,ratio.[HIS_DEPT_CODE]                                                AS [HIS科室编码]
   ,ratio.[HIS_DEPT_NAME]                                                AS [HIS科室名称]
   ,ratio.[ITEM_CODE]                                                    AS [项目代码]
   ,ratio.[ITEM_NAME]                                                    AS [项目名称]
   ,CAST(ratio.[DOC_EXEC_RATIO] AS DECIMAL(18,8))                        AS [医生执行比例]
   ,CAST(ratio.[TECH_EXEC_RATIO] AS DECIMAL(18,8))                       AS [技师执行比例]
   ,CAST(ratio.[NURSE_EXEC_RATIO] AS DECIMAL(18,8))                      AS [护士执行比例]
   ,CAST(ratio.[CLINICAL_EXEC_RATIO] AS DECIMAL(18,8))                   AS [临床执行比例]
   ,ratio.[REMARK]                                                       AS [备注]
   ,ratio.[UPDATE_USER]                                                  AS [更新人]
   ,CONVERT(VARCHAR(23), ratio.[UPDATE_TIME], 121)                       AS [更新时间]
FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS ratio WITH (NOLOCK)
INNER JOIN dbo.[DIM_OUT_HOSP_ITEM] AS out_item WITH (NOLOCK)
    ON ratio.[ITEM_CODE] = out_item.[ITEM_CODE]
WHERE ratio.[IS_ENABLED] = 1
ORDER BY
    ratio.[ITEM_CODE] ASC
   ,ratio.[HIS_DEPT_CODE] ASC
;

-- 复核：生效态残留未清零行核查（应为零行）
SELECT
    COUNT(1)                                                              AS [未清零残留行数]
FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS ratio WITH (NOLOCK)
INNER JOIN dbo.[DIM_OUT_HOSP_ITEM] AS out_item WITH (NOLOCK)
    ON ratio.[ITEM_CODE] = out_item.[ITEM_CODE]
WHERE ratio.[IS_ENABLED] = 1
  AND (
      ratio.[DOC_EXEC_RATIO]      <> 0.00000000
      OR ratio.[TECH_EXEC_RATIO]  <> 0.00000000
      OR ratio.[NURSE_EXEC_RATIO] <> 0.00000000
      OR ratio.[CLINICAL_EXEC_RATIO] <> 0.00000000
      OR ratio.[REMARK] IS NULL
      OR ratio.[REMARK] NOT LIKE N'%院外项目，不核算%'
  )
;
