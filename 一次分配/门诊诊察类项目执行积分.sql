/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分.sql
  脚本名称: 门诊诊察类项目执行积分.sql
  业务说明: 门诊诊察类项目（绩效大类 ITEM_CAT_CODE = '1043'）按日汇总执行数据抽取，
            供门诊诊察工作量分配测算消费。

  数据流向: dbo.[PF临时医疗服务项目26A]               (事实·医疗服务项目明细)
            ──▶ INNER JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION] (维表·绩效项目 RVU 属性)
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
  9. 【事实表孤儿行】：本脚本为汇总宽表（非分配结果），采用 INNER JOIN，
     未命中维表配置的项目明细将被剔除，属预期收缩行为；如需做配置缺口盘点，
     请另行编写 LEFT JOIN 反查脚本，严禁在本文件内混用两种口径。
 10. 【查询提示】：事实表与维表均加 WITH (NOLOCK)，明细抽取不加锁、不阻塞业务写入。

  ── 输出粒度 ──
  每行 = 按天+科室+人员+项目 汇总后的诊察执行数据。患者级明细
  （[HIS主键] / [患者ID] / [挂号ID]）已剔除，不可逆。

  修改日志：
  2026-09-15 10:55:00 | 粒度重构 | 剔除 HIS主键/患者ID/挂号ID 患者级主键，三个时间列 CAST AS DATE 截断按日，
                                 引入 GROUP BY 并对 数量/金额 执行 SUM 聚合；过滤项精简为仅 ITEM_CAT_CODE
  2026-09-15 10:20:00 | 脚本新建 | 新建门诊诊察类项目（1043）执行明细基础查询，事实表×RVU 维表 INNER JOIN 宽表抽取
=============================================================================== */


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

    -- ── 开单环节（时间为按日截断） ──
   ,f.[开单科室代码]                                          AS [开单科室代码]
   ,f.[开单科室]                                              AS [开单科室]
   ,f.[开单人员代码]                                          AS [开单人员代码]
   ,f.[开单人]                                                AS [开单人]
   ,CAST(f.[开单时间] AS DATE)                                 AS [开单日期]

    -- ── 执行环节（门诊诊察类绩效归属的核心维度） ──
   ,f.[执行科室代码]                                          AS [执行科室代码]
   ,f.[执行科室]                                              AS [执行科室]
   ,f.[执行人员代码]                                          AS [执行人员代码]
   ,f.[执行人员]                                              AS [执行人员]
   ,CAST(f.[执行时间] AS DATE)                                 AS [执行日期]

    -- ── 结算环节（时间为按日截断） ──
   ,CAST(f.[缴费时间] AS DATE)                                 AS [缴费日期]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN (
    -- ── 维表作用域：编码硬匹配 1043 + 按 PROJ_CODE 聚合归一，消除多版本一对多放大风险 ──
    SELECT
        v0.[PROJ_CODE]                     AS PROJ_CODE
       ,MAX(v0.[ITEM_CAT_CODE])            AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])            AS ITEM_CAT_NAME
       ,CAST(MAX(v0.[RVU_VAL])   AS DECIMAL(18,8)) AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF]) AS DECIMAL(18,8)) AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND v0.[ITEM_CAT_CODE] = '1043'
    GROUP BY v0.[PROJ_CODE]
) AS v
    ON f.[项目代码] = v.[PROJ_CODE]
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
   ,f.[开单人员代码]
   ,f.[开单人]
   ,CAST(f.[开单时间] AS DATE)
   ,f.[执行科室代码]
   ,f.[执行科室]
   ,f.[执行人员代码]
   ,f.[执行人员]
   ,CAST(f.[执行时间] AS DATE)
   ,CAST(f.[缴费时间] AS DATE);
