# Shell 启动层级规范

## Scenario: login 与 interactive shell 共用基础环境

### 1. Scope / Trigger

- Trigger：修改 `shell/profile.d/**`、`shell/shared.d/**`、`shell/bash.d/**`、`shell/zsh.d/**`、`shell/deploy.sh` 或 Linux shell 部署与验证入口。
- Scope：Bash 3.2+ 与 Zsh；login profile、interactive rc、片段同步、marker 迁移与启动副作用边界。
- Design intent：基础环境只有一个实现，login 与 interactive 均可恢复工具链；alias、补全、prompt、网络探测和 TTY 行为只进入交互层。

### 2. Signatures

目录与部署目标：

```text
shell/profile.d/*.sh -> ~/.profile.d/*.sh
shell/shared.d/*.sh  -> ~/.bashrc.d/*.sh
shell/bash.d/*.sh    -> ~/.bashrc.d/*.sh
shell/zsh.d/*.zsh    -> ~/.bashrc.d/*.sh
```

受管入口：

```bash
bash shell/deploy.sh [--dry-run] [--shell bash|zsh] [--exclude <pattern>]
```

稳定 marker：

```text
# >>> powershell-scripts login env >>>
# <<< powershell-scripts login env <<<
# >>> powershell-scripts interactive env >>>
# <<< powershell-scripts interactive env <<<
```

### 3. Contracts

- `profile.d` 是 login 与 interactive 共用的安静、幂等基础环境层；只允许环境变量、幂等 PATH 变更与受控工具环境生成。
- `profile.d` 禁止 alias、补全、prompt、键位、交互函数、网络探测、后台进程和 stdout/stderr 输出；临时函数与变量必须在片段结束前清理。
- `shared.d` 只放 Bash/Zsh 共享交互行为；`bash.d` 与 `zsh.d` 只放对应 shell 专属交互行为。交互片段 source 时不得无条件输出。
- login loader 只 source `~/.profile.d/*.sh`。interactive loader 先 source `~/.profile.d/*.sh`，再仅在 `$-` 含 `i` 时 source `~/.bashrc.d/*.sh`；loader 不得 `return` 或 `exit`。
- 写入用户 profile/rc 的受管块必须保持可直接阅读：只保留简短职责注释、顺序加载循环和交互守卫；解析、迁移、备份等实现细节留在 `deploy.sh`，不得泄漏进用户配置。
- Bash login target 按 `.bash_profile`、`.bash_login`、`.profile` 选择第一个已存在文件；都不存在时创建 `.profile`。Zsh 固定使用 `.zprofile`。
- 每次 Bash 部署从非活动候选删除精确 login marker block；目标变化时完成迁移，不保留双重入口。marker 外用户内容逐行保留。
- 只有 start marker 时受管范围延伸到文件尾并由新 block 修复；孤立 end marker 视为用户内容，不删除。
- 内容变化前为既有非空文件创建 `YYYY-MM-DD_HH-MM-SS.bak`；内容相同不写入、不备份。dry-run 只报告，不创建目录、文件、链接或备份。
- `--exclude` 同时按源文件 basename 作用于 profile 与交互片段；模板 `*.example.sh`、`*.sample.sh` 永不部署。
- `profile.d/20-node.sh` 非交互执行 `fnm env`，交互执行 `fnm env --use-on-cd`；生成或 eval 失败均安静降级，且仅在成功后记录当前会话模式。
- Homebrew、package source、fnm、Bun 与 pnpm 环境分别由 `profile.d/05-package-sources.sh`、`10-homebrew.sh`、`20-node.sh` 单点拥有；不得在 loader 或交互片段复制。
- `shell/shared.d/env.local.sh` 保持交互层与 PowerShell 解析合同，不进入 profile 层，不读取、记录或输出真实内容。

片段归属清单：

