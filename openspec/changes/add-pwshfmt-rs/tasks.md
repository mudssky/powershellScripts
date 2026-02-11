## 0. 清理旧实现

- [x] 0.1 删除 `projects/clis/pwshfmt-rs/src/main.rs` 旧实现并保留最小可编译入口
- [x] 0.2 清理与旧实现强绑定的测试与文档描述

## 1. 重建项目骨架

- [x] 1.1 建立 `src/lib.rs` 与模块文件（`cli.rs`、`config.rs`、`discovery.rs`、`processor.rs`、`formatter/mod.rs`、`summary.rs`、`error.rs`）
- [x] 1.2 在 `Cargo.toml` 增加 `clap`、`figment`、`serde`、`toml`、`walkdir`、`globset`、`miette` 及测试依赖
- [x] 1.3 将 `src/main.rs` 收敛为薄入口（解析参数 -> 调用应用层 -> 映射退出码）

## 2. CLI 与配置

- [x] 2.1 使用 `clap derive` 设计可扩展命令接口
- [x] 2.2 定义执行模式冲突/必填约束与帮助信息
- [x] 2.3 实现 `Config` 默认值与 `pwshfmt-rs.toml` 解析
- [x] 2.4 实现配置覆盖顺序：默认值 -> 配置文件 -> ENV -> CLI

## 3. 核心流程重建

- [x] 3.1 重建 Git changed 与路径模式文件发现逻辑（`walkdir + globset`）
- [x] 3.2 重建 check/write 执行流程与 no-op 写回优化
- [x] 3.3 重建 strict fallback 流程与结果汇总
- [x] 3.4 使用 `miette` 统一错误类型与诊断输出

## 4. 测试与文档

- [x] 4.1 新增集成测试覆盖 CLI、配置、check/write、fallback、文件发现
- [x] 4.2 补充必要单元测试（格式化状态机、关键纯函数）
- [x] 4.3 更新 `projects/clis/pwshfmt-rs/README.md`（新 CLI、配置、错误输出）
- [x] 4.4 运行 `cargo test --manifest-path projects/clis/pwshfmt-rs/Cargo.toml`
- [x] 4.5 运行 `pnpm qa:pwsh` 并修复出现的问题
