#!/usr/bin/env node

import { spawnSync } from 'node:child_process'

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

if (!supportedModes.has(mode)) {
  console.error(`[qa] unsupported mode: ${mode}`)
  console.error('[qa] use one of: changed, all')
  process.exit(1)
}

function runCommand(command, args, options = {}) {
  if (verbose) {
    console.log(`[qa:verbose] run: ${command} ${args.join(' ')}`)
  }

  const result = spawnSync(command, args, {
    stdio: 'inherit',
    ...options,
  })

  if (result.error) {
    throw result.error
  }

  if (result.status !== 0) {
    process.exit(result.status ?? 1)
  }
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

function runWorkspaceQa(modeValue, sinceRef) {
  if (modeValue === 'all') {
    console.log('[qa] run workspace qa (all)')
    runCommand('pnpm', ['-r', '--if-present', 'run', 'qa'])
    return
  }

  if (!sinceRef) {
    console.log('[qa] no base ref found, fallback to workspace qa (all)')
    runCommand('pnpm', ['-r', '--if-present', 'run', 'qa'])
    return
  }

  console.log(`[qa] run workspace qa (changed since ${sinceRef})`)
  runCommand('pnpm', ['--filter', `[${sinceRef}]`, '-r', '--if-present', 'run', 'qa'])
}

function runRootPwshQa(modeValue, sinceRef) {
  if (modeValue === 'all') {
    console.log('[qa] run root qa:pwsh (all)')
    runCommand('pnpm', ['run', 'qa:pwsh'])
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
    console.log('[qa] skip root qa:pwsh (no changes)')
    return
  }

  console.log('[qa] run root qa:pwsh (changed)')
  runCommand('pnpm', ['run', 'qa:pwsh'])
}

const sinceRef = mode === 'changed' ? resolveSinceRef() : null

if (mode === 'changed' && sinceRef) {
  console.log(`[qa] mode=changed, since=${sinceRef}`)
} else if (mode === 'changed') {
  console.log('[qa] mode=changed, since=<not-found>')
} else {
  console.log('[qa] mode=all')
}

runWorkspaceQa(mode, sinceRef)
runRootPwshQa(mode, sinceRef)

console.log('[qa] done')
