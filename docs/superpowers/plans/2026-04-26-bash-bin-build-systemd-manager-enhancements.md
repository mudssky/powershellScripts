# Bash Bin Build 与 systemd-service-manager 增强 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 补齐 Bash 工具统一构建入口，并增强 `systemd-service-manager` 的 `list`、`restart` 与 retry 能力。

**Architecture:** `Manage-BinScripts.ps1` 继续只管理 `.ps1` / `.py` shim；新增 `scripts/bash/build.sh` 作为 Bash 工具构建入口，支持 `build` 与 `copy` 两类目标，并由 `install.ps1` 调用。`systemd-service-manager` 保持现有模块边界：命令层处理 CLI 输出，parser 层校验配置，render 层生成 unit。

**Tech Stack:** Bash, PowerShell, Vitest, Pester, systemd unit 文本渲染

---

## Planned File Map

- Create: `scripts/bash/build.sh`  
  Bash 工具统一构建入口，负责参数解析、目标清单、并发调度、日志摘要、单文件复制。
- Create: `scripts/bash/vitest.config.ts`  
  `scripts/bash` 根级 Vitest 配置，用于测试统一 Bash 构建入口。
- Create: `scripts/bash/tests/bash-build.test.ts`  
  覆盖 `--list`、`--jobs` 日志、copy 目标、失败摘要。
- Modify: `package.json`  
  增加 `test:bash` / `qa:bash` 脚本。
- Modify: `scripts/qa.mjs` and `scripts/qa-turbo.mjs`  
  在根 QA 中按 `scripts/bash/build.sh`、`scripts/bash/tests`、`scripts/bash/aliyun-oss-put.sh` 变更触发 `qa:bash`。
- Modify: `install.ps1`  
  增加 `Install-BashScripts`，在同步 `.ps1/.py` shim 后调用 `scripts/bash/build.sh`。
- Create: `tests/Install.Tests.ps1`  
  用临时项目和 mock 命令验证 `install.ps1` 会调用 Bash 构建入口。
- Modify: `scripts/bash/systemd-service-manager/commands/list.sh`  
  输出 service/timer 摘要，并支持 `--json`。
- Modify: `scripts/bash/systemd-service-manager/lib/cli.sh`  
  补充 `restart` 示例和 `list --json` help。
- Modify: `scripts/bash/systemd-service-manager/lib/parser-timer.sh`  
  校验 `RETRY_ATTEMPTS` / `RETRY_DELAY_SEC`，并禁止 service-target timer 使用 retry。
- Modify: `scripts/bash/systemd-service-manager/lib/render-service.sh`  
  为 timer task 渲染可选 retry wrapper。
- Modify: `scripts/bash/systemd-service-manager/lib/validate.sh`  
  增加整数校验 helper。
- Modify: `scripts/bash/systemd-service-manager/templates/timer-task.conf.example`  
  增加 retry 示例字段，保持默认注释或空值不启用。
- Modify: `scripts/bash/systemd-service-manager/README.md` and `scripts/bash/README.md`  
  记录统一构建入口、`list --json`、`restart` 和 retry 字段。
- Modify: `scripts/bash/systemd-service-manager/tests/*.test.ts`  
  增加 list、restart、retry 回归测试。

## Task 1: Bash Build Entry

**Files:**
- Create: `scripts/bash/build.sh`
- Create: `scripts/bash/vitest.config.ts`
- Create: `scripts/bash/tests/bash-build.test.ts`
- Modify: `package.json`
- Modify: `scripts/qa.mjs`
- Modify: `scripts/qa-turbo.mjs`

- [ ] **Step 1: Write failing Vitest coverage for `scripts/bash/build.sh`**

Create `scripts/bash/tests/bash-build.test.ts` with these test cases:

