/* ===============================================================================
  脚本名称: UPDATE_DIM_DEPT_ITEM_EXEC_RATIO_HPS_MAPPING.sql
  文件路径: sqlserver\patches\UPDATE_DIM_DEPT_ITEM_EXEC_RATIO_HPS_MAPPING.sql
  脚本类型: DML 数据刷洗补丁（一次性执行，非表结构 DDL）
  目标表  : dbo.[DIM_DEPT_ITEM_EXEC_RATIO]
  业务说明: 以旧暂存列 [DOC_HPS_DEPT_NAME] 为映射匹配基准，将原单一核算单元映射基线
            刷洗为医技护三路独立核算单元映射（编码 + 名称）。
  映射基准: CTE_MAP 内存映射集（VALUES 内联常量表），
            MATCH_KEY = 原 [DOC_HPS_DEPT_NAME] 旧值（字符串精确匹配，无前导零 CAST）。
  -------------------------------------------------------------------------------
  【匹配键物理事实声明 —— 执行前必读】
  作为 MATCH_KEY 的旧暂存列 [DOC_HPS_DEPT_NAME] 是全表唯一的来源依据。
  若该列在目标库中不存在，或未能预先回填旧值，则 CTE_MAP 将零行命中，
  本脚本 UPDATE 影响行数 = 0，核算单元编码列将全量保持 NULL。
  本脚本不内置任何兜底回填逻辑（严禁臆造旧值），执行前请先核对该列存在性与填充率。
  -------------------------------------------------------------------------------
  【角色映射口径】
  · 三角色同源（DOC = TECH = NURSE）: 激光美容科医生护士工勤 / 手术室（麻醉医生、护士） / 药剂科
  · 仅写 DOC 与 NURSE（TECH 显式置 NULL）: 治疗科 / 外科（含门诊、病房）/ 变态反应科 / 毛发
                                          / 日间治疗中心 / 中医美容科 / 皮肤科 / 皮肤科护士（处置室等）
                                          / 中医外治科 / 性病科（含门诊、病房）
                                          / 皮肤一病房 / 皮肤二病房 / 皮肤三病房
  · 仅写 DOC（TECH / NURSE 显式置 NULL）: 皮肤CT / 皮肤镜 / 麻风住院部
  · 仅写 TECH（DOC / NURSE 显式置 NULL）: 病理医技护 / 检验科医技
  · 互联网医院: 三路编码与名称全量保持 NULL（不写入任何映射）
  · 方便门诊  : 三路编码与名称全量置 NULL，并追加 REMARK = N'按员工属性'（员工属性动态归集，不落固定核算单元）
  -------------------------------------------------------------------------------
  【非侵入与最小修改原则 —— REMARK 存量保护】
  1. 本次 Patch 核心更新域严格锁死在医技护 6 列：
     DOC_HPS_DEPT_CODE / DOC_HPS_DEPT_NAME / TECH_HPS_DEPT_CODE
     / TECH_HPS_DEPT_NAME / NURSE_HPS_DEPT_CODE / NURSE_HPS_DEPT_NAME。
  2. REMARK 仅对「方便门诊」行作增量追加，严禁覆写存量备注：
     · 存量 REMARK 为 NULL   → 写入 N'按员工属性'
     · 存量 REMARK 非 NULL   → 追加为 旧备注 + N' | 按员工属性'（原文 100% 留存）
     · 其余普通科室          → 严格保留 r.[REMARK] 原值不动（ELSE 分支恒等赋值）
  3. 纠偏动因：原 CASE WHEN 逻辑对「方便门诊」行强制覆写 REMARK 为 N'按员工属性'，
     会永久抹除该行原有人工录入业务说明且不可逆，违反数据补丁的非侵入原则。
  4. 追加分隔符采用 ' | '（半角空格 + 竖线 + 半角空格），与 .clinerules 审计文本
     管道符排版规范一致，保证备注追加内容可被肉眼与程序双向解析。
  -------------------------------------------------------------------------------
  【关键纠偏（防熵增）】
  1. 显式置 NULL 而非 COALESCE 保留旧值：映射口径未定义的执行角色必须清空，
     防止旧基线残留造成「已刷洗」的假象，确保数据状态与映射集完全一致可审计。
  2. 未命中 CTE_MAP 的行保持原值不动（UPDATE ... FROM 内连接天然隔离），
     不设全局兜底 UPDATE 覆盖，避免未确认科室被静默写脏。
  3. 编号 100010（病理医技护）、100014（检验科医技）为 TECH 专属核算单元编码，
     其数值顺序不参与任何排序推断，严禁通过编码大小猜测定序关系。
  4. 编码列全量 VARCHAR(60) 字符串语义，映射常量一律以单引号文本字面量写入，
     严禁 CAST 为 INT/BIGINT（防前导零丢弃与关联失配）。
  -------------------------------------------------------------------------------
  【幂等性说明】
  本脚本为「绝对值赋值」而非增量计算，可重复执行且结果一致。
  重复执行时会覆盖 UPDATE_TIME；如需区分重跑与首跑，请结合影响行数变更情况判断。
  -------------------------------------------------------------------------------
  修改日志：
  2026-09-14 05:00:00 | 逻辑纠偏 | REMARK 赋值改为增量追加，严禁覆写存量备注：
                                     原 CASE WHEN 逻辑对「方便门诊」行强制覆写 REMARK，会永久抹除该行原有人工录入业务说明且不可逆；
                                     现改为 COALESCE 防 NULL + 字符串增量追加（存量为 NULL 写 N'按员工属性'；
                                     存量非 NULL 追加为 旧备注 + N' | 按员工属性'；普通科室严格保留原值不动）；
                                     同步在头部契约块声明「非侵入与最小修改原则」，并锁死本次 Patch 核心更新域为医技护 6 列。
  2026-09-14 04:00:00 | 脚本新建 | 创建医技护核算单元映射刷洗补丁：
                                     以 [DOC_HPS_DEPT_NAME] 旧值为匹配键，内联 CTE_MAP 内存映射集一次性 UPDATE；
                                     三角色映射口径按 DOC / TECH / NURSE 显式三写（未定义角色显式置 NULL）；
                                     包裹显式事务并输出影响行数，末尾附 3 段未映射异常核查 SELECT；
                                     全局禁 GO 协议、单批分号结束。
=============================================================================== */

