## ADDED Requirements

### Requirement: 跨平台 shell 配置目录结构
项目 SHALL 在仓库根目录下维护一个 `shell/` 顶级目录，作为所有跨平台 shell 配置片段的唯一存放位置。

#### Scenario: 目录结构布局
- **WHEN** 查看 `shell/` 目录
- **THEN** SHALL 包含以下子目录和文件：
  - `shell/shared.d/` — 存放 Bash/Zsh 通用的 `.sh` 片段
  - `shell/bash.d/` — 存放 Bash 专属的 `.sh` 片段
  - `shell/zsh.d/` — 存放 Zsh 专属的 `.zsh` 片段
  - `shell/deploy.sh` — 统一部署脚本

### Requirement: shared.d 包含所有通用片段
`shell/shared.d/` SHALL 包含所有 Bash/Zsh 通用的配置片段，这些片段 MUST 在两种 shell 下均能正常 source。

#### Scenario: 通用片段列表
- **WHEN** 列出 `shell/shared.d/` 目录内容
- **THEN** SHALL 包含以下文件（从原 `linux/.bashrc.d/` 迁移）：`aliases.sh`、`proxy.sh`、`path.sh`、`node.sh`、`python.sh`、`java.sh`、`ai.sh`、`env.local.sh`

### Requirement: bash.d 包含 Bash 专属片段
`shell/bash.d/` SHALL 包含仅在 Bash 下使用的配置片段。

#### Scenario: Bash 专属片段
- **WHEN** 列出 `shell/bash.d/` 目录内容
- **THEN** SHALL 包含 `fzf-history.sh`（原 `linux/.bashrc.d/fzf-history.sh`，使用 `bind -x` 和 `READLINE_LINE`）

### Requirement: zsh.d 包含 Zsh 专属片段
`shell/zsh.d/` SHALL 包含仅在 Zsh 下使用的配置片段。

#### Scenario: Zsh 专属片段
- **WHEN** 列出 `shell/zsh.d/` 目录内容
- **THEN** SHALL 包含 `fzf-history.zsh`（fzf 历史搜索的 Zsh 版本，使用 `zle` widget 和 `BUFFER` 变量）

### Requirement: 原 linux 目录清理
迁移完成后，`linux/` 目录 SHALL 不再包含 `.bashrc.d/` 子目录和 `01manage-shell-snippet.sh` 文件。

#### Scenario: linux 目录仅保留平台专属内容
- **WHEN** 列出 `linux/` 目录内容
- **THEN** SHALL 不包含 `.bashrc.d/` 目录
- **THEN** SHALL 不包含 `01manage-shell-snippet.sh` 文件
- **THEN** SHALL 保留 `02installHomeBrew.sh`、`ubuntu/`、`wsl2/`、`arch/` 等平台专属内容
