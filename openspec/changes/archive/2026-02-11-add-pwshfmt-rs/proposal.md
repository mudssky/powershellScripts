## Why

当前 `projects/clis/pwshfmt-rs` 代码属于探索版实现，虽然验证了 Rust 快速链路方向可行，但结构集中、扩展成本高。鉴于该项目尚无外部下游依赖，本次决定采用“清空旧实现并重新开发”的方式，一次性建立长期可维护的 CLI、配置、错误诊断与测试体系。

## What Changes

- 清理 `projects/clis/pwshfmt-rs` 现有实现代码，并基于新架构重新开发。
- 重新定义 `pwshfmt-rs` 的命令行接口与内部模块边界（CLI、配置、发现、执行、格式化、汇总、错误）。
- 引入 `clap` 构建可扩展命令行模型。
- 引入 `figment + serde + toml` 提供配置文件能力与分层覆盖规则（CLI > ENV > 配置文件 > 默认值）。
- 引入 `walkdir + globset` 实现路径遍历与模式匹配。
- 引入 `miette` 统一错误建模与诊断输出。
- 将关键行为验证迁移为集成测试（`projects/clis/pwshfmt-rs/tests/`）。
- 更新文档，发布新的 CLI、配置与错误输出契约。
- **BREAKING**：旧版参数细节、日志文本格式与内部实现均不再兼容，统一以新版契约为准。

## Capabilities

### New Capabilities
- `pwshfmt-rs`: 定义重新开发后的 Rust PowerShell 格式化工具能力，包括命令行模型、配置系统、文件发现、casing 修复、fallback 策略与错误诊断契约。

### Modified Capabilities
- (none)

## Impact

- 受影响代码：`projects/clis/pwshfmt-rs/src/**`、`projects/clis/pwshfmt-rs/tests/**`。
- 受影响依赖：`clap`、`figment`、`serde`、`toml`、`walkdir`、`globset`、`miette`（及测试辅助依赖）。
- 受影响文档：`projects/clis/pwshfmt-rs/README.md` 与仓库根文档相关章节。
- 实施方式：从零重建，不沿用旧实现代码。
