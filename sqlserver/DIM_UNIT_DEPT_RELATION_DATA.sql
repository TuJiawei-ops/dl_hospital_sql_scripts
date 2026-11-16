-- ===================================================================
-- 数据初始化：dim_unit_dept_relation（核算单元 → 业务科室）
-- 生成方式：T_DEPARTMENT 名称语义推断（去括号 + 去角色后缀）+ 少量人工同义词
-- 生成日期：2026-11-16
-- 说明：
--   已匹配 34 条；未匹配/歧义 13 条见文件末尾注释（需人工确认）
--   生效区间统一 [1900-01-01, 9999-12-31)；后续科室调整请关闭旧记录 valid_to 并新增，不要覆盖
--   幂等：按 (unit_code, dept_code, valid_from) 判重
-- ===================================================================
SET NOCOUNT ON;

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100001', N'治疗科医生', N'UNIT054', N'治疗科', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100001' AND r.[dept_code]=N'UNIT054' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100002', N'治疗科护士', N'UNIT054', N'治疗科', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100002' AND r.[dept_code]=N'UNIT054' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100004', N'外科医生（含门诊、病房）', N'UNIT060', N'外科类门诊', N'医生', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100004' AND r.[dept_code]=N'UNIT060' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100005', N'外科护士（含门诊、病房）', N'UNIT060', N'外科类门诊', N'护士', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100005' AND r.[dept_code]=N'UNIT060' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100007', N'变态反应科医生', N'UNIT002', N'变态反应科', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100007' AND r.[dept_code]=N'UNIT002' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100008', N'变态反应科护士', N'UNIT002', N'变态反应科', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100008' AND r.[dept_code]=N'UNIT002' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100010', N'病理医技护', N'UNIT065', N'病理科', N'医技', '1900-01-01', '9999-12-31', N'语义推断（plus:科）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100010' AND r.[dept_code]=N'UNIT065' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100014', N'检验科医技', N'UNIT024', N'检验科', N'医技', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100014' AND r.[dept_code]=N'UNIT024' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100015', N'日间治疗中心医生', N'UNIT040', N'日间治疗中心', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100015' AND r.[dept_code]=N'UNIT040' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100016', N'日间治疗中心护士', N'UNIT040', N'日间治疗中心', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100016' AND r.[dept_code]=N'UNIT040' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100017', N'中医美容科医生', N'UNIT056', N'中医美容科', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100017' AND r.[dept_code]=N'UNIT056' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100018', N'中医美容科护士', N'UNIT056', N'中医美容科', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100018' AND r.[dept_code]=N'UNIT056' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100019', N'皮肤科医生', N'UNIT067', N'皮肤科类门诊', N'医生', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100019' AND r.[dept_code]=N'UNIT067' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100020', N'皮肤科护士（处置室等）', N'UNIT067', N'皮肤科类门诊', N'护士', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100020' AND r.[dept_code]=N'UNIT067' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100021', N'中医外治科医生', N'UNIT059', N'中医外治科类门诊', N'医生', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100021' AND r.[dept_code]=N'UNIT059' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100022', N'中医外治科护士', N'UNIT059', N'中医外治科类门诊', N'护士', '1900-01-01', '9999-12-31', N'语义推断（plus:类门诊）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100022' AND r.[dept_code]=N'UNIT059' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100023', N'性病科医生（含门诊、病房）', N'UNIT042', N'性病科病房', N'医生', '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100023' AND r.[dept_code]=N'UNIT042' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100024', N'性病科护士（含门诊、病房）', N'UNIT042', N'性病科病房', N'护士', '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100024' AND r.[dept_code]=N'UNIT042' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100025', N'皮肤一病房医生', N'UNIT036', N'皮肤一病房', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100025' AND r.[dept_code]=N'UNIT036' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100026', N'皮肤一病房护士', N'UNIT036', N'皮肤一病房', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100026' AND r.[dept_code]=N'UNIT036' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100027', N'皮肤二病房医生', N'UNIT030', N'皮肤二病房', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100027' AND r.[dept_code]=N'UNIT030' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100028', N'皮肤二病房护士', N'UNIT030', N'皮肤二病房', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100028' AND r.[dept_code]=N'UNIT030' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100029', N'皮肤三病房医生', N'UNIT032', N'皮肤三病房', N'医生', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100029' AND r.[dept_code]=N'UNIT032' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100030', N'皮肤三病房护士', N'UNIT032', N'皮肤三病房', N'护士', '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100030' AND r.[dept_code]=N'UNIT032' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100031', N'收款处', N'UNIT006', N'财务审计科（收款室）', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100031' AND r.[dept_code]=N'UNIT006' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100032', N'食堂', N'UNIT038', N'质控与运营管理科（食堂）', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100032' AND r.[dept_code]=N'UNIT038' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100033', N'药剂科', N'UNIT045', N'药剂科（药房）', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100033' AND r.[dept_code]=N'UNIT045' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100034', N'制剂室', N'UNIT046', N'药剂科（制剂室）', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100034' AND r.[dept_code]=N'UNIT046' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100038', N'药物临床试验机构办', N'UNIT068', N'临床药物试验办公室', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100038' AND r.[dept_code]=N'UNIT068' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100040', N'党政办（中层、职工）', N'UNIT051', N'党政办', NULL, '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100040' AND r.[dept_code]=N'UNIT051' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100041', N'党政办（院领导）', N'UNIT051', N'党政办', NULL, '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100041' AND r.[dept_code]=N'UNIT051' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100050', N'三甲（质控办）', N'UNIT053', N'质控与运营管理科', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100050' AND r.[dept_code]=N'UNIT053' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100051', N'运营管理科', N'UNIT053', N'质控与运营管理科', NULL, '1900-01-01', '9999-12-31', N'语义推断（synonym）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100051' AND r.[dept_code]=N'UNIT053' AND r.[valid_from]='1900-01-01');

INSERT INTO [dbo].[dim_unit_dept_relation] ([unit_code],[unit_name],[dept_code],[dept_name],[relation_type],[valid_from],[valid_to],[remark])
SELECT N'100070', N'党政办', N'UNIT051', N'党政办', NULL, '1900-01-01', '9999-12-31', N'语义推断（exact）'
WHERE NOT EXISTS (SELECT 1 FROM [dbo].[dim_unit_dept_relation] r WHERE r.[unit_code]=N'100070' AND r.[dept_code]=N'UNIT051' AND r.[valid_from]='1900-01-01');

-- ===================================================================
-- 未自动匹配的核算单元（需人工确认后补配置）：
--   100003  激光美容科医生护士工勤   （基础名：激光美容科）
--   100006  手术室（麻醉医生、护士）   （基础名：手术室）
--   100009  皮肤CT医生   （基础名：皮肤CT）
--   100011  皮肤镜医生   （基础名：皮肤镜）
--   100012  毛发医生   （基础名：毛发）
--   100013  毛发护士   （基础名：毛发）
--   100052  病案室   （基础名：病案室）
--   100060  体检中心   （基础名：体检中心）
--   1195  后勤保障辅助   （基础名：后勤保障辅助）
--   ceshi  测试   （基础名：测试）
--   LZ  离职人员   （基础名：离职人员）
--   test202611111346  test202611111346   （基础名：test202611111346）
--   XTBM01  图书馆   （基础名：图书馆）
-- ===================================================================
