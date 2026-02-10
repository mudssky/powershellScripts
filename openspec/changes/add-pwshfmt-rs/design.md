## Context

现有 PowerShell 格式化流程基于 `Invoke-Formatter`，在默认规则下部分文件会出现高延迟，导致本地迭代效率下降。我们已验证 `PSUseCorrectCasing` 是主要长尾来源之一，因此拟引入 Rust 工具分担高频路径（文件发现、并发处理、casing 修复），并保留严格回退以确保兼容性。

## Goals / Non-Goals

**Goals:**
- 提供 `pwshfmt-rs` 可执行工具，覆盖常用本地格式化场景。
- 显著降低空改动与少量改动场景下的总耗时。
- 保留严格回退路径，确保复杂场景不阻塞开发流程。

**Non-Goals:**
- 不在首版中完整替代 `Invoke-Formatter` 全规则行为。
- 不修改 PowerShell 业务脚本语义，仅处理格式与 casing 规范。
- 不在本次引入复杂守护进程或常驻服务。

## Decisions

- **Rust 负责快速路径，PowerShell 负责严格兜底**
  - 方案：`pwshfmt-rs` 优先执行，遇到无法安全处理的内容时按 `--strict-fallback` 调用现有 `pwsh` 严格链路。
  - 原因：兼顾性能收益与行为可靠性。
  - 备选：直接全面替换 `Invoke-Formatter`，风险过高，暂不采用。

- **先做可控子集：文件发现 + casing correction + no-op 写回**
  - 方案：首版只修正命令名和参数名大小写，且仅在内容变化时写回。
  - 原因：收益明确，边界清晰，便于测试与回归。
  - 备选：一次性覆盖所有格式规则，开发成本与回归成本过高。

- **CLI 形态优先**
  - 方案：提供 `--git-changed`、`--path`、`--recurse`、`--check`、`--write`、`--strict-fallback`。
  - 原因：可直接接入 npm/pwsh 任务与 CI，无需额外协议层。
  - 备选：作为库嵌入 Node/Pwsh，落地复杂度更高。

- **并发与跨平台兼容并重**
  - 方案：使用 `rayon` 并行处理文件，路径与进程调用均采用跨平台封装。
  - 原因：提高吞吐并降低平台差异问题。
  - 备选：单线程实现，虽然简单但性能收益有限。

## Risks / Trade-offs

- **动态调用与 alias 场景识别不完整** → 默认保守处理，无法判定时不改写或回退 strict。
- **跨平台命令字典差异** → 命令映射支持缓存与平台隔离，CI 上做多平台校验。
- **双链路维护成本上升** → 明确快/严两种模式职责，并以文档与测试约束边界。

## Migration Plan

1. 初始化 `pwshfmt-rs` 工具骨架并实现核心 CLI 参数。
2. 接入文件发现、Git 改动过滤、并发处理、check/write 模式。
3. 实现 casing correction 子集与 no-op 写回。
4. 加入 strict fallback 并在本地命令中提供可选入口。
5. 更新文档与示例命令，逐步引导团队使用。

## Open Questions

- 首版默认是否直接挂到 `format:pwsh`，还是先提供 `format:pwsh:rs` 试运行？
- casing 字典来源是运行时采样 `Get-Command` 还是预置快照优先？
- strict fallback 失败时是否允许“部分成功 + 汇总警告”而非整体失败？
