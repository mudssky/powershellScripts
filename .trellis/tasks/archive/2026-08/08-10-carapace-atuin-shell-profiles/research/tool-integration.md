# Carapace 与 Atuin Shell 接入调研

## 官方资料

- Carapace Setup: https://carapace-sh.github.io/carapace-bin/setup.html
- Carapace 源文档: https://github.com/carapace-sh/carapace-bin/blob/master/docs/src/setup.md
- Atuin `init` reference: https://docs.atuin.sh/main/reference/init/
- Atuin shell integration: https://docs.atuin.sh/latest/guide/shell-integration/
- Atuin installation: https://docs.atuin.sh/latest/guide/installation/

## 已确认命令

| 工具 | Bash | Zsh | PowerShell |
| --- | --- | --- | --- |
| Carapace | `source <(carapace _carapace)` | 先完成 `compinit`，再 `source <(carapace _carapace)` | `carapace _carapace \| Out-String \| Invoke-Expression` |
| Atuin | `eval "$(atuin init bash --disable-up-arrow)"` | `eval "$(atuin init zsh --disable-up-arrow)"` | `atuin init powershell --disable-up-arrow \| Out-String \| Invoke-Expression` |

## 行为约束

- Carapace PowerShell 配置要求 PSReadLine Tab 使用 `MenuComplete`；`Complete` 会把补全样式的 ANSI 转义显示成原始字符。
- Zsh 必须先执行 `compinit`。仓库已有 `shell/zsh.d/00-compinit.zsh`，新增配置不得重复初始化 completion system。
- Atuin `init` 安装命令记录 hooks 与键位；`--disable-up-arrow` 只保留 `Ctrl+r` 等 Atuin 入口，不覆盖原生 Up 键。
- `ATUIN_NOBIND` 会禁用全部自动键位，本任务不采用。
- Bash 的 Atuin shell integration 依赖 preexec 机制；重复 source 需要仓库级会话守卫，避免重复 hooks。

## 仓库适配结论

- Bash/Zsh 使用共享片段，但用数字前缀明确 Zsh 顺序：Carapace 位于 `00-compinit` 之后、命令专属 completion 之前；Atuin靠近末尾加载。
- PowerShell Full 模式同步初始化两项工具，确保首个命令和首次 Tab 即可使用；生成脚本通过现有 `Invoke-WithFileCache` 缓存并 dot-source。
- PowerShell OnIdle 的 Tab 设置根据 Carapace 初始化状态选择 `MenuComplete` 或原有 `Complete`，避免 OnIdle 把 Carapace 要求覆盖回去。
- 安装统一进入 `profile/installer/apps-config.json`：Windows/macOS 标记 Core，Linux 标记 `terminal-extras`；不新增工具专属平台脚本。命令不存在时 profile 仅 Verbose 跳过。

## 安装包与体积

- Homebrew 当前包名：`carapace` 1.7.3、`atuin` 18.19.0；macOS bottle 无运行时依赖。
- Scoop 当前包名：Main bucket 的 `atuin`，Extras bucket 的 `carapace-bin`；Windows Core 安装链需确保 Extras bucket 已添加。
- Apple Silicon 官方 release 包：Carapace 下载约 13.5 MiB、解压后约 65.9 MB；Atuin 下载约 10.1 MiB、解压后约 23.4 MB；合计落盘约 89.3 MB，不含 Atuin 后续历史数据库增长。
- 决策：Windows/macOS 桌面环境进入 Core；Linux Core 面向服务器保持精简，两项工具进入 Full `terminal-extras`。

## 安装资料

- Homebrew Carapace: https://formulae.brew.sh/formula/carapace
- Homebrew Atuin: https://formulae.brew.sh/formula/atuin
- Scoop Extras Carapace: https://github.com/ScoopInstaller/Extras/blob/master/bucket/carapace-bin.json
- Scoop Main Atuin: https://github.com/ScoopInstaller/Main/blob/master/bucket/atuin.json
