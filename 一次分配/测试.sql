-- 1. 挂号/退号统计 CTE (仅计算挂号量，移除了收费、退费等复杂计算)
WITH RegisterStatsOnly AS (
    SELECT
--         a.HIS_PERFORM_DEPT_CODE,
--         a.HIS_PERFORM_DEPT_NAME,
        a.操作员姓名,
        COUNT(a.收入项目id) AS 挂号量 -- 只需要这个指标
    FROM sjjk_mzfyjl_2025_06_01 a
    WHERE a.记录性质 = 4
        AND a.记录状态 IN (1, 2, 3)
        AND a.操作员姓名 IS NOT NULL
        AND a.操作员姓名 NOT IN (SELECT EXCL_OPERATOR_NAME FROM sjjk_EXCLUDED_OPERATOR_CONFIG_2025_12_02 WHERE '{start_time}' BETWEEN START_DATE AND ISNULL(END_DATE, '9999-12-31'))
        AND a.登记时间 BETWEEN '{start_time}' AND '{end_time}'
    GROUP BY 
--     a.HIS_PERFORM_DEPT_CODE, 
--     a.HIS_PERFORM_DEPT_NAME, 
    a.操作员姓名
),

-- 2. 最终聚合和筛选操作员的 CTE (只聚合挂号量)
FinalAggregatedData AS (
    SELECT
--         r.HIS_PERFORM_DEPT_CODE,
--         r.HIS_PERFORM_DEPT_NAME,
        z.姓名 AS 操作员姓名,
        SUM(r.挂号量) AS 挂号量 -- 只保留挂号量
    FROM RegisterStatsOnly r
    -- 联接 sjjk_ryb_2025_06_01 (z) 获取人员ID/信息
    JOIN sjjk_ryb_2025_06_01 z ON r.操作员姓名 = z.姓名
    -- 联接 sjjk_ryxzsm_2025_06_01 (t) 筛选人员性质 = '门诊挂号员'
    JOIN sjjk_ryxzsm_2025_06_01 t ON t.人员id = z.id AND t.人员性质 = N'门诊挂号员'
    GROUP BY 
--     r.HIS_PERFORM_DEPT_CODE, 
--     r.HIS_PERFORM_DEPT_NAME, 
    z.姓名
),

-- 3. 科室映射筛选 CTE (保持不变，用于过滤生效的映射记录)
ActiveDeptMapping AS (
    SELECT
        HIS_DEPT_CODE,
        HPS_DEPT_CODE,
        HPS_DEPT_NAME
    FROM
        sjjk_DEPT_UNIT_MAPPING_2025_11_27
    WHERE
        START_DATE <= '{start_time}'
        AND END_DATE >= '{start_time}'
),

-- 4. 联接 T_STAFF 和科室映射的 CTE (只保留所需字段)
DETAIL_HPS AS (
    SELECT
--         a.HIS_PERFORM_DEPT_CODE,
--         a.HIS_PERFORM_DEPT_NAME,
--         b.HPS_DEPT_CODE,
--         b.HPS_DEPT_NAME,
        r.name AS 姓名,
        r.user_code,
        a.挂号量 -- 只保留挂号量
    FROM FinalAggregatedData a
    LEFT JOIN T_STAFF r ON r.name = a.操作员姓名
--     LEFT JOIN ActiveDeptMapping b ON b.HIS_DEPT_CODE = a.HIS_PERFORM_DEPT_CODE
--     WHERE HPS_DEPT_CODE NOT IN {struct_codes})
)
-- SELECT * FROM DETAIL_HPS
-- 最终 SELECT
SELECT
{
    'UNIT006' AS struct_code,
    '财务科（收款室）' AS struct_name,
    SUM(挂号量) AS result_value
    }
FROM DETAIL_HPS
-- ~
-- GROUP BY
--     HPS_DEPT_CODE,
--     HPS_DEPT_NAME
--     ~
-- ORDER BY HPS_DEPT_CODE;