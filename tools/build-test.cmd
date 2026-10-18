@echo off
rem Build with the automated visual test script (tools\debug\debug.aqua) swapped in.
setlocal
cd /d "%~dp0.."
copy /y src\debug.aqua build\debug.aqua.bak >nul
copy /y tools\debug\debug.aqua src\debug.aqua >nul
call tools\build.cmd %*
set RESULT=%ERRORLEVEL%
copy /y build\debug.aqua.bak src\debug.aqua >nul
exit /b %RESULT%
