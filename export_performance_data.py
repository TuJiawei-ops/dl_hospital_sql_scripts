#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
=================================================================================
 大连市皮肤病医院绩效测算 - 绩效核算基础数据 CSV 批量导出脚本
=================================================================================

 Relative Path : export_performance_data.py

 功能概述
 --------
 连接本地 SQL Server 绩效库 hospital_performance_dalian_derma, 一次性导出 7 项
 绩效核算基础数据为 UTF-8-BOM (utf-8-sig) 编码的 CSV 文件, 供 Excel / 业务人员
 直接打开核对, 零乱码、零二次转换。

   任务 1  一次分配明细                      -> analyses/01_报表_一次分配明细业务视图.sql (纯 SELECT 直执行)
   任务 2  核算单元                          -> dbo.T_DEPARTMENT                      (32 列, 按 DDL 声明序对齐)
   任务 3  科室与核算单元映射表               -> dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27  (11 列)
   任务 4  医院收费项目绩效点数版本维表        -> dbo.DIM_PRF_ITEM_RVU_VERSION            (23 列)
   任务 5  各科室收费项目医技护执行划分维表     -> dbo.DIM_DEPT_ITEM_EXEC_RATIO            (26 列)
   任务 6  核算单元月度岗位系数与在岗状态明细表 -> dbo.ads_dept_post_coefficient_m          (16 列)
   任务 7  绩效核算日历维度表                 -> dbo.DIM_WORK_CALENDAR                   (11 列, 实体源自 20260915_create_dim_work_calendar.sql)

 输出目录规范
 ------------
 输出目录 : ./{TIMESTAMP}_大连市皮肤病医院绩效核算/
 文件命名 : {TIMESTAMP}_<任务中文名>.csv  (与目录时间戳同源, 全局一致)
 CSV 编码 : utf-8-sig (UTF-8 带 BOM, 保障 Excel 双击直开不乱码)

 关键技术决策
 ------------
 1. 【只读声明】全部 7 项任务均为纯只读 SELECT, 零 INSERT / UPDATE / DELETE /
    TRUNCATE / DDL 副作用, 对生产库绝对零写入。
 2. 【占位符零注入】任务 1 的 SQL 不含 '{year}' / '{month}' / {struct_codes} 等
    模板占位符 (业务全量透视视图), 故本脚本无需任何参数替换动作, 直接整段执行;
    若未来该 SQL 引入占位符, 须在此处同步补齐替换逻辑, 严禁静默失败。
 3. 【列序显式锁定】任务 2~7 一律使用显式列清单 SELECT, 严禁 SELECT *, 保证
    CSV 列序与 DDL 物理声明顺序、扩展属性中文注释严格一一对齐, 不受数据库
    物理列序变更或列追加影响。
 4. 【流式写出】采用 pyodbc 流式游标 + csv.writer 逐行写出, 内存占用恒定,
    不引入 pandas 一次性载入 (一次分配明细可达百万行量级)。
 5. 【编码隔离】SQL 文本与 CSV 写入统一显式 UTF-8 处理, 杜绝驱动层 GBK 转码
    造成的中文乱码; 连接串携带 TrustServerCertificate=yes 兼容自签证书。

 依赖
 ----
   pip install -r python/requirements.txt      (pyodbc>=5.0.0 + ODBC Driver 17)

 运行
 ----
   python export_performance_data.py

 修改日志：
 2026-09-19 12:00:00 | 脚本新建 | 建立 7 项绩效核算基础数据 CSV 批量导出管道：pyodbc 流式游标 + csv.writer 逐行写出, 全局统一 TIMESTAMP(YYYYMMDD_HHMMSS) 字符串贯穿目录与文件名; 任务 1 直读 analyses/01_报表_一次分配明细业务视图.sql 纯 SELECT 内容执行, 任务 2~7 按 DDL 声明顺序显式列清单 + 中文别名映射导出; 输出 utf-8-sig 带 BOM, 保障 Excel 直开无乱码; 含逐任务错误处理、部分失败容错与连接物理清理动作。
