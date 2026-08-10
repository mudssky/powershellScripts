# 技术设计

## 1. 边界与选择

本任务的 Zsh 运行时增强仅覆盖 macOS Core：安装并 source `zsh-autosuggestions`、`zsh-syntax-highlighting`，同时修复并安装 `dust`。`git-delta` 扩展到三平台：Windows/macOS Core，Linux Full `terminal-extras`。`tealdeer` 只进入 macOS Core 与 Linux/WSL Full，不进入原生 Windows。

运行时继续使用现有两层：

- `profile/installer/apps-config.json`：Scoop/Homebrew 安装与只读验证真源。
- `shell/zsh.d/`：macOS Zsh 专属插件 source；`shell/shared.d/git-delta.sh` 与 `aliases.sh` 继续承载 macOS/Linux Shell 的 Delta/Dust 条件行为。Windows 只安装 Delta，不新增 PowerShell pager 配置。

不新增工具专属安装脚本，不覆盖完整 `~/.zshrc`，不写全局 Git `core.pager`。

## 2. Zsh 加载顺序

相关片段的目标顺序：

```mermaid
flowchart LR
    A[00-compinit] --> B[10-carapace]
    B --> C[90-atuin]
    C --> D[95-zsh-autosuggestions]
    D --> E[99-k8s]
    E --> F[zz-prompt]
    F --> G[zzz-zsh-syntax-highlighting]
```

新增：

- `shell/zsh.d/95-zsh-autosuggestions.zsh`
- `shell/zsh.d/zzz-zsh-syntax-highlighting.zsh`

Autosuggestions 放在 Atuin 后：Atuin 先注册 `atuin-search` 等 widget，Autosuggestions 再观察并包装当前 widget 集合；Atuin 仍只通过既有 `--disable-up-arrow` 接管 `Ctrl+r`，不改变 Up。

Syntax Highlighting 使用 `zzz-`，保证位于 Carapace、Atuin、Autosuggestions、Kubernetes completion 和 Starship prompt 之后。它只负责输入缓冲区着色，不修改补全来源。

## 3. 插件发现与降级

两个片段都只在交互式 Zsh 中运行，并使用独立会话标记防止重复 source。插件路径按以下顺序查找：

1. `POWERSHELL_SCRIPTS_HOMEBREW_PREFIX` 测试/显式覆盖。
2. 已存在的 `HOMEBREW_PREFIX`。
3. Apple Silicon 默认 `/opt/homebrew`。
4. Intel Homebrew 默认 `/usr/local`。

对应文件：

- `share/zsh-autosuggestions/zsh-autosuggestions.zsh`
- `share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh`

不在 Shell 启动时执行 `brew --prefix`，避免为两个静态文件增加外部进程。仅当目标文件可读且 `source` 成功时设置完成标记；缺失或 source 失败时安静返回，其它片段继续加载。

## 4. 安装清单

平台选择矩阵：

| 平台 | 包与命令 | 预设/分组 | 检测方式 |
| --- | --- | --- | --- |
| macOS | `zsh-autosuggestions`、`zsh-syntax-highlighting` | `core + cli` | 不设 `cliName`/`filterCli`；现有 macOS 检测回退到 `brew list` formula |
| macOS | Homebrew `git-delta` | `core + cli` | `cliName: delta`、`filterCli: true` |
| macOS | Homebrew `tealdeer` | `core + cli` | `cliName: tldr`、`filterCli: true` |
| macOS | Homebrew `dust` | `core + cli` | `cliName: dust`、`filterCli: true`；删除 `skipInstall` 与 `du-dust` |
| Windows | Scoop Main `delta` | `core + cli` | `cliName: delta` |
| Linux | Homebrew `git-delta` | `cli + terminal-extras` | `cliName: delta`、`filterCli: true` |
| Linux | Homebrew `tealdeer` | `cli + terminal-extras` | `cliName: tldr`、`filterCli: true` |

macOS 与 Linux 对 Homebrew Delta/Tealdeer 使用 OS 专属条目，避免同一条目同时带 `core` 和 `terminal-extras`。Windows 新增官方 Scoop Main `delta` 条目；现有未分层的 Scoop `tldr` 保持不被 Core/Full 选择，本任务不在原生 Windows 安装 Tealdeer。插件 formula 不提供同名可执行文件，但共享检测层已支持 Homebrew formula；不新增泛化字段或第二套检测函数，Pester 锁定“无同名命令但 `brew list` 包含 formula”合同。

## 5. 运行时行为

### 5.1 Autosuggestions 与 Atuin

- `Ctrl+r`：保持 `atuin-search`。
- Up：保持 Atuin 初始化前的原生绑定。
- Autosuggestions：提供灰色行内建议及其自身接受 widget，不替代 Atuin SQLite 历史。
- 重复加载：不会重复注册插件。

