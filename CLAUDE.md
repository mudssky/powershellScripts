# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Project Vision

A comprehensive cross-platform development environment toolkit centered around PowerShell, with Node.js/TypeScript and Rust CLI companions. It provides daily automation scripts (media processing, system management, file operations, network tools), a reusable PowerShell module (`psutils`), and a unified profile system for Windows/Linux/macOS shells.

## Architecture Overview

This is a **pnpm monorepo** (`pnpm-workspace.yaml`) with Turborepo orchestration. The codebase spans multiple languages but has a clear layering:

```
Source scripts (scripts/pwsh/, scripts/node/src/, scripts/python/)
        |
        v
Shim generation (Manage-BinScripts.ps1, generate-bin.ts)
        |
        v
   bin/ directory (auto-generated executables, NEVER edit manually)
```

### Key Architecture Rules

- **`bin/` is auto-generated**: Running `Manage-BinScripts.ps1 -Action sync` or `install.ps1` creates shim wrappers in `bin/` that delegate to source scripts. **Never manually edit files in `bin/`**.
- **PowerShell shims**: Parse the source script's AST to extract `param()` blocks, `CmdletBinding`, help comments, and `@ShimProfile` directives, then generate a forwarding shim.
- **Node.js shims**: `scripts/node/generate-bin.ts` creates Unix shell + Windows CMD wrappers pointing to Rspack-bundled `.cjs` output files.
- **Python shims**: Generated as PowerShell wrappers that invoke `uv run` on the source `.py` file.

## Project Structure

```
root/
├── bin/                          # Auto-generated shims (gitignored, DO NOT edit)
├── scripts/
│   ├── pwsh/                     # PowerShell script sources (categorized)
│   │   ├── devops/               # DevOps tools (SSH setup, containers, formatting)
│   │   ├── filesystem/           # File system utilities
│   │   ├── media/                # FFmpeg, image compression
│   │   ├── misc/                 # General utilities (env cleanup, proxy, etc.)
│   │   └── network/              # Download & network tools
│   ├── node/                     # Node.js/TypeScript tools (pnpm workspace package)
│   │   ├── src/                  # TypeScript source (Rspack entry auto-detection)
│   │   │   ├── rule-loader/      # AI rule file converter CLI
│   │   │   └── hello.ts          # Example entry
│   │   ├── tests/                # Vitest tests
│   │   ├── rspack.config.ts      # Build config (SWC loader, banner injection)
│   │   └── generate-bin.ts       # Post-build bin wrapper generator
│   ├── python/                   # Python utility scripts (shims via uv)
│   ├── ahk/                      # AutoHotkey v2 scripts (Windows only)
│   │   ├── scripts/              # AHK modules
│   │   ├── base.ahk              # Shared base config
│   │   └── makeScripts.ps1       # Build script to merge modules
│   ├── qa.mjs                    # Monorepo QA orchestrator (changed/all modes)
│   ├── qa-turbo.mjs              # Turbo-based QA orchestrator
│   └── qa-benchmark.mjs          # QA benchmark sampling
├── psutils/                      # PowerShell utility module
│   ├── psutils.psd1              # Module manifest (v1.0.0, author: mudssky)
│   ├── index.psm1                # Root module (NestedModules in psd1 handle loading)
│   ├── modules/                  # Sub-modules (18 .psm1 files)
│   │   ├── cache.psm1            # Caching (Invoke-WithCache, Invoke-WithFileCache)
│   │   ├── env.psm1              # .env file handling, PATH manipulation
│   │   ├── filesystem.psm1       # Get-Tree, gitignore-aware tree
│   │   ├── functions.psm1        # General utilities (history, shortcuts, semver)
│   │   ├── git.psm1              # Git helpers
│   │   ├── help.psm1             # Module help search
│   │   ├── install.psm1          # Package manager app installation
│   │   ├── network.psm1          # Port checks, URL waiting
│   │   ├── os.psm1               # OS detection, admin check
│   │   ├── test.psm1             # Testing utilities
│   │   ├── web.psm1              # Web shortcuts
│   │   └── ...                   # (font, hardware, proxy, string, etc.)
│   └── tests/                    # Pester tests for each module
├── profile/                      # PowerShell profile system
│   ├── profile.ps1               # Main entry (dot-sources core -> mode -> loaders -> features)
│   ├── profile_unix.ps1          # Linux/macOS entry
│   ├── core/                     # Core loading (encoding, mode detection, loaders)
│   ├── features/                 # Feature modules (environment, help, install)
│   ├── config/aliases/           # User alias definitions
│   └── installer/                # App/module/font installation scripts
├── projects/clis/                # Standalone CLI tools (pnpm workspace packages)
│   ├── pwshfmt-rs/               # Rust-based PowerShell formatter
│   │   ├── src/                  # Rust source (formatter, discovery, processor)
│   │   ├── tests/                # Rust integration tests
│   │   └── package.json          # npm wrapper for Turbo (cargo commands)
│   └── json-diff-tool/           # TypeScript JSON/JSONC/JSON5 diff CLI
│       ├── src/                  # TypeScript source
│       └── tests/                # Vitest tests
├── config/                       # Software configurations
│   ├── software/mpv/             # MPV player config + TypeScript scripts
│   ├── clash/                    # Proxy configs
│   ├── git/                      # Git utilities
│   └── frontend/                 # Frontend project templates
├── ai/                           # AI tooling (prompts, MCP configs, model downloads)
├── docs/cheatsheet/              # Technical cheatsheets by topic
├── linux/                        # Linux setup scripts (Ubuntu, Arch, WSL2)
├── macos/                        # macOS setup scripts + Hammerspoon
├── tests/                        # Root-level Pester tests
├── install.ps1                   # Project entry: PATH setup + sync bin + build Node
├── Manage-BinScripts.ps1         # Bin shim generator (sync/clean)
├── PesterConfiguration.ps1       # Pester test framework configuration
├── package.json                  # Root package (pnpm workspace root)
├── pnpm-workspace.yaml           # Workspaces: projects/**, scripts/node
├── turbo.json                    # Turborepo task pipeline
├── biome.json                    # Biome linter/formatter config
└── lint-staged.config.js         # Pre-commit hooks config
```

