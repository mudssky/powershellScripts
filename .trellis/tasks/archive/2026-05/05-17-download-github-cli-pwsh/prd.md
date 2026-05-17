# brainstorm: 下载 GitHub 命令行工具脚本

## Goal

开发一个位于 `scripts/pwsh/download` 的 PowerShell 下载脚本，用于按 JSON 配置下载 GitHub 项目资源，并复用 `psutils/src/config` 中的通用配置能力，目标是支持跨平台运行。

## What I already know

* 目标脚本目录为 `scripts/pwsh/download`。
* 需要支持跨平台 PowerShell。
* 下载目标由 JSON 配置文件声明。
* 配置读取/合并应使用通用配置库 `psutils/src/config`。
* 示例 GitHub 项目为 `betterleaks/betterleaks`。
* `scripts/pwsh/download` 当前为空目录，可作为新下载工具目录。
* `scripts/pwsh/network/downGithub.ps1` 已有按 GitHub 用户批量 clone 仓库的旧脚本，但它面向仓库备份，不适合直接表达 release asset 下载。
* `psutils/modules/config.psm1` 通过 dot-source 复用 `psutils/src/config`，并导出 `Resolve-ConfigSources` 等公共函数。
* `psutils/src/config` 的 `JsonFile` source 会将 JSON 顶层对象转换为 hashtable，适合读取下载清单。
* `betterleaks/betterleaks` 的 `v1.2.0` release 提供 Windows/Linux/macOS 的 x64/arm64 包和 `checksums.txt`。

## Assumptions (temporary)

* “下载 GitHub 命令行”可能指从 GitHub 项目下载 release artifact、源码压缩包或可执行产物，具体目标格式待确认。
* 脚本需要可重复运行，并能处理已有文件、网络失败、平台差异等场景。

## Open Questions

* 暂无阻塞问题。

## Requirements (evolving)

* 提供跨平台 PowerShell 脚本入口。
* 支持 JSON 配置声明待下载项目。
* 复用 `psutils/src/config` 的配置读取能力。
* MVP 聚焦 GitHub Release Asset 下载。
* 下载后自动解压并安装 CLI 到固定路径。
* 安装路径必须可配置，并支持不同平台使用不同路径。
* 默认安装路径采用用户级目录，避免依赖管理员权限：
  * Windows 默认 `%USERPROFILE%\.local\bin`
  * Linux/macOS 默认 `~/.local/bin`
* JSON 配置可以覆盖全局默认安装路径，也可以按项目/平台覆盖安装路径。
* 安装完成后只检测安装目录是否在 PATH，不自动修改用户环境变量或 shell 配置。
* 当安装目录不在 PATH 时，按当前平台输出添加 PATH 的命令或操作方法。
* 目标 CLI 文件已存在时默认覆盖，用于支持重复运行更新。
* 提供 `--no-overwrite` 参数，目标文件已存在时跳过安装。

## Acceptance Criteria (evolving)

* [x] 可以通过 JSON 配置声明至少一个 GitHub 项目并执行下载。
* [x] 脚本在 Windows、Linux/macOS PowerShell 上使用平台无关路径处理。
* [x] 配置加载逻辑复用 `psutils/src/config`。
* [x] 示例配置可覆盖 `betterleaks/betterleaks`。
* [x] 能根据当前平台选择对应 release asset 并下载。
* [x] 能解压 `.zip` 与 `.tar.gz` 发布包。
* [x] 能把 CLI 可执行文件安装到配置指定的平台路径。
* [x] 安装目录不在 PATH 时，输出 Windows/Linux/macOS 对应的 PATH 添加提示。
* [x] 目标文件已存在时默认覆盖。
* [x] 传入 `--no-overwrite` 时目标文件已存在则跳过。

## Definition of Done (team quality bar)

* Tests added/updated (unit/integration where appropriate)
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* 暂不支持 Git clone 备份模式。
* 暂不支持源码归档下载模式。

## Technical Notes

* PowerShell 脚本需遵循 `.trellis/spec/pwsh-scripts/package/index.md`：修改脚本逻辑后至少运行根目录 PowerShell QA 或 `pnpm --filter pwsh-scripts test:qa`。
* 若修改 `psutils` 源码/测试，需遵循 `.trellis/spec/psutils/package/index.md`。
* `Resolve-ConfigSources -ConfigFile <json> -BasePath <dir> -ErrorOnMissing` 可作为下载清单读取入口。
* 当前可复用 `config/service/oss/rclone/rclone-ops.ps1` 中“脚本自行 Import-Module psutils/modules/config.psm1”的模式。
* GitHub CLI 文档调研见 `research/github-cli-release-download.md`。

## Research References

* [`research/github-cli-release-download.md`](research/github-cli-release-download.md) — 建议 MVP 聚焦 `gh release download` 的 GitHub Release Asset 下载。

## Research Notes

### Feasible approaches here

**Approach A: GitHub CLI Release Asset 下载（Recommended）**

* How it works: JSON 配置声明 repo、tag、平台 asset pattern 与输出目录；脚本按当前 OS/CPU 选择 pattern，调用 `gh release download`。
* Pros: 复用 GitHub CLI 认证、下载、错误处理；最贴合命令行工具发布方式；实现较小。
* Cons: 依赖本机安装 `gh`，未安装时需诊断。

**Approach B: GitHub REST API 直接下载**

* How it works: 脚本自行请求 release API，匹配 asset，使用 PowerShell 下载。
* Pros: 不依赖 `gh`。
* Cons: 需要处理认证、限流、重定向和更多测试边界。

**Approach C: release asset / source archive / clone 混合**

* How it works: JSON 中每个项目声明下载模式。
* Pros: 泛化能力最强。
* Cons: MVP 配置 schema 与实现复杂度明显增加。

## Decision (ADR-lite)

**Context**: 该工具的主要目标是安装 GitHub 上分发的 CLI，用户希望下载后直接安装到固定目录，且不同平台可使用不同安装路径。

**Decision**: MVP 采用 GitHub CLI Release Asset 下载方案，并包含自动解压/安装能力。JSON 配置需要表达 repo、tag 或 latest、平台 asset 匹配规则、CLI 可执行文件名与平台安装路径。

**Consequences**: 工具会比纯下载多处理压缩格式、目标覆盖、可执行权限等边界；源码归档和 clone 留到后续扩展。

## Decisions

* 默认安装路径采用用户级目录，并允许配置覆盖；不默认使用系统级目录，避免 sudo/管理员权限成为常规路径。
* PATH 处理采用“检测 + 平台化提示”，不自动修改环境变量或 shell 配置。
* 覆盖策略采用“默认覆盖 + `--no-overwrite` 可跳过”，贴合 CLI 安装/更新场景。