### 5.2 Syntax Highlighting 与 Carapace

- Carapace 继续生成候选和参数补全。
- Syntax Highlighting 只观察当前编辑缓冲区并着色；最后加载，避免后续 widget 覆盖其 hook。
- 插件失败不影响 Carapace、Atuin 或 prompt。

### 5.3 Delta、TLDR、Dust

- Delta 在 macOS/Linux 复用 `shell/shared.d/git-delta.sh`：仅真实 stdout TTY 且 `delta` 存在时设置 `GIT_PAGER=delta`；管道、Agent 和非交互输出不注入 ANSI pager。Windows 只安装可执行文件，不修改 PowerShell 环境或 Git 全局配置。
- Tealdeer 在 macOS 与 Linux/WSL 只提供 `tldr`；不定义 `man` alias。macOS 本机安装后更新 page cache，并执行一次真实页面查询 smoke。原生 Windows 不安装，避免与 WSL 重复缓存。
- Dust 复用 `aliases.sh`：存在时 `du` 指向 `dust`，不存在时继续 `du -h`。

## 6. 测试设计

### 6.1 Shell 行为测试

扩展现有 Vitest fixture，使用临时 Homebrew prefix 和最小插件脚本观察运行态：

- Bash/非交互式 Zsh 不 source 插件。
- 交互式 Zsh 按 Atuin → Autosuggestions → Syntax Highlighting 顺序形成运行标记。
- 重复 source 每个插件只执行一次。
- 插件缺失和 source 返回非零时无 stderr、后续插件仍执行。
- 实际 widget 状态保持 `Ctrl+r = atuin-search`，Up 绑定前后相同；Autosuggestions/Syntax Highlighting 标记函数或 widget 存在。
- 部署后的文件名字典序保证 Syntax Highlighting 最后。

### 6.2 安装与验证测试

扩展 Pester：

- macOS Core 预览包含五项，字体/Full 选择不受影响。
- Windows Core 精确集合由 12 项更新为 13 项，新增 Scoop `delta`；Core/Full 均不选择 Tealdeer。
- Linux Core 排除 Delta/Tealdeer，Linux Full `terminal-extras` 包含二者。
- 三平台只读验证结果与安装选择使用同一清单名称。
- Homebrew formula 在没有同名命令时仍通过 `brew list` 识别两个 Zsh 插件。
- Dust 命令为 `brew install dust`，不再 `skipInstall`；Delta/Tealdeer/Dust 使用目标可执行命令检测。

### 6.3 本机 smoke

实施批准后执行 Homebrew 安装、`shell/deploy.sh --shell zsh`，再从新交互式 Zsh 观察：

- 两个真实插件函数/widget 已注册。
- Atuin `Ctrl+r` 和 Up 绑定符合要求。
- Carapace、Atuin 与 Starship 仍初始化。
- `delta --version`、`tldr --version`、`dust --version` 成功。
- `tldr` 页面查询成功。
- TTY 设置 `GIT_PAGER=delta`，非 TTY 不设置。

## 7. 文档与规范

更新：

- `docs/install/README.md`：Windows/macOS/Linux 的工具分层与验证入口。
- `.agents/skills/repo-ops/references/shell-profile-integration.md`：Zsh 插件加载顺序、幂等和降级合同。
- `.trellis/spec/infra/macos-install-pipeline.md`：macOS Core 清单和 formula 检测合同。
- `.trellis/spec/infra/windows-install-pipeline.md`：Windows Core 精确集合更新为 13 项。
- `.trellis/spec/infra/linux-install-pipeline.md`：Linux Full `terminal-extras` 增加 Delta/Tealdeer，Core 保持排除。

不新增不存在的平台 README 或 Shell README，不修改 PowerShell Profile 文档，也不为 Windows 新增 Delta pager 配置。

## 8. 风险与回滚

- Widget 顺序风险：Atuin 后加载 Autosuggestions、所有 widget 后加载 Syntax Highlighting；真实 Zsh smoke 检查绑定与函数。
- 启动性能风险：只做文件存在检查与 source，不执行 `brew` 子进程；性能 smoke 对比新 Zsh 启动。
- 非交互输出污染：macOS/Linux Delta 保留现有 TTY 守卫；Windows 不写 Git 全局配置或 PowerShell 环境变量。
- formula 误判：插件用 Homebrew formula 检测，不用虚构 CLI；Pester 覆盖。
- 平台分层漂移：Windows Core 精确集合、Linux Core/Full 排除包含关系和三平台只读验证共同锁定。
- 回滚：删除两个 Zsh 片段并重新部署；移除三平台 Delta、macOS/Linux Tealdeer 条目或标签，恢复 Dust 旧状态。回滚仓库配置不会自动卸载已安装的软件。