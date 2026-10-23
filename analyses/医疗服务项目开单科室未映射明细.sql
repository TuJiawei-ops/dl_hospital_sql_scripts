/* ===============================================================================
  Relative Path : analyses/排查_医疗服务项目开单未映射核算单元明细.sql
  脚本名称: 排查_医疗服务项目开单未映射核算单元明细.sql
  业务说明: 医疗服务项目开单积分归属为 UNIT_CODE = 'UNKNOWN' / N'未映射核算单元' 的根因定位。
            链路: 事实层 [开单科室代码] ──(id)──▶ dbo.[sjjk_bmb_2025_06_01].[编码] (HIS_DEPT_CODE)
                  ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (PERFORM_PERSON_TYPE_CODE='1001')
                  ──(HPS_DEPT_CODE)──▶ 绩效核算单元
  输出形态: 两个结果集（同一 WITH 链，逐段执行即可）
            结果集 1 = 未映射原因汇总表（原始开单科室粒度，含断链类型诊断与配置缺口参考区间）
            结果集 2 = 未映射事实明细抽样表（UNIT_CODE = 'UNKNOWN' 的行级明细透传）

  ── 三类断链根因分层（严格互斥，逐层判定） ──
  ① 字典缺失        事实层 [开单科室代码] 在 sjjk_bmb_2025_06_01 中无对应 [id]（HIS_DEPT_CODE 为 NULL）
  ② 映射未配置      字典命中 HIS_DEPT_CODE，但拉链表内该编码无任何 PERFORM_PERSON_TYPE_CODE='1001' 的配置行
  ③ 时间区间不匹配  拉链表内该 HIS_DEPT_CODE 已有配置，但事实记录时间不落在任一 [START_DATE, END_DATE) 区间内

  ── 关键纠偏（防熵增，务必知悉） ──
  1. 【时间基准锁定执行时间】计算脚本 一次分配/医疗服务项目开单积分.sql 第 103 行以
     a.[执行时间] AS ORDER_TIME 作为拉链区间匹配基准，本排查脚本严格沿用 [执行时间]，
     确保排查结论可直接反证计算侧的 UNKNOWN 成因；[缴费时间] 仅作明细输出参考列，不参与区间判定。
  2. 【归因歧义消解】若仅以 LEFT JOIN 后 m.[HPS_DEPT_CODE] IS NULL 判定，无法区分「无配置」
     与「时间越界」两类根因。故引入 cte_configured（拉链表 DISTINCT 已配置编码清单）反查，
     按「字典缺失 → 映射未配置 → 时间区间不匹配」顺序递进判定，三类结果互斥且完备。
  3. 【零剪枝】拉链表不做 ROW_NUMBER()/MAX() 折叠、不加人员类型以外的过滤，与计算脚本同源裸查口径，
     否则排查结果无法反证计算侧漏计。
  4. 【全时间范围】取消 '{start_time}' / '{end_time}' 时间窗过滤，事实表全量扫描（仅保留 RVU 维度
     大类剪枝口径，与计算脚本一致），定位全历史维度的映射缺口。
  5. 【源列零改造】全部编码类字段裸引用，不做 CAST 整形/补零/去空格，避免隐性截断与关联失配。

  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化）。
            断链诊断结果经 SELECT ... INTO 物化至会话级临时表 #TMP_DIAG，随会话结束自动回收，
            全程不触碰任何业务库表；脚本末尾显式 DROP TABLE 主动释放 tempdb 资源。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符: 无（本脚本为全账期全量扫描，不接受 '{year}' / '{month}' / '{struct_codes}' 注入）
  事实表规模: dbo.[PF临时医疗服务项目26A] 约 1200 万行，全量扫描请注意执行时段。

  修改日志：
  2026-09-19 03:00:00 | 语法加固 | 修复 [42000] 关键字 'IF' 附近有语法错误 (156)：将 #TMP_DIAG 前置清理
                                 IF OBJECT_ID('tempdb..#TMP_DIAG') IS NOT NULL DROP TABLE #TMP_DIAG;
                                 从 CTE 链之后（SELECT ... INTO 上方）整体前移至批处理首语句位置，使 WITH 链
                                 的前置语句形态确定，消除 T-SQL 对「WITH 须为批处理首语句」的语法歧义；
                                 末尾清理同步改为对称的 IF OBJECT_ID 防御式写法，形成前后幂等闭环；
                                 并在首部追加「整段全选一次性执行、严禁分片执行」使用约束说明。
                                 注: SELECT ... INTO 仍严格紧随 WITH 链属同一条语句，INTO 位置保持在
                                 SELECT 列清单之后、FROM 之前，CTE 算法与断链判定逻辑零改动。
  2026-09-19 02:00:00 | 缺陷修复 | 修复 [42S02] 对象名 'cte_diag' 无效 (208)：T-SQL 中 WITH 定义的 CTE 链
                                 作用域仅延伸至紧随其后的第一条 SELECT，首个结果集以 ; 结束后 CTE 即销毁，
                                 导致第二个结果集引用 cte_diag 失效。改为 SELECT ... INTO 将断链诊断结果物化
                                 至会话级临时表 #TMP_DIAG，两个结果集改为独立消费 #TMP_DIAG；
                                 字段别名、DECIMAL(18,8) 转换、NOLOCK 提示与全部诊断逻辑零改动。
  2026-09-19 01:00:00 | 脚本新建 | 建立医疗服务项目开单核算单元未映射专项排查脚本：三层 LEFT JOIN 递进 +
                                 已配置清单反查，严格区分「字典缺失 / 映射未配置 / 时间区间不匹配」三类断链根因；
                                 时间基准锁定事实表 [执行时间] 与计算脚本同源；输出科室粒度汇总表与行级明细抽样表。
=============================================================================== */


