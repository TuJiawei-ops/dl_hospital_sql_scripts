/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分.sql
  脚本名称: 门诊诊察类项目执行积分.sql
  业务说明: 门诊诊察类项目（绩效大类 ITEM_CAT_CODE = '1043'）按日汇总执行数据抽取，
            并补全开单/执行环节的绩效核算单元，供门诊诊察工作量分配测算消费。

  数据流向: dbo.[PF临时医疗服务项目26A]                        (事实·医疗服务项目明细)
            ──▶ INNER JOIN cte_rvu  ← dbo.[DIM_PRF_ITEM_RVU_VERSION]     (维表·绩效项目 RVU 属性)
            ──▶ LEFT JOIN  cte_bmb  ← dbo.[sjjk_bmb_2025_06_01]          (桥接·部门 id → 编码)
            ──▶ LEFT JOIN  cte_dept_map ← dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] (维表·部门编码 → 绩效核算单元)
            ──▶ GROUP BY 按日汇总 (ADS 应用报表/分配计算层)

  ── 核心架构与约束规范（极简版） ──
  1. 【大类前置剪枝】：维表作用域收缩在维表子查询内完成（仅保留 1043），
     严禁将过滤条件下沉至最终 SELECT 或写成 LEFT JOIN 后过滤，避免全表膨胀后再剪枝。
  2. 【编码唯一判据】：仅以主键编码 [ITEM_CAT_CODE] = '1043' 硬匹配。
     严禁叠加 [ITEM_CAT_NAME] 中文名称匹配——名称属可维护文案，配置侧一次误改
     即导致整类项目静默漏抽，且不报任何错误。
  3. 【PROJ_CODE 聚合归一】：维表按 [PROJ_CODE] 一对多（多版本 / 多机构 / 多计费单位）
     时必须先 GROUP BY 收敛，否则事实明细将被维表行数放大（卡特兰积扩散），
     导致 [数量] / [金额] 被重复计入绩效测算。收敛口径：RVU_VAL / EXEC_COFF 取 MAX。
  4. 【计量单位口径】：事实表 [数量] 为实际计费数量，维表 RVU_VAL 为单次点数（点数/计量单位），
     执行点数 = [数量] × [RVU_VAL] × [EXEC_COFF]，该乘积为下游积分测算的统一入口，
     本脚本仅提供原料列，不在本层做乘法预计算。
  5. 【全精度对齐】：维表 RVU_VAL 源物理类型为 numeric(12,4)、EXEC_COFF 为 decimal(5,4)，
     统一 CAST 至 DECIMAL(18,8) 输出；度量 [数量] / [金额] 先 CAST 后 SUM，
     杜绝低精度截断在下游聚合时被放大。
  6. 【时间收敛为日】：[开单时间] / [执行时间] / [缴费时间] 统一 CAST(... AS DATE) 截断至
     YYYY-MM-DD 参与分组。严禁使用 CONVERT(VARCHAR(10), ..., 120) 等字符串化截断，
     避免输出层字符串参与日期比较与排序时产生隐式转换与索引失效。
  7. 【单价保留为维度】：[单价] 保留在 GROUP BY 中而非取 MAX——单价变更必然产生独立行，
     强行折叠会掩盖调价事实。
  8. 【汇总口径的业务含义】：SUM([数量]) / SUM([金额]) 在跨 [单价] 维度分组后，
     单组内单价唯一，故金额 = 数量 × 单价关系在该组内严格成立；与患者级明细不构成
     行数可逆关系，如需患者级追溯请另行编写明细脚本。
  9. 【事实表孤儿行】：本脚本为汇总宽表（非分配结果），RVU 维表采用 INNER JOIN，
     未命中维表配置的项目明细将被剔除，属预期收缩行为；如需做配置缺口盘点，
     请另行编写 LEFT JOIN 反查脚本，严禁在本文件内混用两种口径。
     （注：核算单元链路的 cte_bmb / cte_dept_map 必须保持 LEFT JOIN，见第 11 条。）
 10. 【查询提示】：事实表与维表均加 WITH (NOLOCK)，明细抽取不加锁、不阻塞业务写入。
 11. 【核算单元三层桥接】：事实层 [开单/执行科室代码] 为 BIGINT 主键 id，必须
     经 cte_bmb([id] → [编码]) 换算为 HIS 部门编码后，再以 [编码] = [HIS_DEPT_CODE]
     关联 cte_dept_map 提取 [HPS_DEPT_CODE] / [HPS_DEPT_NAME]。严禁跳过 cte_bmb
     直接用事实层 id 去撞映射表编码列（数值与业务编码跨语义，全量失配）。
 12. 【核算单元链路零收缩】：开单/执行两条核算单元链路一律 LEFT JOIN。映射表为
     人工维护配置，未配置部门属常态，若用 INNER JOIN 会静默丢弃整段诊察执行明细。
 13. 【映射表剪枝前置】：cte_dept_map 在 CTE 内硬过滤 PERFORM_PERSON_TYPE_CODE = '1001'
     并按 [HIS_DEPT_CODE] 分组收敛。该表主键为 (ID, HIS_DEPT_CODE)，同一编码在拉链
     多版本下必然重复，不收敛将按映射行数放大 [数量] / [金额]（卡特兰积扩散）。
 14. 【源列零改造】：[编码] nvarchar(10) / [HIS_DEPT_CODE]·[HPS_DEPT_CODE]·[HPS_DEPT_NAME]
     varchar(300) 均为字符串源列，关联与输出一律裸引用原列，严禁叠加冗余 CAST。
     事实层 [开单/执行科室代码] BIGINT 与 cte_bmb.[id] BIGINT 物理类型天然对齐，
     同样无需转换（严禁为规避格式问题而 CAST 为字符串或整型改造）。

  ── 输出粒度 ──
  每行 = 按天+科室+核算单元+人员+项目 汇总后的诊察执行数据。患者级明细
  （[HIS主键] / [患者ID] / [挂号ID]）已剔除，不可逆。

  修改日志：
  2026-09-15 11:40:00 | 关联链路纠正 | 纠正科室三层血缘链路：新增 cte_bmb（部门 [id]→[编码] 桥接）与
                                  cte_dept_map（映射表 PERFORM_PERSON_TYPE_CODE='1001' 前置剪枝 + 按
                                  [HIS_DEPT_CODE] 收敛）；开单/执行两条链路均以 LEFT JOIN 补全
                                  [开单绩效核算单元编码/名称] 与 [执行绩效核算单元编码/名称] 四个字段，
                                  并同步纳入 GROUP BY 粒度。RVU 维表由内联子查询提升为 cte_rvu，
                                  其 PROJ_CODE 聚合收敛口径（RVU_VAL/EXEC_COFF 取 MAX）零改动。
  2026-09-15 10:55:00 | 粒度重构 | 剔除 HIS主键/患者ID/挂号ID 患者级主键，三个时间列 CAST AS DATE 截断按日，
                                 引入 GROUP BY 并对 数量/金额 执行 SUM 聚合；过滤项精简为仅 ITEM_CAT_CODE
  2026-09-15 10:20:00 | 脚本新建 | 新建门诊诊察类项目（1043）执行明细基础查询，事实表×RVU 维表 INNER JOIN 宽表抽取
