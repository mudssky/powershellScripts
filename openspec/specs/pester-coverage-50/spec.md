## ADDED Requirements

### Requirement: Coverage target
系统 SHALL 让 Pester 测试套件达到至少 50% 的命令覆盖率。

#### Scenario: Coverage measurement
- **WHEN** 开发者运行文档规定的 `pnpm test:pwsh:coverage`
- **THEN** 报告的命令覆盖率不低于 50%

### Requirement: Coverage increases come from tests
系统 SHALL 通过新增或扩展测试来提升覆盖率，而不是通过把模块排除在 coverage 之外来达成。

#### Scenario: Coverage improvement approach
- **WHEN** 覆盖率向 50% 目标提升
- **THEN** 该提升应归因于对现有模块新增或扩展的测试
