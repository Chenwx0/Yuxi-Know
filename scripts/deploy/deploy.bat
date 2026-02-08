@echo off
REM ================================================================================
REM Yuxi-Know Windows 远程部署批处理脚本
REM 简化调用模式，适合 AI 自动执行
REM ================================================================================

setlocal enabledelayedexpansion

REM 设置 AI 模式（无需交互）
set AI_MODE=true

REM 转换命令行参数为 PowerShell 格式
set PS_ARGS=

:parse_args
if "%~1"=="" goto done_args
set PS_ARGS=%PS_ARGS% "%~1"
shift
goto parse_args

:done_args

REM 执行 PowerShell 脚本
powershell -ExecutionPolicy Bypass -NoProfile -Command "& '%~dp0deploy.ps1' %PS_ARGS%"

exit /b %ERRORLEVEL%
