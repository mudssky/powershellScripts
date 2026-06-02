# Pwshfmt Rust Package Guidelines

> 适用于 `projects/clis/pwshfmt-rs` 的 Rust PowerShell formatter CLI。

## Scope

* 包路径：`projects/clis/pwshfmt-rs`
* Workspace 包名：`pwshfmt-rs`
* 主要入口：`projects/clis/pwshfmt-rs/package.json`

## Pre-Development Checklist

* Rust 逻辑改动应复用包内 Cargo 脚本入口，不要从根目录重复拼接 Cargo 命令。
* 格式化行为变更要同时检查 discovery、processor、formatter 与 CLI 配置路径。
* 该包是 Rust CLI，不套用 TypeScript/Node CLI 的测试约定。

## Package Script Contract

* `typecheck:fast` 运行 `cargo check`。
* `check` 运行 `cargo clippy --all-targets`。
* `test:fast` 运行 Cargo 测试并保持单线程，避免测试夹具互相影响。
* `qa` 串联类型检查、Clippy 与测试。

## Quality Check

* 配置或文档改动可只做可发现性检查。
* Rust 逻辑改动时运行 `pnpm --filter pwshfmt-rs qa`。
