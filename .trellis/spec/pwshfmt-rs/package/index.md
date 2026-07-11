# Pwshfmt Rust Package Guidelines

> 适用于 `projects/clis/pwshfmt-rs` 的 Rust PowerShell formatter CLI。

## Scope

* 包路径：`projects/clis/pwshfmt-rs`
* Workspace 包名：`pwshfmt-rs`
* 主要入口：`projects/clis/pwshfmt-rs/package.json`

## Pre-Development Checklist

* Rust 逻辑改动应复用包内 Cargo 脚本入口，不要从根目录重复拼接 Cargo 命令。
* 格式化行为变更要同时检查 discovery、processor、formatter 与 CLI 配置路径。
* 路径排除使用可重复的 `--exclude-path <path>` 和配置字段 `exclude_paths`；不得在 discovery 中硬编码仓库目录名。
* 该包是 Rust CLI，不套用 TypeScript/Node CLI 的测试约定。

## Package Script Contract

* `typecheck:fast` 运行 `cargo check`。
* `check` 运行 `cargo clippy --all-targets`。
* `test:fast` 运行 Cargo 测试并保持单线程，避免测试夹具互相影响。
* `qa` 串联类型检查、Clippy 与测试。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* Rust 逻辑改动时运行 `pnpm --filter pwshfmt-rs qa`。
* discovery 变更必须同时覆盖显式/递归路径和 Git changed 模式；排除目录应在 WalkDir 进入子树前剪枝。

## Exclusion Contract

* CLI、环境变量和 TOML 继续遵循 `CLI > ENV > config file > built-in defaults`；CLI 传入 `--exclude-path` 时覆盖配置文件列表。
* 相对排除路径以 CLI 工作目录为基准；文件等于排除路径或位于排除目录下时跳过。
* 根仓库通过 `pwshfmt-rs.toml` 设置 `exclude_paths = ["archive"]`，包本身的 built-in defaults 保持空列表，避免把个人仓库策略泄漏给通用 CLI。