-- =================================================================
-- 【批处理首语句】临时表前置清理（幂等保障）
-- ── 为何必须置于此处（T-SQL 语法硬约束） ──
-- T-SQL 要求 WITH ... AS (CTE) 必须作为批处理的首条语句，且其前一条语句须以 ; 收口。
-- 将清理语句前置到 CTE 链之前，可确保 WITH 的前置语句形态确定（IF ... DROP TABLE ...;）
-- 而非依赖"前一条语句恰好是注释块"这类隐式假设，从而消除 [42000] 156 语法歧义。
-- ── 使用约束（务必知悉） ──
-- 本脚本含 WITH 链，整段必须「全选一次性执行」，严禁在 SSMS 中选中部分代码分片执行；
-- 分片执行会导致 WITH 与后续语句被拆到不同批次，触发 156 / 208 类错误。
-- =================================================================
IF OBJECT_ID('tempdb..#TMP_DIAG') IS NOT NULL
    DROP TABLE #TMP_DIAG;

WITH cte_bmb_bridge AS (
    -- ── Import CTE: 部门字典桥接层（事实层数值主键 [开单科室代码] → HIS 业务编码 [编码]） ──
    -- [id] 为物理主键聚簇，粒度 1:1；[编码] 裸引用，不做 CAST/补零/去空格加工（§7.1 源列零改造优先）
    SELECT
        b.[id]                                          AS DEPT_ID
       ,b.[编码]                                        AS HIS_DEPT_CODE
       ,b.[名称]                                        AS HIS_DEPT_NAME
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
)
,cte_rvu_scope AS (
    -- ── Import CTE: RVU 维度剪枝作用域（与计算脚本口径严格同源：剔除 1101 出入院服务类 / 1041 诊察类） ──
    -- 仅取 PROJ_CODE 作事实侧剪枝，避免未纳入积分体系的收费项目污染未映射排查结论。
    SELECT DISTINCT
        v.[PROJ_CODE]                                   AS PROJ_CODE
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v WITH (NOLOCK)
    WHERE v.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND v.[PROJ_CODE] IS NOT NULL
)
,cte_dept_unit_mapping AS (
    -- ── Import CTE: HIS 科室 → 绩效核算单元 拉链维表（原始透传，严禁开窗去重折叠） ──
    -- 限定 PERFORM_PERSON_TYPE_CODE='1001'，与计算脚本同源；一对多映射并存属业务预期颗粒度。
    SELECT
        m.[ID]                                          AS MAPPING_ID
       ,m.[HIS_DEPT_CODE]
       ,m.[HIS_DEPT_NAME]
       ,m.[HPS_DEPT_CODE]
       ,m.[HPS_DEPT_NAME]
       ,m.[START_DATE]
       ,m.[END_DATE]
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] = '1001'
)
,cte_configured AS (
    -- ── Import CTE: 已配置 HIS 科室编码清单（用于消解「映射未配置」与「时间区间不匹配」的归因歧义） ──
    -- 凡在拉链表内存在任意一条 1001 类型配置行（无论账期是否覆盖），即视为「已配置」，
    -- 从而将 m.[HPS_DEPT_CODE] IS NULL 精确拆解为「无任何配置」与「有配置但时间越界」两类。
    SELECT DISTINCT
        c.[HIS_DEPT_CODE]                               AS HIS_DEPT_CODE
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS c WITH (NOLOCK)
    WHERE c.[PERFORM_PERSON_TYPE_CODE] = '1001'
      AND c.[HIS_DEPT_CODE] IS NOT NULL
)
,cte_config_span AS (
    -- ── Import CTE: 各 HIS 科室已配置区间的参考跨度（供业务侧直接补配映射，免二次查表） ──
    -- 全时间范围 MIN(START_DATE) / MAX(END_DATE)，END_DATE 为 NULL 视为长期有效。
    -- 注: 此处 MIN/MAX 作用于「区间边界的时间跨度描述」，非对业务主键做强制折叠，符合 .clinerules §6 收敛精神。
    SELECT
        s.[HIS_DEPT_CODE]                               AS HIS_DEPT_CODE
       ,MIN(s.[START_DATE])                             AS SPAN_START_DATE
       ,MAX(s.[END_DATE])                               AS SPAN_END_DATE
       ,COUNT(1)                                        AS CONFIG_ROW_CNT
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS s WITH (NOLOCK)
    WHERE s.[PERFORM_PERSON_TYPE_CODE] = '1001'
      AND s.[HIS_DEPT_CODE] IS NOT NULL
    GROUP BY
        s.[HIS_DEPT_CODE]
)

