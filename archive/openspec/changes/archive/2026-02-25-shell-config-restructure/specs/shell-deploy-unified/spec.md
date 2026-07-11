## ADDED Requirements

### Requirement: 统一部署脚本

`shell/deploy.sh` SHALL 作为 Linux 和 macOS 的统一 shell 配置部署工具，支持将 `shell/` 下的配置片段 symlink 到 `~/.bashrc.d/`。

#### Scenario: 部署 shared.d 片段

- **WHEN** 执行 `shell/deploy.sh`
- **THEN** SHALL 将 `shell/shared.d/*.sh` 中的所有文件 symlink 到 `~/.bashrc.d/`

#### Scenario: Bash 用户部署

- **WHEN** 用户默认 shell 为 Bash 时执行 `shell/deploy.sh`
- **THEN** SHALL 额外将 `shell/bash.d/*.sh` symlink 到 `~/.bashrc.d/`
- **THEN** SHALL 确保 `~/.bashrc` 包含 `.bashrc.d/` loader 代码

#### Scenario: Zsh 用户部署

- **WHEN** 用户默认 shell 为 Zsh 时执行 `shell/deploy.sh`
- **THEN** SHALL 额外将 `shell/zsh.d/*.zsh`（重命名为 `.sh` 后缀）symlink 到 `~/.bashrc.d/`
- **THEN** SHALL 确保 `~/.zshrc` 包含 `.bashrc.d/` loader 代码

#### Scenario: 手动指定 shell

- **WHEN** 执行 `shell/deploy.sh --shell zsh`
- **THEN** SHALL 按 Zsh 模式部署，忽略 `$SHELL` 环境变量的检测结果

### Requirement: 旧 symlink 清理

`deploy.sh` SHALL 在部署前清理 `~/.bashrc.d/` 中指向已不存在路径的旧 symlink。

#### Scenario: 清理失效 symlink

- **WHEN** `~/.bashrc.d/` 中存在指向 `linux/.bashrc.d/` 的旧 symlink（目标路径已不存在）
- **THEN** SHALL 自动删除这些失效 symlink 并输出提示信息

### Requirement: dry-run 模式

`deploy.sh` SHALL 支持 `--dry-run` 参数，仅显示将要执行的操作而不实际修改文件系统。

#### Scenario: dry-run 输出

- **WHEN** 执行 `shell/deploy.sh --dry-run`
- **THEN** SHALL 显示将要创建的 symlink 列表和将要修改的 rc 文件，但不执行任何写操作

### Requirement: exclude 模式

`deploy.sh` SHALL 支持 `--exclude <pattern>` 参数，排除匹配的文件不进行部署。

#### Scenario: 排除特定文件

- **WHEN** 执行 `shell/deploy.sh --exclude proxy.sh`
- **THEN** SHALL 跳过 `proxy.sh` 的 symlink 创建

### Requirement: macOS 安装脚本集成

`macos/01install.sh` SHALL 在安装流程中调用 `shell/deploy.sh` 来部署 shell 配置片段。

#### Scenario: macOS 全新安装

- **WHEN** 在全新 macOS 环境执行 `macos/01install.sh`
- **THEN** SHALL 在安装 Homebrew 和配置 `.zshrc` 之后，调用 `shell/deploy.sh` 部署 `.bashrc.d/` 片段
- **THEN** `~/.bashrc.d/` SHALL 包含所有 `shared.d/` 和 `zsh.d/` 的片段

### Requirement: macOS .zshrc 去重

`macos/config/.zshrc` SHALL 不包含与 `shell/shared.d/` 片段重复的初始化逻辑。

#### Scenario: fnm 初始化去重

- **WHEN** 查看 `macos/config/.zshrc` 内容
- **THEN** SHALL 不包含 `fnm` 初始化代码（已由 `node.sh` 片段提供）

#### Scenario: 保留 macOS 专属配置

- **WHEN** 查看 `macos/config/.zshrc` 内容
- **THEN** SHALL 保留 Homebrew PATH、pyenv 初始化、Hammerspoon 配置、Ollama 配置等 macOS 专属内容
- **THEN** SHALL 保留 `.bashrc.d/` loader 代码
