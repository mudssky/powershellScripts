#!/usr/bin/env node

import { spawnSync } from 'node:child_process'
import { buildPnpmCommand } from './pnpm-command.mjs'
import { shouldRunLinuxOnlyQa } from './qa-platform.mjs'

// Turbo 版 QA 编排器。
// 这个入口把 workspace QA 拆成可缓存、可并行的任务链，优先服务速度和 affected 场景；
// 它与 `qa.mjs` 并存，是为了在引入 Turbo 后保留一个传统基线入口，便于性能对比、
// 行为校验，以及在 Turbo 环境不可用时仍然有可回退方案。

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

  console.error(`[turbo:qa] unsupported argument: ${arg}`)
  console.error(
    '[turbo:qa] usage: node ./scripts/qa-turbo.mjs [changed|all] [--verbose|-v]',
  )
  process.exit(1)
}

if (!verbose) {
  const envValue = (process.env.QA_VERBOSE ?? '').toLowerCase()
  verbose = envValue === '1' || envValue === 'true' || envValue === 'yes'
}

const supportedModes = new Set(['changed', 'all'])
const turboQaTaskChain = ['typecheck:fast', 'check', 'test:fast']

function buildTurboEnv({ sinceRef, affected = false } = {}) {
  const env = {
    ...process.env,
    TURBO_SCM_HEAD: process.env.TURBO_SCM_HEAD ?? 'HEAD',
  }

  if (sinceRef) {
    env.TURBO_SCM_BASE = sinceRef
  }

  const enabled = (process.env.TURBO_REMOTE_CACHE ?? '').toLowerCase()
  const enableRemoteCache =
    enabled === '1' || enabled === 'true' || enabled === 'yes'

  if (enableRemoteCache) {
    if (!env.TURBO_TOKEN || !env.TURBO_TEAM) {
      throw new CommandFailedError(
        'workspace-turbo-remote-cache-missing-config',
        'turbo',
        affected
          ? ['run', ...turboQaTaskChain, '--affected']
          : ['run', ...turboQaTaskChain],
        1,
        new Error('TURBO_REMOTE_CACHE requires TURBO_TOKEN and TURBO_TEAM'),
      )
    }

    if (!env.TURBO_REMOTE_ONLY) {
      env.TURBO_REMOTE_ONLY = process.env.CI ? 'true' : 'false'
    }

    console.log('[turbo:qa] remote cache enabled via TURBO_REMOTE_CACHE')
  }

  return env
}

if (!supportedModes.has(mode)) {
  console.error(`[turbo:qa] unsupported mode: ${mode}`)
  console.error('[turbo:qa] use one of: changed, all')
  process.exit(1)
}

