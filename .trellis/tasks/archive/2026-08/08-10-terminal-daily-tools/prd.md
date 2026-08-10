# 补齐高频 Zsh 与终端工具

## Goal

在现有 macOS Zsh、Carapace、Atuin、Starship 与现代 CLI 基础上，补齐日常输入反馈、Git diff 阅读和命令帮助体验；Zsh 插件与 Dust 聚焦 macOS，Delta 覆盖 Windows/macOS/Linux，Tealdeer 覆盖 macOS 与 Linux/WSL，避免仅在当前机器手工安装后失去可复现性。

## Background

- 当前主要平台是 macOS，默认登录 Shell 为 Zsh 5.9；Bash 兼容不是本任务关注重点。
- `zsh-autosuggestions` 只提供行内历史建议，不替代 Atuin 的 `Ctrl+r` 历史搜索。
- `zsh-syntax-highlighting` 只提供命令行语法着色，不替代 Carapace 参数补全，并要求在其它 Zsh widget 注册完成后靠后加载。
- `shell/shared.d/git-delta.sh` 已有 TTY 与命令存在守卫；macOS/Linux 安装后即可启用现有交互式 Git pager 配置。Windows 安装 Delta 二进制，但不写全局 Git pager。
- `tealdeer` 安装后提供 `tldr` 命令，不替代系统 `man`。原生 Windows 虽有 Scoop 包和 Windows 页面，但当前 Windows 主要作为 WSL 宿主，本任务不纳入 Windows 安装层级，避免重复缓存和低收益 Core 工具。
- `shell/shared.d/aliases.sh` 已在 `dust` 存在时把交互式 `du` 映射为 `dust`；当前 Homebrew 清单仍使用已失效的 `brew install du-dust` 且标记 `skipInstall: true`，而 Homebrew 当前 formula 为 `dust` 1.2.4。
- Homebrew 插件 formula 不提供同名可执行命令；现有 macOS 检测层已支持回退到 `brew list`，实现需复用并锁定该合同，不能把插件文件伪装成 CLI。

## Requirements

1. 安装并配置 `zsh-autosuggestions`，在新 Zsh 会话中提供行内建议，同时保持 Atuin 仅接管 `Ctrl+r`、原生 Up 行为不变。
2. 安装并配置 `zsh-syntax-highlighting`，在 Carapace、Atuin及其它 widget 初始化之后加载；工具缺失或 source 失败时安静降级，不阻断基础 Zsh。
3. 安装 `git-delta`：Windows/macOS 进入 Core，Linux 进入 Full `terminal-extras`；macOS/Linux 复用 `shell/shared.d/git-delta.sh` 的 TTY 守卫，Windows 不写全局 pager。
4. 安装 `tealdeer`：macOS 进入 Core，Linux/WSL 进入 Full `terminal-extras`；统一以 `tldr` 作为安装检测命令，不覆盖 `man`，原生 Windows 不安装。
5. 修复 Dust 的 Homebrew formula 为 `dust`，仅恢复为 macOS Core，并保留现有条件 alias 降级。
6. 复用 `profile/installer/apps-config.json`、三平台既有安装叶子、`shell/deploy.sh` 与数字前缀加载顺序；不直接覆盖完整 `~/.zshrc`。
7. 为插件 formula 保持明确、可验证、可复用的安装状态检测合同；不得因没有同名可执行文件而每次重复安装。
8. 更新三平台安装规范/文档、Shell 配置说明、安装选择测试和真实 Zsh 行为测试。

## Acceptance Criteria

- [ ] 新 Zsh 会话同时存在 Autosuggestions、Syntax Highlighting、Carapace 与 Atuin；`Ctrl+r` 仍绑定 Atuin，Up 未被 Atuin 接管。
- [ ] Autosuggestions 与 Syntax Highlighting 的实际 source 顺序满足后者最后加载，重复 source 不产生重复 hook 或错误。
- [ ] 工具未安装或插件文件不可用时，Zsh 启动无错误且其它片段继续加载。
- [ ] macOS/Linux 真实 TTY 中 `git diff` 使用 Delta，非 TTY 中不设置 Delta pager；Windows Core 安装并能直接调用 `delta`，但不写全局 pager。
- [ ] macOS 与 Linux/WSL 能通过 `tldr --version` 验证 Tealdeer；Windows Core/Full 都不选择 Tealdeer。macOS 能通过 `dust --version` 验证 Dust，且 `du` 仅在 Dust 存在时使用现有 alias。
- [ ] macOS Core 预览包含四项新增工具及 Dust 修复；Windows Core 新增 Delta；Linux Core 排除 Delta/Tealdeer，而 Full `terminal-extras` 包含二者。
- [ ] `profile/installer/apps-config.json` 通过 schema 校验，Homebrew 插件 formula 可被只读验证识别，`brew install du-dust` 不再存在。
- [ ] Zsh 语法、Shell 行为测试、三平台安装测试、`pnpm test:bash`、`pnpm test:pwsh:all` 与 `pnpm qa` 通过；Docker 不可用时按仓库规则执行本机覆盖率门禁并说明 Linux 覆盖依赖 CI/WSL。

## Out of Scope

- 不配置 Bash 插件或解决 macOS Bash 3.2 的交互体验。
- 不启用 `fzf-tab`，不改变 Carapace 补全 UI。
- 不引入 `mise`、`direnv`、`procs`、`lazydocker` 等其它候选工具。
- 不启用 Atuin 账号、云同步或自托管同步。
- 不替换 Starship、现有 fzf、zoxide、Yazi、Lazygit 配置。
- 不为 Windows PowerShell 新增 Delta pager 环境变量或修改 Git 全局配置。
- 不在原生 Windows 安装 Tealdeer；Windows 上的命令速查优先在 WSL 内使用 Linux Tealdeer。

## Decision

- Zsh 插件与 Dust：仅 macOS Core。
- Delta：Windows/macOS Core；Linux Full `terminal-extras`。
- Tealdeer：macOS Core；Linux/WSL Full `terminal-extras`；原生 Windows 不安装。
