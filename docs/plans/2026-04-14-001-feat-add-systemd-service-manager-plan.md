---
title: feat: add systemd service manager
type: feat
status: active
date: 2026-04-14
origin: docs/superpowers/specs/2026-04-14-systemd-service-manager-design.md
---

# Systemd Service Manager Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a modular Bash-based systemd service manager that can scaffold project configs, generate and install service/timer units for system or user scope, and manage lifecycle/logs with Vitest coverage.

**Architecture:** The manager lives under `scripts/bash/systemd-service-manager/` as focused Bash modules that are concatenated by `build.sh` into `bin/systemd-service-manager` and `scripts/bash/systemd-service-manager.sh`. Runtime behavior is split into project discovery, safe dotenv loading, config parsing, schedule conversion, unit rendering, and thin wrappers around `systemctl`, `journalctl`, and `systemd-analyze` so the source entry and built output behave identically.

**Tech Stack:** Bash, systemd (`systemctl`, `journalctl`, `systemd-analyze`), Vitest, execa, Node.js test helpers

---

## Planned File Map

### Tool Source

- Create: `scripts/bash/systemd-service-manager/README.md`
- Create: `scripts/bash/systemd-service-manager/build.sh`
- Create: `scripts/bash/systemd-service-manager/main.sh`
- Create: `scripts/bash/systemd-service-manager/common.sh`
- Create: `scripts/bash/systemd-service-manager/lib/cli.sh`
- Create: `scripts/bash/systemd-service-manager/lib/project.sh`
- Create: `scripts/bash/systemd-service-manager/lib/env.sh`
- Create: `scripts/bash/systemd-service-manager/lib/parser-service.sh`
- Create: `scripts/bash/systemd-service-manager/lib/parser-timer.sh`
- Create: `scripts/bash/systemd-service-manager/lib/schedule.sh`
- Create: `scripts/bash/systemd-service-manager/lib/render-service.sh`
- Create: `scripts/bash/systemd-service-manager/lib/render-timer.sh`
- Create: `scripts/bash/systemd-service-manager/lib/systemd.sh`
- Create: `scripts/bash/systemd-service-manager/lib/validate.sh`
- Create: `scripts/bash/systemd-service-manager/commands/init.sh`
- Create: `scripts/bash/systemd-service-manager/commands/list.sh`
- Create: `scripts/bash/systemd-service-manager/commands/install.sh`
- Create: `scripts/bash/systemd-service-manager/commands/uninstall.sh`
- Create: `scripts/bash/systemd-service-manager/commands/start.sh`
- Create: `scripts/bash/systemd-service-manager/commands/stop.sh`
- Create: `scripts/bash/systemd-service-manager/commands/restart.sh`
- Create: `scripts/bash/systemd-service-manager/commands/status.sh`
- Create: `scripts/bash/systemd-service-manager/commands/logs.sh`
- Create: `scripts/bash/systemd-service-manager/commands/enable.sh`
- Create: `scripts/bash/systemd-service-manager/commands/disable.sh`

### Templates and Generated Project Docs

- Create: `scripts/bash/systemd-service-manager/templates/README.md`
- Create: `scripts/bash/systemd-service-manager/templates/project.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/project.env.example`
- Create: `scripts/bash/systemd-service-manager/templates/service.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/service.env.example`
- Create: `scripts/bash/systemd-service-manager/templates/timer-service.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/timer-task.conf.example`

### Build Outputs

- Create: `bin/systemd-service-manager`
- Create: `scripts/bash/systemd-service-manager.sh`

### Tests

- Create: `scripts/bash/systemd-service-manager/vitest.config.ts`
- Create: `scripts/bash/systemd-service-manager/tests/test-utils.ts`
- Create: `scripts/bash/systemd-service-manager/tests/build.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/manager-cli.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/parser.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/schedule.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/init.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/install.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/lifecycle.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/project.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/project.env`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.env`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.env.local`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/timers/restart-api.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/timers/cleanup.conf`

### Root QA and Package Wiring

- Modify: `package.json`
- Modify: `scripts/qa.mjs`
- Modify: `scripts/qa-turbo.mjs`
- Modify: `scripts/bash/README.md`

## Task 1: Scaffold the manager, build entrypoints, and Vitest harness

**Files:**
- Create: `scripts/bash/systemd-service-manager/build.sh`
- Create: `scripts/bash/systemd-service-manager/main.sh`
- Create: `scripts/bash/systemd-service-manager/common.sh`
- Create: `scripts/bash/systemd-service-manager/lib/cli.sh`
- Create: `scripts/bash/systemd-service-manager/README.md`
- Create: `scripts/bash/systemd-service-manager/vitest.config.ts`
- Create: `scripts/bash/systemd-service-manager/tests/test-utils.ts`
- Create: `scripts/bash/systemd-service-manager/tests/build.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/manager-cli.test.ts`

- [ ] **Step 1: Write the failing build/help tests**

```ts
// scripts/bash/systemd-service-manager/tests/manager-cli.test.ts
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  runBuild,
  runBuilt,
  runSource,
} from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('systemd service manager cli', () => {
  it('shows top-level help from the source entry and built binary', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const build = await runBuild(workspace)
    expect(build.exitCode).toBe(0)

    const sourceHelp = await runSource(workspace, ['help'])
    const builtHelp = await runBuilt(workspace, 'bin', ['help'])

    expect(sourceHelp.exitCode).toBe(0)
    expect(builtHelp.exitCode).toBe(0)
    expect(sourceHelp.stdout).toContain(
      'Usage: systemd-service-manager <command> [options]',
    )
    expect(builtHelp.stdout).toBe(sourceHelp.stdout)
  })

  it('fails on unknown commands with a clear error', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runSource(workspace, ['unknown-command'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unknown command')
  })
})
```

```ts
// scripts/bash/systemd-service-manager/tests/build.test.ts
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  runBuild,
  readText,
} from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('systemd service manager build', () => {
  it('produces portable outputs with the generated banner', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace)

    expect(result.exitCode).toBe(0)
    expect(readText(workspace.builtBin)).toContain(
      '# Auto-generated by scripts/bash/systemd-service-manager/build.sh.',
    )
    expect(readText(workspace.builtLocal)).toContain(
      '# Auto-generated by scripts/bash/systemd-service-manager/build.sh.',
    )
  })
})
```

- [ ] **Step 2: Add the Vitest config and execa-based test harness**

```ts
// scripts/bash/systemd-service-manager/vitest.config.ts
import path from 'node:path'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    include: [path.join(__dirname, 'tests', '**/*.test.ts')],
    testTimeout: 30_000,
  },
})
```

```ts
// scripts/bash/systemd-service-manager/tests/test-utils.ts
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'

