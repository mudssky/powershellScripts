## ADDED Requirements

### Requirement: Linux local tests SHALL run through a containerized entrypoint
The project SHALL provide a documented Linux-local Pester execution path based on a container runtime so that developers on Windows and macOS can run equivalent Linux checks without WSL dependency.

#### Scenario: Run Linux checks from Windows or macOS host
- **WHEN** a developer executes the documented Linux-local test command
- **THEN** tests run inside a Linux container with `pwsh` and Pester available

#### Scenario: Linux path is discoverable and reproducible
- **WHEN** a developer follows repository testing documentation
- **THEN** they can find a single canonical command path for Linux-local Pester runs

### Requirement: Host platform tests SHALL remain available for platform-specific behavior
The local workflow SHALL preserve host `pwsh` test execution to validate platform-specific behavior that cannot be represented by Linux containers.

#### Scenario: Windows-specific tests remain validated on Windows host
- **WHEN** a developer runs host-local tests on Windows
- **THEN** Windows-specific test behavior (including `windowsOnly` coverage) remains executable in the host workflow

#### Scenario: Host workflow coexists with Linux container workflow
- **WHEN** a developer needs broad local confidence
- **THEN** they can run both host and Linux-container checks as part of one documented workflow

### Requirement: Parallel host and container runs SHALL avoid artifact collisions
The local workflow SHALL define an isolation strategy for concurrent host/container test runs to prevent shared artifact overwrites.

#### Scenario: Concurrent runs produce isolated outputs
- **WHEN** host and Linux-container tests execute concurrently
- **THEN** test result artifacts do not overwrite each other

#### Scenario: Isolation method is explicitly documented
- **WHEN** developers review local testing guidance
- **THEN** they can identify approved isolation methods (for example separate work directories or distinct output paths)

### Requirement: Fast and full validation modes SHALL be documented for local use
The local cross-platform workflow SHALL define a fast feedback mode and a full verification mode aligned with existing Pester run semantics.

#### Scenario: Fast mode prioritizes local feedback speed
- **WHEN** a developer invokes the documented fast mode
- **THEN** they run a reduced-cost test path intended for quick iteration

#### Scenario: Full mode is available before push or review
- **WHEN** a developer invokes the documented full mode
- **THEN** they run a comprehensive local verification path before relying on CI
