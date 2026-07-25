# Mac Mini Rust 编译缓存迁外接盘

## Goal

把本机（Mac Mini）Rust 编译/下载缓存从系统盘迁到外接数据盘，并通过可提交的 local env example 让「有哪些本机私有变量」可被发现；真实密钥与机器路径只留在被 gitignore 的 local 文件中。

## Background

- 本机内置盘容量有限（约 228G），Rust 的 `~/.cargo` / `target` / sccache 体积增长快。
- 外接盘 `/Volumes/Data` 已有约 1.1T 空闲，且仓库已有把本机重数据放到该盘的惯例（如 `HERMES_HOME`、docker_data、rclone cache）。
- Profile 仅在探测到 `sccache` 时设置 `RUSTC_WRAPPER`，不配置缓存目录。
- 本机私有环境已集中在 `shell/shared.d/env.local.sh`（同步到 `~/.bashrc.d/env.local.sh`），但缺少可提交 example，导致本地变量清单不可见。

## Requirements

1. 在外接盘创建稳定的 Rust 缓存目录（至少 sccache；可选 cargo home）。
2. 本机 `env.local.sh` 配置：
   - `SCCACHE_DIR` → 外接盘
   - `RUSTC_WRAPPER=sccache`
   - `CARGO_HOME` → 外接盘（registry/git 下载缓存）
   - 外接盘未挂载时不得静默写坏路径；应可安全跳过或给出可理解行为
3. 安装并启用 `sccache`（brew 或等价路径可用）。
4. 仓库提供 **可提交** 的 local env example，至少覆盖：
   - 当前本机已在用的私有变量名（密钥用占位符）
   - 本次新增的 Rust 缓存变量
   - 简短注释：文件如何加载、真实文件名、不可提交
5. `shell/shared.d/path.sh` 在设置了 `CARGO_HOME` 时，应把 `$CARGO_HOME/bin` 加入 PATH，而不是写死 `$HOME/.cargo/bin`。
6. PowerShell profile 会话应能读到与 shell 相同的关键 local export（至少 `CARGO_HOME` / `SCCACHE_DIR` / `RUSTC_WRAPPER`），避免「zsh 有缓存、pwsh 无缓存」。
7. 不提交真实 API key；修改 `env.local.sh` 前按项目规则做时间戳 `.bak` 备份。
8. 不强制迁移/删除现有 `~/.cargo` 本体；若启用新 `CARGO_HOME`，可 rsync 复制后由新路径生效，旧目录保留待确认清理。

## Non-Goals

- 不把全局 `CARGO_TARGET_DIR` 指到单一目录（多项目会互相污染）。
- 不强制迁移 `RUSTUP_HOME`（可在 example 中作为可选注释）。
- 不做跨机器自动发现外接盘挂载点；Mac Mini 使用约定路径 `/Volumes/Data/...`。
- 不改 CI / 其他主机的默认 cargo 行为。

## Acceptance Criteria

- [x] 存在可提交 example：`shell/shared.d/env.local.example.sh`（或等价命名），列出已知本机私有变量与 Rust 缓存变量，密钥为占位符。
- [x] 本机 `shell/shared.d/env.local.sh` 含 Rust 缓存相关 export，且已做 `.bak` 备份。
- [x] `/Volumes/Data/cache/sccache` 与 `/Volumes/Data/cache/cargo` 目录存在。
- [x] `sccache` 可在 PATH 中执行；新 shell 中 `RUSTC_WRAPPER` / `SCCACHE_DIR` / `CARGO_HOME` 指向预期值。
- [x] `path.sh` 使用 `${CARGO_HOME:-$HOME/.cargo}/bin`。
- [x] pwsh 加载 profile 后同样能看到上述关键 Rust env（不必解析 alias 行）。
- [x] 真实密钥未进入可提交文件；`git check-ignore` 仍忽略 `env.local.sh`。
- [x] 改动涉及仓库代码时执行 `pnpm qa` 并通过。

## Notes

- 轻量任务：PRD-only，无独立 design/implement。
- 加载链：`env.local.sh` → `shell/deploy.sh` 同步到 `~/.bashrc.d/` → zsh/bash source；pwsh 由 profile 读取同一源文件的 export 行。