const repoRoot = path.resolve(__dirname, '../../../..')
const managerRoot = path.join(repoRoot, 'scripts', 'bash', 'systemd-service-manager')

export type Workspace = {
  root: string
  managerHome: string
  sourceEntry: string
  buildScript: string
  builtBin: string
  builtLocal: string
  fakeSystemDir: string
  fakeUserDir: string
  fakeProjectDir: string
  mockBin: string
  home: string
}

export async function runCommand(
  command: string,
  args: string[],
  workspace: Workspace,
  extraEnv: NodeJS.ProcessEnv = {},
) {
  try {
    const result = await execa(command, args, {
      cwd: workspace.root,
      env: {
        ...process.env,
        HOME: workspace.home,
        SSM_SYSTEM_UNIT_DIR: workspace.fakeSystemDir,
        SSM_USER_UNIT_DIR: workspace.fakeUserDir,
        PATH: `${workspace.mockBin}:${process.env.PATH ?? ''}`,
        ...extraEnv,
      },
      reject: false,
    })

    return {
      stdout: result.stdout,
      stderr: result.stderr,
      exitCode: result.exitCode,
    }
  } catch (error) {
    throw error
  }
}
```

- [ ] **Step 3: Run the tests to verify they fail for missing files**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts
```

Expected: FAIL with missing entry files such as `main.sh`, `build.sh`, or test fixture setup errors.

- [ ] **Step 4: Implement the minimal source layout, build script, and top-level CLI**

```bash
# scripts/bash/systemd-service-manager/build.sh
#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BIN_OUTPUT="${REPO_ROOT}/bin/systemd-service-manager"
LOCAL_OUTPUT="${REPO_ROOT}/scripts/bash/systemd-service-manager.sh"

MODULES=(
  "${SCRIPT_DIR}/common.sh"
  "${SCRIPT_DIR}/lib/cli.sh"
  "${SCRIPT_DIR}/main.sh"
)
```

```bash
# scripts/bash/systemd-service-manager/common.sh
ssm_log() {
  local level="$1"
  shift
  printf '[systemd-service-manager][%s] %s\n' "${level}" "$*"
}

ssm_die() {
  ssm_log "error" "$*" >&2
  exit 1
}

ssm_detect_manager_home() {
  local script_path="$1"
  local script_dir
  script_dir="$(cd "$(dirname "${script_path}")" && pwd)"
  local candidates=(
    "${script_dir}"
    "${script_dir}/systemd-service-manager"
    "${script_dir}/scripts/bash/systemd-service-manager"
  )
  local candidate

  for candidate in "${candidates[@]}"; do
    if [[ -f "${candidate}/build.sh" || -d "${candidate}/templates" ]]; then
      (cd "${candidate}" && pwd)
      return 0
    fi
  done

  printf '%s\n' "${script_dir}"
}

ssm_init_environment() {
  local script_path="$1"
  SSM_MANAGER_HOME="$(ssm_detect_manager_home "${script_path}")"
}
```

```bash
# scripts/bash/systemd-service-manager/lib/cli.sh
ssm_show_help() {
  cat <<'EOF'
Usage: systemd-service-manager <command> [options]

Commands:
  init
  list
  install
  uninstall
  start
  stop
  restart
  status
  logs
  enable
  disable
  help
EOF
}
```

```bash
# scripts/bash/systemd-service-manager/main.sh
if [[ -z "${SSM_STANDALONE:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # shellcheck source=scripts/bash/systemd-service-manager/common.sh
  source "${SCRIPT_DIR}/common.sh"
  # shellcheck source=scripts/bash/systemd-service-manager/lib/cli.sh
  source "${SCRIPT_DIR}/lib/cli.sh"
fi

ssm_main() {
  ssm_init_environment "${BASH_SOURCE[0]}"

  local command="${1:-help}"
  shift || true

  case "${command}" in
    help|--help|-h|'')
      ssm_show_help
      ;;
    *)
      ssm_die "Unknown command: ${command}"
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  ssm_main "$@"
fi
```

- [ ] **Step 5: Add a short manager README for future contributors**

~~~md
# Systemd Service Manager

一个基于 Bash 的轻量 systemd service/timer 管理器。

## Build

```bash
bash scripts/bash/systemd-service-manager/build.sh
```

## Outputs

- `bin/systemd-service-manager`
- `scripts/bash/systemd-service-manager.sh`
~~~

