/* ===============================================================================
  Relative Path : analyses/检查有比例但无核算单元编码或名称异常明细.sql
  脚本名称: 检查有比例但无核算单元编码或名称异常明细.sql
  报表名称: DIM_DEPT_ITEM_EXEC_RATIO「有比例无核算单元」双缺排查明细
  业务说明: 排查 dbo.[DIM_DEPT_ITEM_EXEC_RATIO] 中，四类执行角色（医生 / 技师 / 护士 / 临床）
            存在执行比例（> 0）但缺失对应核算单元编码（*_HPS_DEPT_CODE）
            或核算单元名称（*_HPS_DEPT_NAME）的异常配置数据。
            防止出现「有比例、有编码但名称丢失」或「有比例、编码名称双空」的血缘断裂，
            输出异常明细清单供业务补全核算单元映射。
            输出粒度: 维表单行粒度（HIS 科室 × 收费项目，IS_ENABLED = 1 下业务唯一）
  数据流向: dbo.[DIM_DEPT_ITEM_EXEC_RATIO] (医技护临执行划分维表，生效态 IS_ENABLED = 1)
  校验口径: ① 作用域仅限启用态 IS_ENABLED = 1（与生产计算脚本消费口径一致，
            停用历史行不参与校验，避免废弃数据制造噪声）。
            ② 四类角色统一执行「(执行比例 > 0) AND (编码缺失 OR 名称缺失)」双重防错校验，
            编码/名称缺失判定均以 ISNULL(列, '') = '' 口径统一覆盖 NULL 与空串两种形态，
            杜绝仅判 NULL 而漏判 '' 的隐性逃逸。
            ③ 四角色之间为 OR 并列关系，同一行命中任一角色即整行输出；
            命中角色需由业务侧结合下方比例与编码/名称列对号入座。
            ④ 判定基准为执行比例 > 0：未配置该角色（比例默认 0.00000000）时天然短路剔除，零误报。
  只读声明: 纯 SELECT 排查脚本，无任何 INSERT / UPDATE / DELETE / DDL 副作用（零持久化、零落库）。
  查询提示: WITH (NOLOCK) 只读排查不加锁，避免影响维表写入。
  模板占位符: 无（维表全量扫描，不接受 '{year}' / '{month}' / '{struct_codes}' 注入）

  修改日志：
  2026-09-23 10:00:00 | 脚本新建 | 建立「有比例无核算单元」双缺排查脚本，覆盖医生/技师/护士/临床四角色编码与名称缺失校验
=============================================================================== */

SELECT
    r.[ID]                                                            AS [ID]
   ,r.[HIS_DEPT_CODE]                                                 AS [HIS科室编码]
   ,r.[HIS_DEPT_NAME]                                                 AS [HIS科室名称]
   ,r.[ITEM_CODE]                                                     AS [项目代码]
   ,r.[ITEM_NAME]                                                     AS [项目名称]
   -- 医生角色配置
   ,r.[DOC_EXEC_RATIO]                                                AS [医生执行比例]
   ,r.[DOC_HPS_DEPT_CODE]                                             AS [医生对应核算单元编码]
   ,r.[DOC_HPS_DEPT_NAME]                                             AS [医生对应核算单元名称]
   -- 技师角色配置
   ,r.[TECH_EXEC_RATIO]                                               AS [技师执行比例]
   ,r.[TECH_HPS_DEPT_CODE]                                            AS [技师对应核算单元编码]
   ,r.[TECH_HPS_DEPT_NAME]                                            AS [技师对应核算单元名称]
   -- 护士角色配置
   ,r.[NURSE_EXEC_RATIO]                                              AS [护士执行比例]
   ,r.[NURSE_HPS_DEPT_CODE]                                           AS [护士对应核算单元编码]
   ,r.[NURSE_HPS_DEPT_NAME]                                           AS [护士对应核算单元名称]
   -- 临床角色配置
   ,r.[CLINICAL_EXEC_RATIO]                                           AS [临床执行比例]
   ,r.[CLINICAL_HPS_DEPT_CODE]                                        AS [临床对应核算单元编码]
   ,r.[CLINICAL_HPS_DEPT_NAME]                                        AS [临床对应核算单元名称]
   ,r.[IS_ENABLED]                                                    AS [启用状态]
FROM dbo.[DIM_DEPT_ITEM_EXEC_RATIO] AS r WITH (NOLOCK)
WHERE r.[IS_ENABLED] = 1 -- 仅校验当前启用态配置
      AND (
          -- 1. 医生角色：有比例，但编码或名称缺失
          (r.[DOC_EXEC_RATIO] > 0 AND (ISNULL(r.[DOC_HPS_DEPT_CODE], '') = '' OR ISNULL(r.[DOC_HPS_DEPT_NAME], '') = ''))
          OR
          -- 2. 技师角色：有比例，但编码或名称缺失
          (r.[TECH_EXEC_RATIO] > 0 AND (ISNULL(r.[TECH_HPS_DEPT_CODE], '') = '' OR ISNULL(r.[TECH_HPS_DEPT_NAME], '') = ''))
          OR
          -- 3. 护士角色：有比例，但编码或名称缺失
          (r.[NURSE_EXEC_RATIO] > 0 AND (ISNULL(r.[NURSE_HPS_DEPT_CODE], '') = '' OR ISNULL(r.[NURSE_HPS_DEPT_NAME], '') = ''))
          OR
          -- 4. 临床角色：有比例，但编码或名称缺失
          (r.[CLINICAL_EXEC_RATIO] > 0 AND (ISNULL(r.[CLINICAL_HPS_DEPT_CODE], '') = '' OR ISNULL(r.[CLINICAL_HPS_DEPT_NAME], '') = ''))
      )
ORDER BY
    r.[HIS_DEPT_CODE] ASC
   ,r.[ITEM_CODE] ASC
;