=============================================================================== */


WITH cte_rvu AS (
    -- ── 维表作用域：编码硬匹配 1043 + 按 PROJ_CODE 聚合归一，消除多版本一对多放大风险 ──
    SELECT
        v0.[PROJ_CODE]                              AS PROJ_CODE
       ,MAX(v0.[ITEM_CAT_CODE])                     AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])                     AS ITEM_CAT_NAME
       ,CAST(MAX(v0.[RVU_VAL])   AS DECIMAL(18,8))  AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF]) AS DECIMAL(18,8))  AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
)
,cte_bmb AS (
    -- ── 桥接层：事实层数值主键 id → HIS 业务编码（原值直连，零格式化加工） ──
    SELECT
        b.[id]                                      AS id
       ,MAX(b.[编码])                               AS dept_code
    FROM dbo.[sjjk_bmb_2025_06_01] AS b WITH (NOLOCK)
    WHERE b.[id] IS NOT NULL
    GROUP BY b.[id]
)
,cte_dept_map AS (
    -- ── 映射层：HIS 部门编码 → 绩效核算单元（'1001' 前置硬剪枝 + 编码分组收敛） ──
    SELECT
        m.[HIS_DEPT_CODE]                           AS HIS_DEPT_CODE
       ,MAX(m.[HPS_DEPT_CODE])                      AS HPS_DEPT_CODE
       ,MAX(m.[HPS_DEPT_NAME])                      AS HPS_DEPT_NAME
    FROM dbo.[sjjk_DEPT_UNIT_MAPPING_2025_11_27] AS m WITH (NOLOCK)
    WHERE m.[PERFORM_PERSON_TYPE_CODE] = '1001'
      AND m.[HIS_DEPT_CODE] IS NOT NULL
    GROUP BY m.[HIS_DEPT_CODE]
)
SELECT
    -- ── 来源标识 ──
    f.[来源]                                                  AS [来源]

    -- ── 项目基础信息（事实层口径） ──
   ,f.[项目大类]                                              AS [项目大类]
   ,f.[项目代码]                                              AS [项目代码]
   ,f.[项目名称]                                              AS [项目名称]

    -- ── 绩效属性（维表层：大类归属 / 点数 / 执行系数） ──
   ,v.[ITEM_CAT_CODE]                                         AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                         AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                      AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                      AS [执行系数]

    -- ── 收费计量（尺度：单价为维度，数量/金额为度量） ──
   ,CAST(f.[单价] AS DECIMAL(18,8))                           AS [单价]
   ,SUM(CAST(f.[数量] AS DECIMAL(18,8)))                      AS [数量]
   ,SUM(CAST(f.[金额] AS DECIMAL(18,8)))                      AS [金额]

    -- ── 开单环节（id → 编码 → 绩效核算单元；时间为按日截断） ──
   ,f.[开单科室代码]                                          AS [开单科室代码]
   ,f.[开单科室]                                              AS [开单科室]
   ,map_open.[HPS_DEPT_CODE]                                  AS [开单绩效核算单元编码]
   ,map_open.[HPS_DEPT_NAME]                                  AS [开单绩效核算单元名称]
   ,f.[开单人员代码]                                          AS [开单人员代码]
   ,f.[开单人]                                                AS [开单人]
   ,CAST(f.[开单时间] AS DATE)                                 AS [开单日期]

    -- ── 执行环节（门诊诊察类绩效归属的核心维度；id → 编码 → 绩效核算单元） ──
   ,f.[执行科室代码]                                          AS [执行科室代码]
   ,f.[执行科室]                                              AS [执行科室]
   ,map_exec.[HPS_DEPT_CODE]                                  AS [执行绩效核算单元编码]
   ,map_exec.[HPS_DEPT_NAME]                                  AS [执行绩效核算单元名称]
   ,f.[执行人员代码]                                          AS [执行人员代码]
   ,f.[执行人员]                                              AS [执行人员]
   ,CAST(f.[执行时间] AS DATE)                                 AS [执行日期]

    -- ── 结算环节（时间为按日截断） ──
   ,CAST(f.[缴费时间] AS DATE)                                 AS [缴费日期]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN cte_rvu AS v
    ON f.[项目代码] = v.[PROJ_CODE]