function runCommand(step, command, args, options = {}) {
  if (verbose) {
    console.log(`[turbo:qa:verbose] run: ${command} ${args.join(' ')}`)
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

function runCapture(command, args) {
  if (verbose) {
    console.log(`[turbo:qa:verbose] inspect: ${command} ${args.join(' ')}`)
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

function hasPathChanges(pathspecs, sinceRef, ignorePatterns = []) {
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

  return checks.some((checkArgs) => {
    const result = runCapture('git', checkArgs)

    if (result.status !== 0 || result.stdout.length === 0) {
      return false
    }

    const changedLines = result.stdout
      .split('\n')
      .filter(Boolean)
      .filter(
        (line) =>
          !ignorePatterns.some((pattern) =>
            typeof pattern === 'string' ? line.includes(pattern) : pattern.test(line),
          ),
      )

    if (verbose && changedLines.length > 0) {
      console.log(
        `[turbo:qa:verbose] matched changes via: git ${checkArgs.join(' ')}`,
      )
      for (const line of changedLines) {
        console.log(`[turbo:qa:verbose]   ${line}`)
      }
    }

    return changedLines.length > 0
  })
}

function resolveTurboRunner() {
  // 优先走 `pnpm exec turbo`，确保使用工作区锁定的版本；
  // 若外部环境已安装 turbo，则允许回退到全局命令，降低本地接入门槛。
  // 这里复用共享 pnpm 解析逻辑，避免 Windows 下把 pnpm 可执行文件交给错误的启动器。
  const pnpmTurboCommand = buildPnpmCommand(['exec', 'turbo'])
  const pnpmTurboVersionCommand = buildPnpmCommand(['exec', 'turbo', '--version'])
  const candidates = [
    {
      command: pnpmTurboCommand.command,
      args: pnpmTurboCommand.args,
      versionArgs: pnpmTurboVersionCommand.args,
    },
    { command: 'turbo', args: [], versionArgs: ['--version'] },
  ]

  for (const candidate of candidates) {
    const result = spawnSync(candidate.command, candidate.versionArgs, {
      stdio: 'ignore',
    })

    if (result.status === 0) {
      return candidate
    }
  }

  return null
}

function runWorkspaceQa(modeValue, sinceRef) {
  // 这里不再执行包级 `qa` 脚本，而是直接运行 Turbo 任务图，
  // 让 typecheck/check/test 这些细粒度任务获得并行与缓存收益。
  const turboRunner = resolveTurboRunner()

  if (!turboRunner) {
    const pnpmTurboVersionCommand = buildPnpmCommand(['exec', 'turbo', '--version'])
    throw new CommandFailedError(
      'workspace-turbo-not-found',
      pnpmTurboVersionCommand.command,
      pnpmTurboVersionCommand.args,
      1,
      new Error('turbo command is not available'),
    )
  }

  if (modeValue === 'all') {
    const env = buildTurboEnv({ affected: false })

    console.log('[turbo:qa] run workspace qa task chain via turbo (all)')
    runCommand('workspace-turbo-qa-all', turboRunner.command, [
      ...turboRunner.args,
      'run',
      ...turboQaTaskChain,
    ], { env })
    return
  }

  if (!sinceRef) {
    const env = buildTurboEnv({ affected: false })

    console.log(
      '[turbo:qa] no base ref found, fallback to workspace qa task chain (all)',
    )
    runCommand('workspace-turbo-qa-fallback-all', turboRunner.command, [
      ...turboRunner.args,
      'run',
      ...turboQaTaskChain,
    ], { env })
    return
  }

  const workspacePathspecs = ['projects', 'scripts/node']

  if (!hasPathChanges(workspacePathspecs, sinceRef, [/[\\/]\.turbo[\\/]/])) {
    console.log('[turbo:qa] skip workspace qa (no workspace changes)')
    return
  }

  const env = buildTurboEnv({ sinceRef, affected: true })

  console.log(
    `[turbo:qa] run workspace qa task chain via turbo (affected, base=${sinceRef})`,
  )
  runCommand(
    'workspace-turbo-qa-changed',
    turboRunner.command,
    [...turboRunner.args, 'run', ...turboQaTaskChain, '--affected'],
    { env },
  )
}

function runRootPwshQa(modeValue, sinceRef) {
  // Root PowerShell 逻辑暂时不在 Turbo 图里，因此继续沿用单独触发的方式；
  // 这样可以在享受 workspace 并行收益的同时，避免一次性重构根目录测试编排。
  if (modeValue === 'all') {
    console.log('[turbo:qa] run root qa:pwsh (all)')
    const pnpmCommand = buildPnpmCommand(['run', 'qa:pwsh'])
    runCommand('root-qa-pwsh-all', pnpmCommand.command, pnpmCommand.args)
    return
  }

  const pwshPathspecs = [
    'scripts/pwsh',
    'profile',
    'tests',
    'PesterConfiguration.ps1',
    'install.ps1',
    'Manage-BinScripts.ps1',
  ]

  if (!hasPathChanges(pwshPathspecs, sinceRef)) {
    console.log('[turbo:qa] skip root qa:pwsh (no changes)')
    return
  }

  console.log('[turbo:qa] run root qa:pwsh (changed)')
  const pnpmCommand = buildPnpmCommand(['run', 'qa:pwsh'])
  runCommand('root-qa-pwsh-changed', pnpmCommand.command, pnpmCommand.args)
}

function runRootFnosQa(modeValue, sinceRef) {
  if (!shouldRunLinuxOnlyQa()) {
    console.log(
      `[turbo:qa] skip root qa:fnos (linux only, current platform: ${process.platform})`,
    )
    return
  }

  if (modeValue === 'all') {
    console.log('[turbo:qa] run root qa:fnos (all)')
    const pnpmCommand = buildPnpmCommand(['run', 'qa:fnos'])
    runCommand('root-qa-fnos-all', pnpmCommand.command, pnpmCommand.args)
    return
  }

  const fnosPathspecs = ['linux/fnos', 'package.json']

  if (!hasPathChanges(fnosPathspecs, sinceRef)) {
    console.log('[turbo:qa] skip root qa:fnos (no changes)')
    return
  }

  console.log('[turbo:qa] run root qa:fnos (changed)')
  const pnpmCommand = buildPnpmCommand(['run', 'qa:fnos'])
  runCommand('root-qa-fnos-changed', pnpmCommand.command, pnpmCommand.args)
}

function runRootBashQa(modeValue, sinceRef) {
  // Bash 根级工具暂不进入 Turbo 图，通过路径触发独立 Vitest 套件。
  if (!shouldRunLinuxOnlyQa()) {
    console.log(
      `[turbo:qa] skip root qa:bash (linux only, current platform: ${process.platform})`,
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
    console.log('[turbo:qa] run root qa:bash (all)')
    const pnpmCommand = buildPnpmCommand(['run', 'qa:bash'])
    runCommand('root-qa-bash-all', pnpmCommand.command, pnpmCommand.args)
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[turbo:qa] skip root qa:bash (no changes)')
    return
  }

  console.log('[turbo:qa] run root qa:bash (changed)')
  const pnpmCommand = buildPnpmCommand(['run', 'qa:bash'])
  runCommand('root-qa-bash-changed', pnpmCommand.command, pnpmCommand.args)
}

function runRootSystemdServiceManagerQa(modeValue, sinceRef) {
  if (!shouldRunLinuxOnlyQa()) {
    console.log(
      `[turbo:qa] skip root qa:systemd-service-manager (linux only, current platform: ${process.platform})`,
    )
    return
  }

  const pathspecs = ['scripts/bash/systemd-service-manager', 'package.json']

  if (modeValue === 'all') {
    console.log('[turbo:qa] run root qa:systemd-service-manager (all)')
    const pnpmCommand = buildPnpmCommand(['run', 'qa:systemd-service-manager'])
    runCommand(
      'root-qa-systemd-service-manager-all',
      pnpmCommand.command,
      pnpmCommand.args,
    )
    return
  }

  if (!hasPathChanges(pathspecs, sinceRef)) {
    console.log('[turbo:qa] skip root qa:systemd-service-manager (no changes)')
    return
  }

  console.log('[turbo:qa] run root qa:systemd-service-manager (changed)')
  const pnpmCommand = buildPnpmCommand(['run', 'qa:systemd-service-manager'])
  runCommand(
    'root-qa-systemd-service-manager-changed',
    pnpmCommand.command,
    pnpmCommand.args,
  )
}

const sinceRef = mode === 'changed' ? resolveSinceRef() : null

if (mode === 'changed' && sinceRef) {
  console.log(`[turbo:qa] mode=changed, since=${sinceRef}`)
} else if (mode === 'changed') {
  console.log('[turbo:qa] mode=changed, since=<not-found>')
} else {
  console.log('[turbo:qa] mode=all')
}

try {
  runWorkspaceQa(mode, sinceRef)
  runRootPwshQa(mode, sinceRef)
  runRootFnosQa(mode, sinceRef)
  runRootBashQa(mode, sinceRef)
  runRootSystemdServiceManagerQa(mode, sinceRef)
  console.log('[turbo:qa] done')
} catch (error) {
  if (error instanceof CommandFailedError) {
    console.error(`[turbo:qa:error] step=${error.step}`)
    console.error(
      `[turbo:qa:error] command=${error.command} ${error.args.join(' ')}`,
    )

    if (error.spawnError) {
      console.error(`[turbo:qa:error] spawn=${error.spawnError.message}`)
    }

    if (error.step === 'workspace-turbo-not-found') {
      console.error('[turbo:qa:error] tip=run `pnpm add -D turbo -w` first')
    }

    if (error.step === 'workspace-turbo-remote-cache-missing-config') {
      console.error(
        '[turbo:qa:error] tip=set TURBO_TOKEN and TURBO_TEAM when TURBO_REMOTE_CACHE=1',
      )
    }

    console.error(`[turbo:qa:error] exitCode=${error.exitCode}`)
    console.error('[turbo:qa:error] tip=run `pnpm turbo:qa:verbose` for traces')
    process.exit(error.exitCode || 1)
  }

  throw error
}
