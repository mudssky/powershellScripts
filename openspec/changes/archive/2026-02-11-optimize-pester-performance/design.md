## Context

Current `pnpm test` runs `pwsh -Command "Invoke-Pester -Configuration ( ./PesterConfiguration.ps1 )"`, which loads the PowerShell profile and enables coverage for all modules. Two tests (`install.Tests.ps1` and `test.Tests.ps1`) call expensive system queries that dominate runtime.

## Goals / Non-Goals

**Goals:**
- Provide a fast local test mode with no profile load and no coverage.
- Keep CI/full mode unchanged in behavior and reporting.
- Reduce test runtime by mocking or isolating slow environment queries.

**Non-Goals:**
- Changing production module behavior for users.
- Redesigning the overall test suite structure beyond performance improvements.

## Decisions

- **Introduce two Pester modes (fast/full)**: Add separate pnpm scripts (e.g., `test:fast` and `test:full`). Fast mode uses `pwsh -NoProfile` and disables code coverage. Full mode preserves current defaults. This isolates expensive profile load and coverage overhead from daily local runs.
- **Configurable PesterConfiguration**: Make coverage and other expensive toggles conditional via environment variables (e.g., `PWSH_TEST_MODE=fast`), so the same config file supports both modes.
- **Mock slow system calls in tests**: Use Pester `Mock` for `Get-Module -ListAvailable` and `Get-Command` in the targeted tests. This keeps semantics while removing filesystem/Path scanning costs.

## Risks / Trade-offs

- **Fast mode could hide issues that only appear with profile loading** → Keep dedicated profile tests in full mode and enforce full mode in CI.
- **Mocks may drift from real behavior** → Limit mocks to slow calls and add a small integration test subset in full mode.
- **Dual modes add complexity** → Document scripts clearly and keep defaults simple (`pnpm test` stays full).
