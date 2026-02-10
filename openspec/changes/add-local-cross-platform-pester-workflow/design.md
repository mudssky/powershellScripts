## Context

Current local Pester validation is fragmented: Windows developers may use host `pwsh` or WSL, while macOS developers often use ad-hoc Docker commands. CI already validates multiple OS targets, but local workflows do not provide a consistent Linux parity path. In addition, concurrent host/container runs can overwrite shared test outputs if they target the same workspace.

## Goals / Non-Goals

**Goals:**
- Define a single, repeatable local workflow for Linux Pester execution via containers on both Windows and macOS.
- Preserve host `pwsh` runs for platform-specific behavior checks.
- Provide clear fast/full verification paths that map to existing Pester run modes.
- Ensure host and container runs can execute concurrently without output collisions.

**Non-Goals:**
- Replacing CI matrix testing.
- Rewriting existing Pester test cases or changing assertion semantics.
- Supporting Windows PowerShell 5.1.

## Decisions

### 1) Standardize Linux local verification on containers
- Decision: Use a Docker-based Linux test entrypoint (compose service + documented command) as the official Linux local path.
- Rationale: Works consistently on Windows and macOS; avoids WSL-only coupling.
- Alternatives considered:
  - WSL-only Linux run: rejected because macOS cannot use WSL.
  - Ad-hoc `docker run` snippets: rejected due to inconsistent parameters and discoverability.

### 2) Keep host verification as a first-class step
- Decision: Keep host `pwsh` test commands as the primary way to validate host-specific behavior (especially `windowsOnly`-tagged tests on Windows).
- Rationale: Linux containers cannot replace host platform semantics.
- Alternatives considered:
  - Linux-only local strategy: rejected due to incomplete coverage of host behavior.

### 3) Define collision-safe output strategy
- Decision: Require isolation for parallel host/container runs, either by separate work directories (worktree) or distinct result output paths.
- Rationale: Current fixed result filename can collide during parallel runs.
- Alternatives considered:
  - Serial-only execution: rejected because it slows local feedback.

### 4) Publish fast/full runbook aligned to existing modes
- Decision: Reuse existing fast/full/serial concepts and map them to host + container commands.
- Rationale: Reduces cognitive load and preserves existing team habits.

## Risks / Trade-offs

- [Risk] Docker is unavailable or misconfigured on developer machines → Mitigation: keep host-only fallback path and clear prerequisites.
- [Risk] Path/volume mapping differences across Windows/macOS cause flaky container runs → Mitigation: define a single compose working directory and explicit mount strategy.
- [Risk] Increased local workflow complexity (host + container) → Mitigation: provide opinionated default command set (fast and full presets).
- [Risk] Parallel run artifact confusion → Mitigation: standardize output locations and naming by environment.

## Migration Plan

1. Add container execution assets for Linux `pwsh` + Pester.
2. Add/adjust package scripts for host/container fast and full runs.
3. Document Windows/macOS usage with quick-start commands.
4. Validate behavior on at least one Windows and one macOS environment.
5. Keep CI matrix unchanged as the final cross-platform authority.

## Open Questions

- Should the default local command run host+container serially or in parallel?
- Do we require separate output files by default, or only document worktree-based isolation?
- Should macOS-specific host checks be explicitly tagged and included in the local runbook?
