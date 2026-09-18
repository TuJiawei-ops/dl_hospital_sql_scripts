/* ===============================================================================
 Relative Path : analyses/01_报表_一次分配明细业务视图.sql
 脚本名称: 01_报表_一次分配明细业务视图.sql
 业务说明: 面向业务人员的「一次分配明细」通用查询报表。以 DWD_FIN_CALC_ALLOC1_DETAIL_LOG
           持久化明细为唯一事实源，按【核算单元 → 所属职系】左连部门维表 T_DEPARTMENT 补全
           职系属性，全列中文别名化输出，屏蔽底层技术字段名，供业务直接核对与导出。
 数据链路: dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] (log，分配明细持久化事实)
           ──▶ dbo.[T_DEPARTMENT]                (经 CODE 收敛后左连补职系属性)
           粒度保持: 与事实表物理粒度 1:1 严格同构，零行倍增、零明细丢失。
 只读声明: 纯 SELECT 分析报表，无任何 INSERT / UPDATE / DELETE / DDL 副作用。
 模板占位符: 无（本报表为业务全量透视视图，不接受 '{year}' / '{month}' / {struct_codes} 注入）

 关键纠偏:
 1. 【阻断级·行倍增防御】T_DEPARTMENT 物理主键为 [ID] 且 [CODE] 为 nvarchar(20) NULL、
    无唯一约束（唯一索引建在 [NAME] 上），一条 UNIT_CODE 可能命中多行部门记录。
    若直接 LEFT JOIN 将静默放大明细行数，导致业务侧「最终分配值」被虚假重复计列。
    故必须按 .clinerules §6 以 ROW_NUMBER() OVER (PARTITION BY [CODE] ORDER BY ...) 显式
    收敛至 RANK = 1 后左连；排序键以 [ID] DESC 作确定性 tie-breaker，严禁 MAX() 黑箱折叠。
 2. 【删除态隔离】收敛排序键优先 [DELETE_FLAG] ASC（置 0 的有效部门优先），避免已删除
    科室记录抢占职系属性位。
 3. 【维度宽度不可逆】事实表 UNIT_CODE 为 NVARCHAR(100)、维表 CODE 仅 NVARCHAR(20)，
    关联由源列无条件裸引用，严禁对 CODE 做 CAST 扩宽或对 UNIT_CODE 做 RIGHT 补零，
    以免引入隐性截断与关联失配（.clinerules §7.1 源列零改造优先）。
 4. 【零行丢失保障】全链路 LEFT JOIN，未映射职系的核算单元仍保留明细行，
    职系名称兜底 N'未分配职系'、职系编码兜底空串，杜绝业务看到 NULL 空洞。
 5. 【列序业务视角】职系两列（所属职系编码/所属职系名称）插入于「核算单元编码」之前，
    体现「先归口职系、再落核算单元」的业务透视层次。

 修改日志：
 2026-09-18 14:20:00 | 脚本新建 | 建立一次分配明细业务视图报表：以 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 为唯一事实源，经 ROW_NUMBER 收敛后的 T_DEPARTMENT 左连补全职系属性（series_code / series_name），22 列全量中文别名化输出；职系两列按业务透视视角插入核算单元编码之前；全列 ISNULL/兜底零值策略统一 N'未分配职系' 与空串；纯只读 SELECT，零 GO、零 DML/DDL 副作用。
================================================================================ */

