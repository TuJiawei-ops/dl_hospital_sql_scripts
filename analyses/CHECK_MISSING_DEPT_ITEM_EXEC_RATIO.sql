/* ===============================================================================
  Relative Path : analyses/CHECK_MISSING_DEPT_ITEM_EXEC_RATIO.sql
  报表名称: DIM_DEPT_ITEM_EXEC_RATIO未配置排查表 (CHECK_MISSING_DEPT_ITEM_EXEC_RATIO.sql)
  业务说明: 排查 dbo.[PF临时医疗服务项目26A] 业务数据中「未在 dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
            配置」的 (HIS_DEPT_CODE, ITEM_CODE) 组合，输出缺失映射清单供业务补全配置。
            输出粒度: HIS 科室编码 × HIS 科室名称 × 项目代码 × 项目名称 × 项目大类
  数据流向: dbo.[PF临时医疗服务项目26A]        (事实层, [开单科室代码] BIGINT / [项目代码] NVARCHAR(60))
            ──(id)──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接: [id] BIGINT 1:1 ➔ [编码] NVARCHAR(10))
            ──(HIS_DEPT_CODE)──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
                                 (执行划分维表, 生效态 IS_ENABLED = 1 过滤唯一索引)

  ── 关键架构决策（防熵增，务必知悉） ──
  1. 【血缘桥接强制化】事实层 [开单科室代码] 物理类型为 BIGINT，属 sjjk_bmb_2025_06_01.[id]
     数值代理主键，绝非业务编码；而维表 [HIS_DEPT_CODE] 为 VARCHAR(60) 字符串语义。
     二者严禁直接比较（BIGINT ↔ VARCHAR 隐式转换将导致 SARGability 衰减且语义错位），
     必须经字典桥接层输出 [编码] 后再与维表关联（对齐 .clinerules 第 7.1 节编码字段规范）。
  2. 【零重复 CAST】字典层 [编码] 本身即 NVARCHAR(10) 字符串，裸引用直出，不再叠加任何
     CAST/VARCHAR 冗余转换（第 7.1 节【源列零改造优先】）。
  3. 【生效态口径锁定】(HIS_DEPT_CODE, ITEM_CODE) 的业务唯一性仅由过滤唯一索引
     UQ_DIM_DEPT_ITEM_EXEC_RATIO_ACTIVE (WHERE IS_ENABLED = 1) 强制约束，故校验域严格锁定
     IS_ENABLED = 1；仅存在于停用态 (IS_ENABLED = 0) 的组合将被判定为「未配置」，符合本脚本
     「业务侧缺项补全」的定位。
  4. 【零折叠】维表侧仅 IS_ENABLED = 1 过滤，严禁 ROW_NUMBER()/MAX() 人工去重
     （启用态业务键唯一，粒度已由物理索引保障）。
  5. 【零版本寻址】维表 [VERSION_NO] 仅作留痕属性，严禁作为动态寻址主控条件
     （.clinerules 第 9 节 VERSION_NO 备注化法则）。

  ── 口径边界声明（避免误读为口径缺陷） ──
  A. 本脚本按任务约定以【开单维度】(HIS_DEPT_CODE = 开单科室代码桥接编码) 校验映射配置，
     而生产计算脚本 一次分配/医疗服务项目执行积分.sql 与 analyses/报表_医疗服务项目执行积分明细.sql
     实际消费的是【执行维度】(HIS_DEPT_CODE = 执行科室代码桥接编码)。
     故本清单为「开单科室侧配置缺口」参考视图，与执行维度计算缺口并非同一集合；
     如需改为执行维度校验，仅需将 cte_bmb_bridge 的关联键由 [开单科室代码] 切至 [执行科室代码]，
     并在 src_aggregated 中同步替换科室代码/名称/分组维度，其余去重与比对逻辑保持零改动。
  B. 本脚本为全账期全量扫描，不施加 '{start_time}' / '{end_time}' 时间窗；
     项目大类维度仅剔除「非核算类」六个大类（西药费 / 中草药费 / 化验费 / 检查费 / 中成药费 / 卫生材料费，
     其中大类为空（NULL）者仍保留在排查范围内），不施加绩效大类（ITEM_CAT_CODE）剪枝，
     以最大范围暴露配置缺口（绩效大类剪枝会掩盖非积分体系项目的映射缺失）。
  C. 【事实表规模】dbo.[PF临时医疗服务项目26A] 约 1200 万行，全量扫描请注意执行时段。

  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符: 无（全账期全量扫描，不接受 '{year}' / '{month}' / '{struct_codes}' 注入）

  修改日志：
  2026-09-22 14:00:00 | 模板空列扩展 | 最外层 SELECT 投影追加 DIM_DEPT_ITEM_EXEC_RATIO 维表配置空列（共 15 列），
                               使排查结果集直接对齐维表导入模板，业务导出 Excel 后可就地填报回灌：
                               [HIS类别名称]（置于 [项目大类] 之后，实体属性区）；
                               [医生/技师/护士/临床执行比例] 4 列 CAST(NULL AS DECIMAL(18,8))，
                               精度与维表四类执行比例物理列（DECIMAL(18,8) 默认 0.00000000）严格对齐；
                               [医生/技师/护士/临床对应核算单元编码] 4 列 CAST(NULL AS VARCHAR(60))、
                               [医生/技师/护士/临床对应核算单元名称] 4 列 CAST(NULL AS NVARCHAR(300))，
                               宽度与维表编码/名称物理列声明完全一致，且编码列强制字符串语义（§7.1）；
                               [提供日期] / [项目新增日期] 2 列 CAST(NULL AS DATETIME)、
                               [备注] CAST(NULL AS NVARCHAR(1000))，对齐维表业务时间与留痕区。
                               剔除的系统与管理列：[ID]（自增代理主键）/ [VERSION_NO]（系统赋值）/ [IS_ENABLED]
                               （自动启用）/ [DISABLE_DATE] / [CREATE_TIME] / [UPDATE_TIME]，
                               规避业务在 Excel 中误填导致 ETL 落库时覆写系统默认值（默认 IS_ENABLED=1 / VERSION_NO=1）。
                               【类型语义保障】全部空列统一 CAST(NULL AS <TYPE>) 显式声明类型，
                               确保 SSMS / Excel / 导出工具按目标物理类型识别列（保留 DECIMAL 精度与
                               DATETIME 属性），避免裸 NULL 被推断为泛型字面量而丢失精度或产生转换乱码。
                               保留既有排查特征列 [发生明细笔数] / [累计金额] 于实体属性区。
                               内部预聚合 CTE、字典桥接、WHERE 过滤、LEFT JOIN 谓词、ORDER BY 排序
                               与模板占位符全程零改动（仅投影层增量）。
  2026-09-22 13:00:00 | 排序口径重构 | 尾部 ORDER BY 排序策略由「金额优先」重构为「业务键升序」：
                               s.[TOTAL_AMOUNT] DESC, s.[RECORD_COUNT] DESC
                               → s.[HIS_DEPT_CODE] ASC, s.[ITEM_CAT_NAME] ASC, s.[ITEM_CODE] ASC。
                               重构动因：【排序稳定性】原金额/笔数排序在数值相同（如并列 0 笔、退费净额相抵）
                               时结果集顺序不确定，同一查询多次执行或不同客户端导出会产生行序漂移，
                               干扰业务逐行核对与增量比对；新排序键 (HIS 科室编码, 项目大类, 项目代码)
                               为输出粒度 (编码 × 名称 × 代码 × 名称 × 大类) 的业务键子集超集，
                               可保证结果集绝对确定性与跨次可比性，且天然贴合业务「按科室 → 按大类 → 按项目」
                               的补配作业顺序。【NULL 排序行为】源列 [项目大类] 可空，SQL Server ASC 排序
                               默认将 NULL 视为最小值置于组内最前（不发生报错或丢行），
                               与下方 WHERE 的 OR IS NULL 兜底口径一致，缺失大类的待补配记录优先曝光。
                               预聚合逻辑、字典桥接、WHERE 条件、输出列契约与模板占位符零改动。
  2026-09-22 12:00:00 | 列表精简与剪枝扩面 | ① SELECT 输出列表移除上一版追加的常量列
                               N'DIM_DEPT_ITEM_EXEC_RATIO未配置排查表' AS [报表名称]，
                               输出列恢复为 7 列纯业务字段、首列回归 s.[HIS_DEPT_CODE] AS [HIS科室编码]；
                               报表中文标识仅保留在头部元数据（报表名称行），避免结果集冗余常量列
                               污染 CSV 导出与 BI 建表结构。② 项目大类剔除集合由 2 类扩至 6 类
                               （西药费 / 中草药费 / 化验费 / 检查费 / 中成药费 / 卫生材料费），
                               统一显式 N 前缀保障 Unicode 语义；同步将 (… OR src.[项目大类] IS NULL)
                               由单行内联表达式改为多行括号块格式，三值逻辑 NULL 兜底语义不变，
                               杜绝后续追加类别时误删 OR IS NULL 子句。
                               ③ 头部口径声明 B 同步改写（剔除类别枚举更新）。
                               聚合粒度、字典桥接链路、LEFT JOIN 谓词、dim.[ID] IS NULL 判定、
                               ORDER BY 排序与 DECIMAL(18,8) 精度全程零改动。
  2026-09-22 11:00:00 | 报表标识与口径剪枝 | ① Task 1：SELECT 输出列最前方新增报表名称固定常量列
                               N'DIM_DEPT_ITEM_EXEC_RATIO未配置排查表' AS [报表名称]（显式 N 前缀，
                               保证 NVARCHAR 语义与结果集恒为 Unicode，规避客户端 ANSI 编码乱码），
                               同步将头部元数据 '脚本名称' 升级为 '报表名称' 并标注原脚本文件名；
                               ② Task 2：事实层预聚合 WHERE 追加药品类剔除条件
                               (src.[项目大类] NOT IN (N'西药费', N'中草药费') OR src.[项目大类] IS NULL)，
                               纠偏原型写法 src.[项目大类] NOT IN (N'西药费', N'中草药费') 的三值逻辑缺陷——
                               源列 [项目大类] NVARCHAR(60) NULL 可空，裸 NOT IN 会使 NULL 行求值为 UNKNOWN
                               而被静默丢弃，隐性缩水缺失清单；显式 OR IS NULL 兜底保留大类缺失的历史记录。
                               条件严格独占一行、行首 AND 前缀，满足 §6 占位符/可变条件独占行法则与
                               `--` 单行注释零副作用隔离。
                               ③ 口径声明 B 同步改写（原「不做绩效大类剪枝」表述已与新增过滤冲突）。
                               聚合粒度、字典桥接链路、LEFT JOIN 谓词、dim.[ID] IS NULL 判定、
                               ORDER BY 排序与 DECIMAL(18,8) 精度全程零改动。
  2026-09-22 10:00:00 | 脚本新建 | 建立 DIM_DEPT_ITEM_EXEC_RATIO 维表缺失科室项目映射专项排查脚本：
                               以 开单科室代码 经 sjjk_bmb_2025_06_01 桥接为 HIS 编码后 LEFT JOIN 执行划分维表，
                               按 (HIS 科室编码/名称 × 项目代码/名称/大类) 分组聚合，过滤 dim.[ID] IS NULL
                               输出未配置组合清单并附发生笔数与累计金额排序；
                               全链路 WITH (NOLOCK) 只读、零折叠、零版本寻址、编码列零冗余 CAST。
=============================================================================== */

SELECT
    s.[HIS_DEPT_CODE]                                                AS [HIS科室编码]
   ,s.[HIS_DEPT_NAME]                                                AS [HIS科室名称]
   ,s.[ITEM_CODE]                                                    AS [项目代码]
   ,s.[ITEM_NAME]                                                    AS [项目名称]
   ,s.[ITEM_CAT_NAME]                                                AS [项目大类]
   ,CAST(NULL AS NVARCHAR(300))                                      AS [HIS类别名称]
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
    -- ── Logical CTE: 事实层【开单科室 × 项目】预聚合去重 ──
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
