## Context

Coverage is currently 23.66% across 20 modules. Several modules either lack tests entirely or only cover nominal paths. External dependencies (filesystem, network, OS commands) make full coverage slow or flaky without mocks.

## Goals / Non-Goals

**Goals:**
- Reach at least 50% command coverage with stable, deterministic tests.
- Prioritize modules that provide frequently used utilities.
- Avoid expanding the test runtime substantially.

**Non-Goals:**
- Achieve 100% coverage.
- Test third-party tools or network services end-to-end.

## Decisions

- **Target modules first**: Focus new tests on `hardware.psm1`, `win.psm1`, `wrapper.psm1`, and deeper coverage for `install.psm1` and `functions.psm1`. These are currently under-tested and represent the largest coverage gap.
- **Mock external dependencies**: Use Pester mocks for OS detection, filesystem, and command invocation to cover logic without hitting real system state.
- **Incremental coverage tracking**: Add a coverage progress check (e.g., baseline + target in CI) to prevent regressions once 50% is reached.

## Risks / Trade-offs

- **Mocks may mask real integration issues** → Keep a small set of integration tests (tagged) to validate real-world behavior.
- **Coverage focus may bias toward easy-to-test code** → Track module-level coverage to ensure important modules improve first.
- **Additional tests increase maintenance** → Prefer table-driven tests and shared helper mocks to reduce duplication.
