@echo off
setlocal EnableExtensions DisableDelayedExpansion

set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "RELEASES=%ROOT%\releases"
set "DISTRIBUTION=%ROOT%\distribution"
set "CONFIG=%ROOT%\omniphony-dolby-access.config.yaml"
set "INPUT_CONFIG=%ROOT%\mpv-input.conf"
set "DEFAULT_COOKIE_FILE=%ROOT%\bilibili-cookies.txt"
set "DEFAULT_YTDLP=%DISTRIBUTION%\tools\yt-dlp.exe"
set "DEFAULT_YTDL_HOOK=%DISTRIBUTION%\tools\ytdl_hook.lua"
set "BILIBILI_FORMAT=bestvideo[dynamic_range=DV]+bestaudio[format_id='30250']/bestvideo[dynamic_range=DV]+bestaudio/bestvideo+bestaudio[format_id='30250']/bestvideo+bestaudio/best"

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
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0031-original-mkv-m2ts"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0030-fel-merge"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0029-fel-mkv-m2ts"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0028-fel-mkv-m2ts"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0026-fel-final"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
set "PATCHED_MPV_DIR=%DISTRIBUTION%\mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix-0026-fel"
if exist "%PATCHED_MPV_DIR%\mpv.com" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.com"
    goto :found_mpv
)
if exist "%PATCHED_MPV_DIR%\mpv.exe" (
    set "MPV=%PATCHED_MPV_DIR%\mpv.exe"
    goto :found_mpv
)
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
set "MPV_MUTE_OPTION="
if /I "%SPATIAL_CLICK_TEST_MUTE%"=="1" set "MPV_MUTE_OPTION=--mute=yes"
set "MPV_AUDIO_DECODER=orender"
set "MPV_AUDIO_OUTPUT=wasapi-spatial,wasapi"
set "MPV_CHANNEL_OPTION="
set "MPV_CLICK_TEST_DESCRIPTION="
if /I "%SPATIAL_CLICK_TEST_PATH%"=="plain" (
    set "MPV_AUDIO_OUTPUT=wasapi"
    set "MPV_CHANNEL_OPTION=--audio-channels=stereo"
    set "MPV_CLICK_TEST_DESCRIPTION=Plain WASAPI stereo with the Omniphony renderer"
)
if /I "%SPATIAL_CLICK_TEST_PATH%"=="native" (
    set "MPV_AUDIO_DECODER=lavc"
    set "MPV_AUDIO_OUTPUT=wasapi"
    set "MPV_CHANNEL_OPTION=--audio-channels=stereo"
    set "MPV_CLICK_TEST_DESCRIPTION=Native decoder with plain WASAPI stereo"
)

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
echo Enter a local movie path or a Bilibili video URL, then press Enter.
echo.

set "MOVIE=%~1"
if defined MOVIE goto :movie_path_ready
set /p "MOVIE=Movie path or Bilibili URL: "

:movie_path_ready
if defined MOVIE goto :movie_path_not_empty
echo ERROR: movie path is empty.
exit /b 1

:movie_path_not_empty
rem Drag-and-drop or copied paths may include wrapping quotes.
set "MOVIE=%MOVIE:"=%"

set "ONLINE_PLAYBACK="
if /I "%MOVIE:~0,8%"=="https://" set "ONLINE_PLAYBACK=1"
if /I "%MOVIE:~0,7%"=="http://" set "ONLINE_PLAYBACK=1"
if defined ONLINE_PLAYBACK goto :online_target

if exist "%MOVIE%" goto :movie_exists
echo ERROR: movie file not found:
echo   "%MOVIE%"
exit /b 1

:online_target
set "COOKIE_FILE=%DEFAULT_COOKIE_FILE%"
if defined BILIBILI_COOKIES set "COOKIE_FILE=%BILIBILI_COOKIES%"
set "BILIBILI_LOGIN_HELPER=%ROOT%\development\scripts\export-bilibili-cookies.py"
if exist "%BILIBILI_LOGIN_HELPER%" goto :find_python
echo ERROR: Bilibili QR login helper not found:
echo   "%BILIBILI_LOGIN_HELPER%"
exit /b 1

:find_python
set "PYTHON="
if not defined PYTHON_PATH goto :find_default_python
if exist "%PYTHON_PATH%" (
    set "PYTHON=%PYTHON_PATH%"
    goto :found_python
)
echo ERROR: PYTHON_PATH points to a missing file:
echo   "%PYTHON_PATH%"
exit /b 1

:find_default_python
for /f "delims=" %%F in ('where.exe python.exe 2^>nul') do (
    set "PYTHON=%%F"
    goto :found_python
)

:found_python
if defined PYTHON goto :python_ok
echo ERROR: Python 3 was not found. Install Python 3 with Tk support,
echo or set PYTHON_PATH to python.exe.
exit /b 1

:python_ok
"%PYTHON%" "%BILIBILI_LOGIN_HELPER%" --output "%COOKIE_FILE%"
set "BILIBILI_LOGIN_EXIT=%ERRORLEVEL%"
if "%BILIBILI_LOGIN_EXIT%"=="0" goto :cookie_file_ok
if "%BILIBILI_LOGIN_EXIT%"=="11" (
    echo Bilibili login was cancelled.
    exit /b 1
)
echo ERROR: Bilibili login could not be verified or renewed.
exit /b %BILIBILI_LOGIN_EXIT%

