/* ===============================================================================
  Relative Path : analyses/排查_执行人员核算单元未匹配明细.sql
  脚本名称: 排查_执行人员核算单元未匹配明细.sql
  业务说明: 门诊诊察类（1043）执行人员在「执行人员所在核算单元」投影为 N'未匹配' 的根因定位。
            链路：执行人员代码 → sjjk_ryb_2025_06_01[编号] → MAP_MDM_STAFF[STAFF_CODE] → ads_dept_post_coefficient_m。
  修改日志：
  2026-09-16 16:20:00 | 脚本新建 | 建立执行人员核算单元断链审计脚本：三层 LEFT JOIN 递进定位断点，输出主数据未映射 / 岗位系数表未配置 / 账期未覆盖 三类根因与工作量件数。
=============================================================================== */


WITH cte_rvu AS (
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
)
,cte_ryb AS (
    SELECT
        r.[id]                                      AS id
       ,MAX(r.[编号])                               AS src_staff_code
       ,MAX(r.[姓名])                               AS src_staff_name
    FROM dbo.[sjjk_ryb_2025_06_01] AS r WITH (NOLOCK)
    WHERE r.[id] IS NOT NULL
    GROUP BY r.[id]
)
,cte_mdm_staff AS (
    SELECT
        s.[SRC_STAFF_CODE]                          AS src_staff_code
       ,MAX(s.[STAFF_CODE])                         AS staff_code
       ,MAX(s.[STAFF_NAME])                         AS staff_name
    FROM dbo.[MAP_MDM_STAFF] AS s WITH (NOLOCK)
    WHERE s.[SRC_STAFF_CODE] IS NOT NULL
    GROUP BY s.[SRC_STAFF_CODE]
)
,cte_staff_post AS (
    SELECT
        m.[staff_code]                              AS staff_code
       ,m.[year]                                    AS [year]
       ,m.[month]                                   AS [month]
       ,MIN(m.[unit_code])                          AS unit_code
       ,MIN(m.[unit_name])                          AS unit_name
    FROM dbo.[ads_dept_post_coefficient_m] AS m WITH (NOLOCK)
    WHERE m.[staff_code] IS NOT NULL
    GROUP BY
        m.[staff_code]
       ,m.[year]
       ,m.[month]
)
,cte_exec_fact AS (
    SELECT
        f.[执行人员代码]                              AS exec_staff_id
       ,MAX(f.[执行人员])                            AS exec_staff_name
       ,YEAR(f.[缴费时间])                           AS cal_year
       ,MONTH(f.[缴费时间])                          AS cal_month
       ,COUNT(1)                                    AS item_cnt
    FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
    INNER JOIN cte_rvu AS v
        ON f.[项目代码] = v.[PROJ_CODE]
    WHERE f.[执行科室代码] IS NULL
       OR f.[执行科室代码] <> 36
    GROUP BY
        f.[执行人员代码]
       ,YEAR(f.[缴费时间])
       ,MONTH(f.[缴费时间])
)
,cte_diag AS (
    SELECT
        fa.[exec_staff_id]                          AS 执行人员代码
       ,fa.[exec_staff_name]                        AS 执行人员
       ,fa.[cal_year]                               AS 缴费年份
       ,fa.[cal_month]                              AS 缴费月份
       ,ryb.[src_staff_code]                        AS 原始系统工号
       ,mdm.[src_staff_code]                        AS 主数据命中工号
       ,mdm.[staff_code]                            AS 主数据标准工号
       ,mdm.[staff_name]                            AS 主数据标准姓名
       ,sp.[unit_code]                              AS 核算单元编码
       ,sp.[unit_name]                              AS 核算单元名称
       ,fa.[item_cnt]                               AS 涉及项目工作量件数
       ,CASE
            WHEN ryb.[src_staff_code] IS NULL THEN N'人员表未收录（sjjk_ryb 无此 id）'
            WHEN mdm.[staff_code] IS NULL     THEN N'主数据未映射（MAP_MDM_STAFF 未配置）'
            WHEN sp.[staff_code] IS NULL      THEN N'岗位系数表未配置（当期无记录）'
            ELSE N'核算单元为空（记录存在但 unit_code 为 NULL）'
        END                                         AS 缺失原因定位
    FROM cte_exec_fact AS fa
    LEFT JOIN cte_ryb AS ryb
        ON fa.[exec_staff_id] = ryb.[id]
    LEFT JOIN cte_mdm_staff AS mdm
        ON ryb.[src_staff_code] = mdm.[src_staff_code]
    LEFT JOIN cte_staff_post AS sp
        ON mdm.[staff_code] = sp.[staff_code]
       AND fa.[cal_year]    = sp.[year]
       AND fa.[cal_month]   = sp.[month]
    WHERE sp.[unit_code] IS NULL
       OR LTRIM(RTRIM(sp.[unit_code])) = N''
)
SELECT
    诊断.[执行人员代码]
   ,诊断.[执行人员]
   ,诊断.[缴费年份]
   ,诊断.[缴费月份]
   ,诊断.[原始系统工号]
   ,诊断.[主数据命中工号]
   ,ISNULL(诊断.[主数据标准工号], N'MAP_MDM_STAFF未配置')      AS [主数据标准工号]
   ,诊断.[主数据标准姓名]
   ,诊断.[核算单元编码]
   ,诊断.[核算单元名称]
   ,诊断.[缺失原因定位]                                        AS [核算单元匹配状态]
   ,CAST(诊断.[涉及项目工作量件数] AS DECIMAL(18,8))            AS [涉及项目工作量件数]
FROM cte_diag AS 诊断
ORDER BY
    诊断.[涉及项目工作量件数] DESC
   ,诊断.[执行人员代码] ASC
   ,诊断.[缴费年份] ASC
   ,诊断.[缴费月份] ASC
;
