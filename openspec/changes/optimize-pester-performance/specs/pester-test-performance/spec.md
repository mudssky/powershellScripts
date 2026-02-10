## ADDED Requirements

### Requirement: Fast test mode
The system SHALL provide a fast local Pester run mode that disables profile loading and code coverage.

#### Scenario: Fast mode execution
- **WHEN** the user runs the fast test command
- **THEN** Pester runs with no profile and coverage disabled

### Requirement: Full test mode remains default
The system SHALL keep the current full test mode as the default when no fast mode is selected.

#### Scenario: Default execution
- **WHEN** the user runs the standard test command
- **THEN** Pester loads the profile and code coverage remains enabled

### Requirement: Fast mode avoids expensive environment scans
The system SHALL avoid slow environment queries (module discovery and PATH scans) during fast mode by using test doubles where applicable.

#### Scenario: Fast mode uses mocks
- **WHEN** fast mode is active and a test would call module discovery or PATH scans
- **THEN** the test uses mocks instead of real system queries