- [ ] **Step 6: Re-run the focused tests**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts --testNamePattern "systemd service manager"
```

Expected: PASS for build/help/unknown-command tests.

- [ ] **Step 7: Commit the scaffold**

```bash
git add scripts/bash/systemd-service-manager scripts/bash/systemd-service-manager.sh bin/systemd-service-manager
git commit -m "feat(bash): scaffold systemd service manager"
```

## Task 2: Implement project discovery, safe dotenv loading, parsing, and schedule conversion

**Files:**
- Create: `scripts/bash/systemd-service-manager/lib/project.sh`
- Create: `scripts/bash/systemd-service-manager/lib/env.sh`
- Create: `scripts/bash/systemd-service-manager/lib/parser-service.sh`
- Create: `scripts/bash/systemd-service-manager/lib/parser-timer.sh`
- Create: `scripts/bash/systemd-service-manager/lib/schedule.sh`
- Create: `scripts/bash/systemd-service-manager/lib/validate.sh`
- Create: `scripts/bash/systemd-service-manager/tests/parser.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/schedule.test.ts`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/project.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/project.env`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.env`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/services/api.env.local`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/timers/restart-api.conf`
- Create: `scripts/bash/systemd-service-manager/tests/fixtures/project-basic/deploy/systemd/timers/cleanup.conf`
- Modify: `scripts/bash/systemd-service-manager/build.sh`
- Modify: `scripts/bash/systemd-service-manager/main.sh`

- [ ] **Step 1: Write failing parser and schedule tests**

```ts
// scripts/bash/systemd-service-manager/tests/parser.test.ts
import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { createWorkspace, cleanupWorkspace, runSource, writeText } from './test-utils'

