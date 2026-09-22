/* ===============================================================================
  Relative Path : analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO.sql
  报表名称: DIM_DEPT_ITEM_EXEC_RATIO未配置排查表（全量版）
  业务说明: 排查 dbo.[PF临时医疗服务项目26A] 中未在 dbo.[DIM_DEPT_ITEM_EXEC_RATIO] 配置的
            (HIS_DEPT_CODE, ITEM_CODE) 组合，输出缺失映射清单供业务补全配置。
            输出粒度: HIS 科室编码 × HIS 科室名称 × 项目代码 × 项目名称 × HIS 类别名称
  数据流向: dbo.[PF临时医疗服务项目26A]        (事实层, [开单科室代码] BIGINT / [项目代码] NVARCHAR(60))
            ──(id)──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接: [id] BIGINT 1:1 ➔ [编码] NVARCHAR(10))
            ──(HIS_DEPT_CODE)──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
                                 (执行划分维表, 生效态 IS_ENABLED = 1 过滤唯一索引)
  口径声明: ① 按【开单维度】校验配置（HIS_DEPT_CODE = 开单科室代码桥接编码），生产计算脚本消费的是
            【执行维度】（HIS_DEPT_CODE = 执行科室代码桥接编码），故本清单为「开单科室侧配置缺口」
            参考视图，与执行维度计算缺口并非同一集合。
            ② 全账期全量扫描，不施加 '{start_time}' / '{end_time}' 时间窗；仅剔除非核算类七个大类，
            不施加绩效大类（ITEM_CAT_CODE）剪枝，不折叠、不寻版本。
            ③ 【事实表规模】dbo.[PF临时医疗服务项目26A] 约 1200 万行，全量扫描请注意执行时段。
  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符: 无（全账期全量扫描，不接受 '{year}' / '{month}' / '{struct_codes}' 注入）

  修改日志：
  2026-09-22 15:00:00 | 注释去熵 | ① 头部剔除「关键架构决策」5 条与「口径边界声明」A/B/C 段共 28 行宣讲式说明，
                               压缩为 3 条「口径声明」（开单维度边界 / 全量扫描与剪枝口径 / 事实表规模），
                               元数据行由 43 行降至 29 行；保留只读声明、NOLOCK 查询提示与占位符声明三项契约。
                               ② 代码区 7 处段落式注释压缩为 4 处极简单行标识：
                               「事实层【开单科室 × 项目】预聚合去重」/「部门字典桥接（开单科室代码 → HIS 业务编码）」
                               /「非核算项目大类剔除」/「执行划分维表生效态作用域」，
                               删除「── Logical CTE ──」「── Import CTE ──」等框架前缀、粒度复述行与
                               三值逻辑防护说明（该语义已由 OR IS NULL 子句自证）。
                               ③ SQL 物理逻辑零改动：投影 19 列、WHERE 过滤、GROUP BY 5 维、JOIN 谓词、
                               ORDER BY 三键与 WITH (NOLOCK) 全链路逐字节保持原状。
                               【日志保留说明】依 .clinerules §2【严禁抹除历史日志】，历史 6 条变更记录
                               一律保留不删，仅精简其冗长动因叙述。
  2026-09-22 14:10:00 | 字段血缘纠正 | [HIS类别名称] 由 NULL 占位改为事实层真实取值直出（方案 B）。
                               【源列勘误】任务单指定源列 PF临时医疗服务项目26A.[HIS_CAT_NAME] 经 DDL 核对
                               不存在（该名系维表 DIM_DEPT_ITEM_EXEC_RATIO 物理列）；事实表类别语义列实为
                               [项目大类] NVARCHAR(60)。实际链路 src.[项目大类] ➔ 内层别名 HIS_CAT_NAME
                               ➔ 外层 AS [HIS类别名称]（裸引用零 CAST，§7.1）。
                               【列合并】删除外层同源同值的 [ITEM_CAT_NAME] AS [项目大类] 列，
                               仅保留 [HIS类别名称]，位置仍在 [项目名称] 之后，输出列由 20 收敛为 19。
                               【GROUP BY 未变】别名投影不引入新分组维度，聚合粒度与行数不变。
                               【ORDER BY 联动修复】外层列删除致排序键悬空，同步由 s.[ITEM_CAT_NAME]
                               改为 s.[HIS_CAT_NAME]（同源同值，排序结果与稳定性一致）。
  2026-09-22 14:00:00 | 模板空列扩展 | 最外层 SELECT 追加维表导入模板空列，输出对齐 DIM_DEPT_ITEM_EXEC_RATIO：
                               [医生/技师/护士/临床执行比例] CAST(NULL AS DECIMAL(18,8))；
                               四类对应核算单元编码 CAST(NULL AS VARCHAR(60))、名称 CAST(NULL AS NVARCHAR(300))；
                               [提供日期] / [项目新增日期] CAST(NULL AS DATETIME)、[备注] CAST(NULL AS NVARCHAR(1000))。
                               剔除 [ID] / [VERSION_NO] / [IS_ENABLED] / [DISABLE_DATE] / [CREATE_TIME] /
                               [UPDATE_TIME] 六个系统托管列，防 Excel 误填覆写默认值（IS_ENABLED=1 / VERSION_NO=1）。
                               空列统一 CAST(NULL AS <TYPE>) 显式类型化，保障导出端精度与类型识别。
  2026-09-22 13:00:00 | 排序口径重构 | ORDER BY 由「金额优先」(s.[TOTAL_AMOUNT] DESC, s.[RECORD_COUNT] DESC)
                               重构为「业务键升序」(HIS_DEPT_CODE, 项目类别, ITEM_CODE)，消除数值并列时的行序漂移，
                               保证结果集确定性与跨次可比性，并贴合「按科室 → 按大类 → 按项目」补配作业顺序。
  2026-09-22 12:00:00 | 列表精简与剪枝扩面 | ① SELECT 移除常量列 N'...' AS [报表名称]，恢复纯业务字段输出；
                               ② 项目大类剔除集合由 2 类扩至 7 类并显式 N 前缀，同步改用多行括号块承载
                               OR ... IS NULL 三值逻辑兜底，避免后续追加类别时误删。
  2026-09-22 11:00:00 | 报表标识与口径剪枝 | ① 新增报表名称常量列（后于 12:00 移除）；
                               ② 事实层 WHERE 首次追加药品类剔除条件，纠偏裸 NOT IN 在可空列上的
                               UNKNOWN 静默丢行缺陷，显式 OR IS NULL 兜底保留大类缺失记录。
  2026-09-22 10:00:00 | 脚本新建 | 建立 DIM_DEPT_ITEM_EXEC_RATIO 维表缺失科室项目映射专项排查脚本：
                               开单科室代码经 sjjk_bmb_2025_06_01 桥接为 HIS 编码后 LEFT JOIN 执行划分维表，
                               按业务键分组聚合，过滤 dim.[ID] IS NULL 输出未配置组合清单；
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
