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

 Date: 11/09/2026 13:45:03
*/


-- ----------------------------
-- Table structure for PF临时收入院数据26A
-- ----------------------------
DROP TABLE "DL_PFM"."PF临时收入院数据26A";
CREATE TABLE "DL_PFM"."PF临时收入院数据26A" (
  "项目名称" VARCHAR2(600 BYTE) VISIBLE,
  "开单科室代码" NUMBER(18,0) VISIBLE,
  "开单科室" VARCHAR2(300 BYTE) VISIBLE,
  "开单人员代码" NUMBER VISIBLE,
  "开单人" VARCHAR2(123 BYTE) VISIBLE,
  "开单时间" DATE VISIBLE,
  "执行科室代码" NUMBER(18,0) VISIBLE,
  "执行科室" VARCHAR2(300 BYTE) VISIBLE,
  "执行人员代码" NUMBER VISIBLE,
  "执行人员" VARCHAR2(60 BYTE) VISIBLE,
  "入院登记时间" DATE VISIBLE,
  "患者ID" NUMBER(18,0) VISIBLE,
  "挂号ID" VARCHAR2(243 BYTE) VISIBLE
)
LOGGING
NOCOMPRESS
PCTFREE 10
INITRANS 1
STORAGE (
  INITIAL 3145728 
  NEXT 1048576 
  MINEXTENTS 1
  MAXEXTENTS 2147483645
  BUFFER_POOL DEFAULT
)
PARALLEL 1
NOCACHE
DISABLE ROW MOVEMENT
;