describe('config parsing', () => {
  it('merges project env and service env with .env.local winning', async () => {
    const workspace = createWorkspace()
    try {
      const projectRoot = path.join(workspace.root, 'demo-app')
      fs.cpSync(
        path.join(
          workspace.managerHome,
          'tests',
          'fixtures',
          'project-basic',
        ),
        projectRoot,
        { recursive: true },
      )

      const result = await runSource(
        workspace,
        ['list', '--project', projectRoot],
        { SSM_DEBUG_DUMP_CONFIG: '1' },
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('APP_PORT=3100')
      expect(result.stdout).toContain('scope=system')
    } finally {
      cleanupWorkspace(workspace)
    }
  })

  it('fails when a timer points to a missing service target', async () => {
    const workspace = createWorkspace()
    try {
      const projectRoot = path.join(workspace.root, 'demo-app')
      fs.cpSync(
        path.join(
          workspace.managerHome,
          'tests',
          'fixtures',
          'project-basic',
        ),
        projectRoot,
        { recursive: true },
      )

      writeText(
        path.join(projectRoot, 'deploy/systemd/timers/bad.conf'),
        'TARGET_TYPE=service\nTARGET_NAME=missing\nACTION=restart\nSCHEDULE=@daily\n',
      )

      const result = await runSource(workspace, [
        'install',
        'timer',
        'bad',
        '--project',
        projectRoot,
        '--dry-run',
      ])

      expect(result.exitCode).not.toBe(0)
      expect(result.stderr + result.stdout).toContain('TARGET_NAME')
    } finally {
      cleanupWorkspace(workspace)
    }
  })
})
```

```ts
// scripts/bash/systemd-service-manager/tests/schedule.test.ts
import { describe, expect, it } from 'vitest'
import { createWorkspace, cleanupWorkspace, runSource, writeText } from './test-utils'

describe('schedule conversion', () => {
  it('converts cron to OnCalendar output', async () => {
    const workspace = createWorkspace()
    try {
      const scheduleFile = `${workspace.root}/schedule.conf`
      writeText(scheduleFile, 'SCHEDULE=0 3 * * *\n')

      const result = await runSource(workspace, [
        'help',
      ], { SSM_TEST_SCHEDULE_FILE: scheduleFile })

      expect(result.exitCode).toBe(0)
    } finally {
      cleanupWorkspace(workspace)
    }
  })

  it('rejects unsupported cron syntax', async () => {
    const workspace = createWorkspace()
    try {
      const result = await runSource(workspace, [
        'help',
      ], { SSM_TEST_SCHEDULE: '0 0 ? * *' })

      expect(result.exitCode).not.toBe(0)
      expect(result.stderr + result.stdout).toContain('Unsupported cron')
    } finally {
      cleanupWorkspace(workspace)
    }
  })
})
```

- [ ] **Step 2: Run the parser and schedule tests to capture the failure**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/parser.test.ts scripts/bash/systemd-service-manager/tests/schedule.test.ts
```

Expected: FAIL because `list`, `install --dry-run`, and schedule resolution are not implemented.

- [ ] **Step 3: Implement project discovery and safe dotenv parsing**

```bash
# scripts/bash/systemd-service-manager/lib/project.sh
ssm_find_project_dir() {
  local explicit="${1:-}"
  if [[ -n "${explicit}" ]]; then
    printf '%s\n' "${explicit}"
    return 0
  fi
  printf '%s\n' "${PWD}"
}

ssm_config_root() {
  local project_dir="$1"
  printf '%s/deploy/systemd\n' "${project_dir}"
}
```

```bash
# scripts/bash/systemd-service-manager/lib/env.sh
ssm_trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

ssm_load_env_file() {
  local env_file="$1"
  [[ -f "${env_file}" ]] || return 0
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="$(ssm_trim "${line}")"
    [[ -z "${line}" || "${line}" == \#* ]] && continue
    [[ "${line}" == *=* ]] || ssm_die "Invalid dotenv line in ${env_file}"
    local key="${line%%=*}"
    local value="${line#*=}"
    key="$(ssm_trim "${key}")"
    [[ "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || ssm_die "Invalid dotenv key: ${key}"
    export "${key}=${value}"
  done < "${env_file}"
}
```

- [ ] **Step 4: Implement service/timer parsing, validation, and schedule conversion**

```bash
# scripts/bash/systemd-service-manager/lib/parser-service.sh
ssm_parse_service_config() {
  local service_file="$1"
  source "${service_file}"
  [[ -n "${COMMAND:-}" ]] || ssm_die "Missing COMMAND in ${service_file}"
  SSM_SERVICE_NAME="$(basename "${service_file}" .conf)"
  SSM_SERVICE_SCOPE="${SCOPE:-${DEFAULT_SCOPE:-system}}"
}
```

```bash
# scripts/bash/systemd-service-manager/lib/parser-timer.sh
ssm_parse_timer_config() {
  local timer_file="$1"
  source "${timer_file}"
  [[ -n "${TARGET_TYPE:-}" ]] || ssm_die "Missing TARGET_TYPE in ${timer_file}"
  [[ -n "${SCHEDULE:-}" ]] || ssm_die "Missing SCHEDULE in ${timer_file}"
  SSM_TIMER_NAME="$(basename "${timer_file}" .conf)"
}
```

```bash
# scripts/bash/systemd-service-manager/lib/schedule.sh
ssm_resolve_schedule() {
  local schedule="$1"
  case "${schedule}" in
    @hourly) printf 'OnCalendar=hourly\n' ;;
    @daily) printf 'OnCalendar=daily\n' ;;
    @weekly) printf 'OnCalendar=weekly\n' ;;
    @monthly) printf 'OnCalendar=monthly\n' ;;
    @every-5m) printf 'OnBootSec=5m\nOnUnitActiveSec=5m\n' ;;
    @every-15m) printf 'OnBootSec=15m\nOnUnitActiveSec=15m\n' ;;
    @every-1h) printf 'OnBootSec=1h\nOnUnitActiveSec=1h\n' ;;
    *'?'*|*'L'*|*'W'*|*'#'*)
      ssm_die "Unsupported cron syntax: ${schedule}"
      ;;
    *)
      ssm_convert_cron_to_oncalendar "${schedule}"
      ;;
  esac
}
```

- [ ] **Step 5: Add shared CLI option parsing and expose a debug dump path for tests**

```bash
# scripts/bash/systemd-service-manager/lib/cli.sh
ssm_parse_common_flags() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --project)
        [[ "$#" -ge 2 ]] || ssm_die "Missing value for --project"
        SSM_CLI_PROJECT_DIR="$2"
        shift 2
        ;;
      --dry-run)
        SSM_CLI_DRY_RUN=1
        shift
        ;;
      --follow)
        SSM_CLI_FOLLOW=1
        shift
        ;;
      *)
        printf '%s\n' "$@"
        return 0
        ;;
    esac
  done
}
```

```bash
# scripts/bash/systemd-service-manager/commands/list.sh
ssm_cmd_list() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"
  ssm_load_project_config "${project_dir}"

  if [[ "${SSM_DEBUG_DUMP_CONFIG:-}" == "1" ]]; then
    printf 'project=%s\n' "${SSM_PROJECT_NAME}"
    printf 'scope=%s\n' "${SSM_DEFAULT_SCOPE}"
    printf 'APP_PORT=%s\n' "${APP_PORT:-}"
    return 0
  fi
}
```

- [ ] **Step 6: Re-run the focused tests**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/parser.test.ts scripts/bash/systemd-service-manager/tests/schedule.test.ts
```

Expected: PASS for env precedence, missing target validation, and schedule conversion coverage.

- [ ] **Step 7: Commit parsing and schedule support**

```bash
git add scripts/bash/systemd-service-manager
git commit -m "feat(bash): add systemd manager config parsing"
```

## Task 3: Implement `init`, templates, examples, and generated project README

**Files:**
- Create: `scripts/bash/systemd-service-manager/commands/init.sh`
- Create: `scripts/bash/systemd-service-manager/templates/README.md`
- Create: `scripts/bash/systemd-service-manager/templates/project.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/project.env.example`
- Create: `scripts/bash/systemd-service-manager/templates/service.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/service.env.example`
- Create: `scripts/bash/systemd-service-manager/templates/timer-service.conf.example`
- Create: `scripts/bash/systemd-service-manager/templates/timer-task.conf.example`
- Create: `scripts/bash/systemd-service-manager/tests/init.test.ts`
- Modify: `scripts/bash/systemd-service-manager/main.sh`
- Modify: `scripts/bash/systemd-service-manager/build.sh`

- [ ] **Step 1: Write the failing `init` tests**

```ts
// scripts/bash/systemd-service-manager/tests/init.test.ts
import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import { createWorkspace, cleanupWorkspace, runSource, readText } from './test-utils'

describe('init command', () => {
  it('creates deploy/systemd with actual files, examples, and README', async () => {
    const workspace = createWorkspace()
    try {
      const projectRoot = path.join(workspace.root, 'demo-app')
      fs.mkdirSync(projectRoot, { recursive: true })

      const result = await runSource(workspace, ['init', '--project', projectRoot])

      expect(result.exitCode).toBe(0)
      expect(
        fs.existsSync(path.join(projectRoot, 'deploy/systemd/README.md')),
      ).toBe(true)
      expect(
        fs.existsSync(path.join(projectRoot, 'deploy/systemd/project.conf.example')),
      ).toBe(true)
      expect(
        fs.existsSync(path.join(projectRoot, 'deploy/systemd/project.conf')),
      ).toBe(true)
      expect(
        readText(path.join(projectRoot, 'deploy/systemd/README.md')),
      ).toContain('DEFAULT_SCOPE=system')
    } finally {
      cleanupWorkspace(workspace)
    }
  })
})
```

- [ ] **Step 2: Run the `init` test to verify it fails**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/init.test.ts
```

Expected: FAIL because `init` and template copying are not implemented.

- [ ] **Step 3: Add concrete templates for project, service, timer, and project README**

```dotenv
# scripts/bash/systemd-service-manager/templates/project.conf.example
PROJECT_NAME=myapp
UNIT_PREFIX=myapp
DEFAULT_SCOPE=system
DEFAULT_WORKDIR=/opt/myapp
DEFAULT_USER=myapp
DEFAULT_GROUP=myapp
DEFAULT_RESTART=on-failure
DEFAULT_RESTART_SEC=5s
```

```dotenv
# scripts/bash/systemd-service-manager/templates/service.conf.example
DESCRIPTION=My API Service
COMMAND=/usr/bin/env bash -lc 'node server.js'
WORKDIR=/opt/myapp
SCOPE=system
RESTART=always
RESTART_SEC=3s
WANTED_BY=multi-user.target
AFTER=network.target
WANTS=network.target
```

```dotenv
# scripts/bash/systemd-service-manager/templates/timer-service.conf.example
DESCRIPTION=Restart API Every Night
TARGET_TYPE=service
TARGET_NAME=api
ACTION=restart
SCHEDULE=@daily
PERSISTENT=true
RANDOMIZED_DELAY=5m
```

```md
# deploy/systemd README

这个目录存放项目的 systemd service / timer 配置。

## 优先级

1. CLI 参数
2. `<name>.env.local`
3. `<name>.env`
4. `project.env.local`
5. `project.env`
```

- [ ] **Step 4: Implement `init` to copy templates into `deploy/systemd/`**

```bash
# scripts/bash/systemd-service-manager/commands/init.sh
ssm_cmd_init() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"
  local config_root
  config_root="$(ssm_config_root "${project_dir}")"
  local template_root="${SSM_MANAGER_HOME}/templates"

  mkdir -p "${config_root}/services" "${config_root}/timers"

  cp "${template_root}/README.md" "${config_root}/README.md"
  cp "${template_root}/project.conf.example" "${config_root}/project.conf.example"
  cp "${template_root}/project.env.example" "${config_root}/project.env.example"
  cp "${template_root}/project.conf.example" "${config_root}/project.conf"
  cp "${template_root}/project.env.example" "${config_root}/project.env"
  cp "${template_root}/service.conf.example" "${config_root}/services/api.conf.example"
  cp "${template_root}/service.env.example" "${config_root}/services/api.env.example"
  cp "${template_root}/service.conf.example" "${config_root}/services/api.conf"
  cp "${template_root}/service.env.example" "${config_root}/services/api.env"
  cp "${template_root}/timer-service.conf.example" "${config_root}/timers/restart-api.conf.example"
  cp "${template_root}/timer-service.conf.example" "${config_root}/timers/restart-api.conf"
  cp "${template_root}/timer-task.conf.example" "${config_root}/timers/cleanup.conf.example"
  cp "${template_root}/timer-task.conf.example" "${config_root}/timers/cleanup.conf"
}
```

- [ ] **Step 5: Register `init` in the CLI dispatcher**

```bash
# scripts/bash/systemd-service-manager/main.sh
case "${command}" in
  init)
    ssm_cmd_init "$@"
    ;;
  list)
    ssm_cmd_list "$@"
    ;;
```

- [ ] **Step 6: Re-run the `init` test**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/init.test.ts
```

Expected: PASS with generated actual files, examples, and README content.

- [ ] **Step 7: Commit the scaffold/init task**

```bash
git add scripts/bash/systemd-service-manager
git commit -m "feat(bash): add systemd manager init templates"
```

## Task 4: Implement unit rendering, install/uninstall, and `--dry-run`

**Files:**
- Create: `scripts/bash/systemd-service-manager/lib/render-service.sh`
- Create: `scripts/bash/systemd-service-manager/lib/render-timer.sh`
- Create: `scripts/bash/systemd-service-manager/lib/systemd.sh`
- Create: `scripts/bash/systemd-service-manager/commands/install.sh`
- Create: `scripts/bash/systemd-service-manager/commands/uninstall.sh`
- Create: `scripts/bash/systemd-service-manager/tests/install.test.ts`
- Modify: `scripts/bash/systemd-service-manager/main.sh`
- Modify: `scripts/bash/systemd-service-manager/build.sh`

- [ ] **Step 1: Write failing install and dry-run tests**

```ts
// scripts/bash/systemd-service-manager/tests/install.test.ts
import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  installMockCommand,
  runSource,
} from './test-utils'

