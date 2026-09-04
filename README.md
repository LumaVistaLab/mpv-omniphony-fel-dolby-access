# mpv-omniphony-fel for Dolby Access

Language: English | [简体中文](README_zh-CN.md)

A Windows playback helper project for mpv/Omniphony. It adds an
`ISpatialAudioClient` output to the Omniphony/FEL pipeline so that a named 7.1.4
PCM static bed can be rendered by the active Windows Spatial Sound provider. It
also fixes Spatial Sound stream reconstruction after seeking, runtime
dependencies for the context menu, and persistent live refresh for Playback
statistics.

The audio device is not hardcoded; playback always uses the current Windows
default multimedia output endpoint. Dolby Atmos for Headphones is the reference
configuration. If a compatible HDMI endpoint becomes the default and Dolby
Atmos for Home Theater is enabled, the same backend recreates the spatial stream
for the new endpoint.

## Audio Path

```text
Atmos track -> orender -> named 7.1.4 float PCM
             -> wasapi-spatial -> 12 Windows static audio objects
             -> active Spatial Sound provider -> default headphone or home theater endpoint
```

This does not pass the original Atmos bitstream or dynamic-object metadata
directly to Dolby Access. `orender` first produces a 7.1.4 static bed, and
`wasapi-spatial` submits it to Windows while preserving the positional identity
of each speaker. Ordinary shared-mode WASAPI usually negotiates only a flat 7.1
layout, so the launcher uses `--ao=wasapi-spatial,wasapi`: Spatial Sound receives
7.1.4 when available, with ordinary WASAPI as the initialization fallback.

## Repository Layout

```text
mpv-omniphony-fel-dolby-access/
├── README.md                                 # English documentation
├── README_zh-CN.md                           # Simplified Chinese documentation
├── development/                              # Patches, tool sources, and build scripts
│   ├── mpv/                                  # mpv patches
│   ├── scripts/                              # Source preparation and Windows build scripts
│   └── tools/
│       └── ispatialaudio-probe.c             # Standalone Spatial API probe source
├── mpv-input.conf                            # Live statistics key bindings
├── omniphony-dolby-access.config.yaml        # 7.1.4 render configuration
├── overlay-prefs.conf                        # Spatial-object overlay preferences
├── play-dovi-atmos.bat                       # Playback launcher
├── sources/                                  # Unmodified upstream sources (ignored)
├── releases/                                 # Unmodified upstream packages (ignored)
├── build_temp/                               # Patched trees and intermediates (ignored)
└── distribution/                             # Locally built runnable packages (ignored)
```

Git tracks the patches, tool sources, configuration, and build scripts.
`sources/` and `releases/` contain only unmodified upstream material, while
`build_temp/` and `distribution/` contain only locally generated files. These
four directories and the personal editor workspace are excluded by
`.gitignore`.

## Obtain Upstream Material

Download and extract the required material into the suggested directories
below. Directory names can be overridden through build-script parameters.

### Upstream release packages: `releases/`

