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




SELECT TO_CHAR(出院时间,'YYYY')年,TO_CHAR(出院时间,'MM')月,出院科室代码,出院科室,COUNT(*)人次
FROM PF临时出院数据26A
GROUP BY TO_CHAR(出院时间,'YYYY'),TO_CHAR(出院时间,'MM'),出院科室代码,出院科室
ORDER BY 1 DESC,2 DESC,5 DESC;
/* ===============================================================================
   各核算单元出院人次分布与占比（按月）
   口径：与 一次分配/出院人次积分.sql 一致——HIS科室经映射表折算到核算单元
        （临床系列→医生单元、护理系列→护士单元；映射按出院时间落在生效区间内匹配）
   说明：未匹配到映射的出院记录归入「未映射」，便于发现漏配
   =============================================================================== */
WITH src AS (
    SELECT YEAR(f.[出院时间]) 年, MONTH(f.[出院时间]) 月,
           ISNULL(m.[HPS_DEPT_NAME], N'未映射') 核算单元, COUNT(1) 人次
    FROM dbo.[PF临时出院数据26A] f WITH (NOLOCK)
    JOIN dbo.[sjjk_bmb_2025_06_01] b WITH (NOLOCK) ON f.[出院科室代码]=b.[id]
    LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] m WITH (NOLOCK)
      ON b.[编码]=m.[HIS_DEPT_CODE] AND f.[出院时间]>=m.[START_DATE]
     AND (m.[END_DATE] IS NULL OR f.[出院时间]<=m.[END_DATE])
    GROUP BY YEAR(f.[出院时间]), MONTH(f.[出院时间]), ISNULL(m.[HPS_DEPT_NAME], N'未映射')
)
SELECT 年, 月, 核算单元, 人次,
       CAST(100.0*人次/SUM(人次) OVER (PARTITION BY 年,月) AS DECIMAL(6,2)) AS 占比
FROM src
ORDER BY 年 DESC, 月 DESC, 人次 DESC;
