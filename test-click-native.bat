@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SPATIAL_CLICK_TEST_PATH=native"
call "%~dp0play-dovi-atmos.bat" %*
exit /b %ERRORLEVEL%
