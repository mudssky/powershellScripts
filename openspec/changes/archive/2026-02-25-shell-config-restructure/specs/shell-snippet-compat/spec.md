## ADDED Requirements

### Requirement: zoxide 动态 shell 检测

`aliases.sh` 中的 zoxide 初始化 SHALL 根据当前运行的 shell 动态选择初始化命令。

#### Scenario: 在 Zsh 中加载 aliases.sh

- **WHEN** 在 Zsh 环境下 source `aliases.sh`
- **THEN** SHALL 执行 `zoxide init zsh` 而非 `zoxide init bash`

#### Scenario: 在 Bash 中加载 aliases.sh

- **WHEN** 在 Bash 环境下 source `aliases.sh`
- **THEN** SHALL 执行 `zoxide init bash`

#### Scenario: zoxide 未安装

- **WHEN** 系统未安装 zoxide
- **THEN** SHALL 跳过 zoxide 初始化，不产生错误

### Requirement: ls 别名跨平台兼容

`aliases.sh` 中的 `ls` 相关别名 SHALL 在 macOS（BSD ls）和 Linux（GNU ls）下均能正常工作。

#### Scenario: macOS 下无 eza 时的 ls 别名

- **WHEN** 在 macOS 上且未安装 eza
- **THEN** `ll` 别名 SHALL 使用 `-G` 标志（BSD ls 的颜色选项）而非 `--color=auto`
- **THEN** `la` 和 `l` 别名 SHALL 同样使用 `-G` 标志

#### Scenario: Linux 下无 eza 时的 ls 别名

- **WHEN** 在 Linux 上且未安装 eza
- **THEN** `ll`、`la`、`l` 别名 SHALL 使用 `--color=auto` 标志

#### Scenario: 安装了 eza 时

- **WHEN** 系统安装了 eza（无论 macOS 或 Linux）
- **THEN** `ll` 和 `tree` 别名 SHALL 使用 eza 命令，绕过 BSD/GNU ls 差异

### Requirement: proxy 连通性检测跨 shell 兼容

`proxy.sh` 中的代理端口连通性检测 SHALL 在 Bash 和 Zsh 下均能正常工作。

#### Scenario: 在 Zsh 中检测代理端口

- **WHEN** 在 Zsh 环境下执行 `proxy on`
- **THEN** SHALL 使用 `nc -z` 或 `curl --connect-timeout` 检测端口连通性，而非 Bash 专属的 `/dev/tcp`

#### Scenario: 在 Bash 中检测代理端口

- **WHEN** 在 Bash 环境下执行 `proxy on`
- **THEN** SHALL 正常检测端口连通性

#### Scenario: nc 和 curl 均不可用

- **WHEN** 系统既没有 `nc` 也没有 `curl`
- **THEN** SHALL 跳过连通性检测，仅设置代理环境变量，不产生错误

### Requirement: fzf-history Zsh 版本

SHALL 提供 fzf 历史搜索的 Zsh 原生实现，功能与 Bash 版本对等。

#### Scenario: Zsh 下 fzf-history 快捷键绑定

- **WHEN** 在 Zsh 环境下加载 `fzf-history.zsh`
- **THEN** SHALL 绑定 `Alt+h` 快捷键触发 fzf 历史搜索

#### Scenario: fzf-history Enter 模式

- **WHEN** 用户在 fzf 历史搜索中按 Enter
- **THEN** SHALL 将选中命令放入命令行但不执行

#### Scenario: fzf-history Ctrl-E 模式

- **WHEN** 用户在 fzf 历史搜索中按 Ctrl-E
- **THEN** SHALL 立即执行选中命令

#### Scenario: fzf-history Ctrl-Y 模式

- **WHEN** 用户在 fzf 历史搜索中按 Ctrl-Y
- **THEN** SHALL 将选中命令复制到剪贴板（支持 pbcopy/wl-copy/xclip/xsel）

#### Scenario: fzf 未安装

- **WHEN** 系统未安装 fzf
- **THEN** SHALL 跳过整个 fzf-history 初始化，不产生错误
