# build_temp 清理记录 — 2026-09-21

清理已完成，`build_temp/` 保留为空目录。清理前仓库提交为
`631b52003ebafc4a7ac15ed04d771da2717af38f`。此次未创建提交。

## 空间与范围

- 删除临时普通文件 145,722 个，逻辑大小 25,516,816,605 字节（23.764 GiB）。另有 13 个文件符号链接，其目标不随链接删除。
- 归档证据占 581,872,462 字节（554.92 MiB）。按文件逻辑大小计算净减少约 23.22 GiB。
- C 盘可用空间从 56.36 GiB 增至 79.23 GiB，实测增加 22.87 GiB。此指标可能包含同期其他进程的磁盘活动，且与含硬链接的逻辑文件大小不同。
- 保留文件内容 23,348 份，按 SHA-256 去重为 6,110 个数据块。
- 删除范围仅为本仓库 `build_temp/` 的内容；删除前逐项验证绝对路径、目录不是链接，且无活动构建进程使用临时树。

主要占用如下；完整逐文件清单位于归档中。

| 临时目录 | 清理前 GiB | 普通文件数 |
| --- | ---: | ---: |
| `trim-warp-scope-verify2` | 3.162 | 9,336 |
| `harletty-ddplus-fix-repro` | 3.056 | 8,556 |
| `harletty-ddplus-atmos-fix-verify2` | 2.970 | 9,120 |
| `msys64` | 2.789 | 58,232 |
| `harletty-ddplus-atmos-fix-verify` | 1.940 | 5,778 |
| `harletty-ddplus-atmos-final-check` | 1.937 | 5,774 |
| `rust` | 1.739 | 22,847 |
| `ddplus-fix-regression` | 1.233 | 10 |
| `startup-declick-70db-work` | 1.148 | 3,386 |
| `startup-declick-70db-patch-verify` | 0.731 | 2,722 |

## 追溯材料

本地证据目录：`distribution/build-temp-cleanup/2026-09-21/`（沿用 distribution 的 Git 忽略规则）。

- `retained-blobs.zip`：源码工作树、Git 数据库和索引、未提交修改对应的实际文件、日志、验证结果、脚本、构建配置、锁文件、Rust crate 包、MSYS2 已安装包数据库及工具链版本记录；内容以 `blobs/<sha256>` 存储，避免重复保存。
- `build-temp-manifest.jsonl.gz`：161,758 个文件、目录和链接的相对路径、大小、修改时间、属性、文件 SHA-256 或链接目标，以及 `archived` / `discard-generated` 等处置结果。普通文件均已计算 SHA-256；链接只记录链接本身，不读取目标。
- `summary.json`：各临时目录大小、仓库提交、临时 Git 仓库 HEAD / remote / 状态、归档哈希及统计。
- `preserved-files.jsonl.gz`：清理前 sources、releases、已有 distribution 内容和 development 工具的内容/元数据清单。
- `pre-delete-check.json`、`preserved-check.json`、`restore-check.json`、`restore-git-fsck.log`、`cleanup-result.json`：删除前一致性复核、保留文件验收、恢复试验及最终结果。

工具链安装目录、编译缓存/目标文件、旧测试 DLL/EXE 和大型生成 PCM/WAV 已删除，归档保留它们的路径、大小及哈希。这些生成内容不由恢复工具还原。

## 验收

- 归档内每个数据块均重新读取并核对 SHA-256。
- 删除前 161,758 项路径、修改时间、属性、文件大小及链接目标与清单一致。
- 清理后核对 2,781 项保留记录，其中 2,592 个普通文件的 SHA-256、大小、修改时间、属性均一致；sources / releases 目录结构与既有 junction 目标一致。
- 从归档恢复 `mpv-pristine-70894` 的 1,118 个文件，逐文件校验通过。`git fsck --full` 通过，HEAD 为 `70894ae0390cf20edac0e68de72ab26725520416`，工作树无差异。验收用恢复目录已删除。
- 最终 `build_temp/` 为空。此次没有执行编译或更改播放产物。

## 恢复与后续构建

维护工具位于 `development/tools/archive-build-temp.py` 和 `development/tools/restore-build-temp.py`。
恢复工具要求一个新的、位于 `build_temp/` 内的目标目录；先校验归档整体哈希，再校验恢复文件哈希。链接保留在清单中，不自动重建。归档中的 Git remote 仍记录历史本地路径，需要联网操作时应按原上游来源重新设置。

当前 `sources/mpv/` 不存在，mpv 原始 Git 历史此前仅在临时树中，因此该完整历史已归档。需要重建时可先恢复原始 mpv 树，在仓库根目录执行：

```powershell
python development/tools/restore-build-temp.py `
  distribution/build-temp-cleanup/2026-09-21 `
  mpv-pristine-70894 build_temp/restored-mpv-pristine

pwsh -File development/scripts/prepare-mpv-source.ps1 `
  -MpvSource build_temp/restored-mpv-pristine `
  -Destination build_temp/mpv-ispatial
```

其他历史源码树可使用 `summary.json` 中的路径替换 `mpv-pristine-70894`，例如 `mpv-ispatial-0026-build` 或 `libplacebo-fel-official`。该命令恢复归档时的实际文件，包括临时树中未提交的改动。归档不等同于全部历史构建产物的完整备份。

重编译前需重新安装已删除的临时 MSYS2 / Rust 工具链；包版本、Cargo.lock、Rust crate 包、Meson 配置和构建日志可从归档查阅。现有 distribution 播放产物已保留。

## 证据文件 SHA-256

| 文件 | SHA-256 |
| --- | --- |
| `build-temp-manifest.jsonl.gz` | `3bdcf420ee134536ba92641b83bd4723a41d00c9543a284503e21213e606a867` |
| `cleanup-result.json` | `17de089f5b961872f5c9b29594d72fe322fffd8224be0a6589477f61415f5a75` |
| `pre-delete-check.json` | `da92537f9324f3d48195a9c9a1371b1b85f7feb72f172f158352e8269fc3d2b4` |
| `preserved-check.json` | `b11550be3d2b2c62347ebb81c98635787d04aab4b26bb8be2de7aaf22fbf9fbb` |
| `preserved-files.jsonl.gz` | `8962b1f068dabc66957973e90f4ea55ffd7c45f6d436293094a6803e8737a223` |
| `restore-check.json` | `9e2953651926bc4073ee7bbab6ef40ce383a2f2445d8248b39ebfcac51705705` |
| `restore-git-fsck.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `retained-blobs.zip` | `53d162ff68103dde72438f719a211ed2d39e4393e4d4918166c5479b135e7d41` |
| `summary.json` | `0fedaf7c927311bc5a1bb9fb631ab753efec4599ff3a14f00c9c6b4e8e509fea` |
