# Dolby Vision·Atmos Batch Player

这是一个面向 Windows 的播放辅助项目，用来通过带 Omniphony 集成的 mpv
播放 Dolby Vision·Atmos 影片。仓库把启动脚本、7.1.4 扬声器渲染配置和 overlay
偏好放在一起，日常使用时可以双击批处理脚本，也可以从命令行传入影片路径。

脚本本身保持很小：它优先选择本地 `-ispatial` mpv 运行包，寻找解码桥接
DLL，然后使用项目内的 Omniphony 配置启动 mpv。音频设备不写死，始终跟随
Windows 当前的多媒体默认输出端点。

## 功能

- 使用 `mpv-omniphony` 的 `--ad=orender` 走空间音频渲染链路。
- 使用自定义 `wasapi-spatial` AO，把带名称的 7.1.4 PCM 床提交为 12 个
  `ISpatialAudioClient` 静态对象，交给当前 Windows Spatial Sound provider
  （例如 Dolby Atmos for Headphones）渲染。
- 启动时自动把 `harletty_bridge.dll` 传给 orender。
- 启用 Omniphony OSC，方便 Omniphony Studio 显示实时对象位置和电平。
- 默认使用 7.1.4 扬声器模式输出，并关闭自动增益；扬声器和耳机模式共用的 Master Gain 设为 `0 dB`。
- 视频侧使用 `gpu-next` 和 `target-colorspace-hint`，适合现代 HDR /
  Dolby Vision·Atmos 相关播放路径。
- Playback statistics 使用独立持久 OSD overlay，并以 `0.25 s` 周期重绘，避免
  被 OSC、空间对象 overlay 或其他临时 OSD 消息覆盖。
- 项目输入配置把小写 `i` 从 mpv 默认的四秒一次性快照改为持续 toggle；再次按
  `i` 才会关闭统计叠加。
- 支持 Dolby Vision Profile 7.6 FEL（Full Enhancement Layer）片源；当前 `mpv-omniphony-fel-windows-x86_64` 运行包来自上游 FEL beta 构建。
- `releases/` 和 `sources/` 被 `.gitignore` 排除，避免把大体积运行包和源码快照提交进仓库。

## 运行要求

- Windows x86_64。
- mpv 可读取的影片文件，最好包含 Dolby Vision·Atmos 或其他对象式空间音频。
- Omniphony Studio，可以使用 `releases` 里的安装包，也可以使用兼容的上游版本。
- 带 Omniphony `ad_orender`、FEL 和本仓库 `wasapi-spatial` 补丁的 mpv 构建。
- Windows 运行包需要启用 Lua（当前构建为 Lua 5.2），否则 mpv 内置的右键菜单
  脚本不会加载。若复用上游 DLL，mpv 与 Lua 也必须使用同一 UCRT 运行库，不能
  把链接 `msvcrt.dll` 的自编译 EXE 与 UCRT DLL 混用。
- 播放 Dolby Vision Profile 7.6 FEL 时，需要使用 FEL 版 mpv 构建；普通 mpv-omniphony 构建不一定包含完整 FEL 依赖。
- `harletty_bridge.dll`，供 orender 解码音频流。
- 耳机或一个可用的 Windows 音频输出设备；默认端点需要在 Windows 中启用
  与设备匹配的 Spatial Sound 模式，例如 Dolby Atmos for Headphones 或
  Dolby Atmos for Home Theater。

当前项目约定运行文件放在 `releases/` 下。目录名不需要完全一致，因为批处理脚本会递归搜索；但下面这些文件必须存在于 `releases/` 的某个子目录中：

```text
releases/
  mpv-omniphony-fel-windows-x86_64-ispatial/
    mpv.com
    mpv.exe
    orender.dll
    ...
  mpv-omniphony-fel-windows-x86_64/
    mpv.com
    mpv.exe
    orender.dll
    ...
  harletty-bridge-v0.7.1-windows-x86_64/
    harletty_bridge.dll
  Omniphony.Studio_0.4.1_x64-setup.exe
```

## 运行包下载

可以从上游 releases 下载当前 README 对应的运行包：

