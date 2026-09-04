# Dolby Vision · Atmos Batch Player

面向 Windows 的 mpv/Omniphony 播放辅助项目。当前二次开发在 Omniphony/FEL
链路上增加 `ISpatialAudioClient` 输出，使带名称的 7.1.4 PCM 静态床交给 Windows
Spatial Sound provider 渲染，并修复了 seek 后空间流重建、右键菜单运行时依赖和
Playback statistics 持久实时刷新问题。

音频设备不写死，始终使用 Windows 当前的默认多媒体输出端点。当前以 Dolby
Atmos for Headphones 为基准；切换到支持的 HDMI 默认端点并启用 Dolby Atmos
for Home Theater 后，同一后端会按新端点重新创建空间流。

## 音频链路

```text
Atmos 音轨 -> orender -> 带名称的 7.1.4 float PCM
           -> wasapi-spatial -> 12 个 Windows 静态音频对象
           -> 当前 Spatial Sound provider -> 默认耳机或家庭影院端点
```

这里不是把原始 Atmos bitstream 或动态对象元数据直接传给 Dolby Access。
orender 先生成 7.1.4 静态床，`wasapi-spatial` 再保留每个扬声器的位置语义提交给
Windows。普通 WASAPI 共享模式通常只能协商到平面 7.1，因此启动参数使用
`--ao=wasapi-spatial,wasapi`：7.1.4 优先走 Spatial Sound，初始化失败时才回退。

## 仓库边界

```text
.
  development/                       本项目二次开发，Git 追踪
    mpv/                              mpv 补丁
    scripts/                          源码准备与 Windows 构建脚本
    tools/ispatialaudio-probe.c       Spatial API 独立探针源码
  mpv-input.conf                      实时统计按键绑定
  omniphony-headphones.config.yaml    7.1.4 渲染配置
  overlay-prefs.conf                  空间对象 overlay 偏好
  play-dovi-atmos-headphones.bat      播放入口
  dovi-atmos-batch-player.code-workspace  VS Code 工作区配置
  sources/                            未修改的上游源码，Git 忽略
  releases/                           未修改的上游发布包，Git 忽略
  build/                              打补丁的工作树与中间产物，Git 忽略
  dist/                               本地编译的成品运行包，Git 忽略
```

`sources/` 和 `releases/` 不再放置任何二次开发文件或自编译成品。所有需要维护的
补丁、工具源码、配置和构建脚本都在 Git 中；只有下载材料、编译中间产物和成品
二进制被排除。

详细的补丁顺序、依赖要求和本地构建命令见
[`development/README.md`](development/README.md)。

## 获取原始材料

用户可自行下载并按下面的建议目录解压。目录名可通过构建脚本参数覆盖。

### 原始发布包：`releases/`