| 层 | 文件 | 归属依据 |
|---|---|---|
| 基础环境 | `profile.d/05-package-sources.sh`、`10-homebrew.sh`、`20-node.sh` | 安静恢复 package source、Homebrew、fnm、Bun 与 pnpm；login 必需 |
| 共享交互 | `10-carapace.sh`、`90-atuin.sh`、`aliases.sh`、`modern-tools.sh`、`python.sh`、`tmux.sh`、`zellij.sh`、`bluetooth.sh`、`package-scripts.sh` | alias、补全或面向终端的交互命令 |
| 共享交互 | `fzf-helpers.sh`、`fzf-preview.sh`、`browser-debug.sh`、`claude-profile.sh`、`selfhosted.sh`、`vscode.sh`、`ai.sh` | 交互函数、fzf 生命周期或宿主工具命令 |
| 共享交互 | `env.local.sh`、`path.sh`、`java.sh`、`proxy.sh`、`git-delta.sh`、`zz-prompt.sh` | 私有配置桥接、交互 PATH/SDK hook、网络/TTY 探测或 prompt；不得提升到 login 层 |
| Bash 交互 | `bash.d/fzf-history.sh`、`bash.d/shc-completion.sh` | Readline 与 Bash completion 专属 |
| Zsh 交互 | `zsh.d/00-compinit.zsh`、`10-network.zsh`、`20-shc-completion.zsh`、`30-bun-completion.zsh`、`95-zsh-autosuggestions.zsh`、`99-k8s.zsh`、`fzf-history.zsh`、`zzz-zsh-syntax-highlighting.zsh` | compinit、ZLE、Zsh completion 与插件专属 |

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| Bash 三个候选均不存在 | 创建 `~/.profile` 并写入 login block |
| `.bash_profile`、`.bash_login`、`.profile` 同时存在 | 只在 `.bash_profile` 保留 login block |
| 当前 target 从 `.profile` 变为 `.bash_profile` | 写入新 target，并从旧 target 精确删除受管块 |
| 只有 start marker | 替换从 start marker 到文件尾，恢复完整成对 marker |
| 只有 end marker | 保留该行，并另行写入完整 block |
| legacy rc 单行 loader 存在 | 删除旧 loader 段并写入成对 interactive block |
| 非交互 login | 加载 profile 层；fnm 无 `--use-on-cd`；无 alias、补全、prompt、代理探测 |
| interactive shell | 先加载 profile 层，再加载交互层；fnm 使用 `--use-on-cd` |
| `fnm env` 生成或 eval 失败 | 安静继续后续片段，不记录成功模式 |
| 重复部署或重复 source | loader、PATH 与成功初始化均不重复；无额外备份 |
| dry-run | 日志描述目录、同步、目标、迁移与备份动作；文件系统零变化 |

### 5. Good / Base / Bad Cases

- Good：`bash -lc` 经有效 login profile 加载 `~/.profile.d`，恢复 Homebrew、fnm、Node 与 pnpm，但没有 `pscripts` alias。
- Good：交互 Bash 经 rc block 重复 source `~/.profile.d` 后加载 `~/.bashrc.d`，获得 `--use-on-cd` 与交互命令，PATH 无重复。
- Base：`env.local.sh`、`path.sh`、`java.sh`、`ai.sh`、`proxy.sh` 保留在交互层；它们分别依赖本机私有配置、交互函数/hook 或网络/TTY 行为。
- Bad：login profile source 整个 `~/.bashrc.d`，或在 `deploy.sh` 内联复制 Homebrew/fnm 初始化。
- Bad：为旧 `shared.d/homebrew.sh`、`package-sources.sh`、`node.sh` 保留转发 shim。

### 6. Tests Required

- Vitest 行为测试覆盖双目录同步、模板排除、stale symlink、Bash profile 优先级与迁移、Zsh target、legacy rc loader、损坏 marker、用户内容保留、dry-run、备份与幂等。
- 使用 fake `fnm` 记录 argv：非交互 login 断言无 `--use-on-cd`，interactive Bash/Zsh 断言包含该参数；同时观察 Node/pnpm 可发现。
- profile 片段重复 source 后断言 PATH 无重复，且不遗留 package source 辅助函数。
- 非交互 login 断言不存在交互 alias/函数、补全、prompt 与代理自动探测。
- 保留 `tests/ProfileLocalShellEnv.Tests.ps1`，证明 PowerShell 继续解析既有 `env.local.sh` 合同。
- 语法门禁至少覆盖 `bash -n shell/deploy.sh`、Bash source smoke；环境提供 Zsh 时补充 Zsh source smoke。

### 7. Wrong vs Correct

#### Wrong

```bash
# login profile 直接加载所有交互片段，并复制工具初始化。
for rc in "$HOME/.bashrc.d/"*.sh; do source "$rc"; done
eval "$(fnm env)"
```

#### Correct

```bash
# login 与 interactive shell 共用的基础环境，按文件名顺序加载。
for config in "$HOME/.profile.d/"*.sh; do
    [ -r "$config" ] && . "$config"
done
unset config
```

理由：启动入口只负责编排目录，环境实现集中在 `profile.d`，从而让 login 与 interactive 行为一致，又不把交互副作用带入非交互进程。
