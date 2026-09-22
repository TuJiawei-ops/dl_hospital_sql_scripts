/* ===============================================================================
  Relative Path : analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO_MONTHLY.sql
  报表名称: DIM_DEPT_ITEM_EXEC_RATIO未配置排查表（按月/时间范围）
  业务说明: 排查指定【开单时间】范围内 dbo.[PF临时医疗服务项目26A] 业务数据中
            「未在 dbo.[DIM_DEPT_ITEM_EXEC_RATIO] 配置」的 (HIS_DEPT_CODE, ITEM_CODE) 组合，
            输出缺失映射清单供业务按月补全配置。
            输出粒度: HIS 科室编码 × HIS 科室名称 × 项目代码 × 项目名称 × 项目大类
  数据流向: dbo.[PF临时医疗服务项目26A]        (事实层, [开单科室代码] BIGINT / [开单时间] DATETIME / [项目代码] NVARCHAR(60))
            ──(id)──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接: [id] BIGINT 1:1 ➔ [编码] NVARCHAR(10))
            ──(HIS_DEPT_CODE)──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
                                 (执行划分维表, 生效态 IS_ENABLED = 1 过滤唯一索引)

  ── 与全量版（analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO.sql）的差异声明 ──
  1. 【时间窗切片】追加 [开单时间] 闭区间过滤，将扫描域由全账期约 1200 万行收敛至单月切片，
     提升按月排查效率；闭区间端点由调用方按 '{start_time}' 00:00:00.000 ~ '{end_time}' 23:59:59.997 注入。
  2. 【剔除类别扩集】全量版剔除 6 类，本版剔除 7 类（额外纳入「检验费」）。
  3. 【时间锚点差异】本版时间基准为 [开单时间]（开单业务发生锚点），
     而生产计算脚本 一次分配/医疗服务项目执行积分.sql 采用 [缴费时间]（门诊）/ [执行时间]（非门诊）动态路由，
     两者时间锚点不同，故本清单的账期归属与计算侧账期切片并非同一集合。

  ── 关键架构决策（防熵增，务必知悉） ──
  1. 【血缘桥接强制化】事实层 [开单科室代码] 物理类型为 BIGINT，属 sjjk_bmb_2025_06_01.[id]
     数值代理主键，绝非业务编码；而维表 [HIS_DEPT_CODE] 为 VARCHAR(60) 字符串语义。
     二者严禁直接比较（BIGINT ↔ VARCHAR 隐式转换将导致 SARGability 衰减且语义错位），
     必须经字典桥接层输出 [编码] 后再与维表关联（对齐 .clinerules 第 7.1 节编码字段规范）。
  2. 【零重复 CAST】字典层 [编码] 本身即 NVARCHAR(10) 字符串，裸引用直出，不再叠加任何
     CAST/VARCHAR 冗余转换（第 7.1 节【源列零改造优先】）。
  3. 【时间占位符强类型化】'{start_time}' / '{end_time}' 统一经 CAST(... AS DATETIME) 显式转换，
     与项目内既有脚本（analyses/一次分配 全系列）写法严格一致，规避字符串字面量与 DATETIME 列
     比较时的隐式转换类型推断歧义，并保障 [开单时间] 上的索引 SARGability（列侧零函数包裹）。
  4. 【生效态口径锁定】(HIS_DEPT_CODE, ITEM_CODE) 的业务唯一性仅由过滤唯一索引
     UQ_DIM_DEPT_ITEM_EXEC_RATIO_ACTIVE (WHERE IS_ENABLED = 1) 强制约束，故校验域严格锁定
     IS_ENABLED = 1；仅存在于停用态 (IS_ENABLED = 0) 的组合将被判定为「未配置」，符合本脚本
     「业务侧缺项补全」的定位。
  5. 【零折叠】维表侧仅 IS_ENABLED = 1 过滤，严禁 ROW_NUMBER()/MAX() 人工去重
     （启用态业务键唯一，粒度已由物理索引保障）。
  6. 【零版本寻址】维表 [VERSION_NO] 仅作留痕属性，严禁作为动态寻址主控条件
     （.clinerules 第 9 节 VERSION_NO 备注化法则）。

  ── 口径边界声明（避免误读为口径缺陷） ──
  A. 本脚本按任务约定以【开单维度】(HIS_DEPT_CODE = 开单科室代码桥接编码) 校验映射配置，
     而生产计算脚本 一次分配/医疗服务项目执行积分.sql 与 analyses/报表_医疗服务项目执行积分明细.sql
     实际消费的是【执行维度】(HIS_DEPT_CODE = 执行科室代码桥接编码)。
     故本清单为「开单科室侧配置缺口」参考视图，与执行维度计算缺口并非同一集合；
     如需改为执行维度校验，仅需将字典桥接的关联键由 [开单科室代码] 切至 [执行科室代码]，
     并在预聚合层同步替换科室代码/名称/分组维度，其余去重与比对逻辑保持零改动。
  B. 项目大类维度仅剔除「非核算类」七个大类（西药费 / 中草药费 / 化验费 / 检查费 / 检验费 /
     中成药费 / 卫生材料费，其中大类为空（NULL）者仍保留在排查范围内），
     不施加绩效大类（ITEM_CAT_CODE）剪枝，以最大范围暴露配置缺口。
  C. 【性能提示】过滤条件 [开单时间] 走闭区间裸列比较（列侧无函数包裹）。
     若物理表无 [开单时间] 索引，单月切片仍可显著优于全表扫描；
     如响应偏慢，建议评估在 [开单时间] 上补充非聚簇索引后重跑。

  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符（严禁破坏）:
    '{start_time}' : 开单时间范围起点（带单引号文本，如 '2024-01-01 00:00:00.000'）
    '{end_time}'   : 开单时间范围终点（带单引号文本，如 '2024-01-31 23:59:59.997'）

  修改日志：
  2026-09-22 13:00:00 | 排序口径重构 | 尾部 ORDER BY 排序策略由「金额优先」重构为「业务键升序」：
                               s.[TOTAL_AMOUNT] DESC, s.[RECORD_COUNT] DESC
                               → s.[HIS_DEPT_CODE] ASC, s.[ITEM_CAT_NAME] ASC, s.[ITEM_CODE] ASC，
                               与全量版 analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO.sql 排序口径
                               完成 1:1 对齐（两版清单可直接按行序比对月度增量）。
                               重构动因：【排序稳定性】原金额/笔数排序在数值相同时结果集顺序不确定，
                               同一月度切片多次执行或不同客户端导出会产生行序漂移，干扰逐行核对；
                               新排序键为输出粒度的业务键超集，保证结果集绝对确定性与跨次可比性，
                               并贴合业务「按科室 → 按大类 → 按项目」的补配作业顺序。
                               【NULL 排序行为】源列 [项目大类] 可空，SQL Server ASC 默认将 NULL
                               置于最前（不报错、不丢行），与 WHERE 的 OR IS NULL 兜底口径一致。
                               开单时间窗、预聚合逻辑、字典桥接、剔除条件与模板占位符零改动。
  2026-09-22 12:30:00 | 脚本新建 | 建立按月【开单时间】时间范围校验 DIM_DEPT_ITEM_EXEC_RATIO
                               缺失配置排查脚本：以 [开单时间] 闭区间切片收敛扫描域，
                               经 sjjk_bmb_2025_06_01 桥接 [开单科室代码](BIGINT) 为 HIS 编码后
                               LEFT JOIN 执行划分维表，过滤 dim.[ID] IS NULL 输出未配置组合清单；
                               时间占位符独占行 + 行首 AND 前缀 + CAST(... AS DATETIME) 强类型化，
                               非核算类七大类剔除并显式 OR IS NULL 三值逻辑兜底；
                               全链路 WITH (NOLOCK) 只读、零折叠、零版本寻址、编码列零冗余 CAST。
=============================================================================== */


