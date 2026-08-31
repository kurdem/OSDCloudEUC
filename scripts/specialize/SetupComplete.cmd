@echo off
REM ============================================================================
REM  OSDCloudEUC SetupComplete Wrapper
REM  Windows fuehrt C:\Windows\Setup\Scripts\SetupComplete.cmd nach der
REM  Installation automatisch aus. Dieser Wrapper ruft das PowerShell-Skript auf,
REM  das die Post-Install-Schritte (Treiber, Updates, Rename, Enrollment) steuert.
REM ============================================================================
set PS_SCRIPT=%~dp0SetupComplete.ps1
if not exist "%PS_SCRIPT%" set PS_SCRIPT=C:\Windows\Setup\Scripts\SetupComplete.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%PS_SCRIPT%"
exit /b 0
