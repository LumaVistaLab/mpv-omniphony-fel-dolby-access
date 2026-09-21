@echo off
setlocal EnableExtensions DisableDelayedExpansion
set "SPATIAL_CLICK_TEST_MUTE=1"
call "%~dp0play-dovi-atmos.bat" %*
exit /b %ERRORLEVEL%
