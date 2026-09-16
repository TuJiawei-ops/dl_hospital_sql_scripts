/*
  脚本名称: 出入院服务项目积分.sql
  业务说明: 统计出院人次（纯 SELECT 查询）
*/

SELECT
    YEAR(f.[出院时间])                         AS [出院时间年份]
   ,MONTH(f.[出院时间])                        AS [出院时间月份]
   ,ISNULL(m.[HPS_DEPT_CODE], 'UNKNOWN')      AS [绩效核算单元编码]
   ,ISNULL(m.[HPS_DEPT_NAME], '未映射核算单元') AS [绩效核算单元名称]
   ,COUNT(1)                                   AS [出院人次]
FROM dbo.[PF临时出院数据26A] AS f WITH (NOLOCK)
INNER JOIN dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    ON f.[出院科室代码] = b.[id]
LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    ON b.[编码] = m.[HIS_DEPT_CODE]
   AND f.[出院时间] >= m.[START_DATE]
   AND (m.[END_DATE] IS NULL OR f.[出院时间] <= m.[END_DATE])
GROUP BY
    YEAR(f.[出院时间])
   ,MONTH(f.[出院时间])
   ,m.[HPS_DEPT_CODE]
   ,m.[HPS_DEPT_NAME]
ORDER BY
    [出院时间年份]
   ,[出院时间月份]
   ,[绩效核算单元编码];
