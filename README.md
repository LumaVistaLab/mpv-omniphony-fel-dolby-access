# mpy-omniphony (FEL Beta) for Dolby Access

Language: English | [简体中文](README_zh-CN.md)

A Windows playback helper project for mpv/Omniphony. It adds an
`ISpatialAudioClient` output to the Omniphony/FEL pipeline so that a named 7.1.4
PCM static bed can be rendered by the active Windows Spatial Sound provider. It
also fixes Spatial Sound stream reconstruction after seeking, runtime
dependencies for the context menu, and persistent live refresh for Playback
statistics.

The local DD+ Atmos patch set repairs confirmed defects across the complete
E-AC-3 JOC decode-and-render path; it is not selected by container or limited to
online-media or Blu-ray delivery. Independent 5.1 streams retain their declared
JOC input layout, while paired Blu-ray access units merge the independent core
with discrete channels from the dependent substream before evaluating a
declared 7-input JOC matrix.

Harletty also corrects JOC dequantisation, sparse-matrix and interpolation edge
cases, aligns bypassed LFE and OAMD events with the 577-sample JOC QMF path, and
decodes OAMD gain, inheritance, position, update timing and discontinuity
semantics while keeping presentation trim/warp metadata separate from live
object coordinates. The companion Omniphony patch retains metadata events
across frame boundaries, applies every update at its exact sample, and renders object-gain
ramps in both speaker and binaural paths. DD+ remains a lossy delivery format;
these changes remove additional decoder/renderer errors rather than claiming
bit-identical output to TrueHD Atmos.

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
│   ├── harletty/                             # E-AC-3/JOC decoder patch
│   ├── omniphony/                            # Spatial metadata/rendering patches
│   ├── scripts/                              # Source preparation, build, and yt-dlp installer scripts
│   └── tools/
│       ├── ispatialaudio-probe.c             # Standalone Spatial API probe source
│       └── compare-spatial-wav.py            # Per-channel PCM regression comparison
├── bilibili-cookies.example.txt              # Login-cookie file template (no credentials)
├── mpv-input.conf                            # Live statistics key bindings
├── omniphony-dolby-access.config.yaml        # 7.1.4 render configuration
├── overlay-prefs.conf                        # Spatial-object overlay preferences
├── play-dovi-atmos.bat                       # Playback launcher
├── test-click-muted.bat                      # Digital-mute click isolation launcher
├── test-click-plain-wasapi.bat                # Omniphony through stereo WASAPI diagnostic
├── test-click-native.bat                      # Native decoder/stereo WASAPI diagnostic
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

### Corrected DD+ Atmos decode and render path

The DD+ Atmos fix is built separately from pristine Harletty v0.7.1 and
Omniphony v0.4.1 sources. Use Rust 1.88 or newer with the MSVC target:

- The Harletty patches reconstruct the declared 5- or 7-input JOC topology,
  correct matrix reconstruction, delay bypassed LFE by the QMF path's 577
  samples, and time-shift OAMD events by the same amount.
- OAMD gain/status defaults, previous-object and previous-update inheritance,
  differential positions, sequence discontinuities and all block updates are
  decoded. Presentation trim/warp metadata is parsed but is not applied to live
  playback object coordinates. A block starts at
  `sample_offset + 32 * block_offset_factor`.
- The Omniphony patch queues absolute metadata timestamps across decoded frames,
  splits PCM at every due event boundary, and applies finite linear-amplitude
  gain ramps in speaker and binaural rendering.

```powershell
.\development\scripts\prepare-harletty-source.ps1
.\development\scripts\build-harletty-bridge.ps1
```

The first script copies both upstream trees into
`build_temp/harletty-ddplus-fix/` and applies the tracked patches without
modifying `sources/`. The second runs decoder and spatial-renderer regression
tests and creates:

```text
distribution/harletty-bridge-v0.7.1-ddplus-atmos-fix-windows-x86_64/harletty_bridge.dll
distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/
  orender.dll
  harletty_bridge.dll
```

