# Linux brew 工具链 PATH 一致性：持久化 shellenv 并让 ProfileTools 自解析

## Goal

消除新装 Linux 机器上 Homebrew 工具（fnm/uv/fzf/starship 等）对登录 shell 与安装流水线子进程不可见的问题。2026-09-09 ser8（Ubuntu 26.04）新机安装时暴露：`05 core-cli` 成功后，`07 profile-tools` 仍报"缺少 fnm/uv"，`99 verify` 把已装工具判为 Fail。

## Root Causes

1. **shellenv 不落盘**：`linux/01installHomeBrew.sh` 只在进程内 `eval "$(brew shellenv)"`（`find_linuxbrew`/`load_linuxbrew_environment`），Homebrew 官方安装器在 NONINTERACTIVE 模式下也不修改用户 profile；`04` 部署的 bash/zsh 片段与 `~/.bashrc.d/` 均无 brew 内容。结果：新机器登录 shell 与任何子进程都看不到 `/home/linuxbrew/.linuxbrew/bin`。
2. **ProfileTools 依赖继承 PATH**：`scripts/pwsh/install/ProfileTools.psm1` 的 `Invoke-ProfileToolsInstall` 用裸 `Get-Command fnm`/`Get-Command uv`/`Get-Command corepack` 判定可用性；而 `05 core-cli`（`LinuxInstall.psm1`）走 `Initialize-LinuxBrewEnvironment` 在进程内主动加载 shellenv。两者判定标准不一致，编排器子进程（`pwsh -NoProfile`）继承什么 PATH 全凭运气。

## Requirements

- 流水线负责持久化：在 Stage 0/04 的合适叶子（倾向 `01installHomeBrew.sh` 安装成功后）把 `eval "$(brew shellenv)"` 写入 `~/.profile`（bash 登录路径；zsh 对应 `~/.zprofile`），遵守仓库既有约定：写前带时间戳 `.bak` 备份、幂等（已存在则跳过）、支持 `--dry-run`、尊重 `--network-mode` 事务语义不受影响。
- `ProfileTools.psm1` 不再裸依赖继承 PATH：fnm/uv/corepack 等来自 brew 的命令，判定与调用前先 `Initialize-LinuxBrewEnvironment`（或等价机制），与 `05 core-cli` 行为对齐。
- 不破坏 Windows/macOS 路径；`Initialize-LinuxBrewEnvironment` 在非 brew 环境的安全降级行为保持不变。

## Acceptance Criteria

- [ ] 全新 Ubuntu（无 brew PATH 的登录 shell）跑完 Stage 0/1 后，新登录 shell `command -v fnm uv starship` 全部命中 `/home/linuxbrew/.linuxbrew/bin/*`。
- [ ] 在 PATH 不含 brew 的父进程下执行 `pwsh ./install.ps1 -Preset Core -Step profile-tools`，node-runtime/pnpm/nbstripout 不再因 PATH 误报 Blocked。
- [ ] 重复执行安装/verify 不产生重复 shellenv 行；`.bak` 备份按约定生成。
- [ ] `pnpm qa` 与 `pnpm test:pwsh:all` 通过。

## Notes

- ser8 现场已临时补救：`~/.profile` 手工追加 shellenv（2026-09-09_03-12-03.bak 备份）；本任务落地后可移除该手工痕迹并回归验证。
- 关联任务：`09-09-fix-verify-containskey-noninteractive`（verify 部分已修复，本任务解决其暴露的 PATH 误报根源）。