=================================================================================
"""

from __future__ import annotations

import csv
import logging
import re
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Sequence, Tuple

import pyodbc

# ---------------------------------------------------------------------------------
# 0. 全局常量与运行环境
# ---------------------------------------------------------------------------------

# 脚本所在目录 (项目根目录), 作为所有相对路径的解析基准
BASE_DIR: Path = Path(__file__).resolve().parent

# ---- 数据库连接配置 (按任务书显式给定) ----
DB_HOST: str = "127.0.0.1"
DB_PORT: int = 1433
DB_DATABASE: str = "hospital_performance_dalian_derma"
DB_USER: str = "sa"
DB_PASSWORD: str = "YourStrongPassword123"
DB_SCHEMA: str = "dbo"

# ODBC 驱动候选清单 (按优先级探测, 兼容目标机仅装 18 版或 17 版的情形)
ODBC_DRIVER_CANDIDATES: Tuple[str, ...] = (
    "ODBC Driver 18 for SQL Server",
    "ODBC Driver 17 for SQL Server",
    "SQL Server",
)

# 连接超时 / 查询超时 (秒); 查询超时 0 表示不限, 保障大结果集长查询不被截断
LOGIN_TIMEOUT_SEC: int = 15
QUERY_TIMEOUT_SEC: int = 0

# CSV 写出批尺寸 (流式游标 fetchmany 尺寸, 与内存占用成正比而非结果集大小)
FETCH_BATCH_SIZE: int = 5_000

# CSV 编码: UTF-8 带 BOM, Excel 双击直开不乱码
CSV_ENCODING: str = "utf-8-sig"

# 全局统一时间戳 (目录名与所有 CSV 文件名前缀严格同源)
TIMESTAMP: str = datetime.now().strftime("%Y%m%d_%H%M%S")

# 输出目录名
OUTPUT_DIR_NAME: str = f"{TIMESTAMP}_大连市皮肤病医院绩效核算"

# 任务 1 的 SQL 源文件 (项目内相对路径)
TASK1_SQL_RELATIVE_PATH: str = "analyses/01_报表_一次分配明细业务视图.sql"

# 任务 7 的 DDL 出处 (仅作文档溯源, 实际取数走数据库实体 dbo.DIM_WORK_CALENDAR)
TASK7_DDL_RELATIVE_PATH: str = "sqlserver/20260915_create_dim_work_calendar.sql"


# ---------------------------------------------------------------------------------
# 1. 列映射契约 (Column Mapping Contract)
# ---------------------------------------------------------------------------------
# 说明: dict 在 Python 3.7+ 保证插入顺序, 故其键序即为 CSV 物理列序与 DDL 声明序。

# ---- 任务 2: 核算单元 (dbo.T_DEPARTMENT) ----
# 注: [TYPE_NAME] 为计算列 (PERSISTED), 按 .clinerules 源列零改造原则裸引用投影。
T_DEPARTMENT_COLS: Dict[str, str] = {
    "ID": "主键ID",
    "NAME": "部门名称",
    "CODE": "部门编码",
    "ABBREVIATION": "部门简称",
    "PERSON_LIABLE": "责任人ids",
    "COST_CENTRE": "成本中心",
    "IS_FICTITIOU": "是否虚拟部门",
    "PINYIN_CODE": "拼音编码",
    "TYPE_ID": "部门类型",
    "P_ID": "上级部门",
    "COMPANY_ID": "关联公司",
    "IS_GK_DEPT": "是否归口科室",
    "STATUS": "状态 1.启用 0.禁用",
    "CREATE_USER": "创建者",
    "CREATE_TIME": "创建时间",
    "MODIFY_USER": "修改者",
    "MODIFY_TIME": "修改时间",
    "DELETE_FLAG": "删除标识(0:未删除,1:已删除)",
    "DEPTTYPE": "部门类型(医院 0 行政后勤1 医疗技术 2 临床服务3 医疗辅助4 乡村卫生院 5)",
    "CREATEDATE": "部门成立时间",
    "OWN_ALL_PRODUCT": "OWN_ALL_PRODUCT",
    "IS_FUNCTIONAL_DEPT": "是否为职能科室",
    "IS_NURSING_UNIT": "是否为护理单元",
    "sfhsdy": "是否核算单元",
    "TYPE_NAME": "部门类型名称",
    "children_ids": "下级科室id",
    "temp": "是否缓存科室 0-是 1-否",
    "director_ids": "科室主任",
    "deputy_director_ids": "科室副主任",
    "is_clinical_dept": "是否临床科室0否1是",
    "series_code": "所属职系编码",
    "series_name": "所属职系名称",
}

# ---- 任务 3: 科室与核算单元映射表 (dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27) ----
MAPPING_COLS: Dict[str, str] = {
    "ID": "主键ID",
    "HIS_DEPT_CODE": "HIS科室编码",
    "HIS_DEPT_NAME": "HIS科室名称",
    "PERFORM_PERSON_TYPE": "执行人员类型名称",
    "HPS_DEPT_CODE": "HPS绩效科室编码",
    "HPS_DEPT_NAME": "HPS绩效科室名称",
    "START_DATE": "映射开始时间",
    "END_DATE": "映射结束时间",
    "REMARK": "备注",
    "create_time": "记录创建时间",
    "PERFORM_PERSON_TYPE_CODE": "执行人员类型编码",
}

# ---- 任务 4: 医院收费项目绩效点数版本维表 (dbo.DIM_PRF_ITEM_RVU_VERSION) ----
RVU_COLS: Dict[str, str] = {
    "VERSION_NO": "版本号",
    "VERSION_DESC": "版本方案业务中文描述",
    "ORG_CODE": "机构编码",
    "ORG_NAME": "机构名称",
    "SRC_SYS_CODE": "源系统编码",
    "PROJ_CODE": "收费项目编码",
    "PROJ_NAME": "收费项目名称",
    "MEAS_UNIT": "原始计费单位",
    "RVU_VAL": "单项绩效点数",
    "ITEM_CAT_CODE": "绩效标准核算分类编码",
    "ITEM_CAT_NAME": "绩效标准核算分类名称",
    "UNIT_PRICE": "历史参考单价",
    "OPR_LEVEL_CODE": "手术等级编码",
    "OPR_LEVEL_NAME": "手术等级名称",
    "CREATE_USER": "初始化创建人",
    "CREATE_TIME": "初始化创建时间",
    "UPDATE_USER": "最后修改人",
    "UPDATE_TIME": "最后修改时间戳",
    "ID": "冗余ID",
    "DECISION_COFF": "诊疗决策系数",
    "EXEC_COFF": "执行系数",
    "REMARK": "备注说明",
    "SCORE_REASON": "评分理由依据",
}

# ---- 任务 5: 各科室收费项目医技护执行划分维表 (dbo.DIM_DEPT_ITEM_EXEC_RATIO) ----
EXEC_RATIO_COLS: Dict[str, str] = {
    "ID": "自增代理主键",
    "HIS_DEPT_CODE": "HIS科室编码",
    "HIS_DEPT_NAME": "HIS科室名称",
    "ITEM_CODE": "收费项目编码",
    "ITEM_NAME": "收费项目名称",
    "HIS_CAT_NAME": "HIS类别名称",
    "DOC_EXEC_RATIO": "医生执行比例",
    "TECH_EXEC_RATIO": "技师执行比例",
    "NURSE_EXEC_RATIO": "护士执行比例",
    "CLINICAL_EXEC_RATIO": "临床执行比例",
    "DOC_HPS_DEPT_CODE": "医生对应核算单元编码",
    "DOC_HPS_DEPT_NAME": "医生对应核算单元名称",
    "TECH_HPS_DEPT_CODE": "技师对应核算单元编码",
    "TECH_HPS_DEPT_NAME": "技师对应核算单元名称",
    "NURSE_HPS_DEPT_CODE": "护士对应核算单元编码",
    "NURSE_HPS_DEPT_NAME": "护士对应核算单元名称",
    "CLINICAL_HPS_DEPT_CODE": "临床对应核算单元编码",
    "CLINICAL_HPS_DEPT_NAME": "临床对应核算单元名称",
    "PROVIDE_DATE": "提供日期",
    "ITEM_ADD_DATE": "项目新增日期",
    "DISABLE_DATE": "停用日期",
    "REMARK": "备注",
    "VERSION_NO": "版本号",
    "IS_ENABLED": "是否启用",
    "CREATE_TIME": "创建时间",
    "UPDATE_TIME": "更新时间",
}

# ---- 任务 6: 核算单元月度岗位系数与在岗状态明细表 (dbo.ads_dept_post_coefficient_m) ----
POST_COEFF_COLS: Dict[str, str] = {
    "year": "核算年份",
    "month": "核算月份",
    "unit_code": "核算单元编码",
    "unit_name": "核算单元名称",
    "staff_code": "员工编码",
    "staff_name": "员工姓名",
    "staff_sequence": "员工序列",
    "series_code": "所属职系编码",
    "series_name": "所属职系名称",
    "post_code": "岗位物理编码",
    "post_name": "职务标签名称",
    "post_coefficient": "岗位系数",
    "on_duty_days": "月度实际在岗天数",
    "is_transferred": "是否转科标识",
    "remark": "备注",
    "create_time": "创建时间",
}

# ---- 任务 7: 绩效核算日历维度表 (dbo.DIM_WORK_CALENDAR) ----
# 列序严格对齐 sqlserver/20260915_create_dim_work_calendar.sql 的 DDL 字段声明顺序,
# 中文别名取字段级扩展属性 (MS_Description) 的规范注释口径。
WORK_CALENDAR_COLS: Dict[str, str] = {
    "CALC_DATE": "日期",
    "WEEKDAY_CODE": "星期编码",
    "WEEKDAY_NAME": "星期名称",
    "DAY_TYPE_CODE": "日期类型编码",
    "DAY_TYPE_NAME": "日期类型名称",
    "IS_HOLIDAY": "是否法定节假日",
    "HOLIDAY_NAME": "节假日名称",
    "IS_MAKEUP_WORK": "是否调休补班",
    "PERF_COEFF": "绩效核算系数",
    "REMARK": "备注",
    "CREATE_TIME": "创建时间",
}


# ---------------------------------------------------------------------------------
# 2. 导出任务契约 (Export Task Contract)
# ---------------------------------------------------------------------------------


@dataclass(frozen=True)
class ExportTask:
    """
    单项导出任务契约。

    属性
    ----
    order        : 任务序号 (1..7), 用于控制台进度编排与日志排序
    file_prefix  : CSV 文件名业务后缀 (最终文件名 = f"{TIMESTAMP}_{file_prefix}.csv")
    describe     : 业务中文描述 (日志与异常提示)
    columns      : 列映射契约 {物理列名: 中文别名}; 为 None 时表示列头完全由 SQL 结果集决定
    table_name   : 物理表名 (schema 限定的三段式), columns 非空时必填
    sql_file     : SQL 文件相对项目根目录的路径 (任务 1 走此路径)
    """

    order: int
    file_prefix: str
    describe: str
    columns: Optional[Dict[str, str]] = None
    table_name: Optional[str] = None
    sql_file: Optional[str] = None

    @property
    def csv_file_name(self) -> str:
        """带全局时间戳前缀的 CSV 文件名。"""
        return f"{TIMESTAMP}_{self.file_prefix}.csv"

    def build_select_sql(self) -> str:
        """
        组装/读取最终执行的 SELECT 文本。

        返回
        ----
        str: 可直接送入游标执行的单批 SQL 文本 (零 GO、纯 SELECT)。

        异常
        ----
        RuntimeError: 契约不完整 (既无 sql_file 又无 columns + table_name), 或 SQL 文件缺失/未解析出可执行 SELECT。
        """
        # 路径 A: 从项目内 SQL 文件加载 (任务 1)
        if self.sql_file is not None:
            return load_select_sql_from_file(self.sql_file)

        # 路径 B: 按列契约组装显式列清单 SELECT (任务 2~7)
        if not self.columns or not self.table_name:
            raise RuntimeError(
                f"[任务 {self.order}] 契约不完整: 必须提供 sql_file 或 (columns + table_name)。"
            )
        col_list = ", ".join(f"[{c}]" for c in self.columns.keys())
        return f"SELECT {col_list} FROM {self.table_name} WITH (NOLOCK);"

    def build_csv_header(self, db_header: Sequence[str]) -> List[str]:
        """
        生成 CSV 列头。

        参数
        ----
        db_header : 数据库游标返回的原始列名序列

        返回
        ----
        List[str]: columns 非空时返回契约中文别名 (且与 DB 列名做一致性校验);
                   columns 为空时直接透传数据库列名 (任务 1 SQL 内部已中文别名化)。
        """
        if not self.columns:
            return list(db_header)

        expected = list(self.columns.keys())
        actual = list(db_header)
        if [c.upper() for c in expected] != [c.upper() for c in actual]:
            raise RuntimeError(
                f"[任务 {self.order}] 列契约与数据库结果集不匹配。\n"
                f"        契约列序: {expected}\n"
                f"        数据库列序: {actual}"
            )
        return list(self.columns.values())


# ---------------------------------------------------------------------------------
# 3. 工具函数: SQL 文件装载与文本清洗
# ---------------------------------------------------------------------------------

# 行注释 (-- ...) 与块注释 (/* ... */) 清理正则; 采用 re.DOTALL 支持跨行块注释
_RE_BLOCK_COMMENT: "re.Pattern[str]" = re.compile(r"/\*.*?\*/", re.DOTALL)
_RE_LINE_COMMENT: "re.Pattern[str]" = re.compile(r"--[^\n]*")


def project_path(relative_path: str) -> Path:
    """
    将项目内相对路径解析为绝对路径 (基准: 本脚本所在目录 = 项目根目录)。

    参数
    ----
    relative_path : 正斜杠分隔的项目相对路径, 如 'analyses/01_报表_一次分配明细业务视图.sql'
    """
    normalized = relative_path.replace("/", str(Path("/")))
    return BASE_DIR / Path(normalized)


def load_select_sql_from_file(relative_path: str) -> str:
    """
    读取项目内 SQL 文件并剥离全部注释, 返回可直接执行的纯 SELECT 文本。

    实现说明
    --------
    1. 以 utf-8-sig 读取 (兼容文件含 BOM 的情形), 剔除 BOM 残留字符。
    2. 剥离块注释与行注释, 保留纯 SQL 语句体。
    3. 剔除语句末尾分号, 规避部分驱动/协议组合的尾部截断歧义。
    4. 只读护栏: 命中任何写操作关键字 (INSERT/UPDATE/DELETE/DROP/...) 即拒绝执行。

    参数
    ----
    relative_path : SQL 文件的项目内相对路径

    异常
    ----
    FileNotFoundError : SQL 文件不存在
    RuntimeError      : 内容未解析出可执行 SELECT, 或命中非只读关键字
    """
    sql_path = project_path(relative_path)
    if not sql_path.is_file():
        raise FileNotFoundError(
            f"SQL 文件不存在: {sql_path}\n"
            f"        请确认项目根目录 [{BASE_DIR}] 下存在相对路径 [{relative_path}]。"
        )

    raw_text = sql_path.read_text(encoding=CSV_ENCODING)
    # 剔除 BOM 残留 (utf-8-sig 已处理 BOM, 此处防御性二次清洗)
    raw_text = raw_text.lstrip("\ufeff")

    # 剥离注释 (先块后行, 顺序不可颠倒)
    pure_sql = _RE_BLOCK_COMMENT.sub(" ", raw_text)
    pure_sql = _RE_LINE_COMMENT.sub(" ", pure_sql)
    pure_sql = pure_sql.strip().rstrip(";").strip()

    if not pure_sql:
        raise RuntimeError(f"SQL 文件剥离注释后为空: {sql_path}")

    if re.search(r"\bSELECT\b", pure_sql, re.IGNORECASE) is None:
        raise RuntimeError(f"SQL 文件未包含可执行 SELECT 语句: {sql_path}")

    # 只读护栏: 任何写操作关键字命中即拒绝执行, 杜绝误跑 DML/DDL 脚本
    forbidden = ("INSERT", "UPDATE", "DELETE", "TRUNCATE", "DROP", "ALTER", "CREATE", "EXEC", "MERGE")
    upper_sql = pure_sql.upper()
    for keyword in forbidden:
        if re.search(rf"\b{keyword}\b", upper_sql):
            raise RuntimeError(
                f"SQL 文件包含非只读关键字 [{keyword}], 已拒绝执行以保障生产库安全: {sql_path}"
            )

    return pure_sql


# ---------------------------------------------------------------------------------
# 4. 数据库连接配置 (Connection Config)
# ---------------------------------------------------------------------------------


@dataclass
class DbConfig:
    """SQL Server 连接配置快照 (明文口令仅存在于运行期内存, 不落日志)。"""

    host: str = DB_HOST
    port: int = DB_PORT
    database: str = DB_DATABASE
    user: str = DB_USER
    password: str = DB_PASSWORD
    driver: str = ""

    def resolve_driver(self) -> str:
        """
        探测本机已安装的 ODBC 驱动, 返回首个可用驱动名。

        异常
        ----
        RuntimeError: 候选驱动全部缺失
        """
        installed = {name.strip() for name in pyodbc.drivers()}
        for candidate in ODBC_DRIVER_CANDIDATES:
            if candidate in installed:
                self.driver = candidate
                return candidate
        raise RuntimeError(
            "未检测到可用的 SQL Server ODBC 驱动。\n"
            f"        已安装驱动: {sorted(installed)}\n"
            "        请安装 'ODBC Driver 17 for SQL Server' 或 'ODBC Driver 18 for SQL Server'。"
        )

    @property
    def conn_str(self) -> str:
        """构造 pyodbc 连接串 (字符串列与 SQL 文本统一 Unicode 语义, 防中文乱码)。"""
        return (
            f"DRIVER={{{self.driver}}};"
            f"SERVER={self.host},{self.port};"
            f"DATABASE={self.database};"
            f"UID={self.user};"
            f"PWD={self.password};"
            f"TrustServerCertificate=yes;"
            f"LoginTimeout={LOGIN_TIMEOUT_SEC};"
        )

    @property
    def alias(self) -> str:
        """脱敏后的连接标识, 供日志输出 (不泄露口令)。"""
        return f"{self.host},{self.port}/{self.database}"


# ---------------------------------------------------------------------------------
# 5. 日志装配 (Logging Setup)
# ---------------------------------------------------------------------------------

LOG_FORMAT: str = "[%(asctime)s] [%(levelname)-7s] %(message)s"
LOG_DATEFMT: str = "%Y-%m-%d %H:%M:%S"


def setup_console_logger() -> logging.Logger:
    """
    装配控制台日志器 (stdout, UTF-8 安全输出)。

    说明: 仅面向控制台; 本脚本为一次性交付工具, 不落日志文件以免污染项目根目录。
    """
    logger = logging.getLogger("export_performance_data")
    logger.setLevel(logging.INFO)
    logger.propagate = False

    if not logger.handlers:
        handler = logging.StreamHandler(stream=sys.stdout)
        handler.setFormatter(logging.Formatter(fmt=LOG_FORMAT, datefmt=LOG_DATEFMT))
        logger.addHandler(handler)

    # Windows 控制台默认 GBK, 中文输出需强制 UTF-8 避免 UnicodeEncodeError
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
    except (AttributeError, ValueError):
        pass

    return logger


# ---------------------------------------------------------------------------------
# 6. 任务清单装配 (Task Registry)
# ---------------------------------------------------------------------------------


def build_export_tasks() -> List[ExportTask]:
    """
    装配 7 项导出任务清单。

    返回
    ----
    List[ExportTask]: 按 order 升序排列的任务契约列表
    """
    return [
        # ---- 任务 1: 一次分配明细 (直读 analyses 下纯 SELECT 报表脚本) ----
        ExportTask(
            order=1,
            file_prefix="一次分配明细",
            describe=f"一次分配明细 (源: {TASK1_SQL_RELATIVE_PATH})",
            columns=None,           # 列头由 SQL 内部中文别名决定, 直接透传结果集列名
            sql_file=TASK1_SQL_RELATIVE_PATH,
        ),
        # ---- 任务 2: 核算单元 ----
        ExportTask(
            order=2,
            file_prefix="核算单元",
            describe="核算单元 (源: dbo.T_DEPARTMENT)",
            columns=T_DEPARTMENT_COLS,
            table_name=f"[{DB_SCHEMA}].[T_DEPARTMENT]",
        ),
        # ---- 任务 3: 科室与核算单元映射表 ----
        ExportTask(
            order=3,
            file_prefix="科室与核算单元映射表",
            describe="科室与核算单元映射表 (源: dbo.sjjk_DEPT_UNIT_MAPPING_2025_11_27)",
            columns=MAPPING_COLS,
            table_name=f"[{DB_SCHEMA}].[sjjk_DEPT_UNIT_MAPPING_2025_11_27]",
        ),
        # ---- 任务 4: 医院收费项目绩效点数版本维表 ----
        ExportTask(
            order=4,
            file_prefix="医院收费项目绩效点数版本维表",
            describe="医院收费项目绩效点数版本维表 (源: dbo.DIM_PRF_ITEM_RVU_VERSION)",
            columns=RVU_COLS,
            table_name=f"[{DB_SCHEMA}].[DIM_PRF_ITEM_RVU_VERSION]",
        ),
        # ---- 任务 5: 各科室收费项目医技护执行划分维表 ----
        ExportTask(
            order=5,
            file_prefix="各科室收费项目医技护执行划分维表",
            describe="各科室收费项目医技护执行划分维表 (源: dbo.DIM_DEPT_ITEM_EXEC_RATIO)",
            columns=EXEC_RATIO_COLS,
            table_name=f"[{DB_SCHEMA}].[DIM_DEPT_ITEM_EXEC_RATIO]",
        ),
        # ---- 任务 6: 核算单元月度岗位系数与在岗状态明细表 ----
        ExportTask(
            order=6,
            file_prefix="核算单元月度岗位系数与在岗状态明细表",
            describe="核算单元月度岗位系数与在岗状态明细表 (源: dbo.ads_dept_post_coefficient_m)",
            columns=POST_COEFF_COLS,
            table_name=f"[{DB_SCHEMA}].[ads_dept_post_coefficient_m]",
        ),
        # ---- 任务 7: 绩效核算日历维度表 ----
        ExportTask(
            order=7,
            file_prefix="绩效核算日历维度表",
            describe=f"绩效核算日历维度表 (源: dbo.DIM_WORK_CALENDAR, DDL 出处 {TASK7_DDL_RELATIVE_PATH})",
            columns=WORK_CALENDAR_COLS,
            table_name=f"[{DB_SCHEMA}].[DIM_WORK_CALENDAR]",
        ),
    ]


# ---------------------------------------------------------------------------------
# 7. 导出结果契约 (Export Result Contract)
# ---------------------------------------------------------------------------------


@dataclass
class TaskResult:
    """单项任务导出结果 (用于汇总与退出码判定)。"""

    order: int
    file_prefix: str
    file_name: str
    rows: int = 0
    elapsed_sec: float = 0.0
    status: str = "PENDING"        # SUCCESS / FAILED / PENDING
    message: str = ""


# ---------------------------------------------------------------------------------
# 8. 导出引擎 (Export Engine)
# ---------------------------------------------------------------------------------


class PerformanceDataExporter:
    """
    绩效核算基础数据 CSV 批量导出引擎。

    生命周期: 由 run() 以 with 语句托管, 保证异常路径下连接与游标的物理清理。
    """

    def __init__(self, config: DbConfig, output_dir: Path, logger: logging.Logger) -> None:
        self._config = config
        self._output_dir = output_dir
        self._log = logger
        self._conn: Optional[pyodbc.Connection] = None
        self._results: List[TaskResult] = []

    # ---- 上下文管理: 保障连接物理释放 ----

    def __enter__(self) -> "PerformanceDataExporter":
        self._connect()
        return self

    def __exit__(self, exc_type, exc_val, exc_tb) -> bool:
        self._disconnect()
        return False        # 不吞异常, 交由上游统一处理

    def _connect(self) -> None:
        """建立数据库连接并校验连通性。"""
        self._log.info("[数据库] 正在连接: %s (驱动: %s)", self._config.alias, self._config.driver)
        self._conn = pyodbc.connect(self._config.conn_str, autocommit=True, timeout=LOGIN_TIMEOUT_SEC)
        self._conn.timeout = QUERY_TIMEOUT_SEC
        # 连通性冒烟校验
        with self._conn.cursor() as probe:
            probe.execute("SELECT DB_NAME();")
            row = probe.fetchone()
        self._log.info("[数据库] 连接成功: %s", row[0] if row else "(unknown db)")

    def _disconnect(self) -> None:
        """物理关闭数据库连接 (无论成功与否均执行)。"""
        if self._conn is not None:
            try:
                self._conn.close()
                self._log.info("[数据库] 连接已关闭")
            except Exception as exc:                        # pragma: no cover - 防御性
                self._log.warning("[数据库] 关闭连接时发生异常: %s", exc)
            finally:
                self._conn = None

    # ---- 目录准备 ----

    def ensure_output_dir(self) -> Path:
        """
        确保输出目录存在 (幂等: 已存在则直接复用, 不删除历史产物)。

        返回
        ----
        Path: 输出目录绝对路径
        """
        if self._output_dir.exists():
            self._log.info("[输出目录] 已存在, 直接复用: %s", self._output_dir)
        else:
            self._output_dir.mkdir(parents=True, exist_ok=True)
            self._log.info("[输出目录] 创建成功: %s", self._output_dir)
        return self._output_dir

    # ---- 核心导出动作 ----

    def export_task(self, task: ExportTask) -> TaskResult:
        """
        执行单项导出任务: 组装 SQL -> 流式取数 -> UTF-8-BOM CSV 写出。

        参数
        ----
        task : 导出任务契约

        返回
        ----
        TaskResult: 含行数、耗时与状态的结果对象 (失败时状态为 FAILED, 不向上抛出)
        """
        start = time.perf_counter()
        result = TaskResult(
            order=task.order,
            file_prefix=task.file_prefix,
            file_name=task.csv_file_name,
        )
        csv_path = self._output_dir / task.csv_file_name

        try:
            if self._conn is None:
                raise RuntimeError("数据库连接尚未建立, 无法执行导出。")

            sql_text = task.build_select_sql()
            self._log.info("[任务 %d] 开始导出: %s", task.order, task.describe)

            with self._conn.cursor() as cursor:
                cursor.execute(sql_text)
                if cursor.description is None:
                    raise RuntimeError("SQL 执行未返回结果集 (description 为空)。")
                db_header = [col[0] for col in cursor.description]
                csv_header = task.build_csv_header(db_header)

                rows = self._write_csv(cursor, csv_header, csv_path)

            result.rows = rows
            result.status = "SUCCESS"
            result.message = f"共 {rows} 行"
            self._log.info("[SUCCESS] 导出文件: %s (共 %d 行)", task.csv_file_name, rows)

        except Exception as exc:
            # 失败容错: 清理半成品文件, 记录错误并继续后续任务
            result.status = "FAILED"
            result.message = str(exc)
            self._log.error("[任务 %d] 导出失败: %s", task.order, task.describe)
            self._log.error("         根因: %s", exc)
            if csv_path.exists():
                try:
                    csv_path.unlink()
                    self._log.warning("         已清理未完成的半成品文件: %s", csv_path.name)
                except OSError as clean_exc:                # pragma: no cover - 防御性
                    self._log.warning("         半成品文件清理失败: %s", clean_exc)

        finally:
            result.elapsed_sec = time.perf_counter() - start
            self._results.append(result)

        return result

    def _write_csv(self, cursor: pyodbc.Cursor, header: Sequence[str], csv_path: Path) -> int:
        """
        流式将游标结果写入 CSV (utf-8-sig 带 BOM)。

        参数
        ----
        cursor   : 已执行且带结果集的游标
        header   : CSV 列头 (中文别名或透传列名)
        csv_path : 目标 CSV 物理路径

        返回
        ----
        int: 实际写出行数 (不含表头)
        """
        row_count = 0
        # newline="" 为 csv 模块官方强制要求, 防止 Windows 下产生空行;
        # encoding="utf-8-sig" 写入 BOM, 保障 Excel 直开中文列头与内容零乱码。
        with open(csv_path, "w", newline="", encoding=CSV_ENCODING) as fp:
            writer = csv.writer(fp, quoting=csv.QUOTE_MINIMAL, lineterminator="\r\n")
            writer.writerow(list(header))

            while True:
                batch = cursor.fetchmany(FETCH_BATCH_SIZE)
                if not batch:
                    break
                writer.writerows([tuple(row) for row in batch])
                row_count += len(batch)

        return row_count

    # ---- 汇总输出 ----

    @property
    def results(self) -> List[TaskResult]:
        """外部只读访问任务结果清单。"""
        return self._results

    def print_summary(self) -> None:
        """打印导出汇总表 (含逐任务状态、行数与耗时)。"""
        self._log.info("-" * 96)
        self._log.info("%-6s %-56s %12s %10s", "任务", "文件", "行数", "耗时(秒)")
        self._log.info("-" * 96)

        total_rows = 0
        failed: List[TaskResult] = []

        for r in sorted(self._results, key=lambda x: x.order):
            self._log.info(
                "%-6d %-56s %12s %10.1f",
                r.order,
                r.file_name[:56],
                f"{r.rows:,}" if r.status == "SUCCESS" else "FAILED",
                r.elapsed_sec,
            )
            if r.status == "SUCCESS":
                total_rows += r.rows
            else:
                failed.append(r)

        self._log.info("-" * 96)
        self._log.info(
            "%-6s %-56s %12s %10.1f",
            "合计",
            f"成功 {len(self._results) - len(failed)} / 共 {len(self._results)} 项",
            f"{total_rows:,}",
            sum(r.elapsed_sec for r in self._results),
        )
        self._log.info("-" * 96)

        if failed:
            self._log.error("[汇总] 失败任务清单:")
            for r in failed:
                self._log.error("  - 任务 %d [%s]: %s", r.order, r.file_prefix, r.message)
        else:
            self._log.info("[汇总] 全部 %d 项任务导出成功", len(self._results))


# ---------------------------------------------------------------------------------
# 9. 主流程入口 (Main Entry)
# ---------------------------------------------------------------------------------


def run() -> int:
    """
    导出主流程。

    返回
    ----
    int: 进程退出码 (0=全部成功, 1=存在失败任务, 2=配置/初始化异常)
    """
    logger = setup_console_logger()
    t_all_start = time.perf_counter()

    logger.info("")
    logger.info("#" * 96)
    logger.info("# 大连市皮肤病医院绩效测算 - 绩效核算基础数据 CSV 批量导出")
    logger.info("# 启动时间   : %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("# 全局时间戳 : %s", TIMESTAMP)
    logger.info("# Python     : %s", sys.version.split()[0])
    logger.info("# 项目根目录 : %s", BASE_DIR)
    logger.info("#" * 96)

    # ---- 1. 驱动探测与配置装配 ----
    config = DbConfig()
    try:
        driver = config.resolve_driver()
    except Exception as exc:
        logger.error("[环境异常] %s", exc)
        return 2

    logger.info("[运行配置] 目标数据库 : %s", config.alias)
    logger.info("[运行配置] ODBC 驱动 : %s", driver)

    # ---- 2. 输出目录与任务清单准备 ----
    output_dir = BASE_DIR / OUTPUT_DIR_NAME
    tasks = build_export_tasks()
    logger.info("[运行配置] 任务总数   : %d 项", len(tasks))
    logger.info("[运行配置] 输出目录   : %s", output_dir)
    logger.info("-" * 96)

    # ---- 3. 导出执行 (with 保证连接物理清理) ----
    exporter: Optional[PerformanceDataExporter] = None
    try:
        with PerformanceDataExporter(config, output_dir, logger) as active_exporter:
            exporter = active_exporter
            active_exporter.ensure_output_dir()
            for task in tasks:
                active_exporter.export_task(task)
    except Exception as exc:
        logger.error("[致命异常] 导出流程中断: %s", exc, exc_info=True)
        if exporter is not None and exporter.results:
            exporter.print_summary()
        return 1

    # ---- 4. 汇总与退出码 ----
    exporter.print_summary()
    total_sec = time.perf_counter() - t_all_start
    logger.info("[总耗时] %.1f 秒 (%.1f 分钟)", total_sec, total_sec / 60.0)
    logger.info("[输出目录] %s", output_dir)
    logger.info("[完成时间] %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

    failed = [r for r in exporter.results if r.status != "SUCCESS"]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run())
