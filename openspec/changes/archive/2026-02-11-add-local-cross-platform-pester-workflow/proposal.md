## Why

Local Pester runs currently depend on each developer manually assembling platform environments (Windows host, WSL, or ad-hoc containers), which is inconsistent and hard to reproduce across Windows and macOS machines. We need a single local workflow that reliably validates Linux behavior via containers while still covering host-specific behavior.

## What Changes

- Add a documented local cross-platform test workflow that combines:
  - Linux Pester execution in a container
  - Host `pwsh` execution for platform-specific checks (Windows/macOS)
- Add a containerized Pester entrypoint for Linux runs that can be invoked consistently from both Windows and macOS developer machines.
- Add guidance for safe concurrent runs (separate work directories or isolated outputs) to prevent test result file collisions.
- Define standard local commands for fast feedback and full verification before CI.

## Capabilities

### New Capabilities
- `local-cross-platform-pester-testing`: Standardizes local Pester validation across host and Linux container environments, including command conventions and output isolation requirements.

### Modified Capabilities
- (none)

## Impact

- Developer workflow documentation and runbook for local testing.
- Test orchestration assets for Linux container execution (for example, compose/service definitions and helper scripts).
- NPM/PNPM script surface for local test execution convenience.
- Pester result handling when running host and container checks in parallel.