describe('install command', () => {
  it('prints generated unit names in dry-run mode without writing files', async () => {
    const workspace = createWorkspace()
    try {
      installMockCommand(
        workspace,
        'systemd-analyze',
        '#!/usr/bin/env bash\nexit 0\n',
      )
      const projectRoot = path.join(
        workspace.managerHome,
        'tests',
        'fixtures',
        'project-basic',
      )

      const result = await runSource(workspace, [
        'install',
        'service',
        'api',
        '--project',
        projectRoot,
        '--dry-run',
      ])

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('myapp-api.service')
      expect(fs.readdirSync(workspace.fakeSystemDir)).toHaveLength(0)
    } finally {
      cleanupWorkspace(workspace)
    }
  })

  it('writes service and timer units to the selected scope', async () => {
    const workspace = createWorkspace()
    try {
      installMockCommand(
        workspace,
        'systemd-analyze',
        '#!/usr/bin/env bash\nexit 0\n',
      )
      installMockCommand(
        workspace,
        'systemctl',
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"${SSM_SYSTEMCTL_LOG}"\nexit 0\n',
      )

      const projectRoot = path.join(
        workspace.managerHome,
        'tests',
        'fixtures',
        'project-basic',
      )

      const result = await runSource(workspace, [
        'install',
        'timer',
        'cleanup',
        '--project',
        projectRoot,
      ], {
        SSM_SYSTEMCTL_LOG: path.join(workspace.root, 'systemctl.log'),
      })

      expect(result.exitCode).toBe(0)
      expect(
        fs.existsSync(path.join(workspace.fakeSystemDir, 'myapp-cleanup.timer')),
      ).toBe(true)
      expect(
        fs.existsSync(path.join(workspace.fakeSystemDir, 'myapp-task-cleanup.service')),
      ).toBe(true)
    } finally {
      cleanupWorkspace(workspace)
    }
  })
})
```

- [ ] **Step 2: Run the install test to confirm failure**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/install.test.ts
```

Expected: FAIL because unit rendering, systemd verification, and target directory writes are not implemented.

- [ ] **Step 3: Implement systemd scope resolution and command wrappers**

