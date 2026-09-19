/* ===============================================================================
  Relative Path : analyses/报表_医疗服务项目执行积分明细.sql
  脚本名称: 报表_医疗服务项目执行积分明细.sql
  业务说明: 医疗服务项目执行积分的「全过程明细分析报表」。以 绩效核算单元 × 收费项目 × 执行角色
            为唯一粒度，全字段平铺透传 fact_raw 预聚合 → 字典桥接 → RVU 维度配置 → 医技护执行比例
            的完整中间计算链，含各角色分摊比例与反推综合比例，供业务直接导出核对。
  数据流向: dbo.[PF临时医疗服务项目26A]                  (事实层, 按 执行科室 × 项目 预聚合)
            ──▶ dbo.[sjjk_bmb_2025_06_01]                (字典桥接: [执行科室代码] = [id] ➔ [编码])
            ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION]           (绩效大类维度, 单版本 1:1 直连)
            ──▶ dbo.[DIM_DEPT_ITEM_EXEC_RATIO]           (医技护执行划分, IS_ENABLED = 1)

  ── 与计算脚本（一次分配/医疗服务项目执行积分.sql）的口径差异声明 ──
  本报表 = 计算脚本的「全过程展开视图」，CTE 链（dept_dict → fact_raw → dim_version_scope →
  dim_exec_ratio_raw → joined → cte_role_unpivot）与落库投影口径完全同源，但下列为显式差异：
  1. 【剥离持久化】彻底剔除 Envelope Pattern：无 DELETE 幂等清场、无 INSERT 落库、
     无波浪号 ~ 区块、无 DWD_FIN_CALC_ALLOC1_DETAIL_LOG 读写，纯 SELECT 零副作用。
  2. 【比例可见化】计算脚本 final 层仅输出反推综合比例 EXEC_RATIO，各角色原始分摊比例
     (DOC/TECH/NURSE_EXEC_RATIO) 在 cte_role_unpivot 展开后即被丢弃；本报表在角色展开时
     同步携带 [分摊执行比例]，使「分摊比例 → 加权积分 → 反推比例」三态可交叉验证。
  3. 【struct_codes 过滤位】本报表保留计算脚本 cte_role_unpivot 的同一过滤位
     (u.[HPS_DEPT_CODE] IN {struct_codes})，并以注释态提供（-- 前缀）便于按需启停；
     计算脚本为强制生效，本报表默认关闭以保证未配置核算单元的行可被显式核查（防隐性漏计）。
  4. 【BIZ_EPOCH 剪枝】账期右端点哨兵 BIZ_EPOCH 为计算脚本内部穿越字段（契约 §8），
     严禁对外输出或参与聚合/分组，本报表在 joined 层即已剔除，不进入任何输出列。

  只读声明: 纯 SELECT 分析报表，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化）。
  查询提示: 全链路 WITH (NOLOCK)，只读核对不加锁，避免影响生产事实表写入。

  输出结构（双层出口设计）:
  层 1/2  res CTE        : 全过程明细平铺网格（22 列，纯投影 + 精度对齐 + 审计文本拼接），
                           不含任何 WHERE / ORDER BY，计量口径与计算脚本落库粒度严格一致。
  层 2/2  最外层查询通道 : SELECT * FROM res WHERE 1=1 + ORDER BY，内置「个性化查询扩展插入位」
                           （注释态示例：按核算单元、项目代码、执行角色、积分阈值、大类筛选），
                           对上游计算链零侵入，可自由追加过滤与排序而不改变任何计算结果。

  依赖契约:
  事实表 : dbo.[PF临时医疗服务项目26A] —— [执行科室代码] BIGINT / [项目代码] NVARCHAR(60) /
           [来源] NVARCHAR(可空) / [缴费时间·执行时间] DATETIME / [数量·金额] DECIMAL(18,8)
  桥接表 : dbo.[sjjk_bmb_2025_06_01] —— [id] BIGINT 主键聚簇 / [编码] NVARCHAR(10) ➔ VARCHAR(60)
  维表 A : dbo.[DIM_PRF_ITEM_RVU_VERSION] —— 主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)
  维表 B : dbo.[DIM_DEPT_ITEM_EXEC_RATIO] —— [IS_ENABLED] 生效态过滤

  ── 关键纠偏（防熵增） ──
  1. 【单版本直连】RVU 维表 1:1 直连，VERSION_NO / VERSION_DESC 仅作备注属性输出，
     严禁作为动态寻址主控条件（.clinerules §9 零版本寻址与 VERSION_NO 备注化法则）。
  2. 【预聚合后置】fact_raw 沿用计算脚本的 (执行科室 × 项目) 预聚合口径，移除开单科室、
     单价及执行时间，压降明细行数；这是与落库日志表可比对的前提，严禁擅自改为明细粒度。
  3. 【零折叠】维表 B 仅以 IS_ENABLED = 1 过滤，严禁 ROW_NUMBER()/MAX() 人工去重；
     多 HIS 执行科室映射同一绩效核算单元时，由 cte_role_unpivot 按【单元 × 项目 × 角色】收敛。
  4. 【角色展开】CROSS APPLY 行转列严格沿用计算脚本的过滤条件
     （EXEC_RATIO > 0 且 HPS_DEPT_CODE IS NOT NULL），零改动。
  5. 【时间维度分流】事实层时间窗按 [来源] 动态路由：门诊走 [缴费时间]、
     非门诊走 [执行时间]，两分支均显式 CAST(... AS DATETIME) 保障 SARGability。
  6. 【三段式审计文本】[计算过程描述] 严格遵循 .clinerules 三段式硬性表达规范：
     [元数据段] | [中文逻辑公式段] | [纯数学代入算式段]，数学段落零汉字，运算符两侧留 1 空格。
  7. 【精度统一】全部数值计算与 CAST 统一 DECIMAL(18,8)，空值兜底常量同精度。

  模板占位符（严禁破坏）:
  '{year}' / '{month}'          : 账期标签，输出列展示（CAST AS VARCHAR(10)）
  '{start_time}' / '{end_time}' : 事实层时间窗，按 [来源] 动态路由，显式 CAST AS DATETIME
  {struct_codes}                : 核算单元过滤集，位于 cte_role_unpivot，默认注释态

  修改日志：
  2026-09-19 06:00:00 | 字段扩展 | 原始 HIS 执行科室全链透传：cte_role_unpivot 新增透传 j.[EXEC_DEPT_ID] /
                                j.[EXEC_DEPT_NAME] 并同步纳入 GROUP BY（HIS 科室成为增量粒度维度），
                                final 对应投影 EXEC_DEPT_ID / EXEC_DEPT_NAME，res 层输出中文别名
                                [原始HIS执行科室代码] / [原始HIS执行科室名称]，输出网格由 20 列扩展至 22 列；
                                列位紧随 [核算月份] 之后、[绩效核算单元编码] 之前，形成
                                「HIS 科室 ➔ 绩效核算单元」横向映射比对流向。最外层 WHERE 扩展位追加
                                HIS 科室过滤示例两行。注: fact_raw 与 joined 自建表起即已携带这两列
                                （并非本次解除剥离），本次仅补齐三段下游断链；三段式审计文本、
                                DECIMAL(18,8) 精度、NOLOCK 提示、双层出口封装结构零损毁。
                                粒度声明: 报表粒度由【单元 × 项目 × 角色】扩展为
                                【HIS科室 × 单元 × 项目 × 角色】，同一核算单元若由多 HIS 科室映射而来将
                                展开为多行（各 HIS 科室独立计量，血缘可回溯）；如需还原计算脚本的单元汇总态，
                                按 [绩效核算单元编码] 二次 SUM 即可。
  2026-09-19 05:00:00 | 出口封装 | 最外层二次封装（Envelope Slot Pattern）：将原 `SELECT ... FROM final AS f` 平铺
                                查询整体上收为 res CTE（层 1/2，纯投影零过滤），并在脚本末尾新增最外层查询
                                通道 `SELECT * FROM res WHERE 1=1 + ORDER BY`（层 2/2），内置「个性化查询扩展
                                插入位」注释态示例（核算单元 / 项目名称模糊 / 项目代码 / 执行角色 / 积分阈值 /
                                绩效大类六类）；上游 CTE 计算链（dept_dict → fact_raw → dim_version_scope →
                                dim_exec_ratio_raw → joined → cte_role_unpivot → final）与 20 列输出契约、
                                三段式审计文本、DECIMAL(18,8) 精度、占位符契约全程零改动（100% 冻结）。
  2026-09-19 04:00:00 | 脚本新建 | 依据 一次分配/医疗服务项目执行积分.sql 生成纯只读全过程明细报表：
                                剥离 Envelope 持久化区块（DELETE/INSERT/~ 分隔符）与 BIZ_EPOCH 内部哨兵，
                                完整保留 dept_dict → fact_raw → dim_version_scope → dim_exec_ratio_raw
                                → joined → cte_role_unpivot 计算链；在角色展开层补携带 [分摊执行比例]
                                原始值（计算脚本展开后即丢弃），使分摊比例与反推综合比例双态可验；
                                输出 20 列全平铺网格，含账期、核算单元、收费项目、大类、执行角色、
                                汇总数量/金额、单项 RVU 点数、分摊执行比例、反推综合执行比例、最终执行积分、
                                三段式计算过程描述及 RVU 维表快照属性（版本号/版本描述/诊疗决策系数/执行系数）。
=============================================================================== */



