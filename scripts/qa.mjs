#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import { existsSync } from 'node:fs'
import { buildPnpmCommand } from './pnpm-command.mjs'

// 传统版 QA 编排器。
// 这个入口复用各 workspace 包自身定义的 `qa` 脚本，不依赖 Turbo 任务图；
// 它与 `qa-turbo.mjs` 并存，是为了保留一个行为更稳定、排障更直接的基线入口，
// 方便在 Turbo 链路需要对比、回退或逐步迁移时继续使用。

class CommandFailedError extends Error {
  constructor(step, command, args, exitCode, spawnError) {
    super(step)
    this.name = 'CommandFailedError'
    this.step = step
    this.command = command
    this.args = args
    this.exitCode = exitCode
    this.spawnError = spawnError
  }
}

const args = process.argv.slice(2)
let mode = 'changed'
let verbose = false

for (const arg of args) {
  if (arg === '--verbose' || arg === '-v') {
    verbose = true
    continue
  }

  if (arg === 'changed' || arg === 'all') {
    mode = arg
    continue
  }

  console.error(`[qa] unsupported argument: ${arg}`)
  console.error('[qa] usage: node ./scripts/qa.mjs [changed|all] [--verbose|-v]')
  process.exit(1)
}

if (!verbose) {
  const envValue = (process.env.QA_VERBOSE ?? '').toLowerCase()
  verbose = envValue === '1' || envValue === 'true' || envValue === 'yes'
}

const supportedModes = new Set(['changed', 'all'])
// 根目录 PowerShell 测试默认只跑一组稳定且耗时可控的 smoke 集合，
// changed 模式下再根据改动补充对应测试，兼顾反馈速度和问题覆盖面。
const qaSmokeTestPaths = [
  './tests/DeferredLoading.Tests.ps1',
  './tests/losslessToAdaptiveAudio.Tests.ps1',
  './tests/ProfileMode.Tests.ps1',
  './tests/Switch-Mirrors.Tests.ps1',
  './psutils/tests/error.Tests.ps1',
  './psutils/tests/filesystem.Tests.ps1',
  './psutils/tests/font.Tests.ps1',
  './psutils/tests/git.Tests.ps1',
  './psutils/tests/string.Tests.ps1',
  './psutils/tests/win.Tests.ps1',
  './psutils/tests/wrapper.Tests.ps1',
]
const qaExcludedTestPaths = new Set([
  './psutils/tests/cache.Tests.ps1',
  './psutils/tests/hardware.Tests.ps1',
  './psutils/tests/help.Tests.ps1',
  './psutils/tests/install.Tests.ps1',
  './psutils/tests/network.Tests.ps1',
  './psutils/tests/profile_unix.Tests.ps1',
  './psutils/tests/profile_windows.Tests.ps1',
  './psutils/tests/proxy.Tests.ps1',
  './psutils/tests/test.Tests.ps1',
])

if (!supportedModes.has(mode)) {
  console.error(`[qa] unsupported mode: ${mode}`)
  console.error('[qa] use one of: changed, all')
  process.exit(1)
}

function runCommand(step, command, args, options = {}) {
  if (verbose) {
    console.log(`[qa:verbose] run: ${command} ${args.join(' ')}`)
  }

  const result = spawnSync(command, args, {
    stdio: 'inherit',
    ...options,
  })

  if (result.error || result.status !== 0) {
    throw new CommandFailedError(
      step,
      command,
      args,
      result.status ?? 1,
      result.error,
    )
  }
}

function runPnpm(step, pnpmArgs, options = {}) {
  const pnpmCommand = buildPnpmCommand(pnpmArgs)
  runCommand(step, pnpmCommand.command, pnpmCommand.args, options)
}

function runCapture(command, args) {
  if (verbose) {
    console.log(`[qa:verbose] inspect: ${command} ${args.join(' ')}`)
  }

  const result = spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  return {
    status: result.status ?? 1,
    stdout: (result.stdout ?? '').toString().trim(),
  }
}

function refExists(ref) {
  const result = spawnSync('git', ['rev-parse', '--verify', '--quiet', ref], {
    stdio: 'ignore',
  })
  return result.status === 0
}

function resolveSinceRef() {
  const preferred = process.env.QA_BASE_REF
  const candidates = [
    preferred,
    'origin/master',
    'origin/main',
    'master',
    'main',
    'HEAD~1',
  ].filter(Boolean)

  for (const ref of candidates) {
    if (refExists(ref)) {
      return ref
    }
  }

  return null
}

