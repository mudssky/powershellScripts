## Why

当前 `format:pwsh` 在部分文件上存在明显长尾耗时，尤其是 casing correction 相关规则会拖慢本地反馈。我们需要一个 Rust 实现的高性能格式化辅助工具，在保证可回退兼容链路的前提下提升日常开发效率。

## What Changes

- 新增 `pwshfmt-rs` 命令行工具，用于 PowerShell 文件发现、变更判定、并发处理与 casing 修复。
- 支持 `--check` / `--write` 两种模式，分别用于 CI 校验与本地自动修复。
- 支持 `--git-changed` 快速路径，仅处理 Git 改动的 `.ps1` / `.psm1` / `.psd1`。
- 提供 `--strict-fallback` 回退机制：无法安全修复时回退到现有 `pwsh` 严格链路。
- 在文档中补充 `pwshfmt-rs` 的使用方式、边界与迁移建议。

## Capabilities

### New Capabilities
- `pwshfmt-rs`: 定义 Rust 版 PowerShell 格式化辅助工具的输入输出行为、性能目标与回退策略。

### Modified Capabilities
- (none)

## Impact

- 新增 Rust 工具目录（`projects/clis/pwshfmt-rs`）及相关构建脚本。
- PowerShell 格式化流程可新增一条 Rust 快速链路（不破坏现有脚本能力）。
- 文档与开发者命令说明需要同步更新。
