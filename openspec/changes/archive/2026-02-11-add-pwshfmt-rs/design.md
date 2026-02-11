## Context

`pwshfmt-rs` 首版已经证明 Rust 快速链路在 PowerShell 格式化场景下具备性能价值，但当前实现集中在单个 `main.rs`，CLI 解析、配置处理、文件发现、格式化状态机、并发执行与测试耦合较重。继续在该实现上增量重构的收益有限，因此本变更选择 clean-slate rewrite：清空旧实现并按目标架构重新开发。

## Goals / Non-Goals

**Goals:**
- 以“重建”方式交付可维护的 `pwshfmt-rs` 实现。
- 建立清晰模块边界：`cli`、`config`、`discovery`、`processor`、`formatter`、`summary`、`error`。
- 使用 `clap` 提供可扩展命令行模型。
- 使用 `figment + serde + toml` 提供分层配置与默认值。
- 使用 `walkdir + globset` 实现可靠文件发现。
- 使用 `miette` 输出统一错误诊断。
- 以集成测试覆盖关键行为路径。

**Non-Goals:**
- 不在本次覆盖 `Invoke-Formatter` 的全部规则能力。
- 不引入常驻进程、远程配置中心或复杂插件系统。
- 不追求与旧探索版 CLI 文本输出逐字兼容。

## Decisions

- **Decision 1: 采用 clean-slate rewrite 而非增量改造**
  - 方案：删除旧实现代码，基于新模块结构重建。
  - 原因：旧实现结构性耦合高，增量改造成本与风险更大。
  - 备选：在旧代码上逐步拆分，短期改动小但长期维护复杂。

- **Decision 2: 使用模块化 crate 结构**
  - 方案：`main.rs` 作为薄入口，`lib.rs` 组织业务模块。
  - 原因：清晰边界、便于测试与后续扩展。
  - 备选：继续单文件，无法解决复杂度问题。

- **Decision 3: CLI 使用 `clap derive`**
  - 方案：通过 `Parser/Subcommand` 描述命令接口与约束。
  - 原因：降低参数解析分支复杂度，提升帮助文本一致性。
  - 备选：手写解析，维护成本高。

- **Decision 4: 配置使用 `figment + serde + toml`**
  - 方案：采用“默认值 -> 配置文件 -> ENV -> CLI”的覆盖顺序。
  - 原因：满足“无配置可运行”与“多来源覆盖”两类需求。
  - 备选：仅 CLI 参数，不足以支撑后续扩展。

- **Decision 5: 文件发现使用 `walkdir + globset`**
  - 方案：路径遍历由 `walkdir` 提供，glob 匹配由 `globset` 提供。
  - 原因：减少自研匹配逻辑，降低 bug 风险。
  - 备选：保留自研匹配逻辑，维护成本高。

- **Decision 6: 错误治理使用 `miette`**
  - 方案：定义领域错误并统一映射为 `miette` 诊断。
  - 原因：输出一致、上下文完整，便于定位问题。
  - 备选：字符串拼接错误，语义分散。

- **Decision 7: 测试策略为“单测 + 集成测试”**
  - 方案：核心纯函数单测，流程行为集成测试。
  - 原因：覆盖跨模块协作路径，减少实现耦合。
  - 备选：仅单元测试，难覆盖真实链路。

## Risks / Trade-offs

- **重建期间功能回归风险** → 先定义契约，再按测试逐步回填能力。
- **新 CLI 学习成本** → README 提供迁移示例与等价命令说明。
- **依赖增加导致编译时长上升** → 用可维护性与可扩展性收益抵消。

## Migration Plan

1. 清理旧实现并建立新目录结构与模块骨架。
2. 搭建 `clap` CLI 与 `figment` 配置加载。
3. 实现文件发现、执行编排、casing 修复与 fallback。
4. 接入 `miette` 错误诊断并统一退出码契约。
5. 补全集成测试、更新 README，并执行完整验证。

## Open Questions

- CLI 采用扁平参数还是子命令（`check` / `write`）作为默认交互？
- 配置文件默认路径仅当前目录，还是支持 XDG 搜索链？
- 环境变量前缀是否统一为 `PWSHFMT_RS_`？
