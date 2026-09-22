/*
  Relative Path : analyses/RPT_UNMATCHED_RVU_ITEMS_CHECK.sql
  报表名称: 未配置 RVU 点数的医疗服务项目排查清单
  业务说明: 排查 dbo.[PF临时医疗服务项目26A] 中已有业务发生（2025-01-01 起 [开单时间]），
            但尚未在 dbo.[DIM_PRF_ITEM_RVU_VERSION] 配置的收费项目，输出缺失清单供运营补录。
            输出粒度: [项目大类] × [项目代码] × [项目名称]
  数据流向: dbo.[PF临时医疗服务项目26A]  (事实层, [项目代码] NVARCHAR(60) / [项目大类] NVARCHAR(60) NULL)
            ──(PROJ_CODE)──X──▶ dbo.[DIM_PRF_ITEM_RVU_VERSION]
                                 (RVU 点数维表, 复合主键 ORG_CODE + VERSION_NO + PROJ_CODE + MEAS_UNIT)
  口径声明: ① 单版本无状态匹配：维表主键含 VERSION_NO 与 MEAS_UNIT，同一 [PROJ_CODE] 可物理多行，
            故本脚本仅做「存在性判定」（已配置 / 未配置），不 JOIN 维表属性列，防行数膨胀。
            ② 时间边界 [开单时间] >= '2025-01-01' 为硬编码常量（非模板占位符），列侧无函数包裹保 SARGability。
            ③ 仅剔除非核算类八个大类，不施加绩效大类（ITEM_CAT_CODE）剪枝、不折叠、不寻版本。
  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: 全链路 WITH (NOLOCK)，只读排查不加锁，避免影响生产事实表写入。
  模板占位符: 无（时间边界为硬编码常量，不接受 '{year}' / '{month}' / '{struct_codes}' 注入）

  修改日志：
  2026-09-22 16:50:00 | 初始化 | 建立未配置 RVU 点数项目排查清单
  2026-09-22 16:50:00 | 优化 | NOT IN 剔除名单补全 N'卫生材料' 并增补 OR IS NULL 三值逻辑兜底
=============================================================================== */

SELECT
    s.[项目大类]                                                        AS [项目大类]
   ,s.[项目代码]                                                        AS [项目代码]
   ,s.[项目名称]                                                        AS [项目名称]
   ,CAST(s.[开单记录笔数] AS DECIMAL(18,8))                             AS [开单记录笔数]
   ,CAST(s.[累计发生数量] AS DECIMAL(18,8))                             AS [累计发生数量]
   ,CAST(s.[累计涉及金额] AS DECIMAL(18,8))                             AS [累计涉及金额]
   ,CONVERT(VARCHAR(19), s.[首次开单时间], 120)                         AS [首次开单时间]
   ,CONVERT(VARCHAR(19), s.[最近开单时间], 120)                         AS [最近开单时间]
FROM (
    -- 事实层【项目 × 大类】预聚合去重
    SELECT
        src.[项目大类]                                                  AS 项目大类
       ,src.[项目代码]                                                  AS 项目代码
       ,src.[项目名称]                                                  AS 项目名称
       ,COUNT(1)                                                       AS 开单记录笔数
       ,CAST(SUM(CAST(src.[数量] AS DECIMAL(18,8))) AS DECIMAL(18,8))   AS 累计发生数量
       ,CAST(SUM(CAST(src.[金额] AS DECIMAL(18,8))) AS DECIMAL(18,8))   AS 累计涉及金额
       ,MIN(src.[开单时间])                                             AS 首次开单时间
       ,MAX(src.[开单时间])                                             AS 最近开单时间
    FROM dbo.[PF临时医疗服务项目26A] AS src WITH (NOLOCK)
    WHERE 1=1
      AND src.[开单时间] >= '2025-01-01'
      AND src.[项目代码] IS NOT NULL
      -- 非核算项目大类剔除
      AND (
          src.[项目大类] NOT IN (N'西药费', N'中草药费', N'化验费', N'检查费', N'检验费', N'中成药费', N'卫生材料费', N'卫生材料')
          OR src.[项目大类] IS NULL
      )
      -- RVU 未配置判定（存在性语义，单版本无状态匹配）
      AND NOT EXISTS (
          SELECT 1
          FROM dbo.[DIM_PRF_ITEM_RVU_VERSION] AS rvu WITH (NOLOCK)
          WHERE rvu.[PROJ_CODE] = src.[项目代码]
      )
    GROUP BY
        src.[项目大类]
       ,src.[项目代码]
       ,src.[项目名称]
) AS s
ORDER BY
    s.[累计涉及金额] DESC
   ,s.[累计发生数量] DESC
   ,s.[项目代码] ASC
;