```ts
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  buildScript: string
  binDir: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')

function writeText(filePath: string, content: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content, 'utf8')
}

function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bash-build-'))
  const buildScript = path.join(root, 'scripts/bash/build.sh')
  const binDir = path.join(root, 'bin')

  fs.mkdirSync(path.dirname(buildScript), { recursive: true })
  fs.copyFileSync(path.join(repoRoot, 'scripts/bash/build.sh'), buildScript)
  fs.chmodSync(buildScript, 0o755)

  writeText(
    path.join(root, 'scripts/bash/systemd-service-manager/build.sh'),
    [
      '#!/usr/bin/env bash',
      'set -Eeuo pipefail',
      'mkdir -p "$(cd "$(dirname "$0")/../../.." && pwd)/bin"',
      'printf "#!/usr/bin/env bash\\necho ssm\\n" >"$(cd "$(dirname "$0")/../../.." && pwd)/bin/systemd-service-manager"',
      'chmod +x "$(cd "$(dirname "$0")/../../.." && pwd)/bin/systemd-service-manager"',
      'printf "fake systemd build complete\\n"',
      '',
    ].join('\n'),
  )
  fs.chmodSync(path.join(root, 'scripts/bash/systemd-service-manager/build.sh'), 0o755)

  writeText(
    path.join(root, 'scripts/bash/aliyun-oss-put.sh'),
    ['#!/usr/bin/env bash', 'printf "aliyun\\n"', ''].join('\n'),
  )

  return { root, buildScript, binDir }
}

async function runBuild(workspace: Workspace, args: string[] = []) {
  return execa('bash', [workspace.buildScript, ...args], {
    cwd: workspace.root,
    reject: false,
  })
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

describe('scripts/bash/build.sh', () => {
  it('lists build and copy targets with stable metadata', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--list'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('name=systemd-service-manager')
    expect(result.stdout).toContain('type=build')
    expect(result.stdout).toContain('source=scripts/bash/systemd-service-manager/build.sh')
    expect(result.stdout).toContain('output=<managed-by-target-build>')
    expect(result.stdout).toContain('name=aliyun-oss-put')
    expect(result.stdout).toContain('type=copy')
    expect(result.stdout).toContain('source=scripts/bash/aliyun-oss-put.sh')
    expect(result.stdout).toContain('output=bin/aliyun-oss-put')
  })

  it('copies single-file shell scripts into bin without the .sh suffix', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--only', 'aliyun-oss-put'])

    expect(result.exitCode).toBe(0)
    const outputPath = path.join(workspace.binDir, 'aliyun-oss-put')
    expect(fs.existsSync(outputPath)).toBe(true)
    expect(fs.readFileSync(outputPath, 'utf8')).toContain('printf "aliyun')
    expect(fs.statSync(outputPath).mode & 0o111).not.toBe(0)
    expect(result.stdout).toContain('args=--only aliyun-oss-put')
    expect(result.stdout).toContain('ACTION aliyun-oss-put copy source -> bin/aliyun-oss-put')
    expect(result.stdout).toContain('SUMMARY total=1 success=1 failed=0 skipped=0')
  })

  it('runs build targets and prints parsed jobs and task summaries', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--jobs', '1'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('args=--jobs 1')
    expect(result.stdout).toContain('jobs=1 source=--jobs')
    expect(result.stdout).toContain('targets=2')
    expect(result.stdout).toContain('START systemd-service-manager type=build')
    expect(result.stdout).toContain('ACTION systemd-service-manager run build.sh')
    expect(result.stdout).toContain('DONE systemd-service-manager exit=0')
    expect(result.stdout).toContain('START aliyun-oss-put type=copy')
    expect(result.stdout).toContain('SUMMARY total=2 success=2 failed=0 skipped=0')
    expect(fs.existsSync(path.join(workspace.binDir, 'systemd-service-manager'))).toBe(true)
    expect(fs.existsSync(path.join(workspace.binDir, 'aliyun-oss-put'))).toBe(true)
  })

  it('returns non-zero with a failure summary for invalid targets', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    fs.rmSync(path.join(workspace.root, 'scripts/bash/aliyun-oss-put.sh'))

    const result = await runBuild(workspace, ['--only', 'aliyun-oss-put'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stdout + result.stderr).toContain('FAIL aliyun-oss-put')
    expect(result.stdout + result.stderr).toContain('SUMMARY total=1 success=0 failed=1 skipped=0')
    expect(result.stdout + result.stderr).toContain('log=')
  })
})
```

- [ ] **Step 2: Add the root Bash Vitest config**

Create `scripts/bash/vitest.config.ts`:

```ts
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

- [ ] **Step 3: Run tests and verify they fail before implementation**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/vitest.config.ts
```

Expected: FAIL because `scripts/bash/build.sh` does not exist yet.

- [ ] **Step 4: Implement `scripts/bash/build.sh`**

Create `scripts/bash/build.sh` with this structure:

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# 统一构建 scripts/bash 下的 Bash 工具。
# 支持两种目标：调用子目录 build.sh，或复制单文件 .sh 到 bin。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BIN_DIR="${REPO_ROOT}/bin"

BASH_BUILD_TARGETS=(
  "build:systemd-service-manager:scripts/bash/systemd-service-manager/build.sh:<managed-by-target-build>"
  "copy:aliyun-oss-put:scripts/bash/aliyun-oss-put.sh:bin/aliyun-oss-put"
)

bb_log() {
  local level="$1"
  shift
  printf '[bash-build][%s] %s\n' "${level}" "$*"
}

bb_die() {
  bb_log "error" "$*" >&2
  exit 1
}

bb_usage() {
  cat <<'EOF'
Usage: scripts/bash/build.sh [--jobs <n>] [--list] [--only <name>]

Options:
  --jobs <n>     限制并发构建数，必须大于 0
  --list         列出构建目标，不执行构建
  --only <name>  只构建指定目标
  -h, --help     显示帮助
EOF
}

bb_cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN 2>/dev/null || printf '1\n'
    return 0
  fi
  printf '1\n'
}

bb_is_positive_integer() {
  [[ "${1:-}" =~ ^[1-9][0-9]*$ ]]
}

bb_parse_args() {
  BB_LIST=0
  BB_ONLY=""
  BB_JOBS=""
  BB_JOBS_SOURCE="cpu"
  BB_RAW_ARGS="$*"

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --jobs)
        [[ "$#" -ge 2 ]] || bb_die "Missing value for --jobs; args=${BB_RAW_ARGS}"
        BB_JOBS="$2"
        BB_JOBS_SOURCE="--jobs"
        shift 2
        ;;
      --list)
        BB_LIST=1
        shift
        ;;
      --only)
        [[ "$#" -ge 2 ]] || bb_die "Missing value for --only; args=${BB_RAW_ARGS}"
        BB_ONLY="$2"
        shift 2
        ;;
      -h | --help)
        bb_usage
        exit 0
        ;;
      *)
        bb_die "Unknown argument: $1; args=${BB_RAW_ARGS}"
        ;;
    esac
  done

  if [[ -z "${BB_JOBS}" && -n "${BASH_BUILD_JOBS:-}" ]]; then
    BB_JOBS="${BASH_BUILD_JOBS}"
    BB_JOBS_SOURCE="BASH_BUILD_JOBS"
  fi
}

