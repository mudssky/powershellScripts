## 1. Test Run Modes

- [x] 1.1 Add pnpm scripts for fast/full modes (fast uses -NoProfile and disables coverage)
- [x] 1.2 Update PesterConfiguration to read mode env var and toggle coverage settings

## 2. Targeted Test Optimizations

- [x] 2.1 Mock `Get-Module -ListAvailable` in `psutils/tests/install.Tests.ps1` for fast mode
- [x] 2.2 Mock `Get-Command` in `psutils/tests/test.Tests.ps1` for fast mode

## 3. Documentation & Verification

- [x] 3.1 Document how to run fast vs full tests in README or contributing docs
- [x] 3.2 Verify fast mode runtime improvement and full mode coverage still runs
