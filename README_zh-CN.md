# mpy-omniphony (FEL Beta) for Dolby Access

语言：简体中文 | [English](README.md)

面向 Windows 的 mpv/Omniphony 播放辅助项目。本项目在 Omniphony/FEL
链路上增加 `ISpatialAudioClient` 输出，使带名称的 7.1.4 PCM 静态床交给 Windows
Spatial Sound provider 渲染，并修复了 seek 后空间流重建、右键菜单运行时依赖和
Playback statistics 持久实时刷新问题。

本地 DD+ Atmos 补丁集修复的是完整 E-AC-3 JOC 解码与渲染链路中已经确认的问题，
不会按封装格式选择，也不限于 online media 或 Blu-ray。独立 5.1 流保持码流声明的
JOC 输入布局；Blu-ray 成对 access unit 则先把独立主帧与依赖子流中的离散通道
合并，再计算码流声明的 7 输入 JOC 矩阵。

Harletty 还修正了 JOC 反量化、稀疏矩阵和插值边界，让旁路 LFE 与 OAMD 事件对齐
JOC QMF 路径的 577 样本延迟，并正确解码 OAMD 的增益、继承、位置、warp、更新时间
和换段语义。配套的 Omniphony 补丁会跨帧保留元数据事件，在精确样本处应用每次
更新，并在扬声器和双耳路径中渲染对象增益渐变。DD+ 仍然是有损传输格式；这些
修复消除的是额外解码/渲染错误，并不宣称输出与 TrueHD Atmos 位级相同。

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

## 目录结构

```text
mpv-omniphony-fel-dolby-access/
├── README.md                                 # 英文文档
├── README_zh-CN.md                           # 简体中文文档
├── development/                              # 补丁、工具源码与构建脚本
│   ├── mpv/                                  # mpv 补丁
│   ├── harletty/                             # E-AC-3/JOC 解码器补丁
│   ├── omniphony/                            # 空间元数据与渲染补丁
│   ├── scripts/                              # 源码准备与 Windows 构建脚本
│   └── tools/
│       ├── ispatialaudio-probe.c             # Spatial API 独立探针源码
│       └── compare-spatial-wav.py            # 分声道 PCM 回归比较工具
├── mpv-input.conf                            # 实时统计按键绑定
├── omniphony-dolby-access.config.yaml        # 7.1.4 渲染配置
├── overlay-prefs.conf                        # 空间对象 overlay 偏好
├── play-dovi-atmos.bat                       # 播放入口
├── sources/                                  # 未修改的上游源码（Git 忽略）
├── releases/                                 # 未修改的上游发布包（Git 忽略）
├── build_temp/                               # 补丁工作树与中间产物（Git 忽略）
└── distribution/                             # 本地编译的成品运行包（Git 忽略）
```

Git 跟踪补丁、工具源码、配置和构建脚本；`sources/` 与 `releases/` 仅保存未经
修改的上游材料，`build_temp/` 与 `distribution/` 仅保存本地生成内容。这四个
目录以及个人编辑器工作区均由 `.gitignore` 排除。

## 获取原始材料

用户可自行下载并按下面的建议目录解压。目录名可通过构建脚本参数覆盖。

### 原始发布包：`releases/`

