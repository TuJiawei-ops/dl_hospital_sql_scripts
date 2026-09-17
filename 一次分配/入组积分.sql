/* ===============================================================================
  Relative Path : 一次分配/入组积分.sql
  脚本名称     : 入组积分.sql
  分层归属     : 一次分配业务查询层
  业务定义     : 中医优势病种（白疕病 / 蛇串疮 / 蛇盘疮病）入组患者人次统计，
                 按结算年月 × 病种 × 绩效核算单元 × 执行人员类型 聚合计数。
  数据流向     : dbo.[ods_tcm_advantage_disease_patient_d] (事实层 · 中医优势病种入组患者明细)
                 ──▶ dbo.[sjjk_bmb_2025_06_01] (字典桥接 病人科室ID dept_code -> [编码])
                 ──▶ dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (HIS 编码 -> 绩效核算单元 × 执行人员类型)
                 ──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION] (RVU 点数维表 -> 单项点数与入组积分)

  ── 依赖契约 ──
  事实表 : dbo.[ods_tcm_advantage_disease_patient_d]
           [disease_code] VARCHAR(50) / [disease_name] NVARCHAR(100)
           [dept_code]    VARCHAR(50) / [settle_time]  DATETIME
  桥接表 : dbo.[sjjk_bmb_2025_06_01] ([id] bigint -> [编码] nvarchar(10))
  映射表 : dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27]（渐变维拉链表 SCD Type 2）
           [HIS_DEPT_CODE] varchar(300) / [HPS_DEPT_CODE] / [HPS_DEPT_NAME] varchar(300)
           [PERFORM_PERSON_TYPE_CODE] varchar(100) / [PERFORM_PERSON_TYPE] varchar(300)
           [START_DATE] datetime2(7) / [END_DATE] datetime2(7) —— 映射生效区间 [START_DATE, END_DATE]
  RVU维表: dbo.[DIM_PRF_ITEM_RVU_VERSION]
           主键 (ORG_CODE, VERSION_NO, PROJ_CODE, MEAS_UNIT)；
           [ORG_CODE] varchar(50) / [PROJ_CODE] varchar(50) / [RVU_VAL] numeric(12,4) NOT NULL DEFAULT 0.0000
           [VERSION_NO] varchar(20) / [VERSION_DESC] nvarchar(200) —— 降维为普通备注属性列

  ── 关键纠偏（防熵增） ──
  1. 【类型安全桥接】事实层 [dept_code] 为 VARCHAR(50) 字符串语义，桥接表 [id] 为 BIGINT，
     关联时必须单侧显式 CAST(bmb.[id] AS VARCHAR(50)) 对齐字符串域，
     严禁反向将 [dept_code] 整型化（防前导零丢失与索引失配）。
  2. 【维度降维切片】剔除 settle_time 物理列，仅派生 [结算年份] / [结算月份] 文本列，
     并按 .clinerules 第 7.2 节【明细层日期时间强制文本化】强制 CAST 为 VARCHAR。
  3. 【零黑箱收敛】禁用 MAX() / MIN() 折叠与 ROW_NUMBER() 开窗；两级映射 1:N 展开属业务真实语义，
     由 GROUP BY 全维度收敛，COUNT(1) 如实反映展开后的人次口径。
  4. 【拉链表时效闭环】映射表为渐变维拉链表（SCD Type 2），同一 [HIS_DEPT_CODE] 在多个映射版本
     下存在多条物理行。关联时必须将事实层 [settle_time] 锁定于映射生效区间之内（起点容忍空值、
     终点容忍空值），确保单时间点精准命中唯一有效切片；缺失该时序边界将导致旧版本历史映射与
     当期数据交叉匹配，引发 1:N 行级膨胀与人次计数翻倍。
  5. 【零版本寻址】RVU 维表 `DIM_PRF_ITEM_RVU_VERSION` 与衍生项目编码 1:1 直连读取，严禁使用
     ROW_NUMBER() OVER (PARTITION BY ... ORDER BY VERSION_NO DESC) 动态版本路由；
     [VERSION_NO] / [VERSION_DESC] 仅作普通备注属性列，不得作为主控过滤条件。
  6. 【积分口径】入组积分 = 入组人次 × 单项 RVU 点数，RVU 未配置时以 0 兜底（LEFT JOIN 保基数）。
     单项点数与积分全程锁定 DECIMAL(18,8) 精度（.clinerules 第 7 节）。

  ── 模板占位符（严禁破坏） ──
  '{start_time}': 核算开始时间 (如 '2024-01-01 00:00:00.000')
  '{end_time}'  : 核算结束时间 (如 '2024-01-31 23:59:59.997')
  {struct_codes}: 核算单元过滤集 (如 ('10001', '10002'))

  修改日志：
  2026-09-17 15:00:00 | 指标扩展 | 引入 RVU 关联与入组积分计算：SELECT 投影新增 CASE WHEN 衍生项目编码映射（A08.01.02×1001→'METRIC_DRG_DZHZ_DOCTOR'、A08.01.02×1002→'METRIC_DRG_DZHZ_NURSE'、A08.01.15×1001→'METRIC_DRG_YXB_DOCTOR'、A08.01.15×1002→'METRIC_DRG_YXB_NURSE'），并 LEFT JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION]（限定 ORG_CODE='1001'，零版本寻址 1:1 直连）取 [RVU_VAL]；新增导出 [衍生项目编码] / [RVU] / [入组积分]（= COUNT(1) × ISNULL(RVU_VAL,0)，DECIMAL(18,8) 精度），GROUP BY 同步纳入衍生项目编码表达式与 rvu.[RVU_VAL]；头部依赖契约与关键纠偏补录 RVU 维表血缘、零版本寻址与积分口径锚点；时间/占位符过滤与拉链时效边界零改动。
  2026-09-17 14:10:00 | 拉链时效闭环 | 映射表关联补全渐变维（SCD Type 2）时效边界：[settle_time] >= [START_DATE]（容忍 [START_DATE] 空值）且 [settle_time] <= [END_DATE]（容忍 [END_DATE] 空值）双条件下沉至 ON 子句，消除跨版本重叠匹配导致的行级膨胀与人次翻倍；同步在头部依赖契约与关键纠偏块补录拉链表时效闭环规范锚点。输出字段、降维粒度、占位符契约与 WHERE 过滤逻辑零改动。
  2026-09-17 13:40:00 | 脚本创建 | 初始创建入组积分查询脚本，实现时间降维切片（结算年份/结算月份文本化）、科室两级桥接映射（dept_code -> id -> [编码] -> HIS_DEPT_CODE）与人次统计（COUNT(1) AS [入组人次]）。
=============================================================================== */

