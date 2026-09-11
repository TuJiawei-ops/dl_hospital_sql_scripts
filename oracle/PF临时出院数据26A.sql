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

 Date: 11/09/2026 13:47:51
*/


-- ----------------------------
-- Table structure for PF临时出院数据26A
-- ----------------------------
DROP TABLE "DL_PFM"."PF临时出院数据26A";
CREATE TABLE "DL_PFM"."PF临时出院数据26A" (
  "住院ID" VARCHAR2(243 BYTE) VISIBLE,
  "出院科室代码" NUMBER(18,0) VISIBLE,
  "出院科室" VARCHAR2(300 BYTE) VISIBLE,
  "出院时间" DATE VISIBLE
)
LOGGING
NOCOMPRESS
PCTFREE 10
INITRANS 1
STORAGE (
  INITIAL 851968 
  NEXT 1048576 
  MINEXTENTS 1
  MAXEXTENTS 2147483645
  BUFFER_POOL DEFAULT
)
PARALLEL 1
NOCACHE
DISABLE ROW MOVEMENT
;
