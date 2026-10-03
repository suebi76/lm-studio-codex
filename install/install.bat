@echo off
setlocal
cd /d "%~dp0"
echo [lm-studio] Running installer...
powershell -NoLogo -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
set "EXITCODE=%ERRORLEVEL%"
if not "%EXITCODE%"=="0" (
  echo.
  echo [lm-studio] Installer failed with exit code %EXITCODE%.
  echo [lm-studio] Read the messages above for the required fix.
) else (
  echo.
  echo [lm-studio] Installer finished successfully.
)
echo.
pause
exit /b %EXITCODE%