SELECT
    CAST(YEAR(ods.[settle_time]) AS VARCHAR(4))     AS [结算年份]
   ,CAST(MONTH(ods.[settle_time]) AS VARCHAR(2))    AS [结算月份]
   ,ods.[disease_code]                              AS [病种编码]
   ,ods.[disease_name]                              AS [病种名称]
   ,m.[HPS_DEPT_CODE]                               AS [核算单元编码]
   ,m.[HPS_DEPT_NAME]                               AS [核算单元名称]
   ,m.[PERFORM_PERSON_TYPE_CODE]                    AS [执行人员类型编码]
   ,m.[PERFORM_PERSON_TYPE]                         AS [执行人员类型名称]
   -- 【衍生项目编码】病种 × 执行人员类型 条件分支映射，对齐 RVU 维表 PROJ_CODE 血统
   ,CASE
        WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_DZHZ_DOCTOR' AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_DZHZ_NURSE'  AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_YXB_DOCTOR'  AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_YXB_NURSE'   AS VARCHAR(50))
        ELSE CAST('UNKNOWN' AS VARCHAR(50))
    END                                              AS [衍生项目编码]
   ,COUNT(1)                                        AS [入组人次]
   -- 【单项点数】自 RVU 维表取值，未配置时以 0 兜底，全程锁定 DECIMAL(18,8) 精度
   ,ISNULL(CAST(rvu.[RVU_VAL] AS DECIMAL(18,8)), CAST(0 AS DECIMAL(18,8))) AS [RVU]
   -- 【入组积分】入组积分 = 入组人次 × 单项点数
   ,CAST(COUNT(1) * ISNULL(CAST(rvu.[RVU_VAL] AS DECIMAL(18,8)), CAST(0 AS DECIMAL(18,8))) AS DECIMAL(18,8)) AS [入组积分]
