# 统一 Go 安装方式并移除 g 用法

## Goal

统一仓库安装流水线中的 Go 安装来源：Windows 使用 Scoop，Linux 与 macOS 使用 Homebrew，不再安装或依赖 `voidint/g` Go 版本管理器。

## Background

- `profile/installer/apps-config.json` 已有 Homebrew 的 `go` 条目，但被 `skipInstall` 排除且没有安装流水线标签。
- Scoop 清单当前没有 Go 条目。
- `profile/installer/installApp.ps1` 仍会下载并执行 `voidint/g` 的远程安装脚本。
- Windows、Linux、macOS 的 Core CLI 步骤均从 `apps-config.json` 按 `core`、`cli` 标签选择应用。
- 仓库内未发现其他有效的 `g install`、`g use` 或 `voidint/g` 调用。

## Requirements

- Windows 的 Core CLI 清单必须包含 Go，安装命令为 `scoop install go`，目标系统限定为 Windows。
- Linux 与 macOS 的 Core CLI 清单必须包含 Go，安装命令为 `brew install go`，目标系统限定为 Linux 与 macOS。
- 删除 `Initialize-PackageManagers` 中安装 `voidint/g` 的逻辑；包管理器初始化只负责现有包管理器，不再引入 Go 版本管理器。
- 保持统一应用清单为三个平台 Go 安装方式的真源，不新增独立平台专用安装脚本。
- 更新受影响的安装流水线测试，使平台选择结果明确覆盖 Go。

## Acceptance Criteria

- [x] Windows `core-cli` 选择结果包含 `go`，其命令为 `scoop install go`。
- [x] Linux `core-cli` 选择结果包含 `go`，其命令为 `brew install go`。
- [x] macOS `core-cli` 选择结果包含 `go`，其命令为 `brew install go`。
- [x] `profile/installer/installApp.ps1` 不再检测、安装或提及 `voidint/g` 与 Go 版本管理器 `g`。
- [x] 仓库有效代码中不存在遗留的 `voidint/g` 或 `g` 版本管理器安装调用。
- [x] 相关 PowerShell 安装流水线测试、`pnpm qa` 与 `pnpm test:pwsh:all` 通过。

## Out of Scope

- 不引入新的 Go 多版本管理器。
- 不迁移普通 `go install`、`go env`、GOPROXY 或容器构建中的 Go 用法。
- 不处理 `archive/` 中历史资料或 Powerlevel10k 的 `goenv` 展示配置。
- 不改变 Scoop、Homebrew 本身的安装与镜像配置。
