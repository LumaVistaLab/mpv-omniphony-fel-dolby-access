# 二次开发与本地构建

这个目录是本项目所有二次开发内容的唯一入口，并由 Git 追踪。`sources/` 和
`releases/` 只保存用户自行下载、未经修改的上游材料；脚本不会在其中打补丁或
写入构建结果。

## 内容

```text
development/
  mpv/
    0022-ao-wasapi-add-Windows-Spatial-Sound-static-bed.patch
    0023-player-make-playback-statistics-a-live-toggle.patch
  scripts/
    prepare-mpv-source.ps1
    build-mpv-windows.ps1
    build-ispatialaudio-probe.ps1
  tools/
    ispatialaudio-probe.c
```

- `0022` 实现 `ISpatialAudioClient` 7.1.4 静态床输出，并包含 seek/reset 后安全
  重建空间流与对象的修复。
- `0023` 让 mpv 内置 Playback statistics 使用持久 overlay 并持续重绘。
- `ispatialaudio-probe.c` 可独立检查当前 Windows 默认多媒体端点是否支持创建
  7.1.4 Spatial Sound 静态床。

## 目录边界

| 目录 | 内容 | Git |
|---|---|---|
| `development/` | 本项目补丁、工具源码、构建脚本 | 追踪 |
| `sources/` | 未修改的上游源码或 Git clone | 忽略 |
| `releases/` | 未修改的上游发布包、安装包 | 忽略 |
| `build/` | 打过补丁的工作树、中间文件 | 忽略 |
| `dist/` | 本地编译后的可运行包 | 忽略 |

不要直接修改 `sources/` 中的文件。需要调试 mpv 时，重新生成 `build/` 下的工作
树；确定修改后再更新这里的补丁。

## 准备原始材料

至少需要：

1. 完整的 mpv Git clone，放在 `sources/mpv/`。它必须包含提交
   `70894ae0390cf20edac0e68de72ab26725520416`；这是当前补丁集验证过的基线。
2. `mpv-omniphony` 的 `v0.4.1-fel-beta.4` 原始源码，放在
   `sources/mpv-omniphony-0.4.1-fel-beta.4/`。
3. 原始 Windows FEL 运行包，解压到
   `releases/mpv-omniphony-fel-windows-x86_64/`。构建脚本用它作为 DLL 基础包，
   但不会修改它。
4. UCRT 版 LLVM-MinGW、Meson、Ninja、pkg-config，以及可被 pkg-config 找到的
   mpv/FEL 依赖前缀。FEL 依赖包括带 `dovi_split` 的 FFmpeg、`dv-fel`
   libplacebo、libdovi 和 liborender；具体版本与构建方法以原始
   `mpv-omniphony` 源码中的 `.github/workflows/build-fel.yml` 和
   `scripts/build-fel-deps.sh` 为准。

原始包的下载地址列在仓库根目录 README 中。依赖可放在仓库外；如果放进本仓库，
仍应保持在 `sources/` 或 `releases/` 内且不作修改。

## 生成打补丁的工作树

在仓库根目录运行：

```powershell
.\development\scripts\prepare-mpv-source.ps1
```

脚本依次应用上游 `patches-master`、上游 `patches-fel`，最后应用本项目的 `0022`
和 `0023`，默认输出到 `build/mpv-ispatial/`。原始源码不会被修改。也可以显式
指定路径：

```powershell
.\development\scripts\prepare-mpv-source.ps1 `
  -MpvSource D:\src\mpv `
  -IntegrationSource D:\src\mpv-omniphony-0.4.1-fel-beta.4 `
  -Destination .\build\mpv-ispatial
```

## 编译并生成运行包

下面的脚本复现当前 Windows 构建的关键约束：UCRT、Lua 5.2、orender、WASAPI
和 D3D11。它使用用户提供的工具链与依赖，不下载或修改上游材料。

```powershell
.\development\scripts\build-mpv-windows.ps1 `
  -PreparedSource .\build\mpv-ispatial `
  -DependencyPrefix D:\mpv-deps `
  -ToolchainBin D:\llvm-mingw-ucrt\bin `
  -PkgConfig D:\w64devkit\bin\pkg-config.exe `
  -RuntimeBase .\releases\mpv-omniphony-fel-windows-x86_64
```

默认构建目录是 `build/mpv-windows-ucrt/`，成品目录是
`dist/mpv-omniphony-fel-windows-x86_64-ispatial/`。脚本先复制原始运行包的 DLL，
再只替换新编译的 `mpv.exe` 和 `mpv.com`。如果输出目录已经存在，脚本会停止，
避免静默覆盖旧成品。

编译完成后，可直接运行根目录的 `play-dovi-atmos-headphones.bat`。

## 编译 Spatial API 探针

若 `clang` 已在 `PATH` 中：

```powershell
.\development\scripts\build-ispatialaudio-probe.ps1
```

也可以用 `-ToolchainBin D:\llvm-mingw-ucrt\bin` 指定 LLVM-MinGW。成品默认写入
`dist/tools/ispatialaudio-probe.exe`，不会在源码目录旁生成未追踪文件。
