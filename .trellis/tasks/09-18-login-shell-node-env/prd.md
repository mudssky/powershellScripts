# 登录 shell 缺少 Node 环境

## Goal

让非交互登录 shell（ssh 执行命令、cron、`bash -lc`）也能正常使用 fnm 管理的 Node 工具链，并查清 `deploy.sh` 已有的 `ensure_login_profile` 受管块为何未在本机落地。

## 现状（已实测）

| 场景 | 读取的配置 | PATH 中 fnm | node / npm / pnpm |
| --- | --- | --- | --- |
| 交互式 shell | `~/.bashrc` → `~/.bashrc.d/node.sh` | 有 | ✅ v22.16.0 |
| 非交互登录 shell | `~/.profile` | **0 处** | ❌ 全部找不到 |

复现：

```bash
env -i HOME="$HOME" USER="$USER" SHELL=/bin/bash /bin/bash -lc 'command -v node || echo 找不到'
```

关键事实：

- `shell/deploy.sh` 中已实现 `ensure_login_profile()`，会在登录 profile 写入 `>>> powershell-scripts login env >>>` 受管块，内含 Homebrew 恢复与 `eval "$(fnm env)"`（注释明确说明是「为非交互登录 shell（bash -lc、ssh、cron）恢复 Homebrew 与 fnm」）。
- 但本机 `~/.profile` 中**没有**该受管块，`~/.bash_profile` / `~/.bash_login` / `~/.zprofile` 均不存在。
- 受管块内的 fnm 初始化不带 `--use-on-cd`（注释说明为有意设计），即登录 shell 不按 `.nvmrc` 自动切版本，只用 default 别名。

## 需要查清的问题

1. **为何未落地**：`ensure_login_profile` 是否需要显式参数/子命令才触发？是否曾执行失败？还是本机部署时用了跳过该步骤的路径？
2. **写入目标是否正确**：本机只有 `~/.profile`。该函数选择目标 profile 的逻辑是什么，在缺少 `~/.bash_profile` 时行为如何？
3. **与 `~/.bashrc` 的关系**：受管块落地后，交互式 shell 会同时经过 profile 与 bashrc 两条路径初始化 fnm，需确认不会重复前置 PATH 或互相覆盖。
4. **`--use-on-cd` 的取舍**：登录 shell 不自动切版本是否会影响 ssh 远程执行项目脚本（例如远程 `pnpm build` 时拿到 default 版本而非项目 `.nvmrc` 版本）。

## Requirements

- 非交互登录 shell 中 `node`、`npm`、`pnpm` 可用。
- 方案由 `shell/deploy.sh` 统一维护，不手工编辑 `~/.profile`（该文件不在版本控制内）。
- 幂等：重复部署不产生重复 PATH 条目或重复块。
- 不破坏交互式 shell 现有行为，尤其不得在 fnm 的 multishell 目录之前前置任何具体版本目录（参见提交 `1cd81c38`）。

## Acceptance Criteria

- [ ] 查明 `ensure_login_profile` 未落地的原因并记录。
- [ ] `env -i ... bash -lc 'node -v'` 能输出版本号。
- [ ] 重复执行部署后，`~/.profile` 中受管块只有一份，PATH 无重复条目。
- [ ] 交互式 shell 的 `fnm use` 与 `.nvmrc` 自动切换仍然正常。
- [ ] 明确并记录登录 shell 是否需要 `--use-on-cd`，给出结论依据。

## 背景

本任务源于排查「`fnm use` 不生效」时的连带发现。根因（`node.sh` 把 `npm prefix -g` 的结果前置到 PATH，钉死 Node 版本）已由提交 `1cd81c38` 修复；`~/.bashrc` 中 Pi 写入的 PATH 前置也已在本机改为追加。

需要澄清的是：Pi 那行写在 `~/.bashrc` 中，而非交互登录 shell 并不读取 `.bashrc`，因此它**并未**覆盖本任务所说的 profile 缺口——两者是独立的问题。
