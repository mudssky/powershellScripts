### Requirement: Starship prompt 初始化

`shell/shared.d/zz-prompt.sh` SHALL 为 Bash 和 Zsh 提供 Starship prompt 初始化。

#### Scenario: Zsh 会话加载 Starship

- **WHEN** 用户在已安装 starship 的系统上启动 Zsh 会话，且 `~/.bashrc.d/` 片段已部署
- **THEN** Starship prompt 正确显示，替代默认 Zsh prompt

#### Scenario: Bash 会话加载 Starship

- **WHEN** 用户在已安装 starship 的系统上启动 Bash 会话，且 `~/.bashrc.d/` 片段已部署
- **THEN** Starship prompt 正确显示，替代默认 Bash prompt

### Requirement: Shell 类型自动检测

初始化脚本 SHALL 根据当前 shell 类型（`$ZSH_VERSION` 或 `$BASH_VERSION`）自动选择正确的 `starship init` 参数。

#### Scenario: Zsh 环境检测

- **WHEN** 脚本在 Zsh 中被 source
- **THEN** 执行 `eval "$(starship init zsh)"`

#### Scenario: Bash 环境检测

- **WHEN** 脚本在 Bash 中被 source
- **THEN** 执行 `eval "$(starship init bash)"`

### Requirement: 未安装时静默跳过

当 starship 未安装时，脚本 SHALL 静默退出，不输出任何错误或提示信息。

#### Scenario: Starship 未安装

- **WHEN** 系统未安装 starship（`command -v starship` 失败）
- **THEN** 脚本静默退出，shell 使用默认 prompt，无错误输出

### Requirement: 加载顺序保证

脚本文件名 SHALL 使用 `zz-` 前缀，确保在所有其他 `shared.d/` 片段之后加载。

#### Scenario: 片段加载顺序

- **WHEN** `~/.bashrc.d/` 下的片段按字母序加载
- **THEN** `zz-prompt.sh` 在 `aliases.sh`、`path.sh`、`proxy.sh` 等所有其他片段之后加载
