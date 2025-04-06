@echo off
:: 检查是否有管理员权限
net session >nul 2>&1
if %errorLevel% NEQ 0 (
    echo 请求管理员权限...
    powershell -Command "Start-Process '%~f0' -Verb runAs"
    exit /b
)

:: 有权限后运行 mihomo
set WS=%~dp0
"%WS%mihomo.exe" -d . > run.logs 2>&1