,cte_fact AS (
    -- ── Import CTE: 事实层全量明细（取消 '{start_time}' / '{end_time}' 时间窗，全账期扫描） ──
    -- 判定期时间基准锁定 [执行时间]（与计算脚本 a.[执行时间] AS ORDER_TIME 同源）；
    -- [缴费时间] 仅作明细参考输出列，不参与拉链区间判定。INNER JOIN 仅做 RVU 大类剪枝，与计算脚本一致。
    SELECT
        f.[来源]                                        AS SRC_TYPE
       ,f.[HIS主键]                                     AS HIS_PK
       ,f.[患者ID]                                      AS PATIENT_ID
       ,f.[挂号ID]                                      AS REG_ID
       ,f.[开单科室代码]                                AS DEPT_ID
       ,f.[开单科室]                                    AS DEPT_NAME
       ,f.[开单时间]                                    AS ORDER_TIME
       ,f.[执行时间]                                    AS EXEC_TIME
       ,f.[缴费时间]                                    AS PAY_TIME
       ,f.[项目代码]                                    AS PROJ_CODE
       ,f.[项目名称]                                    AS PROJ_NAME
       ,CAST(f.[数量] AS DECIMAL(18,8))                 AS QTY
       ,CAST(f.[金额] AS DECIMAL(18,8))                 AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
    INNER JOIN cte_rvu_scope AS r
        ON f.[项目代码] = r.[PROJ_CODE]
)
,cte_keyed AS (
    -- ── Logical CTE: 事实明细 × 字典桥接（LEFT JOIN 保留桥接断链行，这是诊断 ① 的判定依据） ──
    SELECT
        f.[SRC_TYPE]
       ,f.[HIS_PK]
       ,f.[PATIENT_ID]
       ,f.[REG_ID]
       ,f.[DEPT_ID]
       ,f.[DEPT_NAME]
       ,f.[ORDER_TIME]
       ,f.[EXEC_TIME]
       ,f.[PAY_TIME]
       ,f.[PROJ_CODE]
       ,f.[PROJ_NAME]
       ,f.[QTY]
       ,f.[AMOUNT]
       ,b.[HIS_DEPT_CODE]
       ,b.[HIS_DEPT_NAME]
    FROM cte_fact AS f
    LEFT JOIN cte_bmb_bridge AS b
        ON f.[DEPT_ID] = b.[DEPT_ID]
)
,cte_diag AS (
    -- ── Logical CTE: 拉链映射匹配 + 三层断链根因判定（结果集互斥且完备） ──
    -- 判定顺序: 字典缺失 → 映射未配置 → 时间区间不匹配；[执行时间] 落区间采用半开 [START_DATE, END_DATE)。
    -- 仅输出未命中核算单元的行；为避免同编码多配置行导致的失败匹配放大，按事实主键维度收敛至 1 行。
    SELECT
        k.[SRC_TYPE]
       ,k.[HIS_PK]
       ,k.[PATIENT_ID]
       ,k.[REG_ID]
       ,k.[DEPT_ID]
       ,k.[DEPT_NAME]
       ,k.[ORDER_TIME]
       ,k.[EXEC_TIME]
       ,k.[PAY_TIME]
       ,k.[PROJ_CODE]
       ,k.[PROJ_NAME]
       ,k.[QTY]
       ,k.[AMOUNT]
       ,k.[HIS_DEPT_CODE]
       ,k.[HIS_DEPT_NAME]
       ,MAX(cfg.[HIS_DEPT_CODE])                        AS CFG_HIS_DEPT_CODE
       ,MAX(sp.[SPAN_START_DATE])                       AS SPAN_START_DATE
       ,MAX(sp.[SPAN_END_DATE])                         AS SPAN_END_DATE
       ,MAX(sp.[CONFIG_ROW_CNT])                        AS CONFIG_ROW_CNT
       ,CASE
            WHEN k.[HIS_DEPT_CODE] IS NULL   THEN N'字典缺失'
            WHEN MAX(cfg.[HIS_DEPT_CODE]) IS NULL THEN N'映射未配置'
            ELSE N'时间区间不匹配'
        END                                             AS BREAK_TYPE
    FROM cte_keyed AS k
    LEFT JOIN cte_dept_unit_mapping AS m
        ON k.[HIS_DEPT_CODE] = m.[HIS_DEPT_CODE]
       AND k.[EXEC_TIME] >= m.[START_DATE]
       AND (m.[END_DATE] IS NULL OR k.[EXEC_TIME] < m.[END_DATE])
    LEFT JOIN cte_configured AS cfg
        ON k.[HIS_DEPT_CODE] = cfg.[HIS_DEPT_CODE]
    LEFT JOIN cte_config_span AS sp
        ON cfg.[HIS_DEPT_CODE] = sp.[HIS_DEPT_CODE]
    WHERE m.[HPS_DEPT_CODE] IS NULL
    GROUP BY
        k.[SRC_TYPE]
       ,k.[HIS_PK]
       ,k.[PATIENT_ID]
       ,k.[REG_ID]
       ,k.[DEPT_ID]
       ,k.[DEPT_NAME]
       ,k.[ORDER_TIME]
       ,k.[EXEC_TIME]
       ,k.[PAY_TIME]
       ,k.[PROJ_CODE]
       ,k.[PROJ_NAME]
       ,k.[QTY]
       ,k.[AMOUNT]
       ,k.[HIS_DEPT_CODE]
       ,k.[HIS_DEPT_NAME]
)

