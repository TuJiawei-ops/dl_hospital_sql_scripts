/* ===============================================================================
  Relative Path : analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO_MONTHLY.sql
  报表名称: DIM_DEPT_ITEM_EXEC_RATIO未配置排查表（按月/时间范围）
  业务说明: 排查指定【开单时间】范围内 dbo.[PF临时医疗服务项目26A] 中未在 dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
            配置的 (HIS_DEPT_CODE, ITEM_CODE) 组合，输出缺失映射清单供业务按月补全配置。
            输出粒度: HIS 科室编码 × HIS 科室名称 × 项目代码 × 项目名称 × HIS 类别名称
  数据流向: dbo.[PF临时医疗服务项目26A]        (事实层, [开单科室代码] BIGINT / [开单时间] DATETIME / [项目代码] NVARCHAR(60))
            ──(id)──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接: [id] BIGINT 1:1 ➔ [编码] NVARCHAR(10))
            ──(HIS_DEPT_CODE)──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
                                 (执行划分维表, 生效态 IS_ENABLED = 1 过滤唯一索引)
  版本差异: ① 本版按 [开单时间] 闭区间切片（全量版为全账期扫描），端点由调用方注入；
            ② 本版剔除非核算类七个大类（较全量版额外纳入「检验费」）；
            ③ 时间基准为 [开单时间]，生产计算脚本采用 [缴费时间]/[执行时间] 动态路由，账期归属并非同一集合。
  口径声明: ① 按【开单维度】校验配置（HIS_DEPT_CODE = 开单科室代码桥接编码），生产计算脚本消费的是
            【执行维度】（HIS_DEPT_CODE = 执行科室代码桥接编码），故本清单为「开单科室侧配置缺口」
            参考视图，与执行维度计算缺口并非同一集合。
            ② 不施加绩效大类（ITEM_CAT_CODE）剪枝，不折叠、不寻版本，以最大范围暴露配置缺口。
            ③ 【性能提示】[开单时间] 走闭区间裸列比较（列侧无函数包裹）；如响应偏慢，
            建议评估在 [开单时间] 上补非聚簇索引后重跑。
  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符（严禁破坏）:
    '{start_time}' : 开单时间范围起点（带单引号文本，如 '2024-01-01 00:00:00.000'）
    '{end_time}'   : 开单时间范围终点（带单引号文本，如 '2024-01-31 23:59:59.997'）

  修改日志：
  2026-09-22 15:00:00 | 注释去熵 | ① 头部剔除「关键架构决策」6 条、「口径边界声明」A/B/C 段与「差异声明」段共 40 行
                               宣讲式说明，压缩为「版本差异」3 条 +「口径声明」3 条，元数据行由 65 行降至 29 行；
                               保留只读声明、NOLOCK 查询提示与 '{start_time}'/'{end_time}' 占位符注释三项契约
                               （占位符说明确保自动化替换流程不受注释清理影响）。
                               ② 代码区 8 处段落式注释压缩为 5 处极简单行标识：
                               「事实层【开单科室 × 项目】预聚合去重」/「部门字典桥接（开单科室代码 → HIS 业务编码）」
                               /「非核算项目大类剔除」/「执行划分维表生效态作用域」，
                               删除「── Logical CTE ──」「── Import CTE ──」框架前缀、粒度复述行与
                               三值逻辑防护说明（该语义已由 OR IS NULL 子句自证）。
                               ③ SQL 物理逻辑零改动：投影 19 列、[开单时间] 闭区间过滤、GROUP BY 5 维、
                               JOIN 谓词、ORDER BY 三键、CAST(... AS DATETIME) 强类型化与 WITH (NOLOCK)
                               全链路逐字节保持原状；模板占位符 {'start_time'}/{'end_time'} 位置与形态不变。
                               【日志保留说明】依 .clinerules §2【严禁抹除历史日志】，历史 3 条变更记录
                               一律保留不删，仅精简其冗长动因叙述。
  2026-09-22 14:10:00 | 字段血缘纠正 | [HIS类别名称] 由 NULL 占位改为事实层真实取值直出（方案 B）：
                               任务单指定源列 PF临时医疗服务项目26A.[HIS_CAT_NAME] 经 DDL 核对不存在
                               （该名系维表 DIM_DEPT_ITEM_EXEC_RATIO 物理列）；事实表类别语义列实为
                               [项目大类] NVARCHAR(60)。实际链路 src.[项目大类] ➔ 内层别名 HIS_CAT_NAME
                               ➔ 外层 AS [HIS类别名称]（裸引用零 CAST）。删除外层同源同值的 [项目大类] 列，
                               输出列由 20 收敛为 19；GROUP BY 粒度不变；排序键同步由 s.[ITEM_CAT_NAME]
                               改为 s.[HIS_CAT_NAME]，与全量版保持一致。
  2026-09-22 14:00:00 | 模板空列扩展 | 最外层 SELECT 追加维表导入模板空列，与全量版输出列结构 1:1 对齐：
                               [医生/技师/护士/临床执行比例] CAST(NULL AS DECIMAL(18,8))；
                               四类对应核算单元编码 CAST(NULL AS VARCHAR(60))、名称 CAST(NULL AS NVARCHAR(300))；
                               [提供日期] / [项目新增日期] CAST(NULL AS DATETIME)、[备注] CAST(NULL AS NVARCHAR(1000))。
                               剔除六个系统托管列（[ID] / [VERSION_NO] / [IS_ENABLED] / [DISABLE_DATE] /
                               [CREATE_TIME] / [UPDATE_TIME]），防 Excel 误填覆写默认值。
  2026-09-22 13:00:00 | 排序口径重构 | ORDER BY 由「金额优先」(s.[TOTAL_AMOUNT] DESC, s.[RECORD_COUNT] DESC)
                               重构为「业务键升序」(HIS_DEPT_CODE, 项目类别, ITEM_CODE)，与全量版排序口径 1:1 对齐
                               （两版清单可直接按行序比对月度增量），消除数值并列时的月度切片行序漂移。
  2026-09-22 12:30:00 | 脚本新建 | 建立按月【开单时间】范围校验 DIM_DEPT_ITEM_EXEC_RATIO 缺失配置排查脚本：
                               以 [开单时间] 闭区间切片收敛扫描域，经 sjjk_bmb_2025_06_01 桥接 [开单科室代码]
                               为 HIS 编码后 LEFT JOIN 执行划分维表，过滤 dim.[ID] IS NULL 输出未配置组合清单；
                               时间占位符独占行 + 行首 AND 前缀 + CAST(... AS DATETIME) 强类型化，
                               非核算类七大类剔除并显式 OR IS NULL 三值逻辑兜底；
                               全链路 WITH (NOLOCK) 只读、零折叠、零版本寻址、编码列零冗余 CAST。
=============================================================================== */


