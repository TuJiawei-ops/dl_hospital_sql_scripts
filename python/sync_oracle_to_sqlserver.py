#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
=================================================================================
 大连市皮肤病医院绩效测算 - Oracle -> SQL Server 数据同步脚本
=================================================================================

 功能概述
 --------
 将 Oracle 源端 DL_PFM Schema 下的 4 张 HIS 临时表, 幂等同步至本地
 SQL Server 目标库 hospital_performance_dalian_derma 的 dbo Schema。

 数据规模 (2026-09-11 实测)
 --------------------------
   PF临时医疗服务项目26A   12,206,289 行   ~2,432 MB
   PF临时转诊数据26A          263,292 行      ~56 MB
   PF临时收入院数据26A         20,012 行       ~3 MB
   PF临时出院数据26A           19,213 行     ~0.9 MB
   -------------------------------------------------
   合计                     ~12,508,806 行   ~2.5 GB

 技术选型说明 (为何不用 pandas 走热路径)
 --------------------------------------
 源端单表超过 1200 万行, 若使用 pandas.read_sql 会一次性将整表载入内存,
 在 2.5GB 物理数据下极易触发 OOM 或长时间 GC 停顿。因此本脚本热路径采用
 "流式游标 fetchmany + pyodbc fast_executemany" 的纯流式管道, 内存占用恒定
 与批尺寸 (SYNC_BATCH_SIZE) 成正比, 与表总行数无关。

 幂等策略
 --------
 每张表写入前先执行 TRUNCATE TABLE [dbo].[表名], 保证重复执行不产生重复数据。

 依赖
 ----
   pip install -r requirements.txt
   (oracledb 使用 thin mode, 无需安装 Oracle Instant Client)

 运行
 ----
   python sync_oracle_to_sqlserver.py

=================================================================================
 修改日志：
 2026-09-11 15:20:00 | 脚本新建 | 建立 Oracle -> SQL Server 流式批处理同步管道, 含幂等 TRUNCATE、
                                类型适配(NVARCHAR/BIGINT/DECIMAL(18,8)/DATETIME)、UTF-8 编码防护
