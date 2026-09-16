/*
  脚本名称: 出入院服务项目积分.sql
  Relative Path : 一次分配/出入院服务项目积分.sql
  业务说明: 统计出院人次，并按人员类型路由 RVU 点数计算积分（纯 SELECT 查询）

  积分口径: 积分 = 出院人次 × RVU
  RVU 路由: 人员类型 '1001' → METRIC_DISCHARGE_DOCTOR
            人员类型 '1002' → METRIC_DISCHARGE_NURSE
  核算期间截面: f.[出院时间] 落于 ['{start_time}', '{end_time}'] 闭区间（外部注入核算起止时间占位符）
  维度期间截面: 出院时间落于核算单元映射表 [START_DATE, END_DATE] 有效期（闭区间，与计算主脚本口径一致）

  修改日志:
  2026-09-16 00:00:00 | 逻辑修正 | 追加出院时间核算范围过滤条件 WHERE f.[出院时间] >= '{start_time}' AND f.[出院时间] <= '{end_time}'，补齐原脚本缺失的核算期间约束（原实现无 WHERE 子句将全量累计出院人次）；同步补齐 Relative Path 标注并拆分核算期间截面与维度期间截面注释语义
*/

WITH cte_rvu AS (
    -- RVU 维表收敛：PROJ_CODE 非唯一键（物理主键含 ORG_CODE/VERSION_NO/MEAS_UNIT），
    -- 按 PROJ_CODE 折叠为单值，防一对多放大出院人次
    SELECT
        v.[PROJ_CODE]                                 AS PROJ_CODE
       ,CAST(MAX(v.[RVU_VAL]) AS DECIMAL(18,8))       AS RVU_VAL
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v WITH (NOLOCK)
    WHERE v.[PROJ_CODE] IN ('METRIC_DISCHARGE_DOCTOR', 'METRIC_DISCHARGE_NURSE')
    GROUP BY v.[PROJ_CODE]
)
SELECT
    YEAR(f.[出院时间])                            AS [出院时间年份]
   ,MONTH(f.[出院时间])                           AS [出院时间月份]
   ,ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN')        AS [绩效核算单元编码]
   ,ISNULL(m.[HPS_DEPT_NAME], '未映射核算单元')   AS [绩效核算单元名称]
   ,m.[PERFORM_PERSON_TYPE_CODE]                 AS [人员类型编码]
   ,m.[PERFORM_PERSON_TYPE]                      AS [人员类型]
   ,COUNT(1)                                     AS [出院人次]
   ,ISNULL(rvu.[RVU_VAL], CAST(0 AS DECIMAL(18,8)))                      AS [RVU]
   ,CAST(COUNT(1) * ISNULL(rvu.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [积分]
   ,CONCAT(
        '出院人次(', CAST(COUNT(1) AS VARCHAR(20)), ') * RVU('
       ,CAST(ISNULL(rvu.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS VARCHAR(32)), ')'
    )                                           AS [计算过程]
FROM dbo.[PF临时出院数据26A] AS f WITH (NOLOCK)
INNER JOIN dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    ON f.[出院科室代码] = b.[id]
LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    ON b.[编码] = m.[HIS_DEPT_CODE]
   AND f.[出院时间] >= m.[START_DATE]
   AND (m.[END_DATE] IS NULL OR f.[出院时间] <= m.[END_DATE])
LEFT JOIN cte_rvu AS rvu
    ON rvu.[PROJ_CODE] = CASE
                            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DISCHARGE_DOCTOR'
                            WHEN m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DISCHARGE_NURSE'
                            ELSE NULL
                         END
WHERE f.[出院时间] >= '{start_time}'
  AND f.[出院时间] <= '{end_time}'
GROUP BY
    YEAR(f.[出院时间])
   ,MONTH(f.[出院时间])
   ,m.[HPS_DEPT_CODE]
   ,m.[HPS_DEPT_NAME]
   ,m.[PERFORM_PERSON_TYPE_CODE]
   ,m.[PERFORM_PERSON_TYPE]
   ,rvu.[RVU_VAL]
ORDER BY
    [出院时间年份]
   ,[出院时间月份]
   ,[绩效核算单元编码]
   ,[人员类型编码];
