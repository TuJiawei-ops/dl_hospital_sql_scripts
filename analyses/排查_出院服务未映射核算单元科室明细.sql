/* ===============================================================================
  Relative Path : analyses/排查_出院服务未映射核算单元科室明细.sql
  脚本名称: 排查_出院服务未映射核算单元科室明细.sql
  业务说明: 出入院服务项目积分计算中「出院科室未能命中 HPS 绩效核算单元」的根因定位。
            链路：出院科室代码 → sjjk_bmb_2025_06_01[编码] → sjjk_DEPT_UNIT_MAPPING_2025_11_27。
  ── 排查要点（与计算脚本口径严格同构，仅追加未映射过滤） ──
  1. 【口径同源】：三表关联条件、拉链时间区间（<= 闭区间）、LEFT JOIN 链路必须与
     一次分配/出院人次积分.sql 完全一致，否则排查结果无法反证计算侧漏计。
  2. 【三层断点递进】：未映射并非单一原因，按链路断点分为三类根因——
     ① 部门字典未收录（f.[出院科室代码] 在 sjjk_bmb 中无对应 id）；
     ② 映射表未配置（部门字典命中，但无任何时间区间匹配的映射行）；
     ③ 账期未覆盖（存在同科室映射配置，但出院时间均落在配置区间之外）。
  3. 【零剪枝】：映射表不做 ROW_NUMBER / MAX / 人员类型过滤，与计算脚本保持同一裸查口径。
  4. 【计数口径】：COUNT(1) 与计算脚本 COUNT(1) 同源，为未映射出院人次（笛卡尔积放大后计数）。
  5. 【查询提示】：全部数据源加 WITH (NOLOCK)，只读排查不加锁。
  修改日志：
  2026-09-16 18:00:00 | 脚本新建 | 建立出院服务核算单元断链审计脚本：逐层 LEFT JOIN 定位断点，
                                输出 HIS 科室三维标识、最早/最晚出院时间、影响未映射出院人次及缺失原因分类。
=============================================================================== */

WITH cte_unmapped AS (
    -- 未命中绩效核算单元的出院明细（关联口径与计算脚本完全一致，仅追加 HPS 为空过滤）
    SELECT
        f.[出院科室代码]                            AS HIS_DEPT_ID
       ,b.[编码]                                    AS HIS_DEPT_CODE
       ,b.[名称]                                    AS HIS_DEPT_NAME
       ,f.[出院科室]                                AS FACT_DEPT_NAME
       ,f.[出院时间]                                AS DISCHARGE_TIME
    FROM dbo.[PF临时出院数据26A] AS f WITH (NOLOCK)
    LEFT JOIN dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
        ON f.[出院科室代码] = b.[id]
    LEFT JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
        ON b.[编码] = m.[HIS_DEPT_CODE]
       AND f.[出院时间] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR f.[出院时间] <= m.[END_DATE])
    WHERE m.[HPS_DEPT_CODE] IS NULL
)
,cte_configured AS (
    -- 映射表已配置的 HIS 科室编码清单（用于剥离「未配置」与「账期未覆盖」两类根因）
    SELECT DISTINCT
        m.[HIS_DEPT_CODE]                           AS HIS_DEPT_CODE
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[HIS_DEPT_CODE] IS NOT NULL
)
,cte_diag AS (
    -- 根因分层：按链路断点归类，隔离辅助判定维度，防污染最终聚合
    SELECT
        u.[HIS_DEPT_ID]                             AS HIS_DEPT_ID
       ,u.[HIS_DEPT_CODE]                           AS HIS_DEPT_CODE
       ,u.[HIS_DEPT_NAME]                           AS HIS_DEPT_NAME
       ,u.[FACT_DEPT_NAME]                          AS FACT_DEPT_NAME
       ,u.[DISCHARGE_TIME]                          AS DISCHARGE_TIME
       ,CASE
            WHEN u.[HIS_DEPT_ID] IS NULL    THEN N'出院科室代码为空'
            WHEN u.[HIS_DEPT_CODE] IS NULL  THEN N'部门字典未收录'
            WHEN c.[HIS_DEPT_CODE] IS NULL  THEN N'映射表未配置'
            ELSE N'账期未覆盖（出院时间落在配置区间外）'
        END                                         AS MISS_REASON
    FROM cte_unmapped AS u
    LEFT JOIN cte_configured AS c
        ON u.[HIS_DEPT_CODE] = c.[HIS_DEPT_CODE]
)
SELECT
    诊断.[HIS_DEPT_ID]                                           AS [HIS科室ID]
   ,ISNULL(诊断.[HIS_DEPT_CODE], N'部门字典未找到')              AS [HIS科室编码]
   ,ISNULL(诊断.[HIS_DEPT_NAME], 诊断.[FACT_DEPT_NAME])         AS [HIS科室名称]
   ,诊断.[FACT_DEPT_NAME]                                       AS [事实层科室名称]
   ,MIN(诊断.[DISCHARGE_TIME])                                  AS [最早出院时间]
   ,MAX(诊断.[DISCHARGE_TIME])                                  AS [最晚出院时间]
   ,COUNT(1)                                                    AS [影响未映射出院人次]
   ,诊断.[MISS_REASON]                                          AS [缺失原因分类]
FROM cte_diag AS 诊断
GROUP BY
    诊断.[HIS_DEPT_ID]
   ,诊断.[HIS_DEPT_CODE]
   ,诊断.[HIS_DEPT_NAME]
   ,诊断.[FACT_DEPT_NAME]
   ,诊断.[MISS_REASON]
ORDER BY
    [影响未映射出院人次] DESC
   ,诊断.[HIS_DEPT_ID] ASC
;