```bash
# scripts/bash/systemd-service-manager/lib/systemd.sh
ssm_system_unit_dir() {
  printf '%s\n' "${SSM_SYSTEM_UNIT_DIR:-/etc/systemd/system}"
}

ssm_user_unit_dir() {
  printf '%s\n' "${SSM_USER_UNIT_DIR:-${HOME}/.config/systemd/user}"
}

ssm_systemctl() {
  local scope="$1"
  shift
  if [[ "${scope}" == "user" ]]; then
    systemctl --user "$@"
  else
    systemctl "$@"
  fi
}

ssm_daemon_reload() {
  local scope="$1"
  ssm_systemctl "${scope}" daemon-reload
}
```

- [ ] **Step 4: Implement service/timer rendering with managed headers**

```bash
# scripts/bash/systemd-service-manager/lib/render-service.sh
ssm_render_service_unit() {
  local source_file="$1"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION}
${AFTER:+After=${AFTER}}
${WANTS:+Wants=${WANTS}}

[Service]
Type=simple
WorkingDirectory=${WORKDIR}
ExecStart=${COMMAND}
${USER:+User=${USER}}
${GROUP:+Group=${GROUP}}
Restart=${RESTART:-on-failure}
RestartSec=${RESTART_SEC:-5s}

[Install]
WantedBy=${WANTED_BY:-multi-user.target}
EOF
}
```

```bash
# scripts/bash/systemd-service-manager/lib/render-timer.sh
ssm_render_timer_unit() {
  local source_file="$1"
  local schedule_block
  schedule_block="$(ssm_resolve_schedule "${SCHEDULE}")"
  cat <<EOF
# Managed by systemd-service-manager
# Source: ${source_file}
[Unit]
Description=${DESCRIPTION}

[Timer]
${schedule_block}
Persistent=${PERSISTENT:-true}
${RANDOMIZED_DELAY:+RandomizedDelaySec=${RANDOMIZED_DELAY}}

[Install]
WantedBy=timers.target
EOF
}
```

- [ ] **Step 5: Implement `install` and `uninstall` with dry-run and verify**

```bash
# scripts/bash/systemd-service-manager/commands/install.sh
ssm_cmd_install() {
  local target_kind="$1"
  local target_name="$2"
  shift 2 || true

  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"
  local render_dir
  render_dir="$(mktemp -d)"
  trap 'rm -rf "${render_dir}"' EXIT

  ssm_prepare_install_units "${project_dir}" "${target_kind}" "${target_name}" "${render_dir}"
  ssm_verify_rendered_units "${render_dir}"

  if [[ "${SSM_CLI_DRY_RUN:-0}" == "1" ]]; then
    find "${render_dir}" -maxdepth 1 -type f -printf '%f\n' | sort
    return 0
  fi

  ssm_write_rendered_units "${render_dir}" "${SSM_ACTIVE_SCOPE}"
  ssm_daemon_reload "${SSM_ACTIVE_SCOPE}"
}
```

```bash
# scripts/bash/systemd-service-manager/commands/uninstall.sh
ssm_cmd_uninstall() {
  local target_kind="$1"
  local target_name="$2"
  shift 2 || true

  ssm_remove_managed_units "${target_kind}" "${target_name}"
  ssm_daemon_reload "${SSM_ACTIVE_SCOPE}"
}
```

- [ ] **Step 6: Re-run install tests**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/install.test.ts
```

Expected: PASS for dry-run output, rendered files, and daemon reload wrapper behavior.

- [ ] **Step 7: Commit install/uninstall support**

```bash
git add scripts/bash/systemd-service-manager
git commit -m "feat(bash): add systemd manager install flow"
```

## Task 5: Implement `list`, lifecycle commands, `status`, and `logs`

**Files:**
- Create: `scripts/bash/systemd-service-manager/commands/list.sh`
- Create: `scripts/bash/systemd-service-manager/commands/start.sh`
- Create: `scripts/bash/systemd-service-manager/commands/stop.sh`
- Create: `scripts/bash/systemd-service-manager/commands/restart.sh`
- Create: `scripts/bash/systemd-service-manager/commands/status.sh`
- Create: `scripts/bash/systemd-service-manager/commands/logs.sh`
- Create: `scripts/bash/systemd-service-manager/commands/enable.sh`
- Create: `scripts/bash/systemd-service-manager/commands/disable.sh`
- Create: `scripts/bash/systemd-service-manager/tests/lifecycle.test.ts`
- Modify: `scripts/bash/systemd-service-manager/main.sh`
- Modify: `scripts/bash/systemd-service-manager/build.sh`

- [ ] **Step 1: Write failing lifecycle and logging tests**

```ts
// scripts/bash/systemd-service-manager/tests/lifecycle.test.ts
import fs from 'node:fs'
import path from 'node:path'
import { describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  installMockCommand,
  runSource,
  writeText,
} from './test-utils'