- [mpv-omniphony FEL Windows x86_64](https://github.com/mgth/mpv-omniphony/releases/download/v0.4.1-fel-beta.4/mpv-omniphony-fel-windows-x86_64.zip)
- [harletty-bridge v0.7.1 Windows x86_64](https://github.com/harletty/harletty-bridge/releases/download/v0.7.1/harletty-bridge-v0.7.1-windows-x86_64.zip)
- [Omniphony Studio 0.4.1 Windows x64](https://github.com/mgth/Omniphony/releases/download/v0.4.1/Omniphony.Studio_0.4.1_x64-setup.exe)（可选，仅用于 3D 可视化、监看和实时控制）

建议布局：

```text
releases/
  mpv-omniphony-fel-windows-x86_64/   原始基础运行包
  harletty-bridge-v0.7.1-windows-x86_64/
    harletty_bridge.dll
  Omniphony.Studio_0.4.1_x64-setup.exe  可选
```

### 原始源码：`sources/`

- [mpv Git 仓库](https://github.com/mpv-player/mpv)
- [mpv-omniphony v0.4.1-fel-beta.4 源码](https://github.com/mgth/mpv-omniphony/archive/refs/tags/v0.4.1-fel-beta.4.zip)
- [Omniphony v0.4.1 源码](https://github.com/mgth/Omniphony/archive/refs/tags/v0.4.1.zip)
- [harletty-bridge v0.7.1 源码](https://github.com/harletty/harletty-bridge/archive/refs/tags/v0.7.1.zip)

构建脚本默认从 `sources/mpv/` 读取完整的 mpv Git clone，并从
`sources/mpv-omniphony-0.4.1-fel-beta.4/` 读取 Omniphony 集成源码。当前补丁集以
mpv 提交 `70894ae0390cf20edac0e68de72ab26725520416` 为可复现基线；不能使用缺少
Git 对象的源码压缩包替代 mpv clone。

## 编译

先生成一个位于 `build_temp/`、不会污染原始源码的工作树：

```powershell
.\development\scripts\prepare-mpv-source.ps1
```

脚本依次应用 mpv-omniphony 的 `patches-master`、`patches-fel`，再应用
`development/mpv/` 中的 `0022` 和 `0023`，默认输出到
`build_temp/mpv-ispatial/`，不会修改 `sources/`。

准备好 UCRT LLVM-MinGW、Meson、Ninja、pkg-config 和 FEL/mpv 依赖前缀后构建：

```powershell
.\development\scripts\build-mpv-windows.ps1 `
  -PreparedSource .\build_temp\mpv-ispatial `
  -DependencyPrefix D:\mpv-deps `
  -ToolchainBin D:\llvm-mingw-ucrt\bin `
  -PkgConfig D:\w64devkit\bin\pkg-config.exe `
  -RuntimeBase .\releases\mpv-omniphony-fel-windows-x86_64
```

成品默认生成到：

```text
distribution/mpv-omniphony-fel-windows-x86_64-ispatial/
```

构建必须启用 Lua 5.2，并使用与基础运行包 DLL 一致的 UCRT ABI，否则 mpv 内置
右键菜单脚本可能无法加载，或出现 DLL 运行库混用问题。构建脚本会复制基础运行
包的 DLL（跳过其 README），再替换新编译的 `mpv.exe` 与 `mpv.com`；若目标目录
已经存在，脚本会停止，避免静默覆盖。

### 修正版 DD+ Atmos 解码与渲染链路

DD+ Atmos 修复从干净的 Harletty v0.7.1 与 Omniphony v0.4.1 源码单独构建；请使用
Rust 1.88 或更新版本以及 MSVC target：

- Harletty 补丁按码流声明重建 5 或 7 输入 JOC 拓扑、修正矩阵重建，把旁路 LFE
  延迟 QMF 路径的 577 样本，并让 OAMD 事件进行相同的时间平移。
- OAMD 的增益/状态默认值、前一对象与前次更新继承、差分位置、trim
  `warp_mode`、序列中断和全部 block update 均会被解析；block 起点为
  `sample_offset + 32 * block_offset_factor`。
- Omniphony 补丁跨解码帧排队绝对元数据时间戳，在每个到期事件的边界切分 PCM，
  并在扬声器及双耳渲染中执行有限时长的线性振幅增益渐变。

```powershell
.\development\scripts\prepare-harletty-source.ps1
.\development\scripts\build-harletty-bridge.ps1
```

第一个脚本把两份上游源码复制到 `build_temp/harletty-ddplus-fix/` 并应用 Git 所
跟踪的补丁，不修改 `sources/`；第二个脚本运行解码器和空间渲染回归测试，并生成：

```text
distribution/harletty-bridge-v0.7.1-ddplus-atmos-fix-windows-x86_64/harletty_bridge.dll
distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/
  orender.dll
  harletty_bridge.dll
```

第二个目录是完整可运行包：它以现有 iSpatial mpv 包为基础，仅替换修正版
`orender.dll` 并加入修正版 bridge。`play-dovi-atmos.bat` 会优先使用这一整套链路。
只有测试其他 bridge 构建时才需要用 `HARLETTY_BRIDGE` 显式指定 DLL；若修正版
不存在，启动器仍会回退到原 iSpatial 包和 `releases/` 中的上游 DLL。

### Spatial API 探针

若 `clang` 已在 `PATH` 中，可单独编译默认音频端点探针：

```powershell
.\development\scripts\build-ispatialaudio-probe.ps1
```

也可通过 `-ToolchainBin D:\llvm-mingw-ucrt\bin` 指定 LLVM-MinGW。成品默认生成到
`distribution/tools/ispatialaudio-probe.exe`。

## 播放

1. 在当前默认 Windows 音频设备上启用对应的 Dolby Atmos 空间音效模式。
2. 确认修正版运行包位于
   `distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/`。
3. 双击 `play-dovi-atmos.bat`，拖入影片并按 Enter。

Omniphony Studio 不是播放依赖，无需安装或预先启动。mpv 运行包自带
`orender.dll`，`--ad=orender` 会在 mpv 进程内创建渲染器。只有需要 3D 对象
可视化、电平监看或实时调参时，才需另行安装并启动 Studio；它会通过 OSC 连接
内嵌渲染器。没有 Studio 连接时，启用 OSC 也不影响解码和音频输出。

也可以直接传入路径：

```powershell
.\play-dovi-atmos.bat "D:\Movies\Example.mkv"
```

若成品在其他位置，可临时指定已打本项目补丁的 mpv：

```powershell
$env:MPV_SPATIAL = "D:\my-mpv\mpv.com"
.\play-dovi-atmos.bat "D:\Movies\Example.mkv"
```

启动器不会从 `releases/` 中任意挑选 mpv，以免误用没有 `wasapi-spatial` 的原始
发布版。它只使用 `distribution/` 中的本地成品或显式设置的 `MPV_SPATIAL`。

## 默认运行参数

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

`omniphony-dolby-access.config.yaml` 默认输出 7.1.4 扬声器布局、按名称映射通道、
Master Gain `0 dB`、关闭自动增益，并启用 OSC metering。耳机模式下的双耳化由
Windows/Dolby Atmos for Headphones 完成。视频默认通过 D3D11VA 零拷贝硬件解码；
这对高码率 4K 以及 50/60 fps 的 Dolby Vision Profile 7 FEL 片源尤其重要，因为
基础层和增强层需要同时解码。若显卡或驱动不兼容，可临时设置
`$env:MPV_HWDEC = "no"` 后再运行启动器，强制回退软件解码。

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

右键菜单依赖 mpv 内置 `select.lua` / `context_menu.lua`。确认运行的是启用
Lua 5.2 的 UCRT `distribution/` 成品。

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

### 高码率片源声音正常但画面卡顿

确认通过 `play-dovi-atmos.bat` 启动，而不是绕过启动器直接运行 mpv。verbose 日志
应针对基础层和增强层各出现一次 `Using hardware decoding (d3d11va)`。如果日志
显示 `Using software decoding`，请检查显卡驱动及 HEVC Main 10 硬解支持；也可用
环境变量 `MPV_HWDEC` 临时指定 mpv 支持的其他硬解后端。

### DD+ Atmos 声场发糊、定位错误或增益/静音异常

检查启动器打印的 `Using mpv:` 与 `Using bridge:`；两者都应指向
`distribution/mpv-omniphony-fel-windows-x86_64-ddplus-atmos-fix/`。如果只替换 bridge
而继续使用旧 `orender.dll`，元数据调度和增益渐变问题仍然存在。verbose 日志应选择
`orender` 解码器，并请求
`fl-fr-fc-lfe-bl-br-sl-sr-tfl-tfr-tbl-tbr` float 输出。

对于主帧加依赖子流，修正版 bridge 会先合并离散环绕扩展，再计算 7 输入 JOC
矩阵，不再把侧环绕复制到后环绕输入。对于独立 online-media 流，同一 bridge 会
直接采用码流声明的 5 输入拓扑而不执行该合并。两条路径都会使用修正后的 JOC
重建、577 样本内部 LFE/OAMD 对齐和样本精确的 OAMD 调度。

## 许可证

仓库根目录使用 GPL-3.0。`sources/` 和 `releases/` 中的用户下载材料保留各自上游
许可证；重新分发本地 `distribution/` 成品前，请同时检查所有所链接组件的许可要求。
