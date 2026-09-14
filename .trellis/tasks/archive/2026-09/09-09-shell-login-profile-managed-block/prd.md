# shell 层接管登录 profile 环境恢复：受管块替代 01 直写

## Goal

把登录 profile（bash `~/.profile`、zsh `~/.zprofile`）的 brew/fnm 环境恢复职责从 `linux/01installHomeBrew.sh` 移交到 `shell/` 共享层（04 链路的 `shell/deploy.sh` 受管块），使登录非交互 shell（`bash -lc`、ssh 单命令、cron）也能看到 brew/node/pnpm，且交互路径行为不变。

## 背景（ser8 实测 + 分层评审结论，2026-09-09）

- 提交 `849533f2` 让 01 直写 `.profile`（追加到末尾），存在三个问题：
  1. **越界**：spec 约定 `04 只调用 shell/deploy.sh`，登录 profile 归 shell 层治理；
  2. **覆盖不全**：非交互登录 shell 的 `.bashrc` 早退，`.bashrc.d/` 片段（含 `node.sh` 的 fnm env）不加载，fnm/node/pnpm 不可见——brew 可见但 node 系不可见（ser8 verify 误报实例）；
  3. **顺序隐患**：追加位置在 `.bashrc` source 之后，语义混乱。
- 交互 shell 不受影响：`shell/shared.d/homebrew.sh` 自探测已知 prefix 且按字母序先于 `node.sh` 加载。

## Requirements

1. **撤销 01 直写**：移除 `01installHomeBrew.sh` 的 `persist_linuxbrew_shellenv` 及调用、usage 行；同步调整 `scripts/bash/tests/linux-install-pipeline.test.ts` 中对应用例（删除或改造为断言"01 不再写 profile"）。
2. **deploy.sh 新增登录 profile 受管块**：
   - bash 写 `~/.profile`，zsh 写 `~/.zprofile`（按 04 现有的 shell 分派约定）；
   - 受管段用 marker 注释包裹（`# >>> powershell-scripts login env >>>` / `# <<<`），内容自包含且顺序正确：先 brew（探测已知 prefix，PATH 去重守卫，风格同 `shell/shared.d/homebrew.sh`），后 fnm（`command -v` 守卫 + `eval "$(fnm env)"`，不用 `--use-on-cd`）；
   - 幂等：marker 已存在则整段原位替换；写前时间戳 `.bak` 备份；支持 `--dry-run`；
   - 与 deploy.sh 现有参数、注释风格、错误处理一致；被测脚本所在目录 `shell/` 的既有测试文件跟随扩展。
3. **交互路径零改动**：`shell/shared.d/` 各片段（homebrew.sh、node.sh 等）不改。
4. **spec 校准**：`.trellis/spec/infra/linux-install-pipeline.md` 三层职责描述更新为"登录 profile 受管块由 04/shell deploy 负责（brew+fnm），01 不写 profile"；Vitest 清单补受管块用例。
5. `linux/INSTALL.md` 如有 01 职责描述需同步。

## Acceptance Criteria

- [x] 空 HOME fixture 下跑 04 链路后，`bash -lc 'command -v brew node pnpm'` 全部可见（implement 端到端用例 + ser8 实机回归均通过）。
- [x] 重复执行 deploy 受管块写入：无重复段、无多余 `.bak`、marker 外内容不丢失（check 8 组边界实测 + ser8 幂等复跑）。
- [x] marker 外用户内容不受影响；`.bak` 时间戳格式符合仓库约定。
- [x] `pnpm qa`（162/0 + vitest 114）与 `pnpm test:pwsh:all` 通过（host 945/0，linux 943/0，exit 0）。
- [x] ser8 回归：移除手工 shellenv 痕迹后重跑 04，登录非交互 shell `bash -lc 'command -v brew node pnpm'` 全部可见，幂等复跑仅 1 个 marker 块。

## Notes

- ser8 现状：`.profile` 顶部有手工 brew shellenv（备份 `~/.profile.2026-09-09_08-48-43.bak`），任务落地后由主会话做 ser8 回归清理。
- 关联：`09-09-fix-linux-brew-path-consistency`（已归档）引入的 01 直写即本任务的撤销对象；交互片段层（shared.d）设计保持不变。
