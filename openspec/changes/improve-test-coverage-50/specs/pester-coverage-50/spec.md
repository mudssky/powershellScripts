## ADDED Requirements

### Requirement: Coverage target
The system SHALL reach at least 50% command coverage for the Pester suite.

#### Scenario: Coverage measurement
- **WHEN** tests are run with coverage enabled
- **THEN** the reported coverage is 50% or higher

### Requirement: Coverage increases come from tests
The system SHALL improve coverage by adding or expanding tests rather than excluding modules from coverage.

#### Scenario: Coverage improvement approach
- **WHEN** coverage improves toward the 50% target
- **THEN** the improvement is attributable to additional tests for existing modules