-- =================================================================
-- 断链诊断结果物化（会话级临时表，紧跟 CTE 链、同属一条语句，严禁拆分）
-- ── 为何必须物化（T-SQL CTE 作用域硬约束） ──
-- WITH 声明的 CTE 链作用域仅延伸至紧随其后的「第一条」SELECT 语句，一旦该语句以 ; 结束，
-- 整条 CTE 架构（含 cte_diag）即被销毁；脚本需由两个结果集（汇总表 / 明细抽样表）分别消费
-- 同一份诊断结果，若直接并列两条 SELECT 将触发 [42S02] 对象名 'cte_diag' 无效 (208)。
-- 故此处以 SELECT ... INTO 将诊断结果物化至会话级临时表 #TMP_DIAG，供后方两个结果集独立消费。
-- ── 语法要点 ──
-- SELECT ... INTO #TMP_DIAG 与上方 WITH 链同属「一条语句」，INTO 必须紧跟 SELECT 的列清单之后、
-- FROM 之前，严禁将 INTO 挂到 CTE 收口处（如 `) SELECT * INTO #TMP_DIAG FROM cte_diag;` 属非法写法）。
-- ── 只读性质声明 ──
-- #TMP_DIAG 属会话级 tempdb 对象，随会话结束自动回收，绝不触碰任何业务库表，
-- 不构成持久化副作用；严禁替换为实体表 CREATE TABLE dbo.* 等写库操作。
-- =================================================================
SELECT
    d.[SRC_TYPE]
   ,d.[HIS_PK]
   ,d.[PATIENT_ID]
   ,d.[REG_ID]
   ,d.[DEPT_ID]
   ,d.[DEPT_NAME]
   ,d.[ORDER_TIME]
   ,d.[EXEC_TIME]
   ,d.[PAY_TIME]
   ,d.[PROJ_CODE]
   ,d.[PROJ_NAME]
   ,d.[QTY]
   ,d.[AMOUNT]
   ,d.[HIS_DEPT_CODE]
   ,d.[HIS_DEPT_NAME]
   ,d.[CFG_HIS_DEPT_CODE]
   ,d.[SPAN_START_DATE]
   ,d.[SPAN_END_DATE]
   ,d.[CONFIG_ROW_CNT]
   ,d.[BREAK_TYPE]
