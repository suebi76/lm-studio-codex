@echo off
set "ROOT=%~dp0.."
powershell -NoLogo -ExecutionPolicy Bypass -File "%ROOT%\lib\status.ps1" %*
