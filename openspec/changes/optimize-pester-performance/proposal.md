## Why

Pester full test runs are slow (~58s) mainly due to expensive module/command scans and profile startup overhead. We need faster local feedback while keeping CI coverage and full checks intact.

## What Changes

- Add a fast local test mode that disables profile loading and code coverage.
- Mock or isolate slow environment queries in targeted tests to reduce runtime.
- Keep full test mode for CI with coverage and profile tests intact.

## Capabilities

### New Capabilities
- `pester-test-performance`: Defines fast vs full Pester run modes and their required behaviors.

### Modified Capabilities
- (none)

## Impact

- Pester configuration (`PesterConfiguration.ps1`) and test suite behavior.
- Test modules with slow environment queries (e.g., module discovery, PATH scans).
- CI and local test scripts (pnpm commands).
