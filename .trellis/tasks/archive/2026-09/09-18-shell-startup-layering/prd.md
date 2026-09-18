# Shell 启动层级与 Profile 治理

## Goal

先为 `shell/` 制定可执行的启动层级规范，再让 `shell/deploy.sh` 按规范分别管理登录环境与交互配置：login profile 能正确、幂等地恢复 Homebrew、fnm 与 Node 工具链，交互 shell 保留 alias、函数、补全和 `--use-on-cd`，整个目录不再依赖混合职责或重复实现。

## Confirmed Facts

### 当前行为

- 交互式 Bash 通过 `~/.bashrc` → `~/.bashrc.d/*.sh` 加载 `shell/shared.d` 与 shell 专属片段。
- `shell/deploy.sh:545-555` 在维护 rc loader 后会无条件调用 `ensure_login_profile`；当前实现没有额外参数或子命令门禁。
- `ensure_login_profile` 对 Bash 固定写 `~/.profile`，对 Zsh 写 `~/.zprofile`，并用 marker 整段替换、内容变化前备份、内容相同时跳过写入。
- 当前登录受管块内联复制了 Homebrew 恢复逻辑，再执行不带 `--use-on-cd` 的 `eval "$(fnm env)"`。
- `shell/shared.d/homebrew.sh` 已有另一份 Homebrew 环境恢复实现；两处候选路径需要人工保持一致，已经形成双事实来源。
- `shell/shared.d` 还包含 alias、函数、补全、fzf 与交互工具初始化，不能直接整体 source 到非交互 login profile。

### 已确认设计方向

- 采用独立 `shell/profile.d/*.sh` 登录环境层，不继续扩展 `deploy.sh` 内联环境块。
- profile 层只承载安静、幂等、可被非交互 login shell source 的环境初始化；交互行为继续归 `shared.d` / `bash.d` / `zsh.d`。
- 规范必须先落到 `.trellis/spec/`，实现随后按规范迁移；不能先改代码再反向补文档。
- `shell/` 当前存在混合职责：`node.sh` 同时包含 fnm/Bun/pnpm 环境、交互函数与 alias；`path.sh` 同时定义可输出函数并在 source 时修改 PATH；`ai.sh`、`java.sh`、`package-sources.sh` 等也需要按新层级逐项判定。

### Bash 启动文件约束

- Bash 登录 shell 按 `~/.bash_profile`、`~/.bash_login`、`~/.profile` 的优先级只读取第一个存在的文件。当前固定写 `~/.profile`，在更高优先级文件存在时可能完全不生效。
- 当前测试覆盖“空 HOME 创建 `~/.profile`”、marker 替换、幂等、dry-run 与 Zsh `~/.zprofile`，但未覆盖 Bash 三个候选文件的优先级、旧受管块迁移或失效目标清理。
- Bash 官方规则中，显式 login shell（如 `bash -lc`）读取 login profile；sshd 启动的非交互 Bash 通常读取 `~/.bashrc` 而不是 login profile；普通 cron 两者都不自动读取。profile 方案应只承诺真正读取 profile 的入口，SSH 与 cron 需分别按实际启动机制处理。

### 已观察问题

| 场景 | 读取的配置 | PATH 中 fnm | node / npm / pnpm |
| --- | --- | --- | --- |
| 交互式 shell | `~/.bashrc` → `~/.bashrc.d/node.sh` | 有 | 可用 |
| `bash -lc` | 当前有效 login profile | 无 | 不可用 |

当前本机 `~/.profile` 没有受管块。由于现版本 `deploy.sh` 会无条件调用 `ensure_login_profile`，代码层面已排除“需要显式开关才触发”；仍需在实施阶段结合引入提交 `fde35788` 与本机部署时间确认是尚未用新版本重新部署，还是后续被其它流程覆盖。

## Requirements

