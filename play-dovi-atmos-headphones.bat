@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "RELEASES=%ROOT%\releases"
set "CONFIG=%ROOT%\omniphony-headphones.config.yaml"
set "INPUT_CONFIG=%ROOT%\mpv-input.conf"

if exist "%RELEASES%\" goto :releases_ok
echo ERROR: releases directory not found:
echo   "%RELEASES%"
exit /b 1

:releases_ok
if exist "%CONFIG%" goto :config_ok
echo ERROR: config file not found:
echo   "%CONFIG%"
exit /b 1

:config_ok
if exist "%INPUT_CONFIG%" goto :input_config_ok
echo ERROR: mpv input config file not found:
echo   "%INPUT_CONFIG%"
exit /b 1

:input_config_ok
set "MPV="
set "SPATIAL_MPV_DIR=%RELEASES%\mpv-omniphony-fel-windows-x86_64-ispatial"
if exist "%SPATIAL_MPV_DIR%\mpv.com" (
    set "MPV=%SPATIAL_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%SPATIAL_MPV_DIR%\mpv.exe" (
    set "MPV=%SPATIAL_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
for /f "delims=" %%F in ('dir /b /s /a:-d "%RELEASES%\mpv.com" 2^>nul') do (
    set "MPV=%%F"
    goto :found_mpv
)
for /f "delims=" %%F in ('dir /b /s /a:-d "%RELEASES%\mpv.exe" 2^>nul') do (
    set "MPV=%%F"
    goto :found_mpv
)

:found_mpv
if defined MPV goto :mpv_ok
echo ERROR: mpv.com or mpv.exe was not found under:
echo   "%RELEASES%"
exit /b 1

:mpv_ok
set "BRIDGE="
for /f "delims=" %%F in ('dir /b /s /a:-d "%RELEASES%\harletty_bridge.dll" 2^>nul') do set "BRIDGE=%%F" & goto :found_bridge

:found_bridge
if defined BRIDGE goto :bridge_ok
echo ERROR: harletty_bridge.dll was not found under:
echo   "%RELEASES%"
exit /b 1

:bridge_ok
echo.
echo Start Omniphony Studio first. Keep it open, then enter the movie path below.
echo You can drag and drop the movie file into this window, then press Enter.
echo.

set "MOVIE=%~1"
if defined MOVIE goto :movie_path_ready
set /p "MOVIE=Movie path: "

:movie_path_ready
if defined MOVIE goto :movie_path_not_empty
echo ERROR: movie path is empty.
exit /b 1

:movie_path_not_empty
rem Drag-and-drop or copied paths may include wrapping quotes.
set "MOVIE=%MOVIE:"=%"

if exist "%MOVIE%" goto :movie_exists
echo ERROR: movie file not found:
echo   "%MOVIE%"
exit /b 1

:movie_exists
echo.
echo Using mpv:
echo   "%MPV%"
echo Using bridge:
echo   "%BRIDGE%"
echo Using config:
echo   "%CONFIG%"
echo Using input config:
echo   "%INPUT_CONFIG%"
echo.

"%MPV%" --vo=gpu-next --target-colorspace-hint=yes --ad=orender --ao=wasapi-spatial,wasapi "--input-conf=%INPUT_CONFIG%" --script-opts-append=stats-persistent_overlay=yes --script-opts-append=stats-redraw_delay=0.25 "--ad-orender-config=%CONFIG%" "--ad-orender-bridge-path=%BRIDGE%" --ad-orender-osc "%MOVIE%"
set "MPV_EXIT=%ERRORLEVEL%"

if "%MPV_EXIT%"=="0" goto :done
echo.
echo mpv exited with code %MPV_EXIT%.

:done
exit /b %MPV_EXIT%
