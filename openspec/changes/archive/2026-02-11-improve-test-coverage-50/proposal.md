## Why

Current Pester coverage is ~23.66%, which makes it hard to trust tests and increases regression risk. We want a realistic near-term target of 50% coverage without destabilizing the suite.

## What Changes

- Add targeted tests for currently uncovered modules, prioritizing highest-impact utilities.
- Use mocks to cover behavior without requiring external dependencies.
- Track progress to the 50% coverage goal.

## Capabilities

### New Capabilities
- `pester-coverage-50`: Defines the coverage target and required test additions to reach 50%.

### Modified Capabilities
- (none)

## Impact

- New or expanded tests under `psutils/tests`.
- Potential updates to Pester coverage configuration and exclusions.
- CI coverage reporting thresholds (if added).
