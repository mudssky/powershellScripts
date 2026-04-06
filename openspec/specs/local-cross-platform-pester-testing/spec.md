## ADDED Requirements

### Requirement: Linux local tests SHALL run through a containerized entrypoint

项目 SHALL 提供基于容器运行时的、文档化的 Linux 本地 Pester 执行入口，以便 Windows 和 macOS 开发者在不依赖 WSL 的情况下运行等价的 Linux 检查。

#### Scenario: Run Linux checks from Windows or macOS host

- **WHEN** 开发者执行文档规定的 Linux 本地测试命令
- **THEN** 测试会在具备 `pwsh` 与 Pester 的 Linux 容器内运行

#### Scenario: Linux path is discoverable and reproducible

- **WHEN** 开发者按照仓库测试文档操作
- **THEN** 他们能够找到唯一、规范的 Linux 本地 Pester 命令路径

### Requirement: Host platform tests SHALL remain available for platform-specific behavior

本地工作流 SHALL 保留 host `pwsh` 测试执行路径，用于验证 Linux 容器无法表达的平台特定行为。

#### Scenario: Windows-specific tests remain validated on Windows host

- **WHEN** 开发者在 Windows 上运行 host 本地测试
- **THEN** Windows 特定测试行为（包括 `windowsOnly` coverage）仍可在 host 工作流中执行

#### Scenario: Host workflow coexists with Linux container workflow

- **WHEN** 开发者需要更广泛的本地验证信心
- **THEN** 他们可以在同一套文档化工作流中同时运行 host 与 Linux 容器检查

#### Scenario: Host workflow remains the local coverage path

- **WHEN** 开发者运行文档规定的 `pnpm test:pwsh:coverage`
- **THEN** `pnpm test:pwsh:coverage` 仍是规范化的本地 coverage 入口，而 `pnpm test:pwsh:all` 继续提供 host assertions 与 Linux container full assertions 的跨平台工作流

### Requirement: Parallel host and container runs SHALL avoid artifact collisions

本地工作流 SHALL 定义并发 host / container 测试运行的隔离策略，以防止共享产物被相互覆盖。

#### Scenario: Concurrent runs produce isolated outputs

- **WHEN** host 与 Linux 容器测试并发执行
- **THEN** 测试结果产物不会相互覆盖

#### Scenario: Isolation method is explicitly documented

- **WHEN** 开发者查看本地测试指南
- **THEN** 他们能够识别被批准的隔离方式（例如独立工作目录或不同输出路径）

### Requirement: Fast and full validation modes SHALL be documented for local use

本地跨平台工作流 SHALL 为本地使用定义快速反馈模式和完整验证模式，并与现有 Pester 运行语义保持一致。

#### Scenario: Fast mode prioritizes local feedback speed

- **WHEN** 开发者调用文档规定的 fast 模式
- **THEN** 他们运行的是一条面向快速迭代、成本更低的测试路径

#### Scenario: Full mode is available before push or review

- **WHEN** 开发者调用文档规定的 full 模式
- **THEN** 他们会在依赖 CI 之前先运行一条完整的本地验证路径
