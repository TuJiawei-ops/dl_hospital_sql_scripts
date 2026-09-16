/*
  Relative Path : analyses/项目执行时间空值率统计报表.sql
  脚本名称: 项目执行时间空值率统计报表.sql
  业务说明: 针对 dbo.[PF临时医疗服务项目26A] 按「年度 + 月份 + 项目」粒度统计【执行时间】缺失率。
            时间基准: 优先取 [开单时间]，为空时回落 [缴费时间]。
            过滤口径: 剔除 [项目大类] 含「药」字记录；仅保留执行时间为空笔数 > 0 的项目。
  修改日志:
  2026-09-16 00:00:00 | 脚本新建 | 建立项目执行时间空值率统计报表：COALESCE 双时间基准回落、缺失标志位判定、NULLIF 除零防护、空值率同精度输出。
  2026-09-16 00:00:00 | 逻辑升级 | 追加双重过滤：cte_fact 剔除 [项目大类] 含「药」字记录；外层仅保留执行时间为空笔数 > 0 的项目。
*/

WITH cte_fact AS (
    SELECT
        f.[项目大类]                                 AS 项目大类
       ,f.[项目代码]                                 AS 项目代码
       ,f.[项目名称]                                 AS 项目名称
       ,YEAR(COALESCE(f.[开单时间], f.[缴费时间]))    AS 统计年度
       ,MONTH(COALESCE(f.[开单时间], f.[缴费时间]))   AS 统计月份
       ,CASE
            WHEN f.[执行时间] IS NULL THEN 1
            ELSE 0
        END                                          AS 执行时间缺失标志
    FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
    WHERE ISNULL(f.[项目大类], N'') NOT LIKE N'%药%'
)
,cte_stat AS (
    SELECT
        fa.[统计年度]                                 AS 统计年度
       ,fa.[统计月份]                                 AS 统计月份
       ,fa.[项目代码]                                 AS 项目代码
       ,MAX(fa.[项目大类])                            AS 项目大类
       ,MAX(fa.[项目名称])                            AS 项目名称
       ,COUNT(1)                                     AS 总记录数
       ,SUM(fa.[执行时间缺失标志])                     AS 执行时间为空笔数
    FROM cte_fact AS fa
    GROUP BY
        fa.[统计年度]
       ,fa.[统计月份]
       ,fa.[项目代码]
)
SELECT
    st.[统计年度]                                                       AS [年度]
   ,st.[统计月份]                                                       AS [月份]
   ,st.[项目代码]                                                       AS [项目代码]
   ,st.[项目大类]                                                       AS [项目大类]
   ,st.[项目名称]                                                       AS [项目名称]
   ,CAST(st.[总记录数] AS DECIMAL(18,8))                                AS [总记录数]
   ,CAST(st.[执行时间为空笔数] AS DECIMAL(18,8))                        AS [执行时间为空笔数]
   ,CAST(1.0 * st.[执行时间为空笔数] / NULLIF(st.[总记录数], 0) AS DECIMAL(18,8)) AS [执行时间空值率]
   ,CAST(100.0 * st.[执行时间为空笔数] / NULLIF(st.[总记录数], 0) AS DECIMAL(18,8)) AS [执行时间空值率百分比]
FROM cte_stat AS st
WHERE st.[执行时间为空笔数] > 0
ORDER BY
    st.[统计年度] DESC
   ,st.[统计月份] DESC
   ,st.[项目代码] ASC
;