FROM dbo.[ods_tcm_advantage_disease_patient_d] AS ods WITH (NOLOCK)
INNER JOIN dbo.[sjjk_bmb_2025_06_01] AS bmb WITH (NOLOCK)
    ON ods.[dept_code] = CAST(bmb.[id] AS VARCHAR(50))
INNER JOIN dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    ON bmb.[编码] = m.[HIS_DEPT_CODE]
    -- 【拉链表时效闭环】渐变维 SCD Type 2 映射生效区间截面：结算时间必须落入 [START_DATE, END_DATE]
    -- 起点/终点均容忍空值（空值视为该侧无界），确保单结算时间点精准命中唯一有效映射切片
    AND (ods.[settle_time] >= m.[START_DATE] OR m.[START_DATE] IS NULL)
    AND (ods.[settle_time] <= m.[END_DATE] OR m.[END_DATE] IS NULL)
-- 【零版本寻址】RVU 维表 1:1 直连，严禁 ROW_NUMBER() OVER (... ORDER BY VERSION_NO DESC) 动态版本路由；
-- [VERSION_NO] / [VERSION_DESC] 降维为普通备注属性列，不作为主控过滤条件。
-- 使用 LEFT JOIN 保基数：衍生项目编码未配置 RVU 时不丢失入组人次事实行。
LEFT JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION] AS rvu WITH (NOLOCK)
    ON rvu.[PROJ_CODE] = CASE
                             WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DRG_DZHZ_DOCTOR'
                             WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DRG_DZHZ_NURSE'
                             WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN 'METRIC_DRG_YXB_DOCTOR'
                             WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN 'METRIC_DRG_YXB_NURSE'
                             ELSE NULL
                         END
    AND rvu.[ORG_CODE] = '1001'
-- 【格式规范】核算期间截面与动态单元过滤逐条独立换行，占位符条件独占一行并以 AND 开头
WHERE 1 = 1
    AND ods.[settle_time] >= '{start_time}'
    AND ods.[settle_time] <= '{end_time}'
    AND m.[HPS_DEPT_CODE] IN {struct_codes}
GROUP BY
    CAST(YEAR(ods.[settle_time]) AS VARCHAR(4))
   ,CAST(MONTH(ods.[settle_time]) AS VARCHAR(2))
   ,ods.[disease_code]
   ,ods.[disease_name]
   ,m.[HPS_DEPT_CODE]
   ,m.[HPS_DEPT_NAME]
   ,m.[PERFORM_PERSON_TYPE_CODE]
   ,m.[PERFORM_PERSON_TYPE]
   -- 【聚合收敛】衍生项目编码表达式必须完整纳入 GROUP BY，确保 COUNT(1) 按衍生维度正确聚合
   ,CASE
        WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_DZHZ_DOCTOR' AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.02' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_DZHZ_NURSE'  AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1001' THEN CAST('METRIC_DRG_YXB_DOCTOR'  AS VARCHAR(50))
        WHEN ods.[disease_code] = 'A08.01.15' AND m.[PERFORM_PERSON_TYPE_CODE] = '1002' THEN CAST('METRIC_DRG_YXB_NURSE'   AS VARCHAR(50))
        ELSE CAST('UNKNOWN' AS VARCHAR(50))
    END
   ,rvu.[RVU_VAL];