=================================================================================
"""

from __future__ import annotations

import logging
import os
import sys
import time
from dataclasses import dataclass, field
from datetime import date, datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Dict, Iterable, Iterator, List, Optional, Sequence, Tuple

import oracledb
import pyodbc

# ---------------------------------------------------------------------------------
# 0. 全局常量
# ---------------------------------------------------------------------------------

# 脚本所在目录, 用于定位 .env (保证在任意工作目录下执行均可加载配置)
BASE_DIR: Path = Path(__file__).resolve().parent

# 数值字段类型: 遵循 .clinerules 第 7 节, 统一 DECIMAL(18,8), 禁止低精度类型
DECIMAL_PRECISION: int = 18
DECIMAL_SCALE: int = 8
# Oracle NUMBER 量化标度 (与 DECIMAL(18,8) 严格对齐)
QUANTIZE_EXP: Decimal = Decimal("1.00000000")

# 控制台进度输出节流: 每处理 N 行输出一次, 避免千万行刷屏拖慢同步
PROGRESS_EVERY_ROWS: int = 200_000

# 日志文件


# ---------------------------------------------------------------------------------
# 1. 表映射契约 (Table Contract)
# ---------------------------------------------------------------------------------


@dataclass(frozen=True)
class ColumnSpec:
    """
    单列规格契约。

    属性
    ----
    name       : 列名 (Oracle 与 SQL Server 两侧同名, 已人工核对一致)
    kind       : 语义类型, 决定 Python 侧的类型清洗策略
                 'str'      -> 文本, 清洗为 str
                 'int'      -> 整型标识 (BIGINT)
                 'decimal'  -> 高精度数值 (DECIMAL(18,8))
                 'datetime' -> 日期时间 (DATETIME)
    max_length : 目标 NVARCHAR 长度上限 (仅文本列), None 表示不校验
    """

    name: str
    kind: str
    max_length: Optional[int] = None


@dataclass(frozen=True)
class TableSpec:
    """单表同步契约: 源表、目标表、列清单。"""

    source_table: str
    target_table: str
    columns: Sequence[ColumnSpec] = field(default_factory=tuple)

    @property
    def column_names(self) -> List[str]:
        """列名清单, 用于生成两侧 SQL 的列投影。"""
        return [c.name for c in self.columns]


# ---------------------------------------------------------------------------------
# 1.1 列规格构造器
# ---------------------------------------------------------------------------------

_STR = "str"
_INT = "int"
_DEC = "decimal"
_DT = "datetime"


def _s(name: str, max_length: Optional[int] = None) -> ColumnSpec:
    """构造文本列规格 (目标列为 NVARCHAR)。"""
    return ColumnSpec(name=name, kind=_STR, max_length=max_length)


def _i(name: str) -> ColumnSpec:
    """构造整型标识列规格 (目标列为 BIGINT)。"""
    return ColumnSpec(name=name, kind=_INT)


def _d(name: str) -> ColumnSpec:
    """构造高精度数值列规格 (目标列为 DECIMAL(18,8))。"""
    return ColumnSpec(name=name, kind=_DEC)


def _t(name: str) -> ColumnSpec:
    """构造日期时间列规格 (目标列为 DATETIME)。"""
    return ColumnSpec(name=name, kind=_DT)

LOG_FILE: Path = BASE_DIR / "sync_oracle_to_sqlserver.log"



# ---------------------------------------------------------------------------------
# 1.2 同步表契约定义
#     严格对齐 sqlserver/his_PF*.sql (目标 DDL) 与 Oracle all_tab_columns (源端实测)
# ---------------------------------------------------------------------------------

TABLE_SPECS: Tuple[TableSpec, ...] = (
    TableSpec(
        source_table="PF临时出院数据26A",
        target_table="PF临时出院数据26A",
        columns=(
            _s("住院ID", 243),
            _i("出院科室代码"),
            _s("出院科室", 300),
            _t("出院时间"),
        ),
    ),
    TableSpec(
        source_table="PF临时收入院数据26A",
        target_table="PF临时收入院数据26A",
        columns=(
            _s("项目名称", 600),
            _i("开单科室代码"),
            _s("开单科室", 300),
            _i("开单人员代码"),
            _s("开单人", 123),
            _t("开单时间"),
            _i("执行科室代码"),
            _s("执行科室", 300),
            _i("执行人员代码"),
            _s("执行人员", 60),
            _t("入院登记时间"),
            _i("患者ID"),
            _s("挂号ID", 243),
        ),
    ),
    TableSpec(
        source_table="PF临时医疗服务项目26A",
        target_table="PF临时医疗服务项目26A",
        columns=(
            _s("项目大类", 60),
            _s("项目代码", 60),
            _s("项目名称", 600),
            _i("开单科室代码"),
            _s("开单科室", 300),
            _i("开单人员代码"),
            _s("开单人", 123),
            _t("开单时间"),
            _i("执行科室代码"),
            _s("执行科室", 300),
            _i("执行人员代码"),
            _s("执行人员", 60),
            _t("执行时间"),
            _d("数量"),
            _d("单价"),
            _d("金额"),
            _t("缴费时间"),
            _i("患者ID"),
            _s("挂号ID", 243),
            _i("HIS主键"),
            _s("来源", 12),
        ),
    ),
    TableSpec(
        source_table="PF临时转诊数据26A",
        target_table="PF临时转诊数据26A",
        columns=(
            _s("项目大类", 60),
            _s("项目代码", 60),
            _s("项目名称", 600),
            _i("转诊后开单科室代码"),
            _s("转诊后开单科室", 300),
            _i("转诊后开单人员代码"),
            _s("转诊开单人", 60),
            _t("转诊后开单时间"),
            _i("患者ID"),
            _s("挂号ID", 243),
            _i("首诊科室代码"),
            _s("首诊科室", 300),
            _i("首诊医生代码"),
            _s("首诊医生", 60),
            _t("执行时间"),
            _d("数量"),
            _d("单价"),
            _d("金额"),
            _t("缴费时间"),
            _i("HIS主键"),
            _s("来源", 12),
        ),
    ),
)



# ---------------------------------------------------------------------------------
# 2. 配置加载 (python-dotenv 隔离, 严禁连接串硬编码)
# ---------------------------------------------------------------------------------


@dataclass
class SyncConfig:
    """同步运行期配置快照。"""

    # Oracle 源端
    oracle_host: str
    oracle_port: int
    oracle_service_name: str
    oracle_user: str
    oracle_password: str
    oracle_schema: str

    # SQL Server 目标端
    mssql_host: str
    mssql_port: int
    mssql_user: str
    mssql_password: str
    mssql_database: str
    mssql_schema: str
    mssql_driver: str

    # 同步行为
    batch_size: int
    truncate_first: bool
    fast_executemany: bool
    command_timeout: int
    only_tables: List[str]

    # ---- 派生连接串 ----

    @property
    def oracle_dsn(self) -> str:
        """oracledb thin mode DSN: host:port/service_name"""
        return f"{self.oracle_host}:{self.oracle_port}/{self.oracle_service_name}"

    @property
    def mssql_conn_str(self) -> str:
        """
        构造 pyodbc 连接串。

        注意: 字符串字段统一声明为 Unicode, 避免中文/多字节在驱动层被
        按 ANSI(GBK) 转码造成乱码。
        """
        return (
            f"DRIVER={{{self.mssql_driver}}};"
            f"SERVER={self.mssql_host},{self.mssql_port};"
            f"DATABASE={self.mssql_database};"
            f"UID={self.mssql_user};"
            f"PWD={self.mssql_password};"
            f"TrustServerCertificate=yes;"
        )

    @property
    def mssql_alias(self) -> str:
        """脱敏后的目标端标识, 供日志输出 (不泄露口令)。"""
        return f"{self.mssql_host},{self.mssql_port}/{self.mssql_database}"

    @property
    def oracle_alias(self) -> str:
        """脱敏后的源端标识, 供日志输出 (不泄露口令)。"""
        return f"{self.oracle_host}:{self.oracle_port}/{self.oracle_service_name}"


def _env(key: str, default: Optional[str] = None, required: bool = False) -> str:
    """
    读取环境变量, 缺失时抛出明确错误而非静默使用空值。

    参数
    ----
    key      : 环境变量名
    default  : 缺省值
    required : 是否必填
    """
    value = os.getenv(key, default)
    if required and (value is None or value.strip() == ""):
        raise RuntimeError(
            f"缺少必需的环境变量 [{key}]。请复制 .env.example 为 .env 并补全连接参数。"
        )
    return "" if value is None else value


def _env_bool(key: str, default: bool) -> bool:
    """读取布尔型环境变量, 兼容 1/0/true/false/yes/no。"""
    raw = os.getenv(key)
    if raw is None or raw.strip() == "":
        return default
    return raw.strip().lower() in ("1", "true", "yes", "y", "on")



def load_config() -> SyncConfig:
    """
    加载 .env 并返回配置快照。

    使用 python-dotenv 将 BASE_DIR/.env 注入进程环境, 实现配置与代码物理隔离。
    """
    try:
        from dotenv import load_dotenv
    except ImportError as exc:  # pragma: no cover
        raise RuntimeError(
            "缺少 python-dotenv。请先执行: python -m pip install -r requirements.txt"
        ) from exc

    env_file = BASE_DIR / ".env"
    if env_file.exists():
        load_dotenv(dotenv_path=env_file, encoding="utf-8")
    else:
        # 无 .env 时回退到进程环境变量, 并给出提示
        print(
            f"[WARN] 未找到配置文件 {env_file}, 将仅使用进程环境变量。"
            f"建议复制 .env.example 为 .env。"
        )

    only_raw = _env("SYNC_ONLY_TABLES", "")
    only_tables = [t.strip() for t in only_raw.split(",") if t.strip()]

    return SyncConfig(
        oracle_host=_env("ORACLE_HOST", "192.168.130.32"),
        oracle_port=int(_env("ORACLE_PORT", "1521")),
        oracle_service_name=_env("ORACLE_SERVICE_NAME", "xepdb1"),
        oracle_user=_env("ORACLE_USER", required=True),
        oracle_password=_env("ORACLE_PASSWORD", required=True),
        oracle_schema=_env("ORACLE_SCHEMA", "DL_PFM"),
        mssql_host=_env("MSSQL_HOST", "127.0.0.1"),
        mssql_port=int(_env("MSSQL_PORT", "1433")),
        mssql_user=_env("MSSQL_USER", required=True),
        mssql_password=_env("MSSQL_PASSWORD", required=True),
        mssql_database=_env("MSSQL_DATABASE", required=True),
        mssql_schema=_env("MSSQL_SCHEMA", "dbo"),
        mssql_driver=_env("MSSQL_DRIVER", "ODBC Driver 17 for SQL Server"),
        batch_size=int(_env("SYNC_BATCH_SIZE", "10000")),
        truncate_first=_env_bool("SYNC_TRUNCATE_FIRST", True),
        fast_executemany=_env_bool("SYNC_FAST_EXECUTEMANY", True),
        command_timeout=int(_env("SYNC_COMMAND_TIMEOUT", "0")),
        only_tables=only_tables,
    )



# ---------------------------------------------------------------------------------
# 3. 日志配置 (控制台 + 文件双通道, UTF-8 强制)
# ---------------------------------------------------------------------------------


def setup_logger() -> logging.Logger:
    """
    构建同步专用日志器。

    控制台与文件均强制 UTF-8, 规避 Windows 默认 GBK 码页导致的
    中文表名/字段名乱码 (参见前期实测: 乱码事故)。
    """
    logger = logging.getLogger("sync_oracle_to_sqlserver")
    logger.setLevel(logging.INFO)
    logger.handlers.clear()
    logger.propagate = False

    fmt = logging.Formatter(
        fmt="%(asctime)s | %(levelname)-7s | %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # ---- 控制台通道 ----
    console = logging.StreamHandler(stream=sys.stdout)
    console.setFormatter(fmt)
    # Python 3.7+ 支持 reconfigure 强制 UTF-8 输出
    try:
        sys.stdout.reconfigure(encoding="utf-8")  # type: ignore[union-attr]
    except Exception:
        pass
    logger.addHandler(console)

    # ---- 文件通道 ----
    try:
        file_handler = logging.FileHandler(LOG_FILE, mode="a", encoding="utf-8")
        file_handler.setFormatter(fmt)
        logger.addHandler(file_handler)
    except Exception as exc:  # pragma: no cover
        logger.warning("日志文件 %s 无法写入, 仅使用控制台输出: %s", LOG_FILE, exc)

    return logger


# ---------------------------------------------------------------------------------
# 4. 数据清洗层 (类型适配与防抖)
# ---------------------------------------------------------------------------------


class RowCleaner:
    """
    行级类型清洗器。

    设计目标
    --------
    在数据离开 Oracle 游标、进入 pyodbc 参数绑定之前完成所有类型收敛,
    把"脏数据"拦截在写入前, 而不是让驱动层抛出难以定位的转换异常。

    处理策略
    --------
    str      : None 保持 None; 其余统一 str(), 并裁掉目标列长度外的溢出字符
               (Oracle BYTE 语义与 SQL Server NVARCHAR 字符语义存在换算差,
                长度超限时静默截断而非中断整批同步)
    int      : None -> None; Decimal/float 走 int() 截断小数; 无法解析 -> None
    decimal  : None -> None; 统一量化到 8 位小数, 保证与 DECIMAL(18,8) 同源同精度
    datetime : None -> None; date -> datetime; 非法值 -> None
    """

    def __init__(self, spec: TableSpec, logger: logging.Logger, row_soft_limit: int) -> None:
        self._spec = spec
        self._logger = logger
        self._row_soft_limit = row_soft_limit
        self._warn_count = 0

    def _warn(self, column: str, value: Any, reason: str) -> None:
        """统一收敛清洗告警, 避免千万行级别刷爆日志。"""
        self._warn_count += 1
        if self._warn_count <= self._row_soft_limit:
            self._logger.warning(
                "  [数据清洗] %s.%s 值=%r 已降级为 NULL (%s)",
                self._spec.target_table,
                column,
                value,
                reason,
            )
        elif self._warn_count == self._row_soft_limit + 1:
            self._logger.warning("  [数据清洗] 告警已达上限, 后续同类告警静默。")

    # ---- 各类型清洗实现 ----

    def _clean_str(self, value: Any, max_length: Optional[int]) -> Optional[str]:
        """文本清洗: 统一 str 并做长度兜底截断。"""
        if value is None:
            return None
        if isinstance(value, str):
            text = value
        else:
            text = str(value)
        if max_length is not None and len(text) > max_length:
            # 目标列长度不足: 静默截断, 防止整批 executemany 因单值超长失败
            text = text[:max_length]
        return text

    def _clean_int(self, value: Any, column: str) -> Optional[int]:
        """整型清洗: NUMBER 可能以 Decimal/float/str 形式返回。"""
        if value is None:
            return None
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, int):
            return value
        if isinstance(value, Decimal):
            return int(value)
        if isinstance(value, float):
            return int(value)
        try:
            return int(str(value).strip())
        except (ValueError, TypeError):
            self._warn(column, value, "无法解析为整数")
            return None

    def _clean_decimal(self, value: Any, column: str) -> Optional[Decimal]:
        """
        高精度数值清洗。

        遵循 .clinerules 第 7 节: 统一量化至 DECIMAL(18,8);
        同时防御 DECIMAL(18,8) 整数位溢出 (仅 10 位可用) 的极端脏值。
        """
        if value is None:
            return None
        try:
            dec = value if isinstance(value, Decimal) else Decimal(str(value))
        except (InvalidOperation, ValueError, TypeError):
            self._warn(column, value, "无法解析为 Decimal")
            return None
        # 量化到 8 位小数, 与目标列标度严格一致
        try:
            dec = dec.quantize(QUANTIZE_EXP)
        except InvalidOperation:
            self._warn(column, value, "量化到 8 位小数失败")
            return None
        # 整数位溢出保护: DECIMAL(18,8) 允许最大绝对值 < 10^10
        if abs(dec) >= Decimal(10) ** (DECIMAL_PRECISION - DECIMAL_SCALE):
            self._warn(column, value, "超出 DECIMAL(18,8) 表示范围")
            return None
        return dec

    def _clean_datetime(self, value: Any, column: str) -> Optional[datetime]:
        """日期时间清洗: date 升格为 datetime, 非法结构降级为 NULL。"""
        if value is None:
            return None
        if isinstance(value, datetime):
            return value
        if isinstance(value, date):
            return datetime(value.year, value.month, value.day)
        if isinstance(value, str):
            text = value.strip()
            for pattern in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%Y/%m/%d %H:%M:%S", "%Y/%m/%d"):
                try:
                    return datetime.strptime(text, pattern)
                except ValueError:
                    continue
        self._warn(column, value, "无法解析为 DATETIME")
        return None

    # ---- 对外唯一入口 ----

    def clean_row(self, row: Sequence[Any]) -> List[Any]:
        """
        清洗单行, 返回与列顺序严格对齐的 Python 值列表。
        """
        cleaned: List[Any] = []
        for spec, value in zip(self._spec.columns, row):
            if spec.kind == _STR:
                cleaned.append(self._clean_str(value, spec.max_length))
            elif spec.kind == _INT:
                cleaned.append(self._clean_int(value, spec.name))
            elif spec.kind == _DEC:
                cleaned.append(self._clean_decimal(value, spec.name))
            elif spec.kind == _DT:
                cleaned.append(self._clean_datetime(value, spec.name))
            else:  # pragma: no cover - 契约定义错误
                raise ValueError(f"未知列类型 kind={spec.kind!r} (列 {spec.name})")
        return cleaned

    @property
    def warn_count(self) -> int:
        """累计清洗告警数, 用于同步结束后的数据质量提示。"""
        return self._warn_count



# ---------------------------------------------------------------------------------
# 5. 同步统计容器
# ---------------------------------------------------------------------------------


@dataclass
class TableResult:
    """单表同步结果记录。"""

    table: str
    source_rows: int = 0
    written_rows: int = 0
    elapsed_sec: float = 0.0
    status: str = "PENDING"
    message: str = ""
    clean_warnings: int = 0

    @property
    def rows_per_sec(self) -> float:
        """吞吐速率 (行/秒), 用于性能评估。"""
        if self.elapsed_sec <= 0:
            return 0.0
        return self.written_rows / self.elapsed_sec


# ---------------------------------------------------------------------------------
# 6. 同步引擎
# ---------------------------------------------------------------------------------


class OracleToSqlServerSyncer:
    """
    Oracle -> SQL Server 流式同步引擎。

    生命周期
    --------
    __enter__  建立两端连接, 校验目标表存在性与列契约一致性
    sync_all   逐表执行 TRUNCATE + 流式批写入
    __exit__   无条件关闭游标与连接 (含异常路径)
    """

    def __init__(self, config: SyncConfig, logger: logging.Logger) -> None:
        self._cfg = config
        self._log = logger
        self._ora_conn: Optional[oracledb.Connection] = None
        self._ms_conn: Optional[pyodbc.Connection] = None
        self._results: List[TableResult] = []

    # ---------- 上下文管理: 保证物理关闭 ----------

    def __enter__(self) -> "OracleToSqlServerSyncer":
        self._open_oracle()
        self._open_mssql()
        self._validate_target_tables()
        return self

    def __exit__(self, exc_type: Any, exc_val: Any, exc_tb: Any) -> bool:
        """
        无论成功或异常, 均确保游标与连接被物理关闭。

        返回 False 表示不吞掉异常, 交由上层处理。
        """
        self._log.info("-" * 86)
        self._log.info("[资源回收] 关闭数据库连接")
        self._close_mssql()
        self._close_oracle()
        return False

    # ---------- 连接建立 ----------

    def _open_oracle(self) -> None:
        """建立 Oracle 连接 (thin mode, 失败即抛出)。"""
        self._log.info(
            "[连接源端] Oracle %s (user=%s, schema=%s)",
            self._cfg.oracle_alias,
            self._cfg.oracle_user,
            self._cfg.oracle_schema,
        )
        self._ora_conn = oracledb.connect(
            user=self._cfg.oracle_user,
            password=self._cfg.oracle_password,
            dsn=self._cfg.oracle_dsn,
        )
        # 说明: 预取调优 (arraysize/prefetchrows) 在每张表的游标上单独设置,
        #       见 _sync_one_table。oracledb 4.x 已移除 Connection.defaults 属性,
        #       此处不做连接级设置, 避免版本耦合。
        self._log.info("[连接源端] Oracle 连接成功")

    def _open_mssql(self) -> None:
        """建立 SQL Server 连接, 并开启 fast_executemany 加速。"""
        self._log.info("[连接目标] SQL Server %s (user=%s)", self._cfg.mssql_alias, self._cfg.mssql_user)
        try:
            self._ms_conn = pyodbc.connect(
                self._cfg.mssql_conn_str,
                timeout=30,
                autocommit=False,
            )
        except pyodbc.Error as exc:
            raise RuntimeError(
                f"SQL Server 连接失败: {self._cfg.mssql_alias}\n"
                f"原始异常: {exc}\n"
                f"请检查: 1) 服务是否启动  2) 账号口令  3) 驱动 [{self._cfg.mssql_driver}] 是否安装"
            ) from exc

        # 命令超时: 0 表示不限时 (千万行写入必须放宽)
        self._ms_conn.timeout = self._cfg.command_timeout
        self._log.info("[连接目标] SQL Server 连接成功 (CommandTimeout=%s)", self._cfg.command_timeout)

    def _close_oracle(self) -> None:
        """安全关闭 Oracle 连接。"""
        if self._ora_conn is not None:
            try:
                self._ora_conn.close()
                self._log.info("[资源回收] Oracle 连接已关闭")
            except Exception as exc:  # pragma: no cover
                self._log.warning("[资源回收] Oracle 连接关闭异常: %s", exc)
            finally:
                self._ora_conn = None

    def _close_mssql(self) -> None:
        """安全关闭 SQL Server 连接。"""
        if self._ms_conn is not None:
            try:
                self._ms_conn.close()
                self._log.info("[资源回收] SQL Server 连接已关闭")
            except Exception as exc:  # pragma: no cover
                self._log.warning("[资源回收] SQL Server 连接关闭异常: %s", exc)
            finally:
                self._ms_conn = None

    # ---------- 目标表契约校验 ----------

    def _validate_target_tables(self) -> None:
        """
        校验目标表存在性与列契约一致性。

        在写入前拦截"表不存在"或"列名错位"这类结构性错误,
        避免出现 TRUNCATE 成功但 INSERT 失败的半污染状态。
        """
        assert self._ms_conn is not None
        self._log.info("-" * 86)
        self._log.info("[契约校验] 核对目标表结构与列定义")

        cursor = self._ms_conn.cursor()
        try:
            for spec in self._specs_to_sync():
                cursor.execute(
                    """
                    SELECT COLUMN_NAME
                      FROM INFORMATION_SCHEMA.COLUMNS
                     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
                     ORDER BY ORDINAL_POSITION
                    """,
                    self._cfg.mssql_schema,
                    spec.target_table,
                )
                target_cols = [row[0] for row in cursor.fetchall()]

                if not target_cols:
                    raise RuntimeError(
                        f"目标表不存在: [{self._cfg.mssql_schema}].[{spec.target_table}]。"
                        f"请先执行 sqlserver/ 目录下的建表脚本。"
                    )

                expected = list(spec.column_names)
                if target_cols != expected:
                    missing = [c for c in expected if c not in target_cols]
                    extra = [c for c in target_cols if c not in expected]
                    raise RuntimeError(
                        f"目标表 [{spec.target_table}] 列契约不一致。\n"
                        f"  期望列: {expected}\n"
                        f"  实际列: {target_cols}\n"
                        f"  缺失列: {missing}\n"
                        f"  多余列: {extra}"
                    )
                self._log.info("  [OK] %s 列数=%d 契约一致", spec.target_table, len(target_cols))
        finally:
            cursor.close()

        self._log.info("[契约校验] 全部通过")

    def _specs_to_sync(self) -> Tuple[TableSpec, ...]:
        """按 SYNC_ONLY_TABLES 过滤出本次需同步的表契约。"""
        if not self._cfg.only_tables:
            return TABLE_SPECS
        selected = tuple(s for s in TABLE_SPECS if s.target_table in self._cfg.only_tables)
        if not selected:
            raise RuntimeError(
                f"SYNC_ONLY_TABLES 未匹配到任何已定义表: {self._cfg.only_tables}"
            )
        return selected

    # ---------- SQL 构造 ----------

    @staticmethod
    def _quote_mssql(identifier: str) -> str:
        """SQL Server 标识符方括号包裹, 并转义内部右括号。"""
        return "[" + identifier.replace("]", "]]") + "]"

    def _build_source_sql(self, spec: TableSpec) -> str:
        """
        构造 Oracle 侧 SELECT 语句。

        要点
        ----
        1. 显式限定 DL_PFM Schema: 实测源端 SYSTEM 模式下存在 3 张同名表,
           不限定 owner 会命中歧义或错误目标。
        2. 列名与表名使用双引号 (Oracle 区分大小写标识符)。
        3. 强制按列清单投影, 严禁 SELECT *, 保证与目标列顺序严格对齐。
        """
        cols = ", ".join(f'"{c}"' for c in spec.column_names)
        return f'SELECT {cols} FROM "{self._cfg.oracle_schema}"."{spec.source_table}"'

    def _build_insert_sql(self, spec: TableSpec) -> str:
        """构造 SQL Server 侧 INSERT 语句 (列投影与源端严格同序)。"""
        cols = ", ".join(self._quote_mssql(c) for c in spec.column_names)
        placeholders = ", ".join("?" for _ in spec.column_names)
        return (
            f"INSERT INTO {self._quote_mssql(self._cfg.mssql_schema)}"
            f".{self._quote_mssql(spec.target_table)} ({cols}) VALUES ({placeholders})"
        )

    def _truncate_target(self, spec: TableSpec) -> None:
        """
        幂等清空: TRUNCATE TABLE 目标表。

        独立提交, 保证清空动作先于写入落定。
        """
        assert self._ms_conn is not None
        sql = (
            f"TRUNCATE TABLE {self._quote_mssql(self._cfg.mssql_schema)}"
            f".{self._quote_mssql(spec.target_table)}"
        )
        cursor = self._ms_conn.cursor()
        try:
            cursor.execute(sql)
            self._ms_conn.commit()
            self._log.info("  [幂等清空] TRUNCATE TABLE 已完成")
        finally:
            cursor.close()


    # ---------- 核心: 单表流式同步 ----------

    def _sync_one_table(self, spec: TableSpec) -> TableResult:
        """
        执行单表同步: TRUNCATE -> 流式抽取 -> 分批写入。

        流程
        ----
        1. TRUNCATE 目标表 (幂等)
        2. 打开 Oracle 服务端游标, 执行 SELECT
        3. 循环 fetchmany(batch_size) 拉取一批
        4. 逐行清洗 (RowCleaner) 后 executemany 写入
        5. 每批 commit, 并输出节流进度

        返回
        ----
        TableResult: 含抽取/写入行数、耗时、状态。
        """
        assert self._ora_conn is not None and self._ms_conn is not None
        result = TableResult(table=spec.target_table)
        t_start = time.perf_counter()

        self._log.info("=" * 86)
        self._log.info("[开始同步] %s", spec.target_table)
        self._log.info("  源表   : %s.%s", self._cfg.oracle_schema, spec.source_table)
        self._log.info("  目标表 : %s.%s", self._cfg.mssql_schema, spec.target_table)
        self._log.info(
            "  列数   : %d | 批尺寸: %d | fast_executemany: %s",
            len(spec.columns),
            self._cfg.batch_size,
            self._cfg.fast_executemany,
        )
        self._log.info("  开始时间: %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

        # ---- Step 1: 幂等清空 ----
        if self._cfg.truncate_first:
            self._truncate_target(spec)
        else:
            self._log.info("  [幂等清空] 已跳过 (SYNC_TRUNCATE_FIRST=0)")

        source_sql = self._build_source_sql(spec)
        insert_sql = self._build_insert_sql(spec)
        cleaner = RowCleaner(spec, self._log, row_soft_limit=20)

        ora_cur: Optional[oracledb.Cursor] = None
        ms_cur: Optional[pyodbc.Cursor] = None

        try:
            # ---- Step 2: 打开源端游标 ----
            ora_cur = self._ora_conn.cursor()
            ora_cur.arraysize = self._cfg.batch_size
            ora_cur.prefetchrows = self._cfg.batch_size + 1
            ora_cur.execute(source_sql)

            # ---- Step 3: 打开目标端游标 ----
            ms_cur = self._ms_conn.cursor()
            if self._cfg.fast_executemany:
                # 启用 C 层批量绑定: 相比逐行 executemany 可提速数倍至数十倍
                ms_cur.fast_executemany = True

            # ---- Step 4: 流式抽取 + 分批写入 ----
            while True:
                batch = ora_cur.fetchmany(self._cfg.batch_size)
                if not batch:
                    break

                cleaned_rows = [cleaner.clean_row(row) for row in batch]
                ms_cur.executemany(insert_sql, cleaned_rows)
                self._ms_conn.commit()

                result.source_rows += len(batch)
                result.written_rows += len(cleaned_rows)

                # 节流进度输出
                if result.written_rows % PROGRESS_EVERY_ROWS < self._cfg.batch_size:
                    elapsed = time.perf_counter() - t_start
                    rate = result.written_rows / elapsed if elapsed > 0 else 0.0
                    self._log.info(
                        "  [进度] 已写入 %s 行 | 耗时 %.1fs | %.0f 行/秒",
                        f"{result.written_rows:,}",
                        elapsed,
                        rate,
                    )

            result.status = "SUCCESS"
            self._ms_conn.commit()

        except pyodbc.Error as exc:
            self._ms_conn.rollback()
            result.status = "FAILED"
            result.message = f"SQL Server 写入失败: {exc}"
            self._log.error("  [失败] %s", result.message)
            raise
        except oracledb.Error as exc:
            self._ms_conn.rollback()
            result.status = "FAILED"
            result.message = f"Oracle 读取失败: {exc}"
            self._log.error("  [失败] %s", result.message)
            raise
        finally:
            # 游标物理关闭 (顺序: 先目标后源端)
            if ms_cur is not None:
                try:
                    ms_cur.close()
                except Exception:
                    pass
            if ora_cur is not None:
                try:
                    ora_cur.close()
                except Exception:
                    pass

            result.elapsed_sec = time.perf_counter() - t_start
            result.clean_warnings = cleaner.warn_count
            self._results.append(result)

        # ---- Step 5: 单表结果汇总 ----
        self._log.info("  结束时间: %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
        self._log.info(
            "  [完成] %s | 抽取 %s 行 | 写入 %s 行 | 耗时 %.1fs | %.0f 行/秒 | 清洗告警 %d",
            spec.target_table,
            f"{result.source_rows:,}",
            f"{result.written_rows:,}",
            result.elapsed_sec,
            result.rows_per_sec,
            result.clean_warnings,
        )
        return result


    # ---------- 编排: 全部表同步 ----------

    def sync_all(self) -> List[TableResult]:
        """
        按契约顺序依次同步全部 (或筛选后的) 表。

        每张表独立捕获异常: 单表失败不阻断后续表同步,
        最终由 run() 汇总失败清单并以非零码退出。
        """
        specs = self._specs_to_sync()
        self._log.info("[同步计划] 本次待同步 %d 张表", len(specs))
        for idx, s in enumerate(specs, start=1):
            self._log.info("  %d) %s -> %s", idx, s.source_table, s.target_table)
        self._log.info("-" * 86)

        for spec in specs:
            try:
                self._sync_one_table(spec)
            except Exception as exc:
                # 单表失败记录后继续, 便于一次性暴露全部问题
                self._log.error("[中断] 表 %s 同步失败, 继续处理后续表: %s", spec.target_table, exc)
                if not any(r.table == spec.target_table for r in self._results):
                    self._results.append(
                        TableResult(
                            table=spec.target_table,
                            status="FAILED",
                            message=str(exc),
                        )
                    )
        return self._results

    # ---------- 结果汇总 ----------

    def print_summary(self) -> None:
        """输出同步结果汇总表与数据质量提示。"""
        self._log.info("=" * 86)
        self._log.info("[同步汇总]")
        self._log.info(
            "%-28s %-10s %12s %12s %10s %12s",
            "目标表", "状态", "抽取行数", "写入行数", "耗时(秒)", "速率(行/秒)",
        )
        self._log.info("-" * 86)

        total_src = 0
        total_written = 0
        total_sec = 0.0
        failed: List[str] = []

        for r in self._results:
            self._log.info(
                "%-28s %-10s %12s %12s %10.1f %12.0f",
                r.table,
                r.status,
                f"{r.source_rows:,}",
                f"{r.written_rows:,}",
                r.elapsed_sec,
                r.rows_per_sec,
            )
            if r.status == "SUCCESS":
                total_src += r.source_rows
                total_written += r.written_rows
                total_sec += r.elapsed_sec
            else:
                failed.append(r.table)

        self._log.info("-" * 86)
        self._log.info(
            "%-28s %-10s %12s %12s %10.1f %12.0f",
            "合计",
            "SUCCESS" if not failed else "PARTIAL",
            f"{total_src:,}",
            f"{total_written:,}",
            total_sec,
            (total_written / total_sec) if total_sec > 0 else 0.0,
        )
        self._log.info("=" * 86)

        # ---- 数据质量提示 ----
        warning_tables = [r for r in self._results if r.clean_warnings > 0]
        if warning_tables:
            self._log.warning("[数据质量] 以下表存在类型清洗告警, 建议人工核查:")
            for r in warning_tables:
                self._log.warning("  - %s: %d 条告警", r.table, r.clean_warnings)

        if failed:
            self._log.error("[同步汇总] 失败表清单: %s", ", ".join(failed))
        else:
            self._log.info("[同步汇总] 全部表同步成功")

    @property
    def results(self) -> List[TableResult]:
        """外部只读访问同步结果。"""
        return self._results



# ---------------------------------------------------------------------------------
# 7. 主流程入口
# ---------------------------------------------------------------------------------


def run() -> int:
    """
    同步主流程。

    返回
    ----
    int: 进程退出码 (0=全部成功, 1=存在失败表, 2=配置/初始化异常)
    """
    logger = setup_logger()
    t_all_start = time.perf_counter()

    logger.info("")
    logger.info("#" * 86)
    logger.info("# 大连市皮肤病医院绩效测算 - Oracle -> SQL Server 数据同步")
    logger.info("# 启动时间: %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    logger.info("# Python  : %s", sys.version.split()[0])
    logger.info("#" * 86)

    # ---- 配置加载 ----
    try:
        cfg = load_config()
    except Exception as exc:
        logger.error("[配置异常] %s", exc)
        return 2

    logger.info("[运行配置] 源端 Oracle  : %s (schema=%s)", cfg.oracle_alias, cfg.oracle_schema)
    logger.info("[运行配置] 目标 SQLServer: %s (schema=%s)", cfg.mssql_alias, cfg.mssql_schema)
    logger.info("[运行配置] ODBC 驱动    : %s", cfg.mssql_driver)
    logger.info("[运行配置] 批尺寸       : %d", cfg.batch_size)
    logger.info("[运行配置] 幂等清空     : %s", "启用" if cfg.truncate_first else "禁用")
    logger.info("[运行配置] 快速批量     : %s", "启用" if cfg.fast_executemany else "禁用")
    logger.info("[运行配置] 日志文件     : %s", LOG_FILE)

    # ---- 同步执行 (上下文管理器保证连接物理关闭) ----
    syncer: Optional[OracleToSqlServerSyncer] = None
    try:
        with OracleToSqlServerSyncer(cfg, logger) as active_syncer:
            syncer = active_syncer
            syncer.sync_all()
    except Exception as exc:
        logger.error("[致命异常] 同步流程中断: %s", exc, exc_info=True)
        if syncer is not None and syncer.results:
            syncer.print_summary()
        return 1

    # ---- 汇总 ----
    syncer.print_summary()
    total_sec = time.perf_counter() - t_all_start
    logger.info("[总耗时] %.1f 秒 (%.1f 分钟)", total_sec, total_sec / 60.0)
    logger.info("[完成时间] %s", datetime.now().strftime("%Y-%m-%d %H:%M:%S"))

    failed = [r for r in syncer.results if r.status != "SUCCESS"]
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(run())