WITH cte_dept_rank AS (
    -- ── Import/Logical CTE: 部门维表按 [CODE] 显式收敛，根治 1:N 行倍增（.clinerules §6） ──
    -- [CODE] 可空且无唯一约束，必须以 ROW_NUMBER 显式排序收敛，严禁 MAX() 黑箱折叠。
    -- 排序优先级：[DELETE_FLAG] ASC（有效部门优先）→ [ID] DESC（确定性 tie-breaker）
    SELECT
        d.[CODE]                                    AS [CODE]
       ,d.[series_code]                             AS [series_code]
       ,d.[series_name]                             AS [series_name]
       ,ROW_NUMBER() OVER (
            PARTITION BY d.[CODE]
            ORDER BY d.[DELETE_FLAG] ASC, d.[ID] DESC
        )                                           AS [RN]
    FROM dbo.[T_DEPARTMENT] AS d WITH (NOLOCK)
    WHERE d.[CODE] IS NOT NULL
)
,cte_dept AS (
    -- ── Logical CTE: 仅保留每个 [CODE] 的唯一胜出行，确保与事实表 1:1 关联 ──
    SELECT
        r.[CODE]                                    AS [CODE]
       ,r.[series_code]                             AS [series_code]
       ,r.[series_name]                             AS [series_name]
    FROM cte_dept_rank AS r
    WHERE r.[RN] = 1
)
,detail AS (
    -- ── Logical CTE: 事实明细左连职系维度，行数与事实表物理粒度严格同构 ──
    SELECT
        log.[CALC_YEAR]                             AS [CALC_YEAR]
       ,log.[CALC_MONTH]                            AS [CALC_MONTH]
       ,log.[ITEM_CODE]                             AS [ITEM_CODE]
       ,log.[ITEM_NAME]                             AS [ITEM_NAME]
       ,ISNULL(dept.[series_code], N'')             AS [series_code]
       ,ISNULL(dept.[series_name], N'未分配职系')    AS [series_name]
       ,log.[UNIT_CODE]                             AS [UNIT_CODE]
       ,log.[UNIT_NAME]                             AS [UNIT_NAME]
       ,log.[PROJ_CODE]                             AS [PROJ_CODE]
       ,log.[PROJ_NAME]                             AS [PROJ_NAME]
       ,log.[ITEM_CAT_CODE]                         AS [ITEM_CAT_CODE]
       ,log.[ITEM_CAT_NAME]                         AS [ITEM_CAT_NAME]
       ,log.[RVU_VAL]                               AS [RVU_VAL]
       ,log.[EXEC_ROLE]                             AS [EXEC_ROLE]
       ,log.[STAFF_CODE]                            AS [STAFF_CODE]
       ,log.[STAFF_NAME]                            AS [STAFF_NAME]
       ,log.[DAY_TYPE_CODE]                         AS [DAY_TYPE_CODE]
       ,log.[DAY_TYPE_NAME]                         AS [DAY_TYPE_NAME]
       ,log.[FINAL_VALUE_TYPE]                      AS [FINAL_VALUE_TYPE]
       ,log.[FINAL_VALUE]                           AS [FINAL_VALUE]
       ,log.[TOTAL_QTY]                             AS [TOTAL_QTY]
       ,log.[CALC_PROCESS_TEXT]                     AS [CALC_PROCESS_TEXT]
    FROM dbo.[DWD_FIN_CALC_ALLOC1_DETAIL_LOG] AS log WITH (NOLOCK)
    LEFT JOIN cte_dept AS dept
        ON log.[UNIT_CODE] = dept.[CODE]
)
,final AS (
    -- ── Final CTE: 业务可读中文别名出口，屏蔽底层技术字段名 ──
    SELECT
        ISNULL(CAST(d.[CALC_YEAR] AS NVARCHAR(4)), N'')          AS [核算年份]
       ,ISNULL(CAST(d.[CALC_MONTH] AS NVARCHAR(2)), N'')         AS [核算月份]
       ,ISNULL(d.[ITEM_CODE], N'')                               AS [核算项编码]
       ,ISNULL(d.[ITEM_NAME], N'')                               AS [核算项名称]
       ,ISNULL(d.[series_code], N'')                             AS [所属职系编码]
       ,ISNULL(d.[series_name], N'未分配职系')                    AS [所属职系名称]
       ,ISNULL(d.[UNIT_CODE], N'')                               AS [核算单元编码]
       ,ISNULL(d.[UNIT_NAME], N'')                               AS [核算单元名称]
       ,ISNULL(d.[PROJ_CODE], N'')                               AS [项目编码]
       ,ISNULL(d.[PROJ_NAME], N'')                               AS [项目名称]
       ,ISNULL(d.[ITEM_CAT_CODE], N'')                           AS [绩效大类编码]
       ,ISNULL(d.[ITEM_CAT_NAME], N'')                           AS [绩效大类名称]
       ,CAST(ISNULL(d.[RVU_VAL], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))     AS [单项绩效点数]
       ,ISNULL(d.[EXEC_ROLE], N'')                               AS [执行角色]
       ,ISNULL(d.[STAFF_CODE], N'')                              AS [员工工号]
       ,ISNULL(d.[STAFF_NAME], N'')                              AS [员工姓名]
       ,ISNULL(d.[DAY_TYPE_CODE], N'')                           AS [日期类型编码]
       ,ISNULL(d.[DAY_TYPE_NAME], N'')                           AS [日期类型名称]
       ,ISNULL(d.[FINAL_VALUE_TYPE], N'')                        AS [数值口径]
       ,CAST(ISNULL(d.[FINAL_VALUE], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [最终分配值]
       ,CAST(ISNULL(d.[TOTAL_QTY], CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8))   AS [汇总工作量]
       ,ISNULL(d.[CALC_PROCESS_TEXT], N'')                       AS [计算过程说明]
    FROM detail AS d
)
SELECT * FROM final;