-- 开单科室链路：id → 部门编码 → 绩效核算单元（全程 LEFT JOIN，未配置映射不收缩事实行）
LEFT JOIN cte_bmb AS bmb_open
    ON f.[开单科室代码] = bmb_open.[id]
LEFT JOIN cte_dept_map AS map_open
    ON bmb_open.[dept_code] = map_open.[HIS_DEPT_CODE]
-- 执行科室链路：id → 部门编码 → 绩效核算单元（全程 LEFT JOIN，未配置映射不收缩事实行）
LEFT JOIN cte_bmb AS bmb_exec
    ON f.[执行科室代码] = bmb_exec.[id]
LEFT JOIN cte_dept_map AS map_exec
    ON bmb_exec.[dept_code] = map_exec.[HIS_DEPT_CODE]
GROUP BY
    f.[来源]
   ,f.[项目大类]
   ,f.[项目代码]
   ,f.[项目名称]
   ,v.[ITEM_CAT_CODE]
   ,v.[ITEM_CAT_NAME]
   ,v.[RVU_VAL]
   ,v.[EXEC_COFF]
   ,CAST(f.[单价] AS DECIMAL(18,8))
   ,f.[开单科室代码]
   ,f.[开单科室]
   ,map_open.[HPS_DEPT_CODE]
   ,map_open.[HPS_DEPT_NAME]
   ,f.[开单人员代码]
   ,f.[开单人]
   ,CAST(f.[开单时间] AS DATE)
   ,f.[执行科室代码]
   ,f.[执行科室]
   ,map_exec.[HPS_DEPT_CODE]
   ,map_exec.[HPS_DEPT_NAME]
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,CAST(f.[执行时间] AS DATE)
   ,CAST(f.[缴费时间] AS DATE)
;