WITH dept_dict AS (
    -- ── Import CTE: 部门字典桥接层（事实层数值主键 [执行科室代码] → HIS 业务编码 [编码]） ──
    -- [id] 为物理主键聚簇，粒度 1:1；[编码] 桥接输出 VARCHAR(60)（与计算脚本同源）
    SELECT
        b.[id]                                          AS DEPT_ID
       ,CAST(b.[编码] AS VARCHAR(60))                    AS DEPT_CODE
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
)
,fact_raw AS (
    -- ── Import CTE: 事实层【执行科室 × 项目】预聚合（与计算脚本口径严格同源） ──
    -- 时间维度按 [来源] 动态分流：门诊 → [缴费时间]，非门诊 → [执行时间]；闭区间保障 SARGability。
    SELECT
        a.[项目代码]                                                AS PROJ_CODE
       ,a.[项目名称]                                                AS PROJ_NAME
       ,a.[执行科室代码]                                            AS EXEC_DEPT_ID
       ,a.[执行科室]                                                AS EXEC_DEPT_NAME
       ,d.[DEPT_CODE]                                               AS EXEC_DEPT_CODE_KEY
       ,CAST(SUM(CAST(a.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS QTY
       ,CAST(SUM(CAST(a.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS AMOUNT
    FROM dbo.[PF临时医疗服务项目26A] AS a WITH (NOLOCK)
    INNER JOIN dept_dict AS d
        ON a.[执行科室代码] = d.[DEPT_ID]
    WHERE 1=1
      AND (
              (a.[来源] = N'门诊' AND a.[缴费时间] >= CAST('{start_time}' AS DATETIME) AND a.[缴费时间] <= CAST('{end_time}' AS DATETIME))
           OR (ISNULL(a.[来源], '') <> N'门诊' AND a.[执行时间] >= CAST('{start_time}' AS DATETIME) AND a.[执行时间] <= CAST('{end_time}' AS DATETIME))
          )
    GROUP BY
        a.[项目代码]
       ,a.[项目名称]
       ,a.[执行科室代码]
       ,a.[执行科室]
       ,d.[DEPT_CODE]
)
,dim_version_scope AS (
    -- ── Import CTE: 绩效大类维度作用域（大类剔除前置剪枝；单版本 1:1 直连，零版本寻址） ──
    SELECT
        b.[PROJ_CODE]                               AS PROJ_CODE
       ,b.[RVU_VAL]                                 AS RVU_VAL
       ,b.[ITEM_CAT_CODE]                           AS ITEM_CAT_CODE
       ,b.[ITEM_CAT_NAME]                           AS ITEM_CAT_NAME
       ,b.[VERSION_NO]                              AS VERSION_NO
       ,b.[VERSION_DESC]                            AS VERSION_DESC
       ,b.[DECISION_COFF]                           AS DECISION_COFF
       ,b.[EXEC_COFF]                               AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS b WITH (NOLOCK)
    WHERE b.[ITEM_CAT_CODE] NOT IN ('1101', '1041')
      AND b.[PROJ_CODE] IS NOT NULL
)
,dim_exec_ratio_raw AS (
    -- ── Import CTE: 医技护执行划分维表作用域（仅取启用态规则，零折叠） ──
    SELECT
        r.[HIS_DEPT_CODE]                           AS HIS_DEPT_CODE
       ,r.[ITEM_CODE]                               AS ITEM_CODE
       ,r.[DOC_EXEC_RATIO]                          AS DOC_EXEC_RATIO
       ,r.[TECH_EXEC_RATIO]                         AS TECH_EXEC_RATIO
       ,r.[NURSE_EXEC_RATIO]                        AS NURSE_EXEC_RATIO
       ,r.[DOC_HPS_DEPT_CODE]                       AS DOC_HPS_DEPT_CODE
       ,r.[DOC_HPS_DEPT_NAME]                       AS DOC_HPS_DEPT_NAME
       ,r.[TECH_HPS_DEPT_CODE]                      AS TECH_HPS_DEPT_CODE
       ,r.[TECH_HPS_DEPT_NAME]                      AS TECH_HPS_DEPT_NAME
       ,r.[NURSE_HPS_DEPT_CODE]                     AS NURSE_HPS_DEPT_CODE
       ,r.[NURSE_HPS_DEPT_NAME]                     AS NURSE_HPS_DEPT_NAME
    FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS r WITH (NOLOCK)
    WHERE r.[IS_ENABLED] = 1
)

,joined AS (
    -- ── Logical CTE: 事实(预聚合) × 绩效大类维度 × 医技护执行划分（宽表三角色并列，供下游行转列消费） ──
    -- 注: 计算脚本内部哨兵 BIZ_EPOCH 在此不引入（契约 §8 严禁对外输出或参与聚合/分组）。
    SELECT
        f.[EXEC_DEPT_ID]                                                AS EXEC_DEPT_ID
       ,f.[EXEC_DEPT_NAME]                                              AS EXEC_DEPT_NAME
       ,f.[EXEC_DEPT_CODE_KEY]                                          AS EXEC_DEPT_CODE_KEY
       ,f.[PROJ_CODE]                                                   AS PROJ_CODE
       ,f.[PROJ_NAME]                                                   AS PROJ_NAME
       ,f.[QTY]                                                         AS QTY
       ,f.[AMOUNT]                                                      AS AMOUNT
       ,c.[ITEM_CAT_CODE]                                               AS ITEM_CAT_CODE
       ,c.[ITEM_CAT_NAME]                                               AS ITEM_CAT_NAME
       ,c.[RVU_VAL]                                                     AS RVU_VAL
       ,c.[VERSION_NO]                                                  AS VERSION_NO
       ,c.[VERSION_DESC]                                                AS VERSION_DESC
       ,c.[DECISION_COFF]                                               AS DECISION_COFF
       ,c.[EXEC_COFF]                                                   AS EXEC_COFF
       ,ISNULL(x.[DOC_EXEC_RATIO],   CAST(0.00000000 AS DECIMAL(18,8))) AS DOC_EXEC_RATIO
       ,ISNULL(x.[TECH_EXEC_RATIO],  CAST(0.00000000 AS DECIMAL(18,8))) AS TECH_EXEC_RATIO
       ,ISNULL(x.[NURSE_EXEC_RATIO], CAST(0.00000000 AS DECIMAL(18,8))) AS NURSE_EXEC_RATIO
       ,x.[DOC_HPS_DEPT_CODE]                                           AS DOC_HPS_DEPT_CODE
       ,x.[DOC_HPS_DEPT_NAME]                                           AS DOC_HPS_DEPT_NAME
       ,x.[TECH_HPS_DEPT_CODE]                                          AS TECH_HPS_DEPT_CODE
       ,x.[TECH_HPS_DEPT_NAME]                                          AS TECH_HPS_DEPT_NAME
       ,x.[NURSE_HPS_DEPT_CODE]                                         AS NURSE_HPS_DEPT_CODE
       ,x.[NURSE_HPS_DEPT_NAME]                                         AS NURSE_HPS_DEPT_NAME
    FROM fact_raw AS f
    INNER JOIN dim_version_scope AS c
        ON f.[PROJ_CODE] = c.[PROJ_CODE]
    LEFT JOIN dim_exec_ratio_raw AS x
        ON f.[EXEC_DEPT_CODE_KEY] = x.[HIS_DEPT_CODE]
       AND f.[PROJ_CODE]          = x.[ITEM_CODE]
)

,cte_role_unpivot AS (
    -- ── Intermediate CTE: 角色展开与核算单元预聚合（按【HIS科室 × 单元 × 项目 × 角色】收敛） ──
    -- 相较计算脚本的增量（2 处）：
    --   ① 透传 j.[EXEC_DEPT_ID] / j.[EXEC_DEPT_NAME] 原始 HIS 执行科室，暴露 HIS ➔ 绩效单元映射血缘；
    --   ② 同步携带 u.[EXEC_RATIO] 原始分摊比例（EXEC_RATIO_SRC），
    --      使「分摊比例 → 加权积分 → 反推综合比例」三态可在同一行内交叉验证。
    -- 注: 因 ① 引入新粒度维度，同一绩效核算单元若由多 HIS 科室映射而来将展开为多行（各 HIS 科室独立计量），
    --     这是本报表「血缘可回溯」的设计意图；如需还原计算脚本的单元汇总态，按 UNIT_CODE 二次 SUM 即可。
    SELECT
        j.[EXEC_DEPT_ID]                                                                AS EXEC_DEPT_ID
       ,j.[EXEC_DEPT_NAME]                                                              AS EXEC_DEPT_NAME
       ,u.[HPS_DEPT_CODE]                                                              AS HPS_DEPT_CODE
       ,u.[HPS_DEPT_NAME]                                                              AS HPS_DEPT_NAME
       ,j.[PROJ_CODE]                                                                  AS PROJ_CODE
       ,j.[PROJ_NAME]                                                                  AS PROJ_NAME
       ,j.[ITEM_CAT_CODE]                                                              AS ITEM_CAT_CODE
       ,j.[ITEM_CAT_NAME]                                                              AS ITEM_CAT_NAME
       ,j.[RVU_VAL]                                                                    AS RVU_VAL
       ,j.[VERSION_NO]                                                                 AS VERSION_NO
       ,j.[VERSION_DESC]                                                               AS VERSION_DESC
       ,j.[DECISION_COFF]                                                              AS DECISION_COFF
       ,j.[EXEC_COFF]                                                                  AS EXEC_COFF
       ,u.[ROLE_NAME]                                                                  AS EXEC_ROLE
       ,CAST(u.[EXEC_RATIO] AS DECIMAL(18,8))                                          AS EXEC_RATIO_SRC
       ,CAST(SUM(CAST(j.[QTY] AS DECIMAL(18,8))) AS DECIMAL(18,8))                     AS TOTAL_QTY
       ,CAST(SUM(CAST(j.[AMOUNT] AS DECIMAL(18,8))) AS DECIMAL(18,8))                  AS TOTAL_AMOUNT
       ,CAST(SUM(CAST(j.[QTY] * j.[RVU_VAL] * u.[EXEC_RATIO] AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS TOTAL_EXEC_POINTS
    FROM joined AS j
    CROSS APPLY (
        VALUES
              ('医生', j.[DOC_EXEC_RATIO],   j.[DOC_HPS_DEPT_CODE],   j.[DOC_HPS_DEPT_NAME])
             ,('技师', j.[TECH_EXEC_RATIO],  j.[TECH_HPS_DEPT_CODE],  j.[TECH_HPS_DEPT_NAME])
             ,('护士', j.[NURSE_EXEC_RATIO], j.[NURSE_HPS_DEPT_CODE], j.[NURSE_HPS_DEPT_NAME])
    ) AS u([ROLE_NAME], [EXEC_RATIO], [HPS_DEPT_CODE], [HPS_DEPT_NAME])
    WHERE 1=1
      -- ── 核算单元过滤集（默认注释态：保证未配置核算单元的行可被显式核查，防隐性漏计） ──
      -- AND u.[HPS_DEPT_CODE] IN {struct_codes}
      AND u.[EXEC_RATIO] > CAST(0.00000000 AS DECIMAL(18,8))
      AND u.[HPS_DEPT_CODE] IS NOT NULL
    GROUP BY
         j.[EXEC_DEPT_ID]
        ,j.[EXEC_DEPT_NAME]
        ,u.[HPS_DEPT_CODE]
        ,u.[HPS_DEPT_NAME]
        ,j.[PROJ_CODE]
        ,j.[PROJ_NAME]
        ,j.[ITEM_CAT_CODE]
        ,j.[ITEM_CAT_NAME]
        ,j.[RVU_VAL]
        ,j.[VERSION_NO]
        ,j.[VERSION_DESC]
        ,j.[DECISION_COFF]
        ,j.[EXEC_COFF]
        ,u.[ROLE_NAME]
        ,u.[EXEC_RATIO]
)
,final AS (
    -- ── Final CTE: 全过程出口契约（纯 1:1 投影 + 反推综合比例，零计算下推） ──
    SELECT
        CAST('{year}'  AS VARCHAR(10))                                                                     AS CALC_YEAR
       ,CAST('{month}' AS VARCHAR(10))                                                                     AS CALC_MONTH
       ,r.[EXEC_DEPT_ID]                                                                                   AS EXEC_DEPT_ID
       ,r.[EXEC_DEPT_NAME]                                                                                 AS EXEC_DEPT_NAME
       ,r.[HPS_DEPT_CODE]                                                                                  AS UNIT_CODE
       ,r.[HPS_DEPT_NAME]                                                                                  AS UNIT_NAME
       ,r.[PROJ_CODE]                                                                                      AS PROJ_CODE
       ,r.[PROJ_NAME]                                                                                      AS PROJ_NAME
       ,r.[ITEM_CAT_CODE]                                                                                  AS ITEM_CAT_CODE
       ,r.[ITEM_CAT_NAME]                                                                                  AS ITEM_CAT_NAME
       ,r.[EXEC_ROLE]                                                                                      AS EXEC_ROLE
       ,r.[EXEC_RATIO_SRC]                                                                                 AS EXEC_RATIO_SRC
       ,r.[TOTAL_QTY]                                                                                      AS QTY
       ,r.[TOTAL_AMOUNT]                                                                                   AS AMOUNT
       ,r.[RVU_VAL]                                                                                        AS RVU_VAL
       ,CAST(ISNULL(r.[TOTAL_EXEC_POINTS] / NULLIF(r.[TOTAL_QTY] * r.[RVU_VAL], 0), 0) AS DECIMAL(18,8))   AS EXEC_RATIO
       ,r.[TOTAL_EXEC_POINTS]                                                                              AS EXEC_POINTS
       ,r.[VERSION_NO]                                                                                     AS VERSION_NO
       ,r.[VERSION_DESC]                                                                                   AS VERSION_DESC
       ,r.[DECISION_COFF]                                                                                  AS DECISION_COFF
       ,r.[EXEC_COFF]                                                                                      AS EXEC_COFF
    FROM cte_role_unpivot AS r
)

-- =================================================================
-- ⟪ 出口插槽层 1/2 ⟫ res CTE：全过程明细平铺网格（纯投影，零持久化，零过滤）
-- 粒度: 绩效核算单元 × 收费项目 × 执行角色（与计算脚本落库粒度严格一致，可直接 SUM 对账）
-- 说明: 本 CTE 仅承担「中文列名投影 + 精度对齐 + 审计文本拼接」，不含任何 WHERE / ORDER BY，
--       确保下方最外层查询通道可对其做任意维度筛选而不改变任何计算口径。
-- =================================================================
,res AS (
SELECT
    f.[CALC_YEAR]                                                                AS [核算年份]
   ,f.[CALC_MONTH]                                                               AS [核算月份]
   ,f.[EXEC_DEPT_ID]                                                             AS [原始HIS执行科室代码]
   ,f.[EXEC_DEPT_NAME]                                                           AS [原始HIS执行科室名称]
   ,f.[UNIT_CODE]                                                                AS [绩效核算单元编码]
   ,f.[UNIT_NAME]                                                                AS [绩效核算单元名称]
   ,f.[PROJ_CODE]                                                                AS [收费项目代码]
   ,f.[PROJ_NAME]                                                                AS [收费项目名称]
   ,f.[ITEM_CAT_CODE]                                                            AS [绩效大类代码]
   ,f.[ITEM_CAT_NAME]                                                            AS [绩效大类名称]
   ,f.[EXEC_ROLE]                                                                AS [执行角色]
   ,CAST(f.[QTY] AS DECIMAL(18,8))                                               AS [汇总数量]
   ,CAST(f.[AMOUNT] AS DECIMAL(18,8))                                            AS [汇总金额]
   ,CAST(f.[RVU_VAL] AS DECIMAL(18,8))                                           AS [单项RVU点数]
   ,CAST(f.[EXEC_RATIO_SRC] AS DECIMAL(18,8))                                    AS [分摊执行比例]
   ,CAST(f.[EXEC_RATIO] AS DECIMAL(18,8))                                        AS [反推综合执行比例]
   ,CAST(f.[EXEC_POINTS] AS DECIMAL(18,8))                                       AS [最终执行积分]
   -- 三段式审计文本：[元数据段] | [中文逻辑公式段] | [纯数学代入算式段]
   -- 数学段落零汉字，运算符两侧强制保留 1 个半角空格（.clinerules 审计文本硬性表达规范）
   ,N'医疗服务执行积分 | 科室项目角色执行积分 = 汇总数量 × 单项RVU点数 × 执行比例 | '
        + CAST(CAST(f.[QTY] AS DECIMAL(18,8)) AS VARCHAR(50)) + N' × '
        + CAST(CAST(f.[RVU_VAL] AS DECIMAL(18,8)) AS VARCHAR(50)) + N' × '
        + CAST(CAST(f.[EXEC_RATIO] AS DECIMAL(18,8)) AS VARCHAR(50)) + N' = '
        + CAST(CAST(f.[EXEC_POINTS] AS DECIMAL(18,8)) AS VARCHAR(50))                 AS [计算过程描述]
   ,CAST(f.[VERSION_NO] AS VARCHAR(11))                                           AS [版本号]
   ,f.[VERSION_DESC]                                                              AS [版本描述]
   ,CAST(f.[DECISION_COFF] AS DECIMAL(18,8))                                      AS [诊疗决策系数]
   ,CAST(f.[EXEC_COFF] AS DECIMAL(18,8))                                          AS [执行系数]
FROM final AS f
)

-- =================================================================
-- ⟪ 出口插槽层 2/2 ⟫ 最外层查询通道（个性化筛选扩展位）
-- 用法: 在 WHERE 1=1 之后自由追加过滤条件，在 ORDER BY 处自由调整排序；
--       本层对上游计算链零侵入，任何筛选/排序均不影响 [最终执行积分] 等计算结果。
-- =================================================================
SELECT
    *
FROM res
WHERE 1=1
  -- ── 个性化查询扩展插入位（示例，按需取消注释） ──
  -- AND [原始HIS执行科室代码] = 100001
  -- AND [原始HIS执行科室名称] LIKE N'%门诊%'
  -- AND [绩效核算单元编码] = '100001'
  -- AND [绩效核算单元名称] LIKE N'%皮肤%'
  -- AND [收费项目代码] = '250403014'
  -- AND [执行角色] = N'医生'
  -- AND [最终执行积分] > 0
  -- AND [绩效大类代码] IN ('1001', '1002')
ORDER BY
    [绩效核算单元编码] ASC
   ,[收费项目代码] ASC
   ,[执行角色] ASC
;
