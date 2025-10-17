@echo off
REM ===========================================
REM PII_Scan_Log.ps1 실행용 BAT
REM PowerShell ExecutionPolicy를 일시적으로 Bypass하고 스크립트 실행
REM ===========================================

powershell.exe -ExecutionPolicy Bypass -File "%~dp0P11Scanner5um1n.ps1"
pause