bb_select_targets() {
  BB_SELECTED_TARGETS=()
  local target type name source output matched=0
  for target in "${BASH_BUILD_TARGETS[@]}"; do
    IFS=':' read -r type name source output <<<"${target}"
    if [[ -n "${BB_ONLY}" && "${name}" != "${BB_ONLY}" ]]; then
      continue
    fi
    matched=1
    BB_SELECTED_TARGETS+=("${target}")
  done

  if [[ -n "${BB_ONLY}" && "${matched}" -eq 0 ]]; then
    bb_die "Unknown target: ${BB_ONLY}"
  fi
}

bb_resolve_jobs() {
  local task_count="$1"
  if [[ "${task_count}" -le 0 ]]; then
    BB_EFFECTIVE_JOBS=1
    return 0
  fi

  if [[ -z "${BB_JOBS}" ]]; then
    BB_JOBS="$(bb_cpu_count)"
    BB_JOBS_SOURCE="cpu"
  fi

  bb_is_positive_integer "${BB_JOBS}" || bb_die "Invalid jobs value: ${BB_JOBS}; args=${BB_RAW_ARGS}"
  BB_EFFECTIVE_JOBS="${BB_JOBS}"
  if [[ "${BB_EFFECTIVE_JOBS}" -gt "${task_count}" ]]; then
    BB_EFFECTIVE_JOBS="${task_count}"
  fi
  [[ "${BB_EFFECTIVE_JOBS}" -ge 1 ]] || BB_EFFECTIVE_JOBS=1
}

bb_list_targets() {
  local target type name source output
  for target in "${BB_SELECTED_TARGETS[@]}"; do
    IFS=':' read -r type name source output <<<"${target}"
    printf 'name=%s\n' "${name}"
    printf 'type=%s\n' "${type}"
    printf 'source=%s\n' "${source}"
    printf 'output=%s\n' "${output}"
    printf '\n'
  done
}

bb_run_target() {
  local target="$1"
  local log_file="$2"
  local type name source output source_path output_path start_time end_time duration
  IFS=':' read -r type name source output <<<"${target}"
  source_path="${REPO_ROOT}/${source}"
  output_path="${REPO_ROOT}/${output}"
  start_time="$(date +%s)"

  printf 'START %s type=%s source=%s\n' "${name}" "${type}" "${source}"

  local exit_code=0
  set +e
  case "${type}" in
    build)
      printf 'ACTION %s run build.sh\n' "${name}"
      if [[ ! -f "${source_path}" ]]; then
        bb_log "error" "Missing build script: ${source}" >"${log_file}" 2>&1
        exit_code=1
      else
        bash "${source_path}" >"${log_file}" 2>&1
        exit_code=$?
      fi
      ;;
    copy)
      printf 'ACTION %s copy source -> %s\n' "${name}" "${output}"
      if [[ ! -f "${source_path}" ]]; then
        bb_log "error" "Missing shell script: ${source}" >"${log_file}" 2>&1
        exit_code=1
      elif [[ "${source_path}" != *.sh ]]; then
        bb_log "error" "Copy target must be .sh: ${source}" >"${log_file}" 2>&1
        exit_code=1
      else
        {
          mkdir -p "$(dirname "${output_path}")"
          cp "${source_path}" "${output_path}"
          chmod 0755 "${output_path}"
        } >"${log_file}" 2>&1
        exit_code=$?
      fi
      ;;
    *)
      bb_log "error" "Unknown target type: ${type}" >"${log_file}" 2>&1
      exit_code=1
      ;;
  esac
  set -e

  end_time="$(date +%s)"
  duration=$((end_time - start_time))
  if [[ "${exit_code}" -eq 0 ]]; then
    printf 'DONE %s exit=0 duration=%ss output=%s log=%s\n' "${name}" "${duration}" "${output}" "${log_file}"
  else
    printf 'FAIL %s exit=%s duration=%ss log=%s\n' "${name}" "${exit_code}" "${duration}" "${log_file}"
  fi
  return "${exit_code}"
}

bb_main() {
  bb_parse_args "$@"
  bb_select_targets
  bb_resolve_jobs "${#BB_SELECTED_TARGETS[@]}"

  local log_dir
  log_dir="$(mktemp -d)"
  bb_log "info" "args=${BB_RAW_ARGS:-<none>}"
  bb_log "info" "repo=${REPO_ROOT}"
  bb_log "info" "bin=${BIN_DIR}"
  bb_log "info" "logs=${log_dir}"
  bb_log "info" "list=$([[ ${BB_LIST} -eq 1 ]] && printf true || printf false) only=${BB_ONLY:-all}"
  bb_log "info" "jobs=${BB_EFFECTIVE_JOBS} source=${BB_JOBS_SOURCE}"
  bb_log "info" "targets=${#BB_SELECTED_TARGETS[@]}"

  if [[ "${BB_LIST}" -eq 1 ]]; then
    bb_list_targets
    return 0
  fi

  local success=0 failed=0 skipped=0 target name log_file result_file
  local -a pids=() result_files=()

  for target in "${BB_SELECTED_TARGETS[@]}"; do
    IFS=':' read -r _ name _ _ <<<"${target}"
    log_file="${log_dir}/${name}.log"
    result_file="${log_dir}/${name}.result"
    (bb_run_target "${target}" "${log_file}" >"${result_file}") &
    pids+=("$!")
    result_files+=("${result_file}")

    if [[ "${#pids[@]}" -ge "${BB_EFFECTIVE_JOBS}" ]]; then
      if wait "${pids[0]}"; then success=$((success + 1)); else failed=$((failed + 1)); fi
      cat "${result_files[0]}"
      pids=("${pids[@]:1}")
      result_files=("${result_files[@]:1}")
    fi
  done

  local index=0
  while [[ "${index}" -lt "${#pids[@]}" ]]; do
    if wait "${pids[${index}]}"; then success=$((success + 1)); else failed=$((failed + 1)); fi
    cat "${result_files[${index}]}"
    index=$((index + 1))
  done

  printf 'SUMMARY total=%s success=%s failed=%s skipped=%s\n' "${#BB_SELECTED_TARGETS[@]}" "${success}" "${failed}" "${skipped}"
  [[ "${failed}" -eq 0 ]]
}