- [mpv-omniphony FEL Windows x86_64](https://github.com/mgth/mpv-omniphony/releases/download/v0.4.1-fel-beta.4/mpv-omniphony-fel-windows-x86_64.zip)
- [harletty-bridge v0.7.1 Windows x86_64](https://github.com/harletty/harletty-bridge/releases/download/v0.7.1/harletty-bridge-v0.7.1-windows-x86_64.zip)
- [Omniphony Studio 0.4.1 Windows x64 installer](https://github.com/mgth/Omniphony/releases/download/v0.4.1/Omniphony.Studio_0.4.1_x64-setup.exe)

下载后请把 mpv zip 和 bridge zip 解压到 `releases/` 下；Omniphony Studio 使用安装程序正常安装，不需要解压到本仓库。

> 推荐使用默认的 7.1.4 扬声器模式，并为当前 Windows 音频输出设备安装、配置 Dolby Access，启用与设备匹配的 Dolby Atmos 空间音效模式。Dolby Access 的可用选项取决于输出设备及其驱动。

## Windows Spatial Sound 音频链路

当前链路为：

```text
Atmos 音轨 -> orender -> 带名称的 7.1.4 float PCM
           -> wasapi-spatial -> 12 个 Windows 静态音频对象
           -> 当前 Spatial Sound provider -> 默认耳机或家庭影院端点
```

这里不是把原始 Atmos bitstream 或原始动态对象元数据直通给 Dolby Access。
orender 先把对象和声床渲染成 7.1.4 静态床，`wasapi-spatial` 再保留每个扬声器
的位置语义提交给 Windows。Dolby Atmos for Headphones 随后完成双耳渲染；切换
到支持的 HDMI 默认端点和 Dolby Atmos for Home Theater 时，同一后端会重新按
该端点的 Spatial Sound provider 建立空间流。

普通 WASAPI 共享模式在这些端点上最多只协商到 7.1，不能承载四个高度声道。
因此脚本使用 `--ao=wasapi-spatial,wasapi`：含高度声道的布局优先走 Spatial
Sound；平面声道布局或 Spatial 初始化失败时才回退到普通 WASAPI。正式脚本
没有 `--audio-device` 参数，切换 Windows 默认多媒体设备后会自动跟随并重载。

## 快速开始

1. 准备 `releases/mpv-omniphony-fel-windows-x86_64-ispatial/`。当前工作区已包含
   本机编译的运行包；重新构建时，对匹配的 mpv/FEL 源码依次应用
   `patches/mpv/0022-ao-wasapi-add-Windows-Spatial-Sound-static-bed.patch` 和
   `patches/mpv/0023-player-make-playback-statistics-a-live-toggle.patch`，再把新的
   `mpv.exe` 和 `mpv.com` 放入该目录，其他 DLL 可沿用基础运行包。构建应启用
   `-Dlua=lua52` 并使用 UCRT 工具链，以兼容基础运行包中的 DLL。
2. 下载并解压 `harletty-bridge-v0.7.1-windows-x86_64.zip` 到 `releases/` 下。
3. 运行 `Omniphony.Studio_0.4.1_x64-setup.exe` 安装 Omniphony Studio。
4. 启动 Omniphony Studio，并在 Studio 中自行完成 OSC 连接配置。
5. 双击 `play-dovi-atmos-headphones.bat`。
6. 把影片文件拖进弹出的控制台窗口，然后按 Enter。

Omniphony Studio 是监督和控制界面，本身不渲染音频；它通过 OSC 连接到 renderer。播放脚本会启动 mpv 并传入 `--ad=orender`、`--ad-orender-osc` 和 bridge 路径，影片音频输入会由 mpv/orender 自动注入，不需要在 Studio 中手动选择音频输入。相关背景见 `sources\Omniphony-0.4.1\README.md`。

也可以直接从命令行传入影片路径：
```powershell
.\play-dovi-atmos-headphones.bat "D:\Movies\Example.mkv"
```

播放开始前，脚本会打印实际选中的 mpv、bridge DLL 和配置文件路径，便于排查环境问题。

## 启动命令

批处理脚本最终会以类似下面的参数启动 mpv：

```bat
mpv --vo=gpu-next --target-colorspace-hint=yes --ad=orender ^
  --ao=wasapi-spatial,wasapi ^
  --input-conf=mpv-input.conf ^
  --script-opts-append=stats-persistent_overlay=yes ^
  --script-opts-append=stats-redraw_delay=0.25 ^
  --ad-orender-config=omniphony-headphones.config.yaml ^
  --ad-orender-bridge-path=harletty_bridge.dll ^
  --ad-orender-osc "movie.mkv"
```

真实路径由脚本运行时自动发现。如果需要增加或修改 mpv 参数，编辑
`play-dovi-atmos-headphones.bat` 即可。

## Dolby Vision Profile 7.6 FEL 支持

当前 `releases/mpv-omniphony-fel-windows-x86_64-ispatial/` 以
`mpv-omniphony-0.4.1-fel-beta.4` 的 FEL 链路为基础，并增加本仓库的
`wasapi-spatial` 后端，面向 Dolby Vision Profile 7.6 FEL / P7 双层片源。
FEL 是 Full Enhancement Layer，不是单独一个 mpv 参数；它要求播放器构建同时具备以下组件：

- mpv `dv-fel` 补丁，用于拆分 BL / EL 并把 EL 交给 libplacebo。
- 带 `dovi_split` bitstream filter 的 ffmpeg，用于拆分 HEVC P7 双层码流。
- 支持 dv-fel 的 libplacebo，且 `PL_API_VER >= 367`。
- libdovi，用于 RPU / enhancement layer 相关解析。

验证 FEL 是否真的启用时，使用 Dolby Vision Profile 7.6 FEL 片源运行 mpv verbose 日志：

```powershell
.\releases\mpv-omniphony-fel-windows-x86_64-ispatial\mpv.exe -v --vo=gpu-next "D:\Movies\Example.mkv"
```

日志中应能看到类似 `Dolby Vision Profile 7 splitter`、`virtual EL stream`、`el_pair` 的信息，并且不应出现 `dovi_split BSF not available` 或 `Invalid NAL unit size`。如果只想对比基础层，可以设置 `MPV_NO_FEL=1` 后再播放同一个片源。

FEL 支持仍按上游说明视为实验性功能。更完整的技术细节见 `sources/mpv-omniphony-0.4.1-fel-beta.4/README.md` 的 `Dolby Vision FEL (experimental)` 段落。

## 配置文件

### `omniphony-headphones.config.yaml`

这是批处理脚本传给 orender 的主渲染配置。文件名保留了 `headphones`，但当前默认输出是 7.1.4 扬声器模式。

当前默认值：

- `render.output_channel_mapping: by_name`，确保交给 mpv 的每个通道保留
  `FL/FR/.../TBL/TBR` 扬声器身份，而不是无位置的 12 通道索引。
- `render.current_layout` 定义 7.1.4 风格的扬声器布局：`FL`、`FR`、`C`、`LFE`、`BL`、`BR`、`SL`、`SR`、`TFL`、`TFR`、`TBL`、`TBR`，布局半径 `radius_m: 1.5`。
- 所有扬声器使用 `coord_mode: cartesian` 和 `delay_ms: 0.0`；除 `LFE` 外都启用 `spatialize: true`，`LFE` 保持 `spatialize: false`。
- `render.vbap_elevation_resolution: 90`，评估网格为 `62 x 62 x 15`，负向 Z 网格为 `0`。
- `render.master_gain: 0.0`（`0 dB`），`render.auto_gain: false`。Master Gain 由扬声器和双耳耳机路径共用，因此两种模式的初始 Master Gain 都是 `0 dB`；当前配置文件没有设置单独的 `auto_gain_ceiling_db`。
- 房间参数为 `room_width_m: 3.0`、`room_front_m: 1.75`、`room_rear_m: 1.75`、`room_height_m: 1.2`、`room_lower_m: 1.2`，中心混合比例 `room_ratio_center_blend: 0.5`。
- `render.osc: true`、`render.osc_metering: true`，允许 Studio 连接、监控播放并接收电平数据；`meter_rate` 和 `diag_rate` 均为 `10.0`。
- `render.binaural.output_mode: speaker`，默认通过 7.1.4 VBAP 扬声器路径输出。推荐保持此模式并配合 Dolby Access 使用；如需改用内置双耳耳机渲染，可将其改为 `binaural`，然后重启 mpv。
- 双耳模式参数保留为 `unit_scale_m: 1.5`、`head_radius_m: 0.0875`、`hrir_source: saf`、`head_tracking.format: auto`，并启用 `air_absorption: true`。
- 关闭 reflections 和 reverb，保留更干净、保守的默认听感；反射模型保留 `4.0 x 5.0 x 2.7 m` 的房间尺寸但 `level: 0.0`。

### `overlay-prefs.conf`

这是与 YAML 配置同目录的 mpv 空间对象 overlay 偏好文件。当前文件默认关闭 mpv 画面上的 overlay：

```ini
enabled=0
labels=1
trails_enabled=1
ttl_ms=7000
mode=diffuse
teleport=0.500
```

如果希望在 mpv 视频画面上显示空间对象 overlay，把 `enabled` 改为 `1` 后重新播放。Omniphony / orender 在运行时修改 overlay 控件时，也可能更新这个文件。

## 项目结构

```text
.
  play-dovi-atmos-headphones.bat      播放启动脚本
  mpv-input.conf                      mpv 按键覆盖（小写 i 切换实时统计）
  omniphony-headphones.config.yaml    主渲染配置（默认 7.1.4 扬声器输出）
  overlay-prefs.conf                  mpv 空间对象 overlay 偏好
  patches/mpv/                        可复现的 mpv Spatial Sound 补丁
  tools/ispatialaudio-probe.c         默认端点 7.1.4 Spatial API 探针
  releases/                           本地运行包，Git 忽略
  sources/                            上游源码快照，Git 忽略
  LICENSE                             项目许可证
```

`sources/` 当前包含这些上游源码快照：

- `Omniphony-0.4.1`
- `harletty-bridge-0.7.1`
- `mpv-omniphony-0.4.1-fel-beta.4`

这些目录适合用于审计、对照或重新构建运行包；只播放影片时不需要进入这些目录。

## 常见问题

### `releases directory not found`

在仓库根目录创建 `releases/`，并把运行包放进去。

### `mpv.com or mpv.exe was not found`

确认带 Omniphony 集成的 Windows mpv 构建已经解压到 `releases/` 下。

### `harletty_bridge.dll was not found`

确认 Harletty bridge 运行包已经解压到 `releases/` 下，或把
`harletty_bridge.dll` 复制到 `releases/` 的任意子目录中。

### Studio 没有显示对象或电平

检查以下事项：

- Omniphony Studio 是否在播放前已经启动，并已按你的环境完成 OSC 连接配置。
- `omniphony-headphones.config.yaml` 中的 `render.osc` 是否仍为 `true`；播放脚本会同时传入 `--ad-orender-osc`。
- Windows 防火墙是否拦截了本机 OSC 通信。
- 当前选中的音轨是否真的包含 Dolby Vision·Atmos 空间音频元数据。
- mpv 是否正在使用 `ad_orender`；打开 mpv stats 时应能看到 orender 解码器处于活动状态。

### 如何确认没有降级为普通 7.1

用 `-v` 启动一次播放，日志必须同时出现：

```text
Using Windows Spatial Sound static bed: fl-fr-fc-lfe-bl-br-sl-sr-tfl-tfr-tbl-tbr
AO: [wasapi-spatial] 48000Hz ... 12ch float
```

如果看到 `AO: [wasapi]`，说明 Spatial 后端未建立，已经走回退路径。检查当前
默认多媒体端点、Dolby Access 的空间音效模式，以及日志里的 `required` / `missing`
静态对象掩码。`tools/ispatialaudio-probe.c` 可独立验证当前默认端点能否创建并
渲染一个静音的 7.1.4 Spatial Sound quantum。

### mpv 画面没有 overlay

当前 `overlay-prefs.conf` 中 `enabled=0`。改成 `enabled=1` 后重新播放即可。若使用自定义 mpv 按键绑定，也可以通过上游提供的
`omniphony_overlay/*` 绑定切换 overlay 功能。

### 右键菜单不显示

右键菜单由 mpv 内置的 `select.lua` / `context_menu.lua` 提供；请确认当前运行的
是 `-ispatial` 目录中的 UCRT + Lua 构建，而不是早期关闭 Lua 的测试构建。当前
运行包会加载默认 `MBTN_RIGHT -> script-binding select/context-menu` 绑定。

### 快进或快退后卡死、闪退

Windows Spatial Sound 的 `Reset()` 会撤销现有静态音频对象。当前补丁会在 seek
时让音频线程同步停止、Reset、释放旧对象并重新建立完整 7.1.4 静态床，然后才
继续送帧。若替换了 `mpv.exe`，请确认新构建仍应用了本仓库的最新补丁。

### Playback statistics 只显示唤出时的数据

mpv 默认小写 `i` 调用的是四秒后自动关闭、期间不重绘的 `display-stats` 一次性
快照；`persistent_overlay` 只表示使用独立绘制层，并不改变该命令的一次性语义。
启动脚本因此加载 `mpv-input.conf`，把小写和大写 `i` 都绑定为
`stats/display-page-1-toggle`。同时给内置 `stats.lua` 追加
`stats-persistent_overlay=yes` 和 `stats-redraw_delay=0.25`，使统计叠加保持显示并
每秒刷新四次，直到再次按 `i`。若绕过批处理脚本直接运行 mpv，请同时加载该
输入配置并传入这两个 stats 参数。

## 更新运行包

更新 mpv、Omniphony Studio 或 bridge 时：

1. 替换 `releases/` 下对应的目录或安装包。
2. 确保 Spatial 版本的 `mpv.com` 或 `mpv.exe` 仍在
   `releases/mpv-omniphony-fel-windows-x86_64-ispatial/` 下；脚本会优先选择它。
3. 确保 `harletty_bridge.dll` 仍在 `releases/` 下。
4. 重新运行 `play-dovi-atmos-headphones.bat`。

普通播放不需要构建步骤。

## 许可证

仓库根目录使用 GPL-3.0。运行包和源码快照保留各自上游项目的许可证；重新分发前请检查对应上游项目中的许可证文件。