- [mpv-omniphony FEL Windows x86_64](https://github.com/mgth/mpv-omniphony/releases/download/v0.4.1-fel-beta.4/mpv-omniphony-fel-windows-x86_64.zip)
- [harletty-bridge v0.7.1 Windows x86_64](https://github.com/harletty/harletty-bridge/releases/download/v0.7.1/harletty-bridge-v0.7.1-windows-x86_64.zip)
- [Omniphony Studio 0.4.1 Windows x64](https://github.com/mgth/Omniphony/releases/download/v0.4.1/Omniphony.Studio_0.4.1_x64-setup.exe)

建议布局：

```text
releases/
  mpv-omniphony-fel-windows-x86_64/   原始基础运行包
  harletty-bridge-v0.7.1-windows-x86_64/
    harletty_bridge.dll
  Omniphony.Studio_0.4.1_x64-setup.exe
```

### 原始源码：`sources/`

- [mpv Git 仓库](https://github.com/mpv-player/mpv)
- [mpv-omniphony v0.4.1-fel-beta.4 源码](https://github.com/mgth/mpv-omniphony/archive/refs/tags/v0.4.1-fel-beta.4.zip)
- [Omniphony v0.4.1 源码](https://github.com/mgth/Omniphony/archive/refs/tags/v0.4.1.zip)
- [harletty-bridge v0.7.1 源码](https://github.com/harletty/harletty-bridge/archive/refs/tags/v0.7.1.zip)

当前补丁集以 mpv 提交
`70894ae0390cf20edac0e68de72ab26725520416` 为可复现基线。mpv 必须使用完整 Git
clone，不能只下载缺少 Git 对象的源码压缩包。

## 编译

先生成一个位于 `build/`、不会污染原始源码的工作树：

```powershell
.\development\scripts\prepare-mpv-source.ps1
```

准备好 UCRT LLVM-MinGW 和 FEL/mpv 依赖前缀后构建：

```powershell
.\development\scripts\build-mpv-windows.ps1 `
  -PreparedSource .\build\mpv-ispatial `
  -DependencyPrefix D:\mpv-deps `
  -ToolchainBin D:\llvm-mingw-ucrt\bin `
  -PkgConfig D:\w64devkit\bin\pkg-config.exe `
  -RuntimeBase .\releases\mpv-omniphony-fel-windows-x86_64
```

成品默认生成到：

```text
dist/mpv-omniphony-fel-windows-x86_64-ispatial/
```

构建必须启用 Lua 5.2，并使用与基础运行包 DLL 一致的 UCRT ABI，否则 mpv 内置
右键菜单脚本可能无法加载，或出现 DLL 运行库混用问题。

## 播放

1. 安装并启动 Omniphony Studio。
2. 在当前默认 Windows 音频设备上启用对应的 Dolby Atmos 空间音效模式。
3. 确认本地构建位于 `dist/mpv-omniphony-fel-windows-x86_64-ispatial/`，并且
   `releases/` 中有原始 `harletty_bridge.dll`。
4. 双击 `play-dovi-atmos-headphones.bat`，拖入影片并按 Enter。

也可以直接传入路径：

```powershell
.\play-dovi-atmos-headphones.bat "D:\Movies\Example.mkv"
```

若成品在其他位置，可临时指定已打本项目补丁的 mpv：

```powershell
$env:MPV_SPATIAL = "D:\my-mpv\mpv.com"
.\play-dovi-atmos-headphones.bat "D:\Movies\Example.mkv"
```

启动器不会从 `releases/` 中任意挑选 mpv，以免误用没有 `wasapi-spatial` 的原始
发布版。它只使用 `dist/` 中的本地成品或显式设置的 `MPV_SPATIAL`。

## 默认运行参数

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

`omniphony-headphones.config.yaml` 默认输出 7.1.4 扬声器布局、按名称映射通道、
Master Gain `0 dB`、关闭自动增益，并启用 OSC metering。虽然文件名保留
`headphones`，实际的耳机双耳化由 Windows/Dolby Atmos for Headphones 完成。

## 验证与排错

### 确认 7.1.4 没有降级

使用 verbose 日志播放时应同时看到：

```text
Using Windows Spatial Sound static bed: fl-fr-fc-lfe-bl-br-sl-sr-tfl-tfr-tbl-tbr
AO: [wasapi-spatial] 48000Hz ... 12ch float
```

如果看到 `AO: [wasapi]`，说明已经回退。检查默认多媒体端点、Dolby Access 模式
以及日志中的 `required` / `missing` 静态对象掩码。可编译并运行
`development/tools/ispatialaudio-probe.c` 单独验证当前默认端点。

### 右键菜单不可用

右键菜单依赖 mpv 内置 `select.lua` / `context_menu.lua`。确认运行的是 UCRT +
Lua 5.2 的 `dist/` 成品，不是早期关闭 Lua 的测试构建。

### 快进或快退后卡死、闪退

`ISpatialAudioClient::Reset()` 会撤销现有静态对象。`0022` 补丁会让音频线程在
seek 时同步停止、Reset、释放旧对象，并重建完整 7.1.4 对象集后继续送帧。若
替换了 `mpv.exe`，请确认仍应用了最新 `0022`。

### Playback statistics 不持久或不刷新

`mpv-input.conf` 把 `i` / `I` 绑定为 `stats/display-page-1-toggle`；启动器同时设置
持久 overlay 与 `0.25 s` 重绘周期。若绕过启动器，请自行加载输入配置和这两个
stats 参数，并确认构建包含 `0023`。

### Dolby Vision Profile 7 FEL

FEL 构建需要同时包含 mpv `dv-fel` 补丁、带 `dovi_split` 的 FFmpeg、支持
`dv-fel` 且 `PL_API_VER >= 367` 的 libplacebo，以及 libdovi。verbose 日志中应能
看到 `Dolby Vision Profile 7 splitter`、`virtual EL stream` 或 `el_pair`，且不应
出现 `dovi_split BSF not available`。

## 许可证

仓库根目录使用 GPL-3.0。`sources/` 和 `releases/` 中的用户下载材料保留各自上游
许可证；重新分发本地 `dist/` 成品前，请同时检查所有所链接组件的许可要求。