bb_main "$@"
```

- [ ] **Step 5: Wire package scripts**

Modify `package.json` scripts:

```json
"test:bash": "vitest run --config ./scripts/bash/vitest.config.ts",
"qa:bash": "pnpm run test:bash",
```

- [ ] **Step 6: Wire root QA path triggers**

In `scripts/qa.mjs`, add `runRootBashQa(mode, sinceRef)` after `runRootFnosQa`:

```js
function runRootBashQa(modeValue, sinceRef) {
  if (!shouldRunLinuxOnlyQa()) {
    console.log(
      `[qa] skip root qa:bash (linux only, current platform: ${process.platform})`,
    )
    return
  }

  const pathspecs = [
    'scripts/bash/build.sh',
    'scripts/bash/tests',
    'scripts/bash/vitest.config.ts',
    'scripts/bash/aliyun-oss-put.sh',
    'package.json',
  ]

  if (modeValue === 'all') {
    console.log('[qa] run root qa:bash (all)')
    runPnpm('root-qa-bash-all', ['run', 'qa:bash'])
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[qa] skip root qa:bash (no changes)')
    return
  }

  console.log('[qa] run root qa:bash (changed)')
  runPnpm('root-qa-bash-changed', ['run', 'qa:bash'])
}
```

Call it before `runRootSystemdServiceManagerQa(mode, sinceRef)`.

Make the equivalent change in `scripts/qa-turbo.mjs` using `buildPnpmCommand(['run', 'qa:bash'])` and `runCommand(...)`, matching the existing `runRootFnosQa` style.

- [ ] **Step 7: Run Bash build tests**

Run:

```bash
pnpm run qa:bash
```

Expected: PASS.

- [ ] **Step 8: Commit Task 1**

```bash
git add package.json scripts/qa.mjs scripts/qa-turbo.mjs scripts/bash/build.sh scripts/bash/vitest.config.ts scripts/bash/tests/bash-build.test.ts
git commit -m "feat(bash): 添加统一构建入口"
```

## Task 2: install.ps1 Integration

**Files:**
- Modify: `install.ps1`
- Create: `tests/Install.Tests.ps1`

- [ ] **Step 1: Write failing Pester coverage for Bash build invocation**

Create `tests/Install.Tests.ps1`:

```powershell
Set-StrictMode -Version Latest

Describe 'install.ps1' {
    BeforeEach {
        $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
        $script:TempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("Install.Tests.{0}" -f [System.Guid]::NewGuid())
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null

        Copy-Item -Path (Join-Path $script:ProjectRoot 'install.ps1') -Destination (Join-Path $script:TempRoot 'install.ps1') -Force

        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'scripts/bash') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'bin') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:TempRoot 'mock-bin') -Force | Out-Null

        Set-Content -Path (Join-Path $script:TempRoot 'Manage-BinScripts.ps1') -Value @'
param([string]$Action, [switch]$Force)
"Action=$Action Force=$Force" | Set-Content -Path (Join-Path $PSScriptRoot 'manage-called.log') -Encoding utf8NoBOM
'@ -Encoding utf8NoBOM

        Set-Content -Path (Join-Path $script:TempRoot 'scripts/bash/build.sh') -Value @'
#!/usr/bin/env bash
printf "%s\n" "$*" >"$(cd "$(dirname "$0")/../.." && pwd)/bash-build-called.log"
'@ -Encoding utf8NoBOM

        Set-Content -Path (Join-Path $script:TempRoot 'mock-bin/bash') -Value @'
