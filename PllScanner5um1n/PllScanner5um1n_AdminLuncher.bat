@echo off
REM ===========================================
REM PII_Scan_Log.ps1 실행용 BAT (관리자 권한 자동 상승)
REM PowerShell ExecutionPolicy를 Bypass하고, 관리자 권한으로 실행
REM ===========================================

:: 현재 스크립트 경로 기준 PS1 지정
set "SCRIPT=%~dp0PllScanner5um1n.ps1"

:: 관리자 권한이 아닌 경우 → 관리자 권한으로 BAT 자체를 재실행
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] 관리자 권한이 필요합니다. 다시 관리자 권한으로 실행합니다...
    powershell -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

:: 여기부터는 관리자 권한 상태
echo [*] PowerShell 스크립트를 관리자 권한으로 실행합니다...
powershell.exe -ExecutionPolicy Bypass -File "%SCRIPT%"
pause