The second directory is a complete runtime package based on the existing
iSpatial mpv package, with only the corrected `orender.dll` replaced and the
corrected bridge added. `play-dovi-atmos.bat` prefers this complete path. Set
`HARLETTY_BRIDGE` only when testing another bridge; if the corrected package is
absent, the launcher falls back to the original iSpatial package and upstream
bridge under `releases/`.

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
2. Confirm that the corrected runtime package is under
   `distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/`.
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

### Bilibili playback

Install the current official yt-dlp executable once. The installer downloads
the release from the upstream GitHub repository and refuses to install it
unless its SHA-256 hash matches the upstream checksum list:

```powershell
.\development\scripts\install-yt-dlp.ps1
```

The launcher now validates the saved Bilibili session before every online
playback. If the file is missing or the session has expired, it opens a native
QR window automatically; scan it with the Bilibili app and confirm on the
phone, then playback continues. This avoids Chromium cookie-database locks and
App-Bound/DPAPI decryption failures and never exports browser tracking cookies.
The QR runtime is bundled under `distribution/tools`; if that generated folder
is being recreated, install the pure-Python dependency once with:

```powershell
.\development\scripts\install-bilibili-login-helper.ps1
```

The QR is generated and rendered locally. After login, the helper validates
the returned authentication-cookie subsets and writes only the smallest one
accepted by Bilibili to `bilibili-cookies.txt`; in testing this is only
`SESSDATA`. An expired QR is refreshed automatically in the same window.
Cookie values are never printed. The real file is ignored by Git but must still
be treated like a password. Python 3 with Tk support is required for the native
window; `PYTHON_PATH` may point the launcher to a specific `python.exe`.

The launcher gives yt-dlp a disposable run-time copy and removes it after
playback, so device or tracking cookies received by yt-dlp cannot pollute the
persistent file. Without a valid logged-in premium account, member-only Dolby
Vision, Dolby Atmos, HDR, 4K, 8K, and high-bitrate formats remain unavailable
according to Bilibili's normal access rules.

The launcher accepts a Bilibili URL in the same prompt as a local path:

```powershell
.\play-dovi-atmos.bat "https://www.bilibili.com/video/BV..."
```

Its default stream policy is, in order:

1. Dolby Vision video plus Dolby Atmos audio (`30250`).
2. Dolby Vision video plus the best available audio.
3. The best available video plus Dolby Atmos audio.
4. The highest-quality available video and audio, or the best combined stream.

Online playback explicitly enables `--flatten-editions=yes`, exposing video
quality editions as video tracks. All DASH video and audio alternatives
reported by yt-dlp therefore appear in their respective track menus. The
selected single-stream video and audio formats are opened immediately, while
unselected alternatives remain delay-loaded. Press `Ctrl+V` for the video-track selector and `Ctrl+A` for the
audio-track selector, or right-click the corresponding video/audio button in
mpv's on-screen controller. The native selector shows the Bilibili quality
name when provided, plus codec, resolution, frame rate, channel count, sample
rate, and bitrate. This allows switching among Dolby Vision, HDR, 8K, 4K,
1080p high-bitrate/high-frame-rate, Dolby Atmos, Hi-Res/FLAC, and AAC variants
that are actually available to the logged-in account. Only the selected remote
tracks are opened.

Format menus prefer the nominal bitrate advertised by Bilibili over a demuxer
probe estimate that may cover only an initial fragment. Files without an
advertised rate still use the demuxer bitrate. Playback statistics continue
to calculate the live bitrate from the packets being played.

Video format menus consistently use the source's advertised frame rate,
preserving fractional values such as `29.97`, `59.933`, and `59.94`. Default
and alternative streams use the same source, unchanged after selection or
switching. Files without an advertised frame rate fall back to the demuxer
rate. Playback continues to follow the media timestamps.

