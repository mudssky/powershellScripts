#!/usr/bin/env node

import { spawnSync } from 'node:child_process'

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
  const candidates = [
    {
      command: 'pnpm',
      args: ['exec', 'turbo'],
      versionArgs: ['exec', 'turbo', '--version'],
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
  const turboRunner = resolveTurboRunner()

  if (!turboRunner) {
    throw new CommandFailedError(
      'workspace-turbo-not-found',
      'pnpm',
      ['exec', 'turbo', '--version'],
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
  if (modeValue === 'all') {
    console.log('[turbo:qa] run root qa:pwsh (all)')
    runCommand('root-qa-pwsh-all', 'pnpm', ['run', 'qa:pwsh'])
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
  runCommand('root-qa-pwsh-changed', 'pnpm', ['run', 'qa:pwsh'])
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