#!/bin/sh
printf "%s\n" "$*" >"${INSTALL_TEST_BASH_LOG}"
exit 0
'@ -Encoding utf8NoBOM
        Set-Content -Path (Join-Path $script:TempRoot 'mock-bin/nbstripout') -Value "#!/bin/sh`nexit 0`n" -Encoding utf8NoBOM

        if (-not $IsWindows) {
            chmod +x (Join-Path $script:TempRoot 'mock-bin/bash')
            chmod +x (Join-Path $script:TempRoot 'mock-bin/nbstripout')
            chmod +x (Join-Path $script:TempRoot 'scripts/bash/build.sh')
        }

        $script:OriginalPath = $env:PATH
        $env:PATH = (Join-Path $script:TempRoot 'mock-bin') + [IO.Path]::PathSeparator + $env:PATH
    }

    AfterEach {
        $env:PATH = $script:OriginalPath
        if ($script:TempRoot -and (Test-Path -LiteralPath $script:TempRoot)) {
            Remove-Item -LiteralPath $script:TempRoot -Recurse -Force
        }
    }

    It 'invokes scripts/bash/build.sh during default install flow' {
        $bashLog = Join-Path $script:TempRoot 'bash-command.log'
        $env:INSTALL_TEST_BASH_LOG = $bashLog

        $result = pwsh -NoProfile -File (Join-Path $script:TempRoot 'install.ps1') 2>&1

        $LASTEXITCODE | Should -Be 0
        Test-Path -LiteralPath (Join-Path $script:TempRoot 'manage-called.log') | Should -BeTrue
        Test-Path -LiteralPath $bashLog | Should -BeTrue
        (Get-Content -LiteralPath $bashLog -Raw) | Should -Match 'scripts[/\\]bash[/\\]build\.sh'
        ($result | Out-String) | Should -Match 'Bash'
    }
}
```

- [ ] **Step 2: Run the focused Pester test and verify failure**

Run:

```bash
pwsh -NoProfile -Command "$env:PWSH_TEST_PATH='./tests/Install.Tests.ps1'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c"
```

Expected: FAIL because `install.ps1` does not call `scripts/bash/build.sh` yet.

- [ ] **Step 3: Add `Install-BashScripts` to `install.ps1`**

Insert this function after `Install-NodeScripts`:

```powershell
function Install-BashScripts {
    <#
    .SYNOPSIS
        构建 scripts/bash 下的 Bash 工具。

    .DESCRIPTION
        调用 scripts/bash/build.sh 统一刷新 Bash 单文件产物与构建型产物。

    .PARAMETER RootPath
        仓库根目录。

    .OUTPUTS
        System.Boolean。成功执行或无需执行时返回 $true；构建失败返回 $false。
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $bashBuildScript = Join-Path $RootPath 'scripts/bash/build.sh'
    if (-not (Test-Path -LiteralPath $bashBuildScript -PathType Leaf)) {
        Write-Warning "未找到 Bash 构建脚本: $bashBuildScript"
        return $true
    }

    if (-not (Get-Command 'bash' -ErrorAction SilentlyContinue)) {
        if ($IsWindows) {
            Write-Warning "未找到 bash，跳过 Bash 工具构建。"
            return $true
        }

        Write-Error "未找到 bash，无法构建 Bash 工具。"
        return $false
    }

    Write-Host "`n=== 开始构建 Bash 脚本工具集 ===" -ForegroundColor Magenta
    & bash $bashBuildScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bash 脚本工具集构建失败，退出码: $LASTEXITCODE"
        return $false
    }

    Write-Host "✓ Bash 脚本工具集构建完成" -ForegroundColor Green
    return $true
}
```

After the `Manage-BinScripts.ps1` sync block, call:

```powershell
if (-not (Install-BashScripts -RootPath $ProjectRoot)) {
    exit 1
}
```

- [ ] **Step 4: Update install script help text**

In `install.ps1` `.DESCRIPTION`, add:

```text
    4. 构建 scripts/bash 下的 Bash 工具集。
```

Renumber the following item for Node scripts.

- [ ] **Step 5: Run the focused Pester test**

Run:

```bash
pwsh -NoProfile -Command "$env:PWSH_TEST_PATH='./tests/Install.Tests.ps1'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c"
```

Expected: PASS.

- [ ] **Step 6: Commit Task 2**

```bash
git add install.ps1 tests/Install.Tests.ps1
git commit -m "feat(install): 接入 Bash 统一构建"
```

## Task 3: systemd-service-manager List Output

**Files:**
- Modify: `scripts/bash/systemd-service-manager/commands/list.sh`
- Modify: `scripts/bash/systemd-service-manager/lib/cli.sh`
- Create: `scripts/bash/systemd-service-manager/tests/list.test.ts`

- [ ] **Step 1: Write failing list tests**

Create `scripts/bash/systemd-service-manager/tests/list.test.ts`:

```ts
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { cleanupWorkspace, createWorkspace, runSource } from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('list command', () => {
  it('prints service and timer summaries with commands and schedules', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const projectRoot = path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic')

    const result = await runSource(workspace, ['list', '--project', projectRoot])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('Services')
    expect(result.stdout).toContain("- api | scope=system | restart=always/3s | command=/usr/bin/env bash -lc 'node server.js'")
    expect(result.stdout).toContain('Timers')
    expect(result.stdout).toContain('- cleanup | scope=system | schedule=0 3 * * * | target=task | command=/usr/bin/find /tmp/myapp -type f -mtime +7 -delete')
    expect(result.stdout).toContain('- restart-api | scope=system | schedule=@daily | target=service:api | action=restart')
  })

  it('prints stable JSON with null fields for missing values', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const projectRoot = path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic')

    const result = await runSource(workspace, ['list', '--project', projectRoot, '--json'])

    expect(result.exitCode).toBe(0)
    const items = JSON.parse(result.stdout)
    expect(items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: 'service',
          name: 'api',
          scope: 'system',
          command: "/usr/bin/env bash -lc 'node server.js'",
          restart: 'always',
          restartSec: '3s',
          schedule: null,
          targetType: null,
          targetName: null,
          action: null,
        }),
        expect.objectContaining({
          type: 'timer',
          name: 'cleanup',
          scope: 'system',
          command: '/usr/bin/find /tmp/myapp -type f -mtime +7 -delete',
          schedule: '0 3 * * *',
          targetType: 'task',
          targetName: null,
          action: null,
        }),
      ]),
    )
  })
})
```

- [ ] **Step 2: Run list tests and verify failure**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/list.test.ts
```

Expected: FAIL because `list` does not print command details or JSON yet.

- [ ] **Step 3: Implement JSON escaping and item emitters in `list.sh`**

Replace the current body of `scripts/bash/systemd-service-manager/commands/list.sh` with helpers that:

```bash
ssm_list_json_escape() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

ssm_json_value() {
  local value="${1-}"
  if [[ -z "${value}" ]]; then
    printf 'null'
  else
    printf '"%s"' "$(ssm_list_json_escape "${value}")"
  fi
}
```

