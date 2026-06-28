# Dolby Vision·Atmos Batch Player

这是一个面向 Windows 的播放辅助项目，用来通过带 Omniphony 集成的 mpv
播放 Dolby Vision·Atmos 影片。仓库把启动脚本、耳机渲染配置和 overlay
偏好放在一起，日常使用时可以双击批处理脚本，也可以从命令行传入影片路径。

脚本本身保持很小：它会在本地 `releases` 目录下递归寻找 mpv 可执行文件和
解码桥接 DLL，然后使用项目内的 Omniphony 配置启动 mpv。

## 功能

- 使用 `mpv-omniphony` 的 `--ad=orender` 走空间音频渲染链路。
- 启动时自动把 `harletty_bridge.dll` 传给 orender。
- 启用 Omniphony OSC，方便 Omniphony Studio 显示实时对象位置和电平。
- 默认使用偏保守的双耳耳机配置，并启用自动增益。
- 视频侧使用 `gpu-next` 和 `target-colorspace-hint`，适合现代 HDR /
  Dolby Vision·Atmos 相关播放路径。
- 支持 Dolby Vision Profile 7.6 FEL（Full Enhancement Layer）片源；当前 `mpv-omniphony-fel-windows-x86_64` 运行包来自上游 FEL beta 构建。
- `releases/` 和 `sources/` 被 `.gitignore` 排除，避免把大体积运行包和源码快照提交进仓库。

## 运行要求

- Windows x86_64。
- mpv 可读取的影片文件，最好包含 Dolby Vision·Atmos 或其他对象式空间音频。
- Omniphony Studio，可以使用 `releases` 里的安装包，也可以使用兼容的上游版本。
- 带 Omniphony `ad_orender` 解码器的 mpv 构建。
- 播放 Dolby Vision Profile 7.6 FEL 时，需要使用 FEL 版 mpv 构建；普通 mpv-omniphony 构建不一定包含完整 FEL 依赖。
- `harletty_bridge.dll`，供 orender 解码音频流。
- 耳机或一个可用的 Windows 音频输出设备。

当前项目约定运行文件放在 `releases/` 下。目录名不需要完全一致，因为批处理脚本会递归搜索；但下面这些文件必须存在于 `releases/` 的某个子目录中：

```text
releases/
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
## 快速开始

1. 下载并解压 `mpv-omniphony-fel-windows-x86_64.zip` 到 `releases/` 下。
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
  --ad-orender-config=omniphony-headphones.config.yaml ^
  --ad-orender-bridge-path=harletty_bridge.dll ^
  --ad-orender-osc "movie.mkv"
```

真实路径由脚本运行时自动发现。如果需要增加或修改 mpv 参数，编辑
`play-dovi-atmos-headphones.bat` 即可。

## Dolby Vision Profile 7.6 FEL 支持

当前 `releases/mpv-omniphony-fel-windows-x86_64/` 使用上游 `mpv-omniphony-0.4.1-fel-beta.4` 的 FEL 链路，面向 Dolby Vision Profile 7.6 FEL / P7 双层片源。FEL 是 Full Enhancement Layer，不是单独一个 mpv 参数；它要求播放器构建同时具备以下组件：

- mpv `dv-fel` 补丁，用于拆分 BL / EL 并把 EL 交给 libplacebo。
- 带 `dovi_split` bitstream filter 的 ffmpeg，用于拆分 HEVC P7 双层码流。
- 支持 dv-fel 的 libplacebo，且 `PL_API_VER >= 367`。
- libdovi，用于 RPU / enhancement layer 相关解析。

验证 FEL 是否真的启用时，使用 Dolby Vision Profile 7.6 FEL 片源运行 mpv verbose 日志：

```powershell
.\releases\mpv-omniphony-fel-windows-x86_64\mpv.exe -v --vo=gpu-next "D:\Movies\Example.mkv"
```

日志中应能看到类似 `Dolby Vision Profile 7 splitter`、`virtual EL stream`、`el_pair` 的信息，并且不应出现 `dovi_split BSF not available` 或 `Invalid NAL unit size`。如果只想对比基础层，可以设置 `MPV_NO_FEL=1` 后再播放同一个片源。

FEL 支持仍按上游说明视为实验性功能。更完整的技术细节见 `sources/mpv-omniphony-0.4.1-fel-beta.4/README.md` 的 `Dolby Vision FEL (experimental)` 段落。

## 配置文件

### `omniphony-headphones.config.yaml`

这是批处理脚本传给 orender 的主渲染配置。

当前默认值：

- `render.osc: true`，允许 Studio 连接并监控播放。
- `render.osc_metering: true`，允许 Studio 接收电平数据。
- `render.auto_gain: true`，并将自动增益上限设为 `-3.0 dB`。
- `render.binaural.output_mode: binaural`，面向耳机双耳播放。
- `render.binaural.hrir_source: saf`。
- 关闭 reflections 和 reverb，保留更干净、保守的默认听感。

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
  omniphony-headphones.config.yaml    耳机渲染配置
  overlay-prefs.conf                  mpv 空间对象 overlay 偏好
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

### mpv 画面没有 overlay

当前 `overlay-prefs.conf` 中 `enabled=0`。改成 `enabled=1` 后重新播放即可。若使用自定义 mpv 按键绑定，也可以通过上游提供的
`omniphony_overlay/*` 绑定切换 overlay 功能。

## 更新运行包

更新 mpv、Omniphony Studio 或 bridge 时：

1. 替换 `releases/` 下对应的目录或安装包。
2. 确保 `mpv.com` 或 `mpv.exe` 仍在 `releases/` 下。
3. 确保 `harletty_bridge.dll` 仍在 `releases/` 下。
4. 重新运行 `play-dovi-atmos-headphones.bat`。

普通播放不需要构建步骤。

## 许可证

仓库根目录使用 GPL-3.0。运行包和源码快照保留各自上游项目的许可证；重新分发前请检查对应上游项目中的许可证文件。
