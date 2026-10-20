@echo off
rem Double-click helper: builds the debug APK and keeps the window open.
rem Pass -Release or -Install to change the mode, e.g.
rem   build_apk.cmd -Release -Install
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_apk.ps1" %*
echo.
pause
