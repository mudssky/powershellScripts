## ADDED Requirements

### Requirement: Fast test mode
系统 SHALL 提供一个关闭 profile 加载和代码覆盖率的本地快速 Pester 模式。

#### Scenario: Fast mode execution
- **WHEN** 用户运行 fast 测试命令
- **THEN** Pester 会在不加载 profile 且关闭 coverage 的条件下执行

### Requirement: Full test mode remains default
系统 SHALL 在未选择 fast 模式时保留一条文档化的 host coverage-enabled 路径，并允许跨平台组合门禁以不含 coverage 的 host full assertions 路径执行。

#### Scenario: Default execution
- **WHEN** 用户运行文档规定的 host coverage 命令（`pnpm test:pwsh:coverage`，或兼容入口 `pnpm test:pwsh:full`）
- **THEN** Pester 仍以 coverage-enabled 方式执行 host full 测试

#### Scenario: Linux full assertions remain available
- **WHEN** 用户运行文档规定的 Linux 容器 full 测试命令
- **THEN** 即使出于兼容性原因将本地 coverage 责任委托给 host 工作流，该路径仍保留为 full assertions 入口

#### Scenario: Combined gate avoids host coverage cleanup cost
- **WHEN** 用户运行文档规定的 `pnpm test:pwsh:all`
- **THEN** host lane 使用不含 coverage 的 full assertions 路径，而 Linux container lane 继续提供 full assertions

### Requirement: Fast mode avoids expensive environment scans
系统 SHALL 在适用时通过 test doubles 避免 fast 模式下的高成本环境查询（例如模块发现和 PATH 扫描）。

#### Scenario: Fast mode uses mocks
- **WHEN** fast 模式启用且某个测试原本会调用模块发现或 PATH 扫描
- **THEN** 该测试应使用 mocks，而不是真实系统查询