function hasPathChanges(pathspecs, sinceRef) {
  const checks = []

  if (sinceRef) {
    checks.push([
      'diff',
      '--name-only',
      '--diff-filter=ACMRT',
      `${sinceRef}...HEAD`,
      '--',
      ...pathspecs,
    ])
  }

  checks.push(['diff', '--name-only', '--diff-filter=ACMRT', '--', ...pathspecs])
  checks.push([
    'diff',
    '--name-only',
    '--diff-filter=ACMRT',
    '--cached',
    '--',
    ...pathspecs,
  ])
  checks.push(['ls-files', '--others', '--exclude-standard', '--', ...pathspecs])

  return checks.some((args) => {
    const result = runCapture('git', args)
    const hasChanges = result.status === 0 && result.stdout.length > 0

    if (verbose && hasChanges) {
      console.log(`[qa:verbose] matched changes via: git ${args.join(' ')}`)
      for (const line of result.stdout.split('\n').filter(Boolean)) {
        console.log(`[qa:verbose]   ${line}`)
      }
    }

    return hasChanges
  })
}

function toRepoPath(pathValue) {
  return pathValue.replace(/\\/g, '/').replace(/^\.\//, '')
}

function toQaTestPath(pathValue) {
  const prefixed = pathValue.startsWith('./') ? pathValue : `./${pathValue}`
  return prefixed.replace(/\\/g, '/')
}

function shouldIncludeQaTest(pathValue) {
  const qaPath = toQaTestPath(pathValue)
  if (qaExcludedTestPaths.has(qaPath)) {
    return false
  }
  const repoPath = toRepoPath(qaPath)
  return existsSync(repoPath)
}

function collectChangedFiles(pathspecs, sinceRef) {
  const checks = []

  if (sinceRef) {
    checks.push([
      'diff',
      '--name-only',
      '--diff-filter=ACMRT',
      `${sinceRef}...HEAD`,
      '--',
      ...pathspecs,
    ])
  }

  checks.push(['diff', '--name-only', '--diff-filter=ACMRT', '--', ...pathspecs])
  checks.push([
    'diff',
    '--name-only',
    '--diff-filter=ACMRT',
    '--cached',
    '--',
    ...pathspecs,
  ])
  checks.push(['ls-files', '--others', '--exclude-standard', '--', ...pathspecs])

  const changed = new Set()

  for (const args of checks) {
    const result = runCapture('git', args)
    if (result.status !== 0 || result.stdout.length === 0) {
      continue
    }
    for (const line of result.stdout.split('\n').filter(Boolean)) {
      changed.add(toRepoPath(line))
    }
  }

  return [...changed]
}

function addQaTestPath(selected, testPath) {
  const normalized = toQaTestPath(testPath)
  if (!shouldIncludeQaTest(normalized)) {
    if (verbose) {
      console.log(`[qa:verbose] skip qa test path: ${normalized}`)
    }
    return
  }
  selected.add(normalized)
}

function resolveQaTestPaths(modeValue, sinceRef, pathspecs) {
  const selected = new Set()
  for (const testPath of qaSmokeTestPaths) {
    addQaTestPath(selected, testPath)
  }

  if (modeValue !== 'changed') {
    return [...selected]
  }

  const changedFiles = collectChangedFiles(pathspecs, sinceRef)
  if (verbose) {
    console.log(`[qa:verbose] root changed files: ${changedFiles.length}`)
  }

  for (const changedFile of changedFiles) {
    if (changedFile.startsWith('tests/') && changedFile.endsWith('.Tests.ps1')) {
      addQaTestPath(selected, changedFile)
      continue
    }

    if (
      changedFile.startsWith('psutils/tests/') &&
      changedFile.endsWith('.Tests.ps1')
    ) {
      addQaTestPath(selected, changedFile)
      continue
    }

    if (
      changedFile.startsWith('psutils/modules/') &&
      changedFile.endsWith('.psm1')
    ) {
      const fileName = changedFile.split('/').pop()
      const moduleName = fileName?.replace(/\.psm1$/i, '')
      if (moduleName) {
        addQaTestPath(selected, `./psutils/tests/${moduleName}.Tests.ps1`)
      }
    }
  }

  return [...selected]
}

function runWorkspaceQa(modeValue, sinceRef) {
  // 这里直接递归执行每个包自己的 `qa`，保持“包内自己定义质量门”的语义，
  // 避免把所有包强制收敛到同一条任务链，适合作为兼容基线入口。
  const recursiveArgs = [
    '-r',
    '--if-present',
    '--reporter',
    'append-only',
    '--aggregate-output',
    'run',
    'qa',
  ]

  if (modeValue === 'all') {
    console.log('[qa] run workspace qa (all)')
    runPnpm('workspace-qa-all', recursiveArgs)
    return
  }

  if (!sinceRef) {
    console.log('[qa] no base ref found, fallback to workspace qa (all)')
    runPnpm('workspace-qa-fallback-all', recursiveArgs)
    return
  }

  console.log(`[qa] run workspace qa (changed since ${sinceRef})`)
  runPnpm('workspace-qa-changed', [
    '--filter',
    `[${sinceRef}]`,
    ...recursiveArgs,
  ])
}

function runRootPwshQa(modeValue, sinceRef) {
  // 根目录 PowerShell 资产不属于 workspace 包，需要单独编排；
  // 同时通过 PWSH_TEST_PATH 精确收缩测试范围，避免 changed 模式退化成全量 Pester。
  const pwshPathspecs = [
    'scripts/pwsh',
    'profile',
    'tests',
    'psutils/modules',
    'psutils/tests',
    'PesterConfiguration.ps1',
    'install.ps1',
    'Manage-BinScripts.ps1',
  ]

  const qaTestPaths = resolveQaTestPaths(modeValue, sinceRef, pwshPathspecs)
  const qaEnv = { ...process.env }
  if (qaTestPaths.length > 0) {
    qaEnv.PWSH_TEST_PATH = qaTestPaths.join(';')
  }

  if (verbose) {
    console.log(`[qa:verbose] qa test paths (${qaTestPaths.length})`)
    for (const testPath of qaTestPaths) {
      console.log(`[qa:verbose]   ${testPath}`)
    }
  }

  if (modeValue === 'all') {
    console.log('[qa] run root qa:pwsh (all)')
    runPnpm('root-qa-pwsh-all', ['run', 'qa:pwsh'], { env: qaEnv })
    return
  }

  if (!hasPathChanges(pwshPathspecs, sinceRef)) {
    console.log('[qa] skip root qa:pwsh (no changes)')
    return
  }

  console.log('[qa] run root qa:pwsh (changed)')
  runPnpm('root-qa-pwsh-changed', ['run', 'qa:pwsh'], { env: qaEnv })
}

function runRootFnosQa(modeValue, sinceRef) {
  const fnosPathspecs = ['linux/fnos', 'package.json']

  if (modeValue === 'all') {
    console.log('[qa] run root qa:fnos (all)')
    runPnpm('root-qa-fnos-all', ['run', 'qa:fnos'])
    return
  }

  if (!hasPathChanges(fnosPathspecs, sinceRef)) {
    console.log('[qa] skip root qa:fnos (no changes)')
    return
  }

  console.log('[qa] run root qa:fnos (changed)')
  runPnpm('root-qa-fnos-changed', ['run', 'qa:fnos'])
}

function runRootSystemdServiceManagerQa(modeValue, sinceRef) {
  const pathspecs = ['scripts/bash/systemd-service-manager', 'package.json']

  if (modeValue === 'all') {
    console.log('[qa] run root qa:systemd-service-manager (all)')
    runPnpm('root-qa-systemd-service-manager-all', [
      'run',
      'qa:systemd-service-manager',
    ])
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[qa] skip root qa:systemd-service-manager (no changes)')
    return
  }

  console.log('[qa] run root qa:systemd-service-manager (changed)')
  runPnpm('root-qa-systemd-service-manager-changed', [
    'run',
    'qa:systemd-service-manager',
  ])
}

const sinceRef = mode === 'changed' ? resolveSinceRef() : null

if (mode === 'changed' && sinceRef) {
  console.log(`[qa] mode=changed, since=${sinceRef}`)
} else if (mode === 'changed') {
  console.log('[qa] mode=changed, since=<not-found>')
} else {
  console.log('[qa] mode=all')
}

try {
  runWorkspaceQa(mode, sinceRef)
  runRootPwshQa(mode, sinceRef)
  runRootFnosQa(mode, sinceRef)
  runRootSystemdServiceManagerQa(mode, sinceRef)
  console.log('[qa] done')
} catch (error) {
  if (error instanceof CommandFailedError) {
    console.error(`[qa:error] step=${error.step}`)
    console.error(
      `[qa:error] command=${error.command} ${error.args.join(' ')}`,
    )

    if (error.spawnError) {
      console.error(`[qa:error] spawn=${error.spawnError.message}`)
    }

    console.error(`[qa:error] exitCode=${error.exitCode}`)
    console.error('[qa:error] tip=run `pnpm qa:verbose` for detailed traces')
    process.exit(error.exitCode || 1)
  }

  throw error
}
