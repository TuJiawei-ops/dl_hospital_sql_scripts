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
  2026-09-22 16:10:00 | 优化 | NOT IN 剔除名单中补全 N'卫生材料' 类别
  2026-09-22 15:30:00 | 优化 | 注释去熵、清理冗余段落、修正字段血缘与对齐导入模板空列
  2026-09-22 13:00:00 | 重构 | 增加按月切片过滤、优化排序规则为业务主键升序
  2026-09-22 12:30:00 | 初始化 | 建立按月排查脚本
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
          src.[项目大类] NOT IN (N'西药费', N'中草药费', N'化验费', N'检查费', N'检验费', N'中成药费', N'卫生材料费', N'卫生材料')
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