## Build / Test / Lint Commands

### Installation

```bash
# Full environment setup (PATH, bin sync, Node build)
pwsh ./install.ps1

# Sync bin shims only
pwsh ./Manage-BinScripts.ps1 -Action sync -Force

# Clean bin directory
pwsh ./Manage-BinScripts.ps1 -Action clean
```

### Testing

```bash
# PowerShell Pester tests (full, with coverage & profile tests)
pnpm test

# Fast local tests (no profile loading, no coverage)
pnpm test:fast

# Serial mode (for debugging discovery phase hangs)
pnpm test:serial

# Debug output
pnpm test:debug

# Profile-specific tests only
pnpm test:profile

# Node.js Vitest (in scripts/node workspace)
cd scripts/node && pnpm test
```

Pester configuration is in `PesterConfiguration.ps1` with environment-driven modes:
- `PWSH_TEST_MODE`: `full` (default) | `fast` | `serial` | `debug`
- `PWSH_TEST_VERBOSE`: set to `1` for detailed output
- `PWSH_TEST_PATH`: override test paths (semicolon/comma separated)
- Test paths: `./psutils` and `./tests`
- Tags: `Slow` always excluded; `windowsOnly` excluded on Linux/macOS
- Parallelism: 4 threads (disabled in serial mode)
- CI: `$env:CI` controls exit-on-failure and detailed output

### Formatting

```bash
# PowerShell formatting (git-changed files only, via pwshfmt-rs)
pnpm format:pwsh

# PowerShell formatting (all files)
pnpm format:pwsh:all

# PowerShell formatting with strict fallback
pnpm format:pwsh:strict

# Rust-based fast formatter
pnpm format:pwsh:rs              # write mode, git-changed
pnpm format:pwsh:rs:all          # write mode, all files
pnpm check:pwsh:rs               # check mode (non-zero exit if changes needed)

# Biome (JS/TS)
pnpm format:biome

# Python (via uvx ruff)
pnpm format:python
pnpm lint:python
```

### QA (Quality Assurance)

```bash
# Monorepo QA - changed packages only (format + lint + test per workspace)
pnpm qa

# Monorepo QA - all packages
pnpm qa:all

# Verbose mode (shows filtering & command execution details)
pnpm qa:verbose

# Turbo-based QA (parallel, with caching)
pnpm turbo:qa              # affected packages
pnpm turbo:qa:all           # all packages
pnpm turbo:qa:verbose       # with verbose output

# Root PowerShell QA only
pnpm qa:pwsh                # format:pwsh && test

# QA benchmark sampling (CI trend analysis)
pnpm qa:benchmark
```

The Turbo pipeline runs: `typecheck:fast -> check -> test:fast` per workspace package.
Set `QA_BASE_REF` to change the diff baseline (default: `origin/master`).

### Per-workspace QA commands

Each workspace package defines its own `qa` script:
- **scripts/node**: `typecheck:fast && check && test:fast`
- **projects/clis/json-diff-tool**: `typecheck:fast && check && test:fast`
- **projects/clis/pwshfmt-rs**: `cargo check && cargo clippy && cargo test`

### Node.js Build (scripts/node)

```bash
cd scripts/node
pnpm build              # Production build (Rspack + generate bin wrappers)
pnpm build:dev          # Dev build (no minification)
pnpm build:standalone   # Build + copy .cjs to bin/
```

Rspack auto-discovers entries from `src/`: top-level `.ts` files and directories with `index.ts`. Output is `dist/[name].cjs` with `#!/usr/bin/env node` banner injected.

## Coding Conventions

### PowerShell

- **Header template**:
  ```powershell
  #!/usr/bin/env pwsh
  [CmdletBinding(SupportsShouldProcess = $true)]
  param(...)
  Set-StrictMode -Version Latest
  $ErrorActionPreference = 'Stop'
  ```