SET XACT_ABORT ON;

BEGIN TRANSACTION;

UPDATE r
SET
    r.[DOC_HPS_DEPT_CODE]   = m.[DOC_HPS_DEPT_CODE],
    r.[DOC_HPS_DEPT_NAME]   = m.[DOC_HPS_DEPT_NAME],
    r.[TECH_HPS_DEPT_CODE]  = m.[TECH_HPS_DEPT_CODE],
    r.[TECH_HPS_DEPT_NAME]  = m.[TECH_HPS_DEPT_NAME],
    r.[NURSE_HPS_DEPT_CODE] = m.[NURSE_HPS_DEPT_CODE],
    r.[NURSE_HPS_DEPT_NAME] = m.[NURSE_HPS_DEPT_NAME],
    r.[REMARK]              = CASE
                                  WHEN m.[IS_LABOR_ATTR] = 1
                                      THEN COALESCE(r.[REMARK] + N' | 按员工属性', N'按员工属性')
                                  ELSE r.[REMARK]
                              END,
    r.[UPDATE_TIME]         = SYSDATETIME()
FROM [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] AS r
INNER JOIN (
    VALUES
        -- MATCH_KEY（旧 DOC_HPS_DEPT_NAME）              DOC_CODE   DOC_NAME                        TECH_CODE  TECH_NAME                       NURSE_CODE  NURSE_NAME                        IS_LABOR_ATTR
        (N'治疗科'                    , '100001', N'治疗科医生'                  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100002', N'治疗科护士'                  , 0),
        (N'激光美容科医生护士工勤'      , '100003', N'激光美容科医生护士工勤'       , '100003', N'激光美容科医生护士工勤'          , '100003', N'激光美容科医生护士工勤'        , 0),
        (N'外科（含门诊、病房）'        , '100004', N'外科医生（含门诊、病房）'      , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100005', N'外科护士（含门诊、病房）'      , 0),
        (N'手术室（麻醉医生、护士）'    , '100006', N'手术室（麻醉医生、护士）'      , '100006', N'手术室（麻醉医生、护士）'         , '100006', N'手术室（麻醉医生、护士）'      , 0),
        (N'变态反应科'                , '100007', N'变态反应科医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100008', N'变态反应科护士'               , 0),
        (N'皮肤CT'                   , '100009', N'皮肤CT医生'                 , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'皮肤镜'                    , '100011', N'皮肤镜医生'                  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'毛发'                      , '100012', N'毛发医生'                    , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100013', N'毛发护士'                    , 0),
        (N'日间治疗中心'               , '100015', N'日间治疗中心医生'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100016', N'日间治疗中心护士'             , 0),
        (N'中医美容科'                 , '100017', N'中医美容科医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100018', N'中医美容科护士'               , 0),
        (N'皮肤科'                     , '100019', N'皮肤科医生'                  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100020', N'皮肤科护士（处置室等）'        , 0),
        (N'皮肤科护士（处置室等）'      , '100019', N'皮肤科医生'                  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100020', N'皮肤科护士（处置室等）'        , 0),
        (N'中医外治科'                 , '100021', N'中医外治科医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100022', N'中医外治科护士'               , 0),
        (N'性病科（含门诊、病房）'      , '100023', N'性病科医生（含门诊、病房）'     , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100024', N'性病科护士（含门诊、病房）'     , 0),
        (N'皮肤一病房'                 , '100025', N'皮肤一病房医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100026', N'皮肤一病房护士'               , 0),
        (N'皮肤二病房'                 , '100027', N'皮肤二病房医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100028', N'皮肤二病房护士'               , 0),
        (N'皮肤三病房'                 , '100029', N'皮肤三病房医生'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100030', N'皮肤三病房护士'               , 0),
        (N'药剂科'                     , '100033', N'药剂科'                     , '100033', N'药剂科'                        , '100033', N'药剂科'                       , 0),
        (N'麻风住院部'                 , '100036', N'麻风住院部'                  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'病理医技护'                 , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100010', N'病理医技护'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'检验科医技'                 , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100014', N'检验科医技'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'互联网医院'                 , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'方便门诊'                   , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 1)
) AS m (
    [MATCH_KEY]
   ,[DOC_HPS_DEPT_CODE]  , [DOC_HPS_DEPT_NAME]
   ,[TECH_HPS_DEPT_CODE] , [TECH_HPS_DEPT_NAME]
   ,[NURSE_HPS_DEPT_CODE], [NURSE_HPS_DEPT_NAME]
   ,[IS_LABOR_ATTR]
)
    ON r.[DOC_HPS_DEPT_NAME] = m.[MATCH_KEY];

SELECT @@ROWCOUNT AS [UPDATED_ROW_COUNT];

COMMIT TRANSACTION;

-- =================================================================
-- 核查 1：全量刷新率总览（按 IS_ENABLED 分组统计三路映射填充情况）
-- =================================================================
SELECT
    [IS_ENABLED]                                                          AS [启用状态]
   ,COUNT(*)                                                              AS [总行数]
   ,SUM(CASE WHEN [DOC_HPS_DEPT_NAME]   IS NOT NULL THEN 1 ELSE 0 END)    AS [医生已映射行数]
   ,SUM(CASE WHEN [TECH_HPS_DEPT_NAME]  IS NOT NULL THEN 1 ELSE 0 END)    AS [技师已映射行数]
   ,SUM(CASE WHEN [NURSE_HPS_DEPT_NAME] IS NOT NULL THEN 1 ELSE 0 END)    AS [护士已映射行数]
   ,SUM(CASE WHEN [DOC_HPS_DEPT_CODE]   IS NULL
              AND [TECH_HPS_DEPT_CODE]  IS NULL
              AND [NURSE_HPS_DEPT_CODE] IS NULL            THEN 1 ELSE 0 END) AS [三路全空行数]
   ,SUM(CASE WHEN [DOC_HPS_DEPT_CODE] IS NOT NULL
              AND [DOC_HPS_DEPT_NAME] IS NULL              THEN 1 ELSE 0 END) AS [编码有名无异常行]
   ,SUM(CASE WHEN [DOC_HPS_DEPT_CODE] IS NULL
              AND [DOC_HPS_DEPT_NAME] IS NOT NULL          THEN 1 ELSE 0 END) AS [名称有编码无异常行]
FROM [dbo].[DIM_DEPT_ITEM_EXEC_RATIO]
GROUP BY [IS_ENABLED]
ORDER BY [IS_ENABLED];

-- =================================================================
-- 核查 2：未成功映射的异常数据行（三路编码全空，且不属于合法空映射科室）
--         合法空映射白名单：互联网医院（刻意留空）、方便门诊（按员工属性动态归集）
-- =================================================================
SELECT
    r.[ID]                AS [行ID]
   ,r.[HIS_DEPT_CODE]     AS [HIS科室编码]
   ,r.[HIS_DEPT_NAME]     AS [HIS科室名称]
   ,r.[ITEM_CODE]         AS [项目编码]
   ,r.[ITEM_NAME]         AS [项目名称]
   ,r.[DOC_HPS_DEPT_NAME] AS [映射基准_旧值]
   ,r.[REMARK]            AS [备注]
   ,r.[IS_ENABLED]        AS [启用状态]
   ,r.[UPDATE_TIME]       AS [更新时间]
   ,N'三路核算单元编码全空：映射基准值未命中 CTE_MAP 或基准值为 NULL' AS [异常原因]
FROM [dbo].[DIM_DEPT_ITEM_EXEC_RATIO] AS r
WHERE r.[DOC_HPS_DEPT_CODE]   IS NULL
  AND r.[TECH_HPS_DEPT_CODE]  IS NULL
  AND r.[NURSE_HPS_DEPT_CODE] IS NULL
  AND ISNULL(r.[DOC_HPS_DEPT_NAME], N'') NOT IN (N'互联网医院', N'方便门诊')
ORDER BY r.[HIS_DEPT_CODE], r.[ITEM_CODE];

-- =================================================================
-- 核查 3：CTE_MAP 全量映射明细（供人工比对，确认 23 条映射口径与业务台账一致）
--         本段为纯查询，不产生任何数据变更。
-- =================================================================
SELECT
    m.[MATCH_KEY]           AS [映射基准_旧值]
   ,m.[DOC_HPS_DEPT_CODE]   AS [医生核算单元编码]
   ,m.[DOC_HPS_DEPT_NAME]   AS [医生核算单元名称]
   ,m.[TECH_HPS_DEPT_CODE]  AS [技师核算单元编码]
   ,m.[TECH_HPS_DEPT_NAME]  AS [技师核算单元名称]
   ,m.[NURSE_HPS_DEPT_CODE] AS [护士核算单元编码]
   ,m.[NURSE_HPS_DEPT_NAME] AS [护士核算单元名称]
   ,CASE WHEN m.[IS_LABOR_ATTR] = 1 THEN N'按员工属性（存量备注为空时写入，非空时追加为 旧备注 + N'' | 按员工属性''）' ELSE NULL END AS [备注增量写入规则]
FROM (
    VALUES
        (N'治疗科'                , '100001', N'治疗科医生'              , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100002', N'治疗科护士'               , 0),
        (N'激光美容科医生护士工勤'  , '100003', N'激光美容科医生护士工勤'   , '100003', N'激光美容科医生护士工勤'      , '100003', N'激光美容科医生护士工勤'     , 0),
        (N'外科（含门诊、病房）'    , '100004', N'外科医生（含门诊、病房）'  , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100005', N'外科护士（含门诊、病房）'   , 0),
        (N'手术室（麻醉医生、护士）', '100006', N'手术室（麻醉医生、护士）'  , '100006', N'手术室（麻醉医生、护士）'     , '100006', N'手术室（麻醉医生、护士）'   , 0),
        (N'变态反应科'            , '100007', N'变态反应科医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100008', N'变态反应科护士'            , 0),
        (N'皮肤CT'               , '100009', N'皮肤CT医生'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'皮肤镜'                , '100011', N'皮肤镜医生'              , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'毛发'                  , '100012', N'毛发医生'                , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100013', N'毛发护士'                 , 0),
        (N'日间治疗中心'           , '100015', N'日间治疗中心医生'         , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100016', N'日间治疗中心护士'          , 0),
        (N'中医美容科'             , '100017', N'中医美容科医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100018', N'中医美容科护士'            , 0),
        (N'皮肤科'                 , '100019', N'皮肤科医生'              , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100020', N'皮肤科护士（处置室等）'     , 0),
        (N'皮肤科护士（处置室等）'  , '100019', N'皮肤科医生'              , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100020', N'皮肤科护士（处置室等）'     , 0),
        (N'中医外治科'             , '100021', N'中医外治科医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100022', N'中医外治科护士'            , 0),
        (N'性病科（含门诊、病房）'  , '100023', N'性病科医生（含门诊、病房）' , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100024', N'性病科护士（含门诊、病房）'  , 0),
        (N'皮肤一病房'             , '100025', N'皮肤一病房医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100026', N'皮肤一病房护士'            , 0),
        (N'皮肤二病房'             , '100027', N'皮肤二病房医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100028', N'皮肤二病房护士'            , 0),
        (N'皮肤三病房'             , '100029', N'皮肤三病房医生'           , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100030', N'皮肤三病房护士'            , 0),
        (N'药剂科'                 , '100033', N'药剂科'                 , '100033', N'药剂科'                    , '100033', N'药剂科'                   , 0),
        (N'麻风住院部'             , '100036', N'麻风住院部'              , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'病理医技护'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100010', N'病理医技护'         , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'检验科医技'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), '100014', N'检验科医技'         , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'互联网医院'             , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 0),
        (N'方便门诊'               , CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), CAST(NULL AS VARCHAR(60)), CAST(NULL AS NVARCHAR(300)), 1)
) AS m (
    [MATCH_KEY]
   ,[DOC_HPS_DEPT_CODE]  , [DOC_HPS_DEPT_NAME]
   ,[TECH_HPS_DEPT_CODE] , [TECH_HPS_DEPT_NAME]
   ,[NURSE_HPS_DEPT_CODE], [NURSE_HPS_DEPT_NAME]
   ,[IS_LABOR_ATTR]
);