Use arrays for JSON object strings:

```bash
SSM_LIST_JSON_ITEMS+=("{\"type\":\"service\",\"name\":$(ssm_json_value "${service_name}"),\"scope\":$(ssm_json_value "${SSM_SERVICE_SCOPE}"),\"command\":$(ssm_json_value "${COMMAND:-}"),\"restart\":$(ssm_json_value "${RESTART:-on-failure}"),\"restartSec\":$(ssm_json_value "${RESTART_SEC:-5s}"),\"schedule\":null,\"targetType\":null,\"targetName\":null,\"action\":null}")
```

For text output, service rows must follow:

```bash
printf -- '- %s | scope=%s | restart=%s/%s | command=%s\n' \
  "${service_name}" "${SSM_SERVICE_SCOPE}" "${RESTART:-on-failure}" "${RESTART_SEC:-5s}" "${COMMAND:-}"
```

Timer rows must use:

```bash
if [[ "${TARGET_TYPE}" == "service" ]]; then
  printf -- '- %s | scope=%s | schedule=%s | target=service:%s | action=%s\n' \
    "${timer_name}" "${SSM_TIMER_SCOPE}" "${SCHEDULE}" "${TARGET_NAME}" "${ACTION:-restart}"
else
  printf -- '- %s | scope=%s | schedule=%s | target=task | command=%s\n' \
    "${timer_name}" "${SSM_TIMER_SCOPE}" "${SCHEDULE}" "${COMMAND:-}"
fi
```

Parse `--json` inside `ssm_cmd_list` before loading configs:

```bash
local output_json=0
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --json)
      output_json=1
      shift
      ;;
    *)
      ssm_die "Unknown list option: $1"
      ;;
  esac
done
```

- [ ] **Step 4: Update help text**

In `scripts/bash/systemd-service-manager/lib/cli.sh`, update list help line:

```text
  list       列出当前项目中声明的 services 与 timers，可配合 --json
```

Add example:

```text
  systemd-service-manager list --project /path/to/app --json
```

- [ ] **Step 5: Run list tests**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/list.test.ts
```

Expected: PASS.

- [ ] **Step 6: Commit Task 3**

```bash
git add scripts/bash/systemd-service-manager/commands/list.sh scripts/bash/systemd-service-manager/lib/cli.sh scripts/bash/systemd-service-manager/tests/list.test.ts
git commit -m "feat(systemd): 增强 list 输出"
```

## Task 4: Restart Regression and Docs

**Files:**
- Modify: `scripts/bash/systemd-service-manager/lib/cli.sh`
- Modify: `scripts/bash/systemd-service-manager/README.md`
- Modify: `scripts/bash/systemd-service-manager/tests/lifecycle.test.ts`
- Modify: `scripts/bash/systemd-service-manager/tests/manager-cli.test.ts`

- [ ] **Step 1: Add failing restart regression tests**

Append to `scripts/bash/systemd-service-manager/tests/lifecycle.test.ts`:

```ts
it('routes restart with inferred and explicit target kinds', async () => {
  const workspace = createWorkspace()
  workspaces.push(workspace)

  const systemctlLog = path.join(workspace.root, 'systemctl.log')
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

  const inferred = await runSource(workspace, ['restart', 'api', '--project', projectRoot], {
    SSM_TEST_EUID: '0',
    SSM_SYSTEMCTL_LOG: systemctlLog,
  })
  const explicit = await runSource(
    workspace,
    ['restart', 'timer', 'cleanup', '--project', projectRoot],
    {
      SSM_TEST_EUID: '0',
      SSM_SYSTEMCTL_LOG: systemctlLog,
    },
  )

  const logText = fs.readFileSync(systemctlLog, 'utf8')
  expect(inferred.exitCode).toBe(0)
  expect(explicit.exitCode).toBe(0)
  expect(logText).toContain('restart myapp-api.service')
  expect(logText).toContain('restart myapp-cleanup.timer')
  expect(inferred.stdout).toContain('restarted=myapp-api.service')
  expect(explicit.stdout).toContain('restarted=myapp-cleanup.timer')
})
```

In `scripts/bash/systemd-service-manager/tests/manager-cli.test.ts`, extend the help assertions:

```ts
expect(sourceHelp.stdout).toContain('restart    重启指定 service 或 timer')
expect(sourceHelp.stdout).toContain('systemd-service-manager restart api --project /path/to/app')
```

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/lifecycle.test.ts scripts/bash/systemd-service-manager/tests/manager-cli.test.ts
```

Expected: lifecycle restart may already PASS; help assertion should FAIL until example is added.

- [ ] **Step 3: Update CLI help and README examples**

In `scripts/bash/systemd-service-manager/lib/cli.sh`, add this example after `start`:

```text
  systemd-service-manager restart api --project /path/to/app
```

In `scripts/bash/systemd-service-manager/README.md`, add:

```bash
systemd-service-manager restart api --project /path/to/app
```