- **Functions**: Must use `Verb-Noun` naming (e.g., `Get-SystemInfo`)
- **Paths**: Always use `Join-Path`, never string concatenation like `"$root\bin"`
- **Documentation**: Every script must have `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- **Error handling**: Use `try/catch`, never swallow errors with empty catch blocks
- **Encoding**: UTF-8 (No BOM), LF line endings
- **File naming**: `PascalCase.ps1` or `camelCase.ps1` (maintain consistency)

### Node.js / TypeScript

- **File naming**: `kebab-case.ts` (preferred) or `camelCase.ts`
- **No `any`**: Define explicit interfaces/types
- **JSDoc**: Required on all exported functions
- **Async**: Must handle Promise rejection (`try/catch` or `.catch()`)
- **Linter**: Biome (single-quote, trailing commas, LF, 2-space indent, no semicolons)

### Rust (pwshfmt-rs)

- Standard `cargo fmt` / `cargo clippy` conventions
- Tests run with `--test-threads=1`

### AutoHotkey

- **AHK v2 only**: `#Requires AutoHotkey v2.0`
- Edit modules in `scripts/ahk/scripts/`, then run `makeScripts.ps1` to rebuild

### General

- **SOLID/SRP**: Each function/script does one thing
- **Comments**: Explain "why", not "what"
- **TODOs**: Format as `// TODO(User): [description]` or `# TODO(User): [description]`
- **Commit messages**: Use Chinese
- **No hallucination**: Never reference packages not in `package.json`

## Pre-commit Hooks

Configured via Husky + lint-staged (`lint-staged.config.js`):
- `*.{ps1,psm1,psd1}`: PowerShell formatting via `Format-PowerShellCode.ps1`
- `*.{js,jsx,ts,tsx,css,html,json,jsonc}`: `biome check --write`
- `*.py`: `uvx ruff check --fix` + `uvx ruff format`
- `*.lua`: `stylua`
- `*.ipynb`: `nbstripout`

## CI (GitHub Actions)

**Workflow: `.github/workflows/test.yml`** (triggers on push/PR to master):
1. **Pester tests**: Matrix across `ubuntu-latest`, `windows-latest`, `macos-latest`
2. **Node Vitest**: Ubuntu only, uses pnpm cache, outputs JUnit XML report
3. Both jobs publish test reports via `dorny/test-reporter`

**Workflow: `.github/workflows/qa-benchmark.yml`**: Standalone QA benchmark sampling.

## Profile System

The profile system (`profile/`) directly affects shell startup performance:

- **Entry**: `profile/profile.ps1` (Windows), `profile/profile_unix.ps1` (Linux/macOS)
- **Load order**: `core/encoding.ps1` -> `core/mode.ps1` -> `core/loaders.ps1` -> `features/*`
- **Mode detection**: Auto-selects `Full`, `Minimal`, or `UltraMinimal` profile mode
- **Performance constraint**: No synchronous network calls in profile scripts; use lazy loading for module imports
- **Error resilience**: Profile errors must not prevent shell startup

## PSUtils Module

Module manifest at `psutils/psutils.psd1` with 18 nested sub-modules. Key patterns:
- All functions are explicitly listed in `FunctionsToExport` (no wildcards)
- Import: `Import-Module ./psutils/psutils.psd1`
- Adding a function: create in `modules/*.psm1` -> add to `FunctionsToExport` in `.psd1` -> add test in `tests/`
- Compatible with PowerShell 5.1+ and Core

## Non-obvious Conventions

1. **Shim `@ShimProfile` directive**: PowerShell source scripts can include a comment `# @ShimProfile: NoProfile|Silent|Default` to control the shim's shebang line (`-NoProfile`, `-NoLogo`, or plain `pwsh`).

2. **Duplicate script name resolution**: `Manage-BinScripts.ps1` handles filename collisions via `DuplicateStrategy`: `PrefixParent` (default, uses parent directory as prefix), `Overwrite`, or `Skip`.

3. **Python scripts become PowerShell shims**: `.py` files in `scripts/python/` are mapped to `.ps1` shims in `bin/` that invoke `uv run`.

4. **Rspack entry auto-detection**: In `scripts/node/`, directories with `index.ts` become a single entry point (named after the directory). Top-level `.ts` files (except `index.ts`) each become their own entry.

5. **Turbo task caching**: The pipeline excludes docs/notebooks from cache inputs. Remote caching is off by default; enable in CI with `TURBO_REMOTE_CACHE=1`.

6. **Profile test isolation**: Profile tests run in a dedicated serial mode (`pnpm test:profile`) due to global state dependencies.

7. **`pwshfmt-rs`**: A custom Rust-based PowerShell formatter at `projects/clis/pwshfmt-rs/` that handles command name and parameter name casing correction. It preserves string literals and comments, and avoids writing unchanged files. Its `package.json` wraps Cargo commands for Turbo integration.

8. **MPV scripts TypeScript build**: `config/software/mpv/mpv_scripts/` is a separate TypeScript project using Rollup. Build with `cd config/software/mpv/mpv_scripts && pnpm build`. All dependencies must be bundled (no runtime `node_modules`).
