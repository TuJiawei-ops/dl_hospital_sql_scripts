/*
 Navicat Premium Dump SQL

 Source Server         : 本地Oracle
 Source Server Type    : Oracle
 Source Server Version : 210000 (Oracle Database 21c Express Edition Release 21.0.0.0.0 - Production)
 Source Host           : 192.168.130.32:1521
 Source Schema         : DL_PFM

 Target Server Type    : Oracle
 Target Server Version : 210000 (Oracle Database 21c Express Edition Release 21.0.0.0.0 - Production)
 File Encoding         : 65001

 Date: 18/09/2026 14:09:20
*/


-- ----------------------------
-- Table structure for PF临时医疗服务项目26A
-- ----------------------------
DROP TABLE "DL_PFM"."PF临时医疗服务项目26A";
CREATE TABLE "DL_PFM"."PF临时医疗服务项目26A" (
  "项目大类" VARCHAR2(20 BYTE) VISIBLE,
  "项目代码" VARCHAR2(20 BYTE) VISIBLE,
  "项目名称" VARCHAR2(200 BYTE) VISIBLE,
  "开单科室代码" NUMBER(18,0) VISIBLE,
  "开单科室" VARCHAR2(100 BYTE) VISIBLE,
  "开单人员代码" NUMBER VISIBLE,
  "开单人" VARCHAR2(41 BYTE) VISIBLE,
  "开单时间" DATE VISIBLE,
  "执行科室代码" NUMBER(18,0) VISIBLE,
  "执行科室" VARCHAR2(100 BYTE) VISIBLE,
  "执行人员代码" NUMBER VISIBLE,
  "执行人员" VARCHAR2(20 BYTE) VISIBLE,
  "执行时间" DATE VISIBLE,
  "数量" NUMBER VISIBLE,
  "单价" NUMBER(16,5) VISIBLE,
  "金额" NUMBER(16,5) VISIBLE,
  "缴费时间" DATE VISIBLE,
  "患者ID" NUMBER(18,0) VISIBLE,
  "挂号ID" VARCHAR2(81 BYTE) VISIBLE,
  "HIS主键" NUMBER(18,0) VISIBLE,
  "接诊时间" DATE VISIBLE,
  "完成时间" DATE VISIBLE,
  "挂号发生时间" DATE VISIBLE,
  "费用性质" CHAR(12 BYTE) VISIBLE,
  "来源" CHAR(8 BYTE) VISIBLE
)
LOGGING
NOCOMPRESS
PCTFREE 10
INITRANS 1
STORAGE (
  INITIAL 2483027968 
  NEXT 1048576 
  MINEXTENTS 1
  MAXEXTENTS 2147483645
  BUFFER_POOL DEFAULT
)
PARALLEL 1
NOCACHE
DISABLE ROW MOVEMENT
;