INTO #TMP_DIAG
FROM cte_diag AS d
;


-- =================================================================
-- 结果集 1：未映射原因汇总表（原始开单科室粒度 GROUP BY）
-- 用途: 按科室锁定断链类型与影响量级，并给出拉链表已有配置区间，供业务直接补配 / 扩期。
-- 数据源: #TMP_DIAG（物化后的断链诊断明细，与结果集 2 共享同一份计算结果）
-- =================================================================
SELECT
    d.[DEPT_ID]                                                     AS [原始开单科室代码]
   ,ISNULL(d.[DEPT_NAME], N'')                                      AS [原始开单科室名称]
   ,ISNULL(d.[HIS_DEPT_CODE], N'')                                  AS [字典桥接HIS编码]
   ,d.[BREAK_TYPE]                                                  AS [断链类型诊断]
   ,COUNT(1)                                                        AS [影响事实明细行数]
   ,CAST(SUM(d.[AMOUNT]) AS DECIMAL(18,8))                          AS [影响总金额]
   ,CONVERT(VARCHAR(19), MIN(d.[EXEC_TIME]), 120)                   AS [涉及最小时间]
   ,CONVERT(VARCHAR(19), MAX(d.[EXEC_TIME]), 120)                   AS [涉及最大时间]
   ,CASE
        WHEN d.[CONFIG_ROW_CNT] IS NULL THEN N'无任何配置'
        ELSE CONVERT(VARCHAR(19), d.[SPAN_START_DATE], 120)
             + N' ~ '
             + CASE
                   WHEN d.[SPAN_END_DATE] IS NULL THEN N'长期有效(NULL)'
                   ELSE CONVERT(VARCHAR(19), d.[SPAN_END_DATE], 120)
               END
             + N' (配置 '
             + CAST(d.[CONFIG_ROW_CNT] AS VARCHAR(11))
             + N' 行)'
    END                                                             AS [拉链表已有配置区间参考]