describe('lifecycle commands', () => {
  it('routes start/enable/status to systemctl with system scope by default', async () => {
    const workspace = createWorkspace()
    try {
      const systemctlLog = path.join(workspace.root, 'systemctl.log')
      installMockCommand(
        workspace,
        'systemctl',
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"${SSM_SYSTEMCTL_LOG}"\nif [[ "$1" == "is-enabled" ]]; then printf "enabled\\n"; fi\nif [[ "$1" == "is-active" ]]; then printf "active\\n"; fi\nexit 0\n',
      )

      const projectRoot = path.join(
        workspace.managerHome,
        'tests',
        'fixtures',
        'project-basic',
      )

      await runSource(workspace, ['start', 'service', 'api', '--project', projectRoot], {
        SSM_SYSTEMCTL_LOG: systemctlLog,
      })
      await runSource(workspace, ['enable', 'service', 'api', '--project', projectRoot], {
        SSM_SYSTEMCTL_LOG: systemctlLog,
      })
      const status = await runSource(workspace, ['status', 'service', 'api', '--project', projectRoot], {
        SSM_SYSTEMCTL_LOG: systemctlLog,
      })

      expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('start myapp-api.service')
      expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('enable myapp-api.service')
      expect(status.stdout).toContain('installed=')
      expect(status.stdout).toContain('active=active')
    } finally {
      cleanupWorkspace(workspace)
    }
  })

  it('routes logs to journalctl --user for user-scoped services', async () => {
    const workspace = createWorkspace()
    try {
      const journalLog = path.join(workspace.root, 'journalctl.log')
      installMockCommand(
        workspace,
        'journalctl',
        '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"${SSM_JOURNALCTL_LOG}"\nexit 0\n',
      )

      const projectRoot = path.join(
        workspace.managerHome,
        'tests',
        'fixtures',
        'project-basic',
      )

      writeText(
        path.join(projectRoot, 'deploy/systemd/services/user-agent.conf'),
        'DESCRIPTION=User Agent\nCOMMAND=/usr/bin/env bash -lc "sleep 10"\nSCOPE=user\n',
      )

      const result = await runSource(workspace, [
        'logs',
        'service',
        'user-agent',
        '--project',
        projectRoot,
        '--follow',
      ], {
        SSM_JOURNALCTL_LOG: journalLog,
      })

      expect(result.exitCode).toBe(0)
      expect(fs.readFileSync(journalLog, 'utf8')).toContain('--user -u myapp-user-agent.service -f')
    } finally {
      cleanupWorkspace(workspace)
    }
  })
})
```

- [ ] **Step 2: Run the lifecycle tests to verify failure**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/lifecycle.test.ts
```

Expected: FAIL because the lifecycle command wrappers are not implemented yet.

- [ ] **Step 3: Add generic command wrappers for systemctl and journalctl**

```bash
# scripts/bash/systemd-service-manager/lib/systemd.sh
ssm_journalctl() {
  local scope="$1"
  shift
  if [[ "${scope}" == "user" ]]; then
    journalctl --user "$@"
  else
    journalctl "$@"
  fi
}

ssm_unit_name_for_service() {
  printf '%s-%s.service\n' "${UNIT_PREFIX}" "$1"
}

ssm_unit_name_for_timer() {
  printf '%s-%s.timer\n' "${UNIT_PREFIX}" "$1"
}
```

- [ ] **Step 4: Implement `start`, `stop`, `restart`, `enable`, `disable`, `status`, and `logs`**

```bash
# scripts/bash/systemd-service-manager/commands/start.sh
ssm_cmd_start() {
  local target_kind="$1"
  local target_name="$2"
  ssm_load_target_context "${target_kind}" "${target_name}"
  ssm_systemctl "${SSM_ACTIVE_SCOPE}" start "${SSM_ACTIVE_UNIT}"
}
```

```bash
# scripts/bash/systemd-service-manager/commands/status.sh
ssm_cmd_status() {
  local target_kind="$1"
  local target_name="$2"
  ssm_load_target_context "${target_kind}" "${target_name}"

  local enabled_state active_state
  enabled_state="$(ssm_systemctl "${SSM_ACTIVE_SCOPE}" is-enabled "${SSM_ACTIVE_UNIT}" 2>/dev/null || true)"
  active_state="$(ssm_systemctl "${SSM_ACTIVE_SCOPE}" is-active "${SSM_ACTIVE_UNIT}" 2>/dev/null || true)"

  printf 'name=%s\n' "${target_name}"
  printf 'unit=%s\n' "${SSM_ACTIVE_UNIT}"
  printf 'scope=%s\n' "${SSM_ACTIVE_SCOPE}"
  printf 'installed=%s\n' "$(ssm_is_unit_installed "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}")"
  printf 'enabled=%s\n' "${enabled_state:-not-installed}"
  printf 'active=%s\n' "${active_state:-not-installed}"
}
```

```bash
# scripts/bash/systemd-service-manager/commands/logs.sh
ssm_cmd_logs() {
  local target_kind="$1"
  local target_name="$2"
  ssm_load_target_context "${target_kind}" "${target_name}"

  local -a args=(-u "${SSM_ACTIVE_UNIT}")
  if [[ "${SSM_CLI_FOLLOW:-0}" == "1" ]]; then
    args+=(-f)
  fi
  ssm_journalctl "${SSM_ACTIVE_SCOPE}" "${args[@]}"
}
```

- [ ] **Step 5: Implement `list` to show grouped services/timers and install state**

```bash
# scripts/bash/systemd-service-manager/commands/list.sh
ssm_cmd_list() {
  local project_dir
  project_dir="$(ssm_find_project_dir "${SSM_CLI_PROJECT_DIR:-}")"

  printf 'Services\n'
  for service_file in "$(ssm_config_root "${project_dir}")"/services/*.conf; do
    [[ -f "${service_file}" ]] || continue
    local service_name
    service_name="$(basename "${service_file}" .conf)"
    ssm_load_target_context service "${service_name}"
    printf '- %s (%s, installed=%s)\n' \
      "${service_name}" \
      "${SSM_ACTIVE_SCOPE}" \
      "$(ssm_is_unit_installed "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}")"
  done

  printf 'Timers\n'
  for timer_file in "$(ssm_config_root "${project_dir}")"/timers/*.conf; do
    [[ -f "${timer_file}" ]] || continue
    local timer_name
    timer_name="$(basename "${timer_file}" .conf)"
    ssm_load_target_context timer "${timer_name}"
    printf '- %s (%s, installed=%s)\n' \
      "${timer_name}" \
      "${SSM_ACTIVE_SCOPE}" \
      "$(ssm_is_unit_installed "${SSM_ACTIVE_SCOPE}" "${SSM_ACTIVE_UNIT}")"
  done
}
```

- [ ] **Step 6: Re-run lifecycle tests**

Run:

```bash
pnpm vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/lifecycle.test.ts
```

Expected: PASS for system scope command routing, status output, and user-scope logs routing.

- [ ] **Step 7: Commit lifecycle management**

```bash
git add scripts/bash/systemd-service-manager
git commit -m "feat(bash): add systemd manager lifecycle commands"
```

