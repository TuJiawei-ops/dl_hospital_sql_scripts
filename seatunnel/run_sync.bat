@echo off
REM =================================================================================
REM  大连市皮肤病医院绩效测算 - Oracle -> SQL Server 一键同步启动器
REM =================================================================================
REM
REM  用法
REM  ----
REM   本文件所在目录下双击运行即可, 无需任何额外参数。
REM   执行链路: run_sync.bat -> D:\Software\apache-seatunnel-2.3.8\bin\seatunnel.cmd
REM                                 --config <本目录>\oracle_to_sqlserver.conf
REM
REM  说明
REM  ----
REM   1. 以 %%~dp0 (本批处理所在目录) 为基准解析配置绝对路径, 与调用者工作目录解耦;
REM   2. 强制 UTF-8 码页, 保证中文表名/字段名日志不乱码;
REM   3. 执行前校验 SeaTunnel 主程序与 JDBC 驱动 (ojdbc8 / mssql-jdbc) 是否就位;
REM   4. 同步过程日志同时落盘至本目录 logs\sync_YYYYMMDD_HHMMSS.log;
REM   5. 透传 SeaTunnel 退出码, 便于任务编排平台 (如 Windows 计划任务/Jenkins) 判定成败。
REM
REM  =================================================================================
REM  修改日志：
REM  2026-09-11 16:30:00 | 脚本新建 | 建立 SeaTunnel Oracle->SQL Server 一键同步启动器,
REM                                 含 UTF-8 码页锁定、依赖前置校验、日志落盘与退出码透传
REM  =================================================================================

setlocal enabledelayedexpansion

REM ---- 强制 UTF-8 码页, 并在退出时恢复原始码页 ----
for /f "tokens=2 delims=:" %%a in ('chcp') do set "OLD_CP=%%a"
set "OLD_CP=%OLD_CP: =%"
chcp 65001 >nul 2>&1

REM ---- 路径常量 (SEATUNNEL_HOME 允许外部覆盖) ----
set "SCRIPT_DIR=%~dp0"
if "%SCRIPT_DIR:~-1%"=="\" set "SCRIPT_DIR=%SCRIPT_DIR:~0,-1%"
if not defined SEATUNNEL_HOME set "SEATUNNEL_HOME=D:\Software\apache-seatunnel-2.3.8"
set "SEATUNNEL_BIN=%SEATUNNEL_HOME%\bin\seatunnel.cmd"
set "CONF_FILE=%SCRIPT_DIR%\oracle_to_sqlserver.conf"
set "LOG_DIR=%SCRIPT_DIR%\logs"

echo ================================================================================
echo  大连市皮肤病医院绩效测算 - Oracle -^> SQL Server 数据同步 (SeaTunnel)
echo ================================================================================
echo  [信息] 执行时间   : %date% %time%
echo  [信息] 配置目录   : %SCRIPT_DIR%
echo  [信息] 配置文件   : %CONF_FILE%
echo  [信息] SeaTunnel  : %SEATUNNEL_HOME%
echo --------------------------------------------------------------------------------

REM ---- 前置校验 1: SeaTunnel 主程序 ----
if not exist "%SEATUNNEL_BIN%" (
    echo  [错误] 未找到 SeaTunnel 启动器: "%SEATUNNEL_BIN%"
    echo  [错误] 请确认 SeaTunnel 安装路径, 或设置环境变量 SEATUNNEL_HOME 后重试。
    set "EXIT_CODE=2"
    goto :finish
)

REM ---- 前置校验 2: 同步配置文件 ----
if not exist "%CONF_FILE%" (
    echo  [错误] 未找到同步配置文件: "%CONF_FILE%"
    set "EXIT_CODE=2"
    goto :finish
)

REM ---- 前置校验 3: JDBC 驱动 ----
if not exist "%SEATUNNEL_HOME%\lib\ojdbc8-19.3.0.0.jar" (
    echo  [警告] 未在 %SEATUNNEL_HOME%\lib 下发现 ojdbc8-19.3.0.0.jar
    echo  [警告] Oracle 源端连接可能失败, 请补充 Oracle JDBC 驱动至 lib 目录。
)
if not exist "%SEATUNNEL_HOME%\lib\mssql-jdbc-12.4.2.jre8.jar" (
    echo  [警告] 未在 %SEATUNNEL_HOME%\lib 下发现 mssql-jdbc-12.4.2.jre8.jar
    echo  [警告] SQL Server 目标端写入可能失败, 请补充 mssql-jdbc 驱动至 lib 目录。
)

REM ---- JAVA 环境校验 ----
where java >nul 2>&1
if errorlevel 1 (
    echo  [错误] 未检测到 java 命令, 请安装 JDK 8/11 并配置 JAVA_HOME 与 PATH。
    set "EXIT_CODE=2"
    goto :finish
)

REM ---- 日志目录 ----
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%" >nul 2>&1
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "STAMP=%%t"
if not defined STAMP set "STAMP=run"
set "LOG_FILE=%LOG_DIR%\sync_%STAMP%.log"

echo  [信息] 同步日志   : %LOG_FILE%
echo --------------------------------------------------------------------------------
echo  [执行] 开始同步, 请稍候 (千万级大表约需数分钟)...
echo --------------------------------------------------------------------------------

REM ---- 执行同步 (控制台实时输出 + 同步落盘) ----
powershell -NoProfile -ExecutionPolicy Bypass -Command "& '%SEATUNNEL_BIN%' --config '%CONF_FILE%' 2>&1 | Tee-Object -FilePath '%LOG_FILE%'; exit $LASTEXITCODE"
set "EXIT_CODE=%ERRORLEVEL%"

if "%EXIT_CODE%"=="0" (
    echo --------------------------------------------------------------------------------
    echo  [完成] 数据同步成功。日志: %LOG_FILE%
) else (
    echo --------------------------------------------------------------------------------
    echo  [失败] 数据同步异常中断, 退出码 = %EXIT_CODE%
    echo  [失败] 请查阅日志定位失败根因: %LOG_FILE%
)
echo ================================================================================

:finish
chcp %OLD_CP% >nul 2>&1
endlocal & exit /b %EXIT_CODE%
