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

 Date: 11/09/2026 13:45:35
*/


-- ----------------------------
-- Table structure for PF临时转诊数据26A
-- ----------------------------
DROP TABLE "DL_PFM"."PF临时转诊数据26A";
CREATE TABLE "DL_PFM"."PF临时转诊数据26A" (
  "项目大类" VARCHAR2(60 BYTE) VISIBLE,
  "项目代码" VARCHAR2(60 BYTE) VISIBLE,
  "项目名称" VARCHAR2(600 BYTE) VISIBLE,
  "转诊后开单科室代码" NUMBER VISIBLE,
  "转诊后开单科室" VARCHAR2(300 BYTE) VISIBLE,
  "转诊后开单人员代码" NUMBER VISIBLE,
  "转诊开单人" VARCHAR2(60 BYTE) VISIBLE,
  "转诊后开单时间" DATE VISIBLE,
  "患者ID" NUMBER(18,0) VISIBLE,
  "挂号ID" VARCHAR2(243 BYTE) VISIBLE,
  "首诊科室代码" NUMBER VISIBLE,
  "首诊科室" VARCHAR2(300 BYTE) VISIBLE,
  "首诊医生代码" NUMBER VISIBLE,
  "首诊医生" VARCHAR2(60 BYTE) VISIBLE,
  "执行时间" DATE VISIBLE,
  "数量" NUMBER VISIBLE,
  "单价" NUMBER(16,5) VISIBLE,
  "金额" NUMBER(16,5) VISIBLE,
  "缴费时间" DATE VISIBLE,
  "HIS主键" NUMBER(18,0) VISIBLE,
  "来源" VARCHAR2(12 BYTE) VISIBLE
)
LOGGING
NOCOMPRESS
PCTFREE 10
INITRANS 1
STORAGE (
  INITIAL 50331648 
  NEXT 1048576 
  MINEXTENTS 1
  MAXEXTENTS 2147483645
  BUFFER_POOL DEFAULT
)
PARALLEL 1
NOCACHE
DISABLE ROW MOVEMENT
;