## Task 6: Wire package scripts, root QA, contributor docs, and final verification

**Files:**
- Modify: `package.json`
- Modify: `scripts/qa.mjs`
- Modify: `scripts/qa-turbo.mjs`
- Modify: `scripts/bash/README.md`
- Modify: `scripts/bash/systemd-service-manager/README.md`

- [ ] **Step 1: Add failing package/QA expectations in a lightweight integration check**

```bash
# Use these commands as the expected contract once wiring is in place.
pnpm run test:systemd-service-manager
pnpm run qa:systemd-service-manager
pnpm qa
```

Expected before wiring: FAIL with missing script errors for `test:systemd-service-manager` and `qa:systemd-service-manager`.

- [ ] **Step 2: Add root dev dependency and package scripts**

```json
// package.json
{
  "devDependencies": {
    "execa": "^9.6.1"
  },
  "scripts": {
    "test:systemd-service-manager": "vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts",
    "qa:systemd-service-manager": "pnpm run test:systemd-service-manager"
  }
}
```

- [ ] **Step 3: Extend `scripts/qa.mjs` to run the new root QA slice**

```js
function runRootSystemdManagerQa(modeValue, sinceRef) {
  const pathspecs = ['scripts/bash/systemd-service-manager', 'package.json']

  if (modeValue === 'all') {
    console.log('[qa] run root qa:systemd-service-manager (all)')
    runPnpm('root-qa-systemd-service-manager-all', ['run', 'qa:systemd-service-manager'])
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[qa] skip root qa:systemd-service-manager (no changes)')
    return
  }

  console.log('[qa] run root qa:systemd-service-manager (changed)')
  runPnpm('root-qa-systemd-service-manager-changed', ['run', 'qa:systemd-service-manager'])
}

runWorkspaceQa(mode, sinceRef)
runRootPwshQa(mode, sinceRef)
runRootFnosQa(mode, sinceRef)
runRootSystemdManagerQa(mode, sinceRef)
```

- [ ] **Step 4: Extend `scripts/qa-turbo.mjs` with the same root QA slice**

```js
function runRootSystemdManagerQa(modeValue, sinceRef) {
  const pathspecs = ['scripts/bash/systemd-service-manager', 'package.json']

  if (modeValue === 'all') {
    console.log('[turbo:qa] run root qa:systemd-service-manager (all)')
    const pnpmCommand = buildPnpmCommand(['run', 'qa:systemd-service-manager'])
    runCommand('root-qa-systemd-service-manager-all', pnpmCommand.command, pnpmCommand.args)
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[turbo:qa] skip root qa:systemd-service-manager (no changes)')
    return
  }

  console.log('[turbo:qa] run root qa:systemd-service-manager (changed)')
  const pnpmCommand = buildPnpmCommand(['run', 'qa:systemd-service-manager'])
  runCommand('root-qa-systemd-service-manager-changed', pnpmCommand.command, pnpmCommand.args)
}
```

- [ ] **Step 5: Update contributor-facing Bash docs**

```md
<!-- scripts/bash/README.md -->
## systemd-service-manager

用于按项目目录管理 systemd `service` / `timer`，支持：

- `init` 生成 `deploy/systemd/` 骨架
- `install` 渲染并写入 systemd unit
- `start/stop/restart/status/logs` 做基础运维
- `system` / `user` 两种 scope
```

~~~md
<!-- scripts/bash/systemd-service-manager/README.md -->
## Test

```bash
pnpm run test:systemd-service-manager
```

## Quality Gate

```bash
pnpm run qa:systemd-service-manager
pnpm qa
```
~~~

- [ ] **Step 6: Run the full verification commands**

Run:

```bash
pnpm run test:systemd-service-manager
pnpm run qa:systemd-service-manager
pnpm qa
```

Expected:

- `pnpm run test:systemd-service-manager` PASS
- `pnpm run qa:systemd-service-manager` PASS
- `pnpm qa` PASS and include the new `root qa:systemd-service-manager` slice when relevant

- [ ] **Step 7: Commit package/QA/docs wiring**

```bash
git add package.json scripts/qa.mjs scripts/qa-turbo.mjs scripts/bash/README.md scripts/bash/systemd-service-manager/README.md
git commit -m "test: wire systemd manager into root qa"
```

## Spec Coverage Check

- 项目目录多服务/多定时任务模型：Task 2, Task 3, Task 5
- 默认 `system` 且支持 `user`：Task 2, Task 4, Task 5
- `.conf` / `.env` 与 `.env.local > .env`：Task 2
- `build.sh` 产出单文件脚本：Task 1
- `init`、`README.md`、`*.example`：Task 3
- `install/uninstall` 与 `--dry-run`：Task 4
- `list/start/stop/restart/status/logs/enable/disable`：Task 5
- 别名与 cron 调度：Task 2, Task 4
- `vitest + execa`：Task 1, Task 6
- root `pnpm qa` 接入：Task 6

## Placeholder Scan

- 本计划不使用 `TODO`、`TBD`、`later` 等占位词。
- 每个任务都给出具体文件、具体测试入口和具体命令。
- 所有后续步骤中使用的核心名称在前文已固定：`systemd-service-manager`、`deploy/systemd/`、`test:systemd-service-manager`、`qa:systemd-service-manager`。

## Type and Naming Consistency

- 工具名统一为 `systemd-service-manager`
- 项目配置根目录统一为 `deploy/systemd/`
- 根级测试命令统一为 `test:systemd-service-manager`
- 根级 QA 命令统一为 `qa:systemd-service-manager`
- scope 统一为 `system` / `user`
- 调度解析入口统一为 `ssm_resolve_schedule`

## Final Verification Checklist

- `bash scripts/bash/systemd-service-manager/build.sh`
- `bash scripts/bash/systemd-service-manager/main.sh help`
- `bash scripts/bash/systemd-service-manager.sh help`
- `pnpm run test:systemd-service-manager`
- `pnpm qa`