- [ ] **Step 4: Run focused tests**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/lifecycle.test.ts scripts/bash/systemd-service-manager/tests/manager-cli.test.ts
```

Expected: PASS.

- [ ] **Step 5: Commit Task 4**

```bash
git add scripts/bash/systemd-service-manager/lib/cli.sh scripts/bash/systemd-service-manager/README.md scripts/bash/systemd-service-manager/tests/lifecycle.test.ts scripts/bash/systemd-service-manager/tests/manager-cli.test.ts
git commit -m "test(systemd): 补齐 restart 回归覆盖"
```

## Task 5: Timer Retry Rendering

**Files:**
- Modify: `scripts/bash/systemd-service-manager/lib/validate.sh`
- Modify: `scripts/bash/systemd-service-manager/lib/parser-timer.sh`
- Modify: `scripts/bash/systemd-service-manager/lib/render-service.sh`
- Modify: `scripts/bash/systemd-service-manager/commands/install.sh`
- Modify: `scripts/bash/systemd-service-manager/templates/timer-task.conf.example`
- Modify: `scripts/bash/systemd-service-manager/tests/install.test.ts`

- [ ] **Step 1: Add failing retry tests**

Append to `scripts/bash/systemd-service-manager/tests/install.test.ts`:

```ts
it('renders retry wrapper for timer task commands when retry attempts are configured', async () => {
  const workspace = createWorkspace()
  workspaces.push(workspace)

  installMockCommand(workspace, 'systemd-analyze', '#!/usr/bin/env bash\nexit 0\n')
  installMockCommand(workspace, 'systemctl', '#!/usr/bin/env bash\nexit 0\n')

  const projectRoot = path.join(
    workspace.managerHome,
    'tests',
    'fixtures',
    'project-basic',
  )

  writeText(
    path.join(projectRoot, 'deploy/systemd/timers/retry-cleanup.conf'),
    [
      'DESCRIPTION=Retry Cleanup',
      'TARGET_TYPE=task',
      'COMMAND=/usr/bin/env bash -lc \'printf cleanup\'',
      'WORKDIR=/opt/myapp',
      'SCHEDULE=@daily',
      'RETRY_ATTEMPTS=3',
      'RETRY_DELAY_SEC=7',
      '',
    ].join('\n'),
  )

  const result = await runSource(
    workspace,
    ['install', 'timer', 'retry-cleanup', '--project', projectRoot],
    { SSM_TEST_EUID: '0' },
  )

  expect(result.exitCode).toBe(0)
  const unitText = fs.readFileSync(
    path.join(workspace.fakeSystemDir, 'myapp-task-retry-cleanup.service'),
    'utf8',
  )
  expect(unitText).toContain('attempt=1')
  expect(unitText).toContain('RETRY_ATTEMPTS=3')
  expect(unitText).toContain('RETRY_DELAY_SEC=7')
  expect(unitText).toContain("/usr/bin/env bash -lc 'printf cleanup'")
})

it('rejects retry attempts on service-target timers', async () => {
  const workspace = createWorkspace()
  workspaces.push(workspace)

  const projectRoot = path.join(
    workspace.managerHome,
    'tests',
    'fixtures',
    'project-basic',
  )

  writeText(
    path.join(projectRoot, 'deploy/systemd/timers/bad-service-retry.conf'),
    [
      'DESCRIPTION=Bad Retry',
      'TARGET_TYPE=service',
      'TARGET_NAME=api',
      'ACTION=restart',
      'SCHEDULE=@daily',
      'RETRY_ATTEMPTS=2',
      '',
    ].join('\n'),
  )

  const result = await runSource(
    workspace,
    ['install', 'timer', 'bad-service-retry', '--project', projectRoot, '--dry-run'],
    { SSM_TEST_EUID: '0' },
  )

  expect(result.exitCode).not.toBe(0)
  expect(result.stderr + result.stdout).toContain('RETRY_ATTEMPTS only supports TARGET_TYPE=task')
})
```

- [ ] **Step 2: Run retry tests and verify failure**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/install.test.ts
```

Expected: FAIL because retry fields are ignored.

- [ ] **Step 3: Add integer validation helper**

In `scripts/bash/systemd-service-manager/lib/validate.sh`, append:

```bash
# 要求字段是大于等于最小值的十进制整数，用于 retry 等数值配置。
ssm_require_integer_at_least() {
  local field_name="$1"
  local value="$2"
  local minimum="$3"

  if [[ ! "${value}" =~ ^[0-9]+$ ]]; then
    ssm_die "Invalid ${field_name}: ${value}"
  fi

  if [[ "${value}" -lt "${minimum}" ]]; then
    ssm_die "Invalid ${field_name}: ${value}, must be >= ${minimum}"
  fi
}
```

- [ ] **Step 4: Parse retry fields in `parser-timer.sh`**

After `SSM_TIMER_RUN_GROUP` defaults are set, add:

```bash
SSM_TIMER_RETRY_ATTEMPTS="${RETRY_ATTEMPTS:-1}"
SSM_TIMER_RETRY_DELAY_SEC="${RETRY_DELAY_SEC:-5}"
ssm_require_integer_at_least "RETRY_ATTEMPTS" "${SSM_TIMER_RETRY_ATTEMPTS}" 1
ssm_require_integer_at_least "RETRY_DELAY_SEC" "${SSM_TIMER_RETRY_DELAY_SEC}" 0

if [[ "${TARGET_TYPE}" == "service" && "${SSM_TIMER_RETRY_ATTEMPTS}" -gt 1 ]]; then
  ssm_die "RETRY_ATTEMPTS only supports TARGET_TYPE=task"
fi
```

- [ ] **Step 5: Render retry wrapper for task services**

In `scripts/bash/systemd-service-manager/lib/render-service.sh`, add:

```bash
# 生成安全的单引号 shell 参数，供 retry wrapper 把原始命令作为参数传入。
ssm_shell_single_quote() {
  local value="$1"
  printf "'%s'" "${value//\'/\'\\\'\'}"
}

# 渲染 timer task 的 ExecStart；未配置 retry 时保持原始命令。
ssm_render_task_exec_start() {
  local exec_command="$1"
  local retry_attempts="${SSM_TIMER_RETRY_ATTEMPTS:-1}"
  local retry_delay_sec="${SSM_TIMER_RETRY_DELAY_SEC:-5}"

  if [[ "${retry_attempts}" -le 1 ]]; then
    printf 'ExecStart=%s\n' "${exec_command}"
    return 0
  fi

  local quoted_command
  quoted_command="$(ssm_shell_single_quote "${exec_command}")"

  printf 'Environment="RETRY_ATTEMPTS=%s"\n' "${retry_attempts}"
  printf 'Environment="RETRY_DELAY_SEC=%s"\n' "${retry_delay_sec}"
  printf 'ExecStart=/usr/bin/env bash -lc %s bash %s\n' \
    "$(ssm_shell_single_quote 'attempt=1; while true; do eval "$1"; code=$?; if [ "$code" -eq 0 ] || [ "$attempt" -ge "$RETRY_ATTEMPTS" ]; then exit "$code"; fi; sleep "$RETRY_DELAY_SEC"; attempt=$((attempt + 1)); done')" \
    "${quoted_command}"
}
```

Then replace the current task service `ExecStart=${exec_command}` line with:

```bash
$(ssm_render_task_exec_start "${exec_command}")
```

- [ ] **Step 6: Ensure install passes retry globals to render**

In `scripts/bash/systemd-service-manager/commands/install.sh`, no new arguments are needed because `ssm_parse_timer_config` sets `SSM_TIMER_RETRY_ATTEMPTS` and `SSM_TIMER_RETRY_DELAY_SEC` before `ssm_render_task_service_unit` is called. Verify the timer branch calls `ssm_parse_timer_config` before constructing `task_exec_command`.

- [ ] **Step 7: Update timer task template**

In `scripts/bash/systemd-service-manager/templates/timer-task.conf.example`, add:

```dotenv
RETRY_ATTEMPTS=1
RETRY_DELAY_SEC=5
```

- [ ] **Step 8: Run retry tests**

Run:

```bash
pnpm exec vitest run --config ./scripts/bash/systemd-service-manager/vitest.config.ts scripts/bash/systemd-service-manager/tests/install.test.ts
```

Expected: PASS.

- [ ] **Step 9: Commit Task 5**

```bash
git add scripts/bash/systemd-service-manager/lib/validate.sh scripts/bash/systemd-service-manager/lib/parser-timer.sh scripts/bash/systemd-service-manager/lib/render-service.sh scripts/bash/systemd-service-manager/commands/install.sh scripts/bash/systemd-service-manager/templates/timer-task.conf.example scripts/bash/systemd-service-manager/tests/install.test.ts
git commit -m "feat(systemd): 支持 timer task 重试"
```

## Task 6: Documentation and Final Verification

**Files:**
- Modify: `scripts/bash/README.md`
- Modify: `scripts/bash/systemd-service-manager/README.md`

- [ ] **Step 1: Update Bash README**

In `scripts/bash/README.md`, add a section near the top:

````markdown
## Build

```bash
scripts/bash/build.sh
scripts/bash/build.sh --jobs 2
scripts/bash/build.sh --list
scripts/bash/build.sh --only aliyun-oss-put
```

`scripts/bash/build.sh` 统一刷新 Bash 工具的 `bin` 产物。目录型工具通过自己的 `build.sh` 生成产物；单文件 `.sh` 会复制到 `bin/<name>`，默认去掉 `.sh` 扩展。
````

- [ ] **Step 2: Update systemd-service-manager README**

Add examples:

```bash
systemd-service-manager list --project /path/to/app --json
systemd-service-manager restart api --project /path/to/app
```

Add retry configuration note:

```markdown
Timer task 可选配置：

- `RETRY_ATTEMPTS`：命令总尝试次数，默认 `1`，即不重试。
- `RETRY_DELAY_SEC`：失败后等待秒数，默认 `5`。

`RETRY_ATTEMPTS` 只适用于 `TARGET_TYPE=task`，不适用于触发 service 的 timer。
```

- [ ] **Step 3: Run focused quality gates**

Run:

```bash
pnpm run qa:bash
pnpm run qa:systemd-service-manager
pwsh -NoProfile -Command "$env:PWSH_TEST_PATH='./tests/Install.Tests.ps1'; $c = ./PesterConfiguration.ps1; $c.Run.Exit = $true; Invoke-Pester -Configuration $c"
```

Expected: all PASS.

- [ ] **Step 4: Run repository quality gates required by project rules**

Run:

```bash
pnpm qa
pnpm test:pwsh:all
```

Expected: PASS. If Docker is unavailable for `pnpm test:pwsh:all`, run `pnpm test:pwsh:full` and note that Linux coverage depends on CI or WSL.

- [ ] **Step 5: Commit documentation and final polish**

```bash
git add scripts/bash/README.md scripts/bash/systemd-service-manager/README.md package.json scripts/qa.mjs scripts/qa-turbo.mjs
git commit -m "docs(bash): 更新构建与 systemd 管理器说明"
```

## Self-Review Notes

- Spec coverage: plan covers Bash build entry, `build` / `copy` target kinds, CPU/jobs logging, `install.ps1` integration, `list` text/JSON, `restart` regression, timer retry, docs, and required QA.
- Placeholder scan: no unresolved placeholder steps remain; each implementation step names concrete files and expected behavior.
- Type consistency: plan uses `RETRY_ATTEMPTS`, `RETRY_DELAY_SEC`, `SSM_TIMER_RETRY_ATTEMPTS`, `SSM_TIMER_RETRY_DELAY_SEC`, `targetType`, `targetName`, and `restartSec` consistently across tests and implementation notes.