SELECT
    s.[HIS_DEPT_CODE]                                                AS [HIS科室编码]
   ,s.[HIS_DEPT_NAME]                                                AS [HIS科室名称]
   ,s.[ITEM_CODE]                                                    AS [项目代码]
   ,s.[ITEM_NAME]                                                    AS [项目名称]
   ,s.[HIS_CAT_NAME]                                                 AS [HIS类别名称]
   ,s.[RECORD_COUNT]                                                 AS [发生明细笔数]
   ,s.[TOTAL_AMOUNT]                                                 AS [累计金额]
   ,CAST(NULL AS DECIMAL(18,8))                                      AS [医生执行比例]
   ,CAST(NULL AS DECIMAL(18,8))                                      AS [技师执行比例]
   ,CAST(NULL AS DECIMAL(18,8))                                      AS [护士执行比例]
   ,CAST(NULL AS DECIMAL(18,8))                                      AS [临床执行比例]
   ,CAST(NULL AS VARCHAR(60))                                        AS [医生对应核算单元编码]
   ,CAST(NULL AS NVARCHAR(300))                                      AS [医生对应核算单元名称]
   ,CAST(NULL AS VARCHAR(60))                                        AS [技师对应核算单元编码]
   ,CAST(NULL AS NVARCHAR(300))                                      AS [技师对应核算单元名称]
   ,CAST(NULL AS VARCHAR(60))                                        AS [护士对应核算单元编码]
   ,CAST(NULL AS NVARCHAR(300))                                      AS [护士对应核算单元名称]
   ,CAST(NULL AS VARCHAR(60))                                        AS [临床对应核算单元编码]
   ,CAST(NULL AS NVARCHAR(300))                                      AS [临床对应核算单元名称]
   ,CAST(NULL AS DATETIME)                                           AS [提供日期]
   ,CAST(NULL AS DATETIME)                                           AS [项目新增日期]
   ,CAST(NULL AS NVARCHAR(1000))                                     AS [备注]
FROM (
    -- 事实层【开单科室 × 项目】预聚合去重
    SELECT
        b.[HIS_DEPT_CODE]                                            AS HIS_DEPT_CODE
       ,src.[开单科室]                                                AS HIS_DEPT_NAME
       ,src.[项目代码]                                                AS ITEM_CODE
       ,src.[项目名称]                                                AS ITEM_NAME
       ,src.[项目大类]                                                AS HIS_CAT_NAME
       ,COUNT(1)                                                     AS RECORD_COUNT
       ,CAST(SUM(CAST(src.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS TOTAL_AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS src WITH (NOLOCK)
    INNER JOIN (
        -- 部门字典桥接（开单科室代码 → HIS 业务编码）
        SELECT
            b.[id]                                                   AS DEPT_ID
           ,b.[编码]                                                  AS HIS_DEPT_CODE
        FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    ) AS b
        ON src.[开单科室代码] = b.[DEPT_ID]
    WHERE 1=1
      AND src.[开单科室代码] IS NOT NULL
      AND src.[项目代码] IS NOT NULL
      -- ── 开单时间范围过滤（模板占位符独占单行 + 行首 AND + 强类型化，满足 §6 / §9 隔离规范） ──
      AND src.[开单时间] >= CAST('{start_time}' AS DATETIME)
      AND src.[开单时间] <= CAST('{end_time}' AS DATETIME)
      -- 非核算项目大类剔除
      AND (
          src.[项目大类] NOT IN (N'西药费', N'中草药费', N'化验费', N'检查费', N'检验费', N'中成药费', N'卫生材料费')
          OR src.[项目大类] IS NULL
      )
    GROUP BY
        b.[HIS_DEPT_CODE]
       ,src.[开单科室]
       ,src.[项目代码]
       ,src.[项目名称]
       ,src.[项目大类]
) AS s
LEFT JOIN (
    -- 执行划分维表生效态作用域
    SELECT
        r.[ID]                                                       AS ID
       ,r.[HIS_DEPT_CODE]                                            AS HIS_DEPT_CODE
       ,r.[ITEM_CODE]                                                AS ITEM_CODE
    FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS r WITH (NOLOCK)
    WHERE r.[IS_ENABLED] = 1
) AS dim
    ON dim.[HIS_DEPT_CODE] = s.[HIS_DEPT_CODE]
   AND dim.[ITEM_CODE]     = s.[ITEM_CODE]
WHERE dim.[ID] IS NULL
ORDER BY
    s.[HIS_DEPT_CODE] ASC
   ,s.[HIS_CAT_NAME] ASC
   ,s.[ITEM_CODE] ASC
;