:cookie_file_ok
if exist "%COOKIE_FILE%" goto :cookie_file_ready
echo ERROR: Bilibili login succeeded but the cookie file was not created:
echo   "%COOKIE_FILE%"
exit /b 1

:cookie_file_ready

set "YTDLP="
if not defined YTDLP_PATH goto :find_default_ytdlp
if exist "%YTDLP_PATH%" (
    set "YTDLP=%YTDLP_PATH%"
    goto :found_ytdlp
)
echo ERROR: YTDLP_PATH points to a missing file:
echo   "%YTDLP_PATH%"
exit /b 1

:find_default_ytdlp
if exist "%DEFAULT_YTDLP%" (
    set "YTDLP=%DEFAULT_YTDLP%"
    goto :found_ytdlp
)
for /f "delims=" %%F in ('where.exe yt-dlp.exe 2^>nul') do (
    set "YTDLP=%%F"
    goto :found_ytdlp
)

:found_ytdlp
if defined YTDLP goto :ytdlp_ok
echo ERROR: yt-dlp was not found at:
echo   "%DEFAULT_YTDLP%"
echo Install the latest official build with:
echo   powershell -ExecutionPolicy Bypass -File development\scripts\install-yt-dlp.ps1
exit /b 1

:ytdlp_ok
set "YTDL_HOOK=%DEFAULT_YTDL_HOOK%"
if defined YTDL_HOOK_PATH set "YTDL_HOOK=%YTDL_HOOK_PATH%"
if exist "%YTDL_HOOK%" goto :ytdl_hook_ok
echo ERROR: the Bilibili metadata-aware yt-dlp hook was not found at:
echo   "%YTDL_HOOK%"
exit /b 1

:ytdl_hook_ok
set "RUNTIME_COOKIE_FILE=%TEMP%\mpv-omniphony-bilibili-%RANDOM%-%RANDOM%.txt"
copy /Y "%COOKIE_FILE%" "%RUNTIME_COOKIE_FILE%" >nul
if errorlevel 1 (
    echo ERROR: could not create the temporary read/write cookie jar:
    echo   "%RUNTIME_COOKIE_FILE%"
    exit /b 1
)
set "PLAY_TARGET=ytdl://%MOVIE%"
goto :movie_exists

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
if defined ONLINE_PLAYBACK (
    echo Using yt-dlp:
    echo   "%YTDLP%"
    echo Using Bilibili metadata-aware yt-dlp hook:
    echo   "%YTDL_HOOK%"
    echo Reading Bilibili login cookies from:
    echo   "%COOKIE_FILE%"
    echo Default online selection: Dolby Vision + Dolby Atmos when available,
    echo then the highest-quality available video and audio streams.
    echo Press Ctrl+V or Ctrl+A in mpv to select another video or audio stream.
)
if defined MPV_MUTE_OPTION echo Diagnostic mute is active; program audio will be silent.
if defined MPV_CLICK_TEST_DESCRIPTION echo Diagnostic path: %MPV_CLICK_TEST_DESCRIPTION%.
echo.

if defined ONLINE_PLAYBACK goto :play_online

"%MPV%" --vo=gpu-next --gpu-api=d3d11 "--hwdec=%MPV_HWDEC%" --target-colorspace-hint=yes "--ad=%MPV_AUDIO_DECODER%" "--ao=%MPV_AUDIO_OUTPUT%" %MPV_CHANNEL_OPTION% %MPV_MUTE_OPTION% "--input-conf=%INPUT_CONFIG%" --script-opts-append=stats-persistent_overlay=yes --script-opts-append=stats-redraw_delay=0.25 "--ad-orender-config=%CONFIG%" "--ad-orender-bridge-path=%BRIDGE%" --ad-orender-osc "%MOVIE%"
set "MPV_EXIT=%ERRORLEVEL%"
goto :playback_finished

:play_online
"%MPV%" --vo=gpu-next --gpu-api=d3d11 "--hwdec=%MPV_HWDEC%" --target-colorspace-hint=yes "--ad=%MPV_AUDIO_DECODER%" "--ao=%MPV_AUDIO_OUTPUT%" %MPV_CHANNEL_OPTION% %MPV_MUTE_OPTION% "--input-conf=%INPUT_CONFIG%" --script-opts-append=stats-persistent_overlay=yes --script-opts-append=stats-redraw_delay=0.25 "--ad-orender-config=%CONFIG%" "--ad-orender-bridge-path=%BRIDGE%" --ad-orender-osc --ytdl=no "--script=%YTDL_HOOK%" "--script-opts-append=ytdl_hook-ytdl_path=%YTDLP%" --script-opts-append=ytdl_hook-all_formats=yes --script-opts-append=ytdl_hook-force_all_formats=yes "--ytdl-raw-options-append=cookies=%RUNTIME_COOKIE_FILE%" --ytdl-raw-options-append=ignore-config= "--ytdl-format=%BILIBILI_FORMAT%" "%PLAY_TARGET%"
set "MPV_EXIT=%ERRORLEVEL%"

:playback_finished
if defined RUNTIME_COOKIE_FILE if exist "%RUNTIME_COOKIE_FILE%" del /Q "%RUNTIME_COOKIE_FILE%" >nul 2>nul
if "%MPV_EXIT%"=="0" goto :done
echo.
echo mpv exited with code %MPV_EXIT%.

:done
exit /b %MPV_EXIT%