- [mpv-omniphony FEL Windows x86_64](https://github.com/mgth/mpv-omniphony/releases/download/v0.4.1-fel-beta.4/mpv-omniphony-fel-windows-x86_64.zip)
- [harletty-bridge v0.7.1 Windows x86_64](https://github.com/harletty/harletty-bridge/releases/download/v0.7.1/harletty-bridge-v0.7.1-windows-x86_64.zip)
- [Omniphony Studio 0.4.1 Windows x64](https://github.com/mgth/Omniphony/releases/download/v0.4.1/Omniphony.Studio_0.4.1_x64-setup.exe) (optional; 3D visualization, monitoring, and live control only)

Suggested layout:

```text
releases/
  mpv-omniphony-fel-windows-x86_64/   original runtime base
  harletty-bridge-v0.7.1-windows-x86_64/
    harletty_bridge.dll
  Omniphony.Studio_0.4.1_x64-setup.exe  optional
```

### Upstream sources: `sources/`

- [mpv Git repository](https://github.com/mpv-player/mpv)
- [mpv-omniphony v0.4.1-fel-beta.4 source](https://github.com/mgth/mpv-omniphony/archive/refs/tags/v0.4.1-fel-beta.4.zip)
- [Omniphony v0.4.1 source](https://github.com/mgth/Omniphony/archive/refs/tags/v0.4.1.zip)
- [harletty-bridge v0.7.1 source](https://github.com/harletty/harletty-bridge/archive/refs/tags/v0.7.1.zip)

By default, the build scripts read a complete mpv Git clone from `sources/mpv/`
and the Omniphony integration source from
`sources/mpv-omniphony-0.4.1-fel-beta.4/`. The reproducible baseline for the
current patch set is mpv commit
`70894ae0390cf20edac0e68de72ab26725520416`; a source archive without the
required Git objects cannot replace the mpv clone.

## Build

First create a patched working tree under `build_temp/` without modifying the
upstream source directories:

```powershell
.\development\scripts\prepare-mpv-source.ps1
```

The script applies mpv-omniphony's `patches-master` and `patches-fel`, followed
by local patches `0022` and `0023` from `development/mpv/`. Its default output is
`build_temp/mpv-ispatial/`, and it does not modify `sources/`.

After preparing UCRT LLVM-MinGW, Meson, Ninja, pkg-config, and an FEL/mpv
dependency prefix, run:

```powershell
.\development\scripts\build-mpv-windows.ps1 `
  -PreparedSource .\build_temp\mpv-ispatial `
  -DependencyPrefix D:\mpv-deps `
  -ToolchainBin D:\llvm-mingw-ucrt\bin `
  -PkgConfig D:\w64devkit\bin\pkg-config.exe `
  -RuntimeBase .\releases\mpv-omniphony-fel-windows-x86_64
```

The runnable package is generated at:

```text
distribution/mpv-omniphony-fel-windows-x86_64-ispatial/
```

The build must enable Lua 5.2 and use the same UCRT ABI as the runtime-base
DLLs. Otherwise, mpv's built-in context-menu scripts may fail to load, or DLLs
from incompatible runtime families may be mixed. The build script copies the
runtime-base DLLs (excluding its README), then replaces `mpv.exe` and `mpv.com`
with the newly built files. It stops if the output directory already exists to
avoid silently overwriting a previous package.

### Spatial API probe

If `clang` is available in `PATH`, build the standalone default-endpoint probe
with:

```powershell
.\development\scripts\build-ispatialaudio-probe.ps1
```

Alternatively, select LLVM-MinGW with
`-ToolchainBin D:\llvm-mingw-ucrt\bin`. The default output is
`distribution/tools/ispatialaudio-probe.exe`.

## Playback

1. Enable the appropriate Dolby Atmos spatial-sound mode on the current default
   Windows audio device.
2. Confirm that the local build is under
   `distribution/mpv-omniphony-fel-windows-x86_64-ispatial/` and that an
   unmodified `harletty_bridge.dll` is present under `releases/`.
3. Double-click `play-dovi-atmos.bat`, drop a movie onto the window, and press
   Enter.

Omniphony Studio is not a playback dependency and does not need to be installed
or started first. The mpv runtime package includes `orender.dll`, and
`--ad=orender` creates the renderer inside the mpv process. Install and run
Studio only when 3D object visualization, level monitoring, or live parameter
control is required; it connects to the embedded renderer over OSC. Enabling
OSC without a Studio connection does not affect decoding or audio output.

A path can also be passed directly:

```powershell
.\play-dovi-atmos.bat "D:\Movies\Example.mkv"
```

If the runnable package is elsewhere, temporarily select a patched mpv build:

```powershell
$env:MPV_SPATIAL = "D:\my-mpv\mpv.com"
.\play-dovi-atmos.bat "D:\Movies\Example.mkv"
```

The launcher does not select arbitrary mpv binaries from `releases/`, which
prevents accidentally using an upstream release without `wasapi-spatial`. It
uses only a local package under `distribution/` or the path explicitly supplied
through `MPV_SPATIAL`.

## Default Runtime Options

```bat
mpv --vo=gpu-next --gpu-api=d3d11 --hwdec=d3d11va ^
  --target-colorspace-hint=yes --ad=orender ^
  --ao=wasapi-spatial,wasapi ^
  --input-conf=mpv-input.conf ^
  --script-opts-append=stats-persistent_overlay=yes ^
  --script-opts-append=stats-redraw_delay=0.25 ^
  --ad-orender-config=omniphony-dolby-access.config.yaml ^
  --ad-orender-bridge-path=harletty_bridge.dll ^
  --ad-orender-osc "movie.mkv"
```

`omniphony-dolby-access.config.yaml` outputs a named 7.1.4 speaker layout by
default, sets Master Gain to `0 dB`, disables automatic gain, and enables OSC
metering. In headphone mode, binauralization is performed by Windows/Dolby Atmos
for Headphones. Video uses zero-copy D3D11VA hardware decoding by default. This
is especially important for high-bitrate 4K and 50/60 fps Dolby Vision Profile
7 FEL sources, since the base and enhancement layers must be decoded together.
If a GPU or driver is incompatible, set `$env:MPV_HWDEC = "no"` before running
the launcher to force software decoding.

## Verification and Troubleshooting

### Confirm that 7.1.4 has not fallen back

Verbose playback logs should contain both of the following lines:

```text
Using Windows Spatial Sound static bed: fl-fr-fc-lfe-bl-br-sl-sr-tfl-tfr-tbl-tbr
AO: [wasapi-spatial] 48000Hz ... 12ch float
```

If `AO: [wasapi]` appears instead, the spatial backend has fallen back. Check the
default multimedia endpoint, the Dolby Access mode, and the `required` and
`missing` static-object masks in the log. The probe source at
`development/tools/ispatialaudio-probe.c` can be built and run to verify the
current default endpoint independently.

### Context menu unavailable

The context menu depends on mpv's built-in `select.lua` and `context_menu.lua`.
Confirm that the UCRT package under `distribution/` was built with Lua 5.2
enabled.

### Freeze or crash after seeking

`ISpatialAudioClient::Reset()` revokes existing static objects. Patch `0022`
makes the audio thread stop and reset synchronously on seek, release the old
objects, and rebuild the complete 7.1.4 object set before feeding more frames.
If `mpv.exe` has been replaced, confirm that the latest `0022` is still applied.

### Playback statistics do not persist or refresh

`mpv-input.conf` binds `i` and `I` to `stats/display-page-1-toggle`. The launcher
also enables the persistent overlay and a `0.25 s` redraw interval. If the
launcher is bypassed, load the input configuration and these two stats options
manually, and confirm that the build includes `0023`.

### Dolby Vision Profile 7 FEL

An FEL build requires mpv's `dv-fel` patch, FFmpeg with the `dovi_split` bitstream
filter, libplacebo with `dv-fel` support and `PL_API_VER >= 367`, and libdovi.
Verbose logs should contain `Dolby Vision Profile 7 splitter`, `virtual EL
stream`, or `el_pair`, and should not contain `dovi_split BSF not available`.

### Audio is smooth but high-bitrate video stutters

Launch playback through `play-dovi-atmos.bat` instead of invoking mpv directly.
Verbose logs should show `Using hardware decoding (d3d11va)` once for the base
layer and once for the enhancement layer. If they show `Using software decoding`,
check the GPU driver and HEVC Main 10 hardware-decoding support. The `MPV_HWDEC`
environment variable can also select another hardware backend supported by mpv.

## License

The repository root is licensed under GPL-3.0. Material downloaded by the user
under `sources/` and `releases/` retains its respective upstream license. Before
redistributing a local package from `distribution/`, also review the licenses of
all linked components.