The launcher prefers `tools/ytdl_hook.lua` inside the selected runtime package,
falling back to `distribution/tools/ytdl_hook.lua`, so the EDL metadata syntax
stays compatible with that mpv build. The hook normalizes Bilibili DASH
codec identifiers: `hvc1`/`dvh1`/`dvhe` become HEVC, `ec-3` becomes E-AC-3,
and `flac` becomes FLAC. Delay-loaded tracks therefore have a real codec before
they are opened. Opening the selected formats immediately also lets Playback
statistics read their real demuxer/decoder profiles, so online playback reports
details such as HEVC `Main 10` and `Dolby Digital Plus + Dolby Atmos · LFE+N
objects · DialNorm -N dB` with the same policy as local playback instead of
falling back to H.264/AAC or showing only the base codec.

Set `BILIBILI_COOKIES` to override the cookie-file path or `YTDLP_PATH` to use a
different yt-dlp executable for a single shell session. `YTDL_HOOK_PATH` may
override the metadata-aware hook.

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

For Bilibili URLs the launcher additionally enables mpv's yt-dlp hook, passes a
disposable copy of the persistent cookie file, exposes all returned formats as
tracks, and uses this default selector (line breaks added for readability):

```text
bestvideo[dynamic_range=DV]+bestaudio[format_id='30250'] /
bestvideo[dynamic_range=DV]+bestaudio /
bestvideo+bestaudio[format_id='30250'] /
bestvideo+bestaudio / best
```

`orender` is available for the E-AC-3 Dolby Atmos track. When AAC or FLAC is
selected, mpv automatically falls back to its normal decoder while keeping the
same configured output-device preference.

## Verification and Troubleshooting

### Click aligned with the first program sound

Run `test-click-muted.bat` with the same movie. It uses the identical decoder,
Spatial Sound stream and timing, but applies mpv's final
digital mute. A click that remains during this otherwise silent run is produced
after mpv's PCM gain stage (Dolby provider, driver, or endpoint). If it
disappears, it is coupled to the first non-zero PCM, but can still be generated
downstream when a Spatial Sound static object becomes active.

For an A/B isolation test with the same movie, run both
`test-click-plain-wasapi.bat` (Omniphony renderer, ordinary WASAPI stereo) and
`test-click-native.bat` (native decoder, ordinary WASAPI stereo). These are
diagnostic launchers only; normal playback remains unchanged.

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

### Several seconds of silence after seeking

Harletty retains its cumulative metadata sample clock across seeks, while
orender restarts output timestamps at zero. Omniphony patch `0003` maintains
the offset between these clocks so new object events take effect on time,
including after repeated seeks. Include this patch when rebuilding
`orender.dll`; `prepare-harletty-source.ps1` applies it automatically.

`development/tools/check-orender-seek.py` verifies this with a raw E-AC-3 or
TrueHD Atmos excerpt. It repeatedly resets and decodes the same excerpt,
comparing per-channel PCM, audio recovery and output timestamps without
opening an audio device. Requires Python and NumPy, for example:

```powershell
python development/tools/check-orender-seek.py sample.ec3 `
  --orender distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/orender.dll `
  --bridge distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/harletty_bridge.dll `
  --config omniphony-dolby-access.config.yaml
```

Add `--codec truehd` for a TrueHD excerpt. The test emits JSON and exits with
a nonzero status on regression.

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

### DD+ Atmos sounds smeared, mispositioned, or has incorrect gain/muting

Check both `Using mpv:` and `Using bridge:` in the launcher output. They should
point into
`distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/`; using only a
corrected bridge with an older `orender.dll` leaves the metadata scheduler and
gain-ramp defects in place. Verbose logs should select the `orender` decoder and
request `fl-fr-fc-lfe-bl-br-sl-sr-tfl-tfr-tbl-tbr` float output.

For core-plus-dependent streams, the corrected bridge merges the discrete
surround extension before the 7-input JOC matrix instead of duplicating side
surrounds into its rear inputs. For independent online-media streams, the same
bridge follows the declared 5-input topology without that merge. Both paths use
the corrected JOC reconstruction, 577-sample internal LFE/OAMD alignment and
sample-accurate OAMD scheduling.

## License

The repository root is licensed under GPL-3.0. Material downloaded by the user
under `sources/` and `releases/` retains its respective upstream license. Before
redistributing a local package from `distribution/`, also review the licenses of
all linked components.
