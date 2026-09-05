@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "RELEASES=%ROOT%\releases"
set "DISTRIBUTION=%ROOT%\distribution"
set "CONFIG=%ROOT%\omniphony-dolby-access.config.yaml"
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
if not defined MPV_SPATIAL goto :find_default_mpv
if exist "%MPV_SPATIAL%" (
    set "MPV=%MPV_SPATIAL%"
    goto :found_mpv
)
echo ERROR: MPV_SPATIAL points to a missing file:
echo   "%MPV_SPATIAL%"
exit /b 1

:find_default_mpv
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "SPATIAL_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ispatial"
if exist "%SPATIAL_MPV_DIR%\mpv.com" (
    set "MPV=%SPATIAL_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%SPATIAL_MPV_DIR%\mpv.exe" (
    set "MPV=%SPATIAL_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
for /f "delims=" %%F in ('dir /b /s /a:-d "%DISTRIBUTION%\mpv.com" 2^>nul') do (
    set "MPV=%%F"
    goto :found_mpv
)
for /f "delims=" %%F in ('dir /b /s /a:-d "%DISTRIBUTION%\mpv.exe" 2^>nul') do (
    set "MPV=%%F"
    goto :found_mpv
)

:found_mpv
if defined MPV goto :mpv_ok
echo ERROR: a locally built Spatial mpv was not found under:
echo   "%DISTRIBUTION%"
echo Build it with development\scripts\build-mpv-windows.ps1,
echo or set MPV_SPATIAL to an existing patched mpv.com/mpv.exe.
exit /b 1

:mpv_ok
if not defined MPV_HWDEC set "MPV_HWDEC=d3d11va"

set "BRIDGE="
set "PATCHED_BRIDGE=%DISTRIBUTION%\harletty-bridge-v0.7.1-ddplus-atmos-fix-windows-x86_64\harletty_bridge.dll"
if defined HARLETTY_BRIDGE (
    if exist "%HARLETTY_BRIDGE%" (
        set "BRIDGE=%HARLETTY_BRIDGE%"
        goto :found_bridge
    )
    echo ERROR: HARLETTY_BRIDGE points to a missing file:
    echo   "%HARLETTY_BRIDGE%"
    exit /b 1
)
if defined PATCHED_MPV_DIR if exist "%PATCHED_MPV_DIR%\harletty_bridge.dll" (
    set "BRIDGE=%PATCHED_MPV_DIR%\harletty_bridge.dll"
    goto :found_bridge
)
if exist "%PATCHED_BRIDGE%" (
    set "BRIDGE=%PATCHED_BRIDGE%"
    goto :found_bridge
)
for /f "delims=" %%F in ('dir /b /s /a:-d "%RELEASES%\harletty_bridge.dll" 2^>nul') do set "BRIDGE=%%F" & goto :found_bridge

:found_bridge
if defined BRIDGE goto :bridge_ok
echo ERROR: harletty_bridge.dll was not found at:
echo   "%PATCHED_BRIDGE%"
echo or under:
echo   "%RELEASES%"
exit /b 1

:bridge_ok
echo.
echo Omniphony Studio is optional; start it only for visualization or live control.
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
echo Using hardware decoder:
echo   "%MPV_HWDEC%"
echo.

"%MPV%" --vo=gpu-next --gpu-api=d3d11 "--hwdec=%MPV_HWDEC%" --target-colorspace-hint=yes --ad=orender --ao=wasapi-spatial,wasapi "--input-conf=%INPUT_CONFIG%" --script-opts-append=stats-persistent_overlay=yes --script-opts-append=stats-redraw_delay=0.25 "--ad-orender-config=%CONFIG%" "--ad-orender-bridge-path=%BRIDGE%" --ad-orender-osc "%MOVIE%"
set "MPV_EXIT=%ERRORLEVEL%"

if "%MPV_EXIT%"=="0" goto :done
echo.
echo mpv exited with code %MPV_EXIT%.

:done
exit /b %MPV_EXIT%
