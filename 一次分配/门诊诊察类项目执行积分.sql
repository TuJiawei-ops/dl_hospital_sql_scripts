/* ===============================================================================
  Relative Path : 一次分配/门诊诊察类项目执行积分.sql
  脚本名称: 门诊诊察类项目执行积分.sql
  业务说明: 门诊诊察类项目（绩效大类 ITEM_CAT_CODE = '1043' / N'门诊诊察类'）执行明细
            与绩效项目 RVU 属性宽表抽取，供门诊诊察工作量分配测算消费。

  数据流向: dbo.[PF临时医疗服务项目26A]               (事实·医疗服务项目明细)
            ──▶ INNER JOIN dbo.[DIM_PRF_ITEM_RVU_VERSION] (维表·绩效项目 RVU 属性)
            ──▶ SELECT (ADS 应用报表/分配计算层)

  ── 核心架构与约束规范（极简版） ──
  1. 【大类前置剪枝】：维表作用域收缩在 dim_rvu_scope 内完成（仅保留 1043），
     严禁将过滤条件下沉至最终 SELECT 或写成 LEFT JOIN 后过滤，避免全表膨胀后再剪枝。
  2. 【PROJ_CODE 聚合归一】：维表按 [PROJ_CODE] 一对多（多版本 / 多机构 / 多计费单位）
     时必须先 GROUP BY 收敛，否则事实明细将被维表行数放大（卡特兰积扩散），
     导致 [数量] / [金额] 被重复计入绩效测算。收敛口径：RVU_VAL / EXEC_COFF 取 MAX。
  3. 【计量单位口径】：事实表 [数量] 为实际计费数量，维表 RVU_VAL 为单次点数（点数/计量单位），
     执行点数 = [数量] × [RVU_VAL] × [EXEC_COFF]，该乘积为下游积分测算的统一入口，
     本脚本仅提供原料列，不在本层做乘法预计算。
  4. 【全精度对齐】：维表 RVU_VAL 源物理类型为 numeric(12,4)、EXEC_COFF 为 decimal(5,4)，
     统一 CAST 至 DECIMAL(18,8) 输出，杜绝低精度截断在下游聚合时被放大。
  5. 【事实表孤儿行】：本脚本为明细宽表（非分配结果），采用 INNER JOIN，
     未命中维表配置的项目明细将被剔除，属预期收缩行为；如需做配置缺口盘点，
     请另行编写 LEFT JOIN 反查脚本，严禁在本文件内混用两种口径。
  6. 【查询提示】：事实表与维表均加 WITH (NOLOCK)，明细抽取不加锁、不阻塞业务写入。

  ── 输出粒度 ──
  每行 = 一条医疗服务项目执行明细（由 [HIS主键] + [来源] 唯一标识），非聚合结果。

  修改日志：
  2026-09-15 10:20:00 | 脚本新建 | 新建门诊诊察类项目（1043）执行明细基础查询，事实表×RVU 维表 INNER JOIN 宽表抽取
=============================================================================== */


SELECT
    -- ── 事实层主键与来源标识（行级唯一粒度） ──
    f.[HIS主键]                                              AS [HIS主键]
   ,f.[来源]                                                 AS [来源]

    -- ── 项目基础信息（事实层口径） ──
   ,f.[项目大类]                                             AS [项目大类]
   ,f.[项目代码]                                             AS [项目代码]
   ,f.[项目名称]                                             AS [项目名称]

    -- ── 绩效属性（维表层：大类归属 / 点数 / 执行系数） ──
   ,v.[ITEM_CAT_CODE]                                        AS [绩效大类编码]
   ,v.[ITEM_CAT_NAME]                                        AS [绩效大类名称]
   ,CAST(v.[RVU_VAL]   AS DECIMAL(18,8))                     AS [项目点数]
   ,CAST(v.[EXEC_COFF] AS DECIMAL(18,8))                     AS [执行系数]

    -- ── 收费计量（数量 / 单价 / 金额） ──
   ,CAST(f.[数量] AS DECIMAL(18,8))                          AS [数量]
   ,CAST(f.[单价] AS DECIMAL(18,8))                          AS [单价]
   ,CAST(f.[金额] AS DECIMAL(18,8))                          AS [金额]

    -- ── 开单环节 ──
   ,f.[开单科室代码]                                         AS [开单科室代码]
   ,f.[开单科室]                                             AS [开单科室]
   ,f.[开单人员代码]                                         AS [开单人员代码]
   ,f.[开单人]                                               AS [开单人]
   ,f.[开单时间]                                             AS [开单时间]

    -- ── 执行环节（门诊诊察类绩效归属的核心维度） ──
   ,f.[执行科室代码]                                         AS [执行科室代码]
   ,f.[执行科室]                                             AS [执行科室]
   ,f.[执行人员代码]                                         AS [执行人员代码]
   ,f.[执行人员]                                             AS [执行人员]
   ,f.[执行时间]                                             AS [执行时间]

    -- ── 结算与患者标识 ──
   ,f.[缴费时间]                                             AS [缴费时间]
   ,f.[患者ID]                                               AS [患者ID]
   ,f.[挂号ID]                                               AS [挂号ID]
FROM dbo.[PF临时医疗服务项目26A] AS f WITH (NOLOCK)
INNER JOIN (
    -- ── 维表作用域：按 PROJ_CODE 聚合归一，消除多版本/多机构一对多放大风险 ──
    SELECT
        v0.[PROJ_CODE]                     AS PROJ_CODE
       ,MAX(v0.[ITEM_CAT_CODE])            AS ITEM_CAT_CODE
       ,MAX(v0.[ITEM_CAT_NAME])            AS ITEM_CAT_NAME
       ,CAST(MAX(v0.[RVU_VAL])   AS DECIMAL(18,8)) AS RVU_VAL
       ,CAST(MAX(v0.[EXEC_COFF]) AS DECIMAL(18,8)) AS EXEC_COFF
    FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS v0 WITH (NOLOCK)
    WHERE v0.[PROJ_CODE] IS NOT NULL
      AND (v0.[ITEM_CAT_CODE] = '1043' OR v0.[ITEM_CAT_NAME] = N'门诊诊察类')
    GROUP BY v0.[PROJ_CODE]
) AS v
    ON f.[项目代码] = v.[PROJ_CODE];
