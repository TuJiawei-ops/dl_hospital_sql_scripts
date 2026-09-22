/* ===============================================================================
  Relative Path : sqlserver/patches/PATCH_UPDATE_OUT_HOSP_ITEM_COFF.sql
  脚本名称: PATCH_UPDATE_OUT_HOSP_ITEM_COFF.sql
  脚本类型: DML 数据刷洗补丁（一次性执行，非表结构 DDL）
  目标表  : dbo.[DIM_PRF_ITEM_RVU_VERSION]
  业务说明: 将院外项目表 dbo.[DIM_OUT_HOSP_ITEM] 中定义的项目，在 RVU 点数维表中
            对应的记录执行「决策系数 / 执行系数」归零，并追加备注标记。
  关联键  : rvu.[PROJ_CODE] = out_item.[ITEM_CODE]（编码字符串裸引用，零 CAST）
  -------------------------------------------------------------------------------
  【影响面声明 —— 执行前必读】
  维表主键为复合键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)，同一 [PROJ_CODE]
  可物理多行。本脚本按需求做「全版本 / 全机构」无差别归零，命中行数 = 所有
  版本与机构下匹配的 RVU 记录。如需限定单一版本或机构，请在 JOIN 后追加
  AND rvu.[VERSION_NO] = N'<版本号>' / AND rvu.[ORG_CODE] = N'<机构编码>'。
  -------------------------------------------------------------------------------
  【类型安全声明】
  1. [UPDATE_TIME] 物理类型为 datetime，而 SYSDATETIME() 返回 datetime2，
     隐式转换会抛「消息 8152 截断」类运行时错误，故必须使用 GETDATE()。
  2. [DECISION_COFF] decimal(18,4) / [EXEC_COFF] decimal(5,4) （后者上限 9.9999），
     赋值字面量 0.0000 两列均安全。
  -------------------------------------------------------------------------------
  【备注追加口径 —— 严禁覆盖存量】
  · 存量 [REMARK] 为 NULL 或全空格  → 写入 N'院外项目，不核算'
  · 存量已含 N'院外项目，不核算'     → 恒等保留原值（幂等性保证，防重复追加）
  · 存量有其他文本                   → 后缀追加 N'；院外项目，不核算'
  -------------------------------------------------------------------------------
  【幂等性说明】
  系数为绝对值赋值、备注为「含标记即跳过」的幂等追加，可重复执行且结果一致。
  重复执行会刷新 [UPDATE_TIME]；如需区分首跑与重跑，请比对影响行数。
  -------------------------------------------------------------------------------
  修改日志：
  2026-09-22 17:20:00 | 初始化 | 建立院外项目系数归零与备注追加补丁
  2026-09-22 17:20:00 | 纠偏 | UPDATE_TIME 改用 GETDATE() 防 datetime2 隐式转换截断错误
=============================================================================== */

SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE rvu
SET
    rvu.[DECISION_COFF] = 0.0000
   ,rvu.[EXEC_COFF]     = 0.0000
   ,rvu.[REMARK]        = CASE
                              WHEN rvu.[REMARK] IS NULL OR LTRIM(RTRIM(rvu.[REMARK])) = N'' THEN N'院外项目，不核算'
                              WHEN rvu.[REMARK] LIKE N'%院外项目，不核算%'                  THEN rvu.[REMARK]
                              ELSE rvu.[REMARK] + N'；院外项目，不核算'
                          END
   ,rvu.[UPDATE_USER]   = N'SYSTEM'
   ,rvu.[UPDATE_TIME]   = GETDATE()
FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS rvu
INNER JOIN dbo.[DIM_OUT_HOSP_ITEM] AS out_item
    ON rvu.[PROJ_CODE] = out_item.[ITEM_CODE]
WHERE rvu.[REMARK] IS NULL
   OR rvu.[REMARK] NOT LIKE N'%院外项目，不核算%';

PRINT N'院外项目系数归零影响行数: ' + CAST(@@ROWCOUNT AS VARCHAR(20));

COMMIT TRANSACTION;

-- 复核：归零结果抽样（系数已归零且备注含标记）
SELECT
    rvu.[ORG_CODE]                                                       AS [机构编码]
   ,rvu.[VERSION_NO]                                                     AS [版本号]
   ,rvu.[PROJ_CODE]                                                      AS [项目代码]
   ,rvu.[PROJ_NAME]                                                      AS [项目名称]
   ,CAST(rvu.[DECISION_COFF] AS DECIMAL(18,8))                           AS [决策系数]
   ,CAST(rvu.[EXEC_COFF] AS DECIMAL(18,8))                               AS [执行系数]
   ,rvu.[REMARK]                                                         AS [备注]
   ,CONVERT(VARCHAR(19), rvu.[UPDATE_TIME], 120)                         AS [更新时间]
FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS rvu WITH (NOLOCK)
INNER JOIN dbo.[DIM_OUT_HOSP_ITEM] AS out_item WITH (NOLOCK)
    ON rvu.[PROJ_CODE] = out_item.[ITEM_CODE]
ORDER BY
    rvu.[PROJ_CODE] ASC
   ,rvu.[VERSION_NO] ASC
;
