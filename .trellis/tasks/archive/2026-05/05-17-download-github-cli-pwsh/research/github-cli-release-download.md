# GitHub CLI Release 下载调研

## 调研问题

如何在跨平台 PowerShell 脚本中按 JSON 配置下载 GitHub 项目的命令行发布产物。

## 资料来源

* Context7：`/cli/cli`，查询 `gh release download owner/repo asset pattern latest output directory json scripting PowerShell cross platform`
* GitHub CLI 实测：`gh release view v1.2.0 -R betterleaks/betterleaks --json tagName,assets,publishedAt,url`
* GitHub 仓库：`betterleaks/betterleaks`

## 关键结论

* GitHub CLI 提供 `gh release download <tag> --pattern <glob> --dir <directory>`，适合按 release asset 下载命令行二进制包。
* `gh` 的 `--json` 输出适合脚本查询 release 元数据；实测 `gh release view` 可用字段包括 `tagName`、`assets`、`publishedAt`、`url` 等。
* `betterleaks/betterleaks` 在 `v1.2.0` 提供多平台 asset：
  * `betterleaks_1.2.0_windows_x64.zip`
  * `betterleaks_1.2.0_windows_arm64.zip`
  * `betterleaks_1.2.0_linux_x64.tar.gz`
  * `betterleaks_1.2.0_linux_arm64.tar.gz`
  * `betterleaks_1.2.0_darwin_x64.tar.gz`
  * `betterleaks_1.2.0_darwin_arm64.tar.gz`
  * `checksums.txt`

## 可选方案

### 方案 A：以 GitHub CLI Release Asset 为主（推荐）

配置声明 `repo`、`tag`、平台 asset pattern 与输出目录，脚本调用 `gh release download` 下载匹配产物。

优点：
* 复用 `gh` 认证、GitHub API 兼容性和 release 下载逻辑。
* 脚本实现较小，跨平台差异主要集中在 asset pattern 选择。
* 对命令行工具分发场景最贴合。

缺点：
* 依赖本机安装 `gh`。
* 未安装或未登录时需要给出清晰诊断。

### 方案 B：直接调用 GitHub REST API 下载

脚本自行查询 GitHub release API，选择 asset URL 后用 `Invoke-WebRequest` 下载。

优点：
* 不依赖 `gh` 可执行文件。
* 下载流程完全由脚本控制。

缺点：
* 需要自己处理 GitHub 认证、限流、重定向、错误映射。
* 实现和测试成本更高。

### 方案 C：支持 clone/源码归档与 release asset 混合

配置允许每个项目选择 `releaseAsset`、`sourceArchive` 或 `clone`。

优点：
* 泛化能力强，可覆盖更多 GitHub 下载场景。

缺点：
* MVP 范围变大，配置 schema 和错误处理更复杂。

## 建议

MVP 采用方案 A：聚焦 GitHub Release Asset 下载，示例覆盖 `betterleaks/betterleaks` 的平台包选择。源码归档、clone、自动解压安装可作为后续扩展。
