/* 每月各科室出院人次（单表直查基表，不做映射） */
SELECT
     YEAR([出院时间])  AS [年]
    ,MONTH([出院时间]) AS [月]
    ,[出院科室代码]     AS [科室代码]
    ,[出院科室]         AS [科室名称]
    ,COUNT(1)           AS [出院人次]
FROM dbo.[PF临时出院数据26A] WITH (NOLOCK)
GROUP BY YEAR([出院时间]), MONTH([出院时间]), [出院科室代码], [出院科室]
ORDER BY [年] DESC, [月] DESC, [出院人次] DESC;