1. 先在 `.trellis/spec/shell-shared/package/` 建立覆盖整个 `shell/` 的启动层级规范，明确 `profile.d`、`shared.d`、`bash.d`、`zsh.d` 的职责、兼容语法、允许副作用、加载顺序和测试合同。
2. `shell/deploy.sh` 必须分别管理登录环境与交互 rc，两类片段边界清晰；login profile 不直接 source 整个 `~/.bashrc.d`。
3. `shell/profile.d` 只允许登录场景需要的安静、幂等环境初始化，不注册 alias、补全、prompt、交互函数或自动网络探测。
4. Bash 必须写入实际会被读取的候选文件：优先复用已存在的 `~/.bash_profile`、`~/.bash_login`、`~/.profile`；三者都不存在时创建 `~/.profile`。Zsh 使用 `~/.zprofile`。
5. 交互式 rc 必须加载同一套基础环境后再加载交互片段，Homebrew、fnm、PATH 等基础逻辑不得在 profile 与 rc 中复制。
6. 所有受管 loader 必须有稳定 marker，支持整段升级、目标迁移、重复部署幂等和内容变化前的可读时间戳 `.bak`。
7. dry-run 必须准确报告目标 profile、目录同步、写入/替换/迁移动作，且不修改文件。
8. 不破坏交互式 fnm 行为，尤其不能在 fnm multishell 目录之前固定前置某个 Node 版本目录。
9. 审计 `shell/` 全目录并记录每个片段的层级归属；发现职责混合时按规范拆分，不为形式统一重写无关业务逻辑。

## Acceptance Criteria

- [ ] `.trellis/spec/shell-shared/package/` 中存在可执行的 Shell 启动层级规范，并由 package index 链接。
- [ ] `shell/` 每个片段都有明确层级归属；混合登录环境与交互行为的文件完成拆分或记录保留依据。
- [ ] 空 HOME 下 Bash 部署创建 `~/.profile`，`bash -lc 'node -v'` 可执行。
- [ ] 分别存在 `~/.bash_profile`、`~/.bash_login`、`~/.profile` 时，受管入口写入 Bash 实际读取的最高优先级文件。
- [ ] Zsh 部署写入 `~/.zprofile`，`zsh -lc` 可恢复 Homebrew 与 fnm 环境。
- [ ] 非 login 的交互 Bash/Zsh 也通过基础环境层获得 Homebrew、fnm 与必要 PATH，再加载交互片段。
- [ ] 重复部署后受管 loader 只有一份，PATH 无重复条目，内容未变化时不生成备份。
- [ ] 目标 profile 变化时，旧目标中的历史受管块完成迁移或清理，不留下双重加载路径。
- [ ] 非交互 login shell 不注册 alias、补全、prompt、fzf 命令或代理自动探测。
- [ ] 交互式 shell 的 `fnm use` 与 `.nvmrc` 自动切换保持正常。
- [ ] dry-run、损坏 marker、文件不存在、用户自有内容位于 marker 前后等场景有行为测试。
- [ ] 明确记录非交互 login shell 不使用 `--use-on-cd`、交互 shell 使用该选项的依据。
- [ ] 查明本机受管块未落地的原因并记录。

## Out of Scope

- 让 login profile 直接 source 整个 `~/.bashrc.d`。
- 修改用户 marker 之外的自有 profile 内容。
- 仅靠 profile 保证普通 cron 或所有 SSH 远程命令自动获得 Node 环境。
- 改变 fnm 默认版本或项目 `.nvmrc` 内容。
- 重构各片段内部与启动层无关的命令行为、alias 设计或领域逻辑。


## Background

本任务源于排查“`fnm use` 不生效”时的连带发现。根因（`node.sh` 把 `npm prefix -g` 的结果前置到 PATH，钉死 Node 版本）已由提交 `1cd81c38` 修复；`~/.bashrc` 中 Pi 写入的 PATH 前置也已在本机改为追加。

Pi 那行位于 `~/.bashrc`，不会解决不读取 `.bashrc` 的 login profile 缺口，两者是独立问题。