SELECT
    s.[HIS_DEPT_CODE]                                                AS [HIS科室编码]
   ,s.[HIS_DEPT_NAME]                                                AS [HIS科室名称]
   ,s.[ITEM_CODE]                                                    AS [项目代码]
   ,s.[ITEM_NAME]                                                    AS [项目名称]
   ,s.[ITEM_CAT_NAME]                                                AS [项目大类]
   ,s.[RECORD_COUNT]                                                 AS [发生明细笔数]
   ,s.[TOTAL_AMOUNT]                                                 AS [累计金额]
FROM (
    -- ── Logical CTE: 事实层【开单科室 × 项目】预聚合去重（限指定开单时间范围） ──
    -- 粒度: 桥接后 HIS 科室编码 × HIS 科室名称 × 项目代码 × 项目名称 × 项目大类
    SELECT
        b.[HIS_DEPT_CODE]                                            AS HIS_DEPT_CODE
       ,src.[开单科室]                                                AS HIS_DEPT_NAME
       ,src.[项目代码]                                                AS ITEM_CODE
       ,src.[项目名称]                                                AS ITEM_NAME
       ,src.[项目大类]                                                AS ITEM_CAT_NAME
       ,COUNT(1)                                                     AS RECORD_COUNT
       ,CAST(SUM(CAST(src.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS TOTAL_AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS src WITH (NOLOCK)
    INNER JOIN (
        -- ── Import CTE: 部门字典桥接层（事实层数值主键 [开单科室代码] → HIS 业务编码 [编码]） ──
        -- [id] 为物理主键聚簇，粒度 1:1；[编码] 裸引用，不做 CAST/补零/去空格加工（§7.1 源列零改造优先）
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
      -- ── 非核算项目大类剔除：药品 / 化验 / 检查 / 卫生材料类不纳入收费项目执行划分体系 ──
      -- 三值逻辑防护：源列 [项目大类] 可空（NVARCHAR(60) NULL），NULL NOT IN (...) 求值为 UNKNOWN
      -- 会被静默丢弃；显式 OR IS NULL 兜底，确保大类缺失的历史记录仍进入缺失配置排查范围。
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
    -- ── Import CTE: 执行划分维表生效态作用域（仅取启用态规则，零折叠、零版本寻址） ──
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
   ,s.[ITEM_CAT_NAME] ASC
   ,s.[ITEM_CODE] ASC
;