FROM #TMP_DIAG AS d
GROUP BY
    d.[DEPT_ID]
   ,d.[DEPT_NAME]
   ,d.[HIS_DEPT_CODE]
   ,d.[BREAK_TYPE]
   ,d.[SPAN_START_DATE]
   ,d.[SPAN_END_DATE]
   ,d.[CONFIG_ROW_CNT]
ORDER BY
    [断链类型诊断] ASC
   ,[影响总金额] DESC
   ,[影响事实明细行数] DESC
   ,[原始开单科室代码] ASC
;

-- =================================================================
-- 结果集 2：未映射事实明细抽样表（UNIT_CODE = 'UNKNOWN' 的行级明细透传）
-- 用途: 定位到具体患者 / 单据 / 项目，核对单笔归属与断链原因。
-- 说明: 执行时请取消下方 TOP 截断注释，或将查询结果集 1 中的重点科室通过
--       「AND d.[DEPT_ID] = <原始开单科室代码>」收敛后再导出，避免千万级明细全量拉取。
-- 数据源: #TMP_DIAG（物化后的断链诊断明细，与结果集 1 共享同一份计算结果）
-- =================================================================
SELECT TOP (5000)
    ISNULL(d.[SRC_TYPE], N'')                                        AS [来源]
   ,ISNULL(CAST(d.[HIS_PK] AS VARCHAR(20)), N'')                    AS [HIS主键]
   ,ISNULL(CAST(d.[PATIENT_ID] AS VARCHAR(20)), N'')                AS [患者ID]
   ,ISNULL(d.[REG_ID], N'')                                         AS [挂号ID]
   ,ISNULL(CAST(d.[DEPT_ID] AS VARCHAR(20)), N'')                   AS [原始开单科室代码]
   ,ISNULL(d.[DEPT_NAME], N'')                                      AS [原始开单科室名称]
   ,ISNULL(d.[HIS_DEPT_CODE], N'')                                  AS [桥接HIS编码]
   ,CONVERT(VARCHAR(19), d.[EXEC_TIME], 120)                        AS [执行时间]
   ,CONVERT(VARCHAR(19), d.[PAY_TIME], 120)                         AS [缴费时间]
   ,ISNULL(d.[PROJ_CODE], N'')                                      AS [项目代码]
   ,ISNULL(d.[PROJ_NAME], N'')                                      AS [项目名称]
   ,CAST(d.[QTY] AS DECIMAL(18,8))                                  AS [数量]
   ,CAST(d.[AMOUNT] AS DECIMAL(18,8))                               AS [金额]
   ,d.[BREAK_TYPE]                                                  AS [断链原因]
FROM #TMP_DIAG AS d
ORDER BY
    d.[BREAK_TYPE] ASC
   ,d.[AMOUNT] DESC
   ,d.[EXEC_TIME] DESC
;

-- =================================================================
-- 资源清理：显式销毁会话级临时表，及时释放 tempdb 空间
-- 注: 临时表随会话结束亦会自动回收，此处显式 DROP 属主动防御，
--     避免长会话 / 连接池复用场景下 tempdb 资源滞留；
--     与脚本首部前置清理形成对称幂等闭环，保障脚本可重复运行。
-- =================================================================
IF OBJECT_ID('tempdb..#TMP_DIAG') IS NOT NULL
    DROP TABLE #TMP_DIAG;

