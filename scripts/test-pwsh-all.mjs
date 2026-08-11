#!/usr/bin/env node

import { spawn, spawnSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'

import { buildPnpmCommand } from './pnpm-command.mjs'

/**
 * 验证 Docker CLI、daemon 与 Compose plugin 均可用于 Linux Pester lane。
 *
 * @param {(command: string, args: string[]) => { status: number | null, error?: Error }} run 同步命令执行器
 * @returns {{ ok: boolean, reason: string }}
 */
export function checkDockerPrerequisites(
  run = (command, args) => spawnSync(command, args, { stdio: 'ignore' }),
) {
  const checks = [
    { args: ['--version'], reason: 'Docker CLI 不可用' },
    { args: ['info'], reason: 'Docker daemon 不可用' },
    { args: ['compose', 'version'], reason: 'Docker Compose plugin 不可用' },
  ]

  for (const check of checks) {
    const result = run('docker', check.args)
    if (result.error || result.status !== 0) {
      return { ok: false, reason: check.reason }
    }
  }
  return { ok: true, reason: '' }
}

/**
 * 终止并发测试 runner 及其子进程树。
 *
 * @param {import('node:child_process').ChildProcess} child 子进程
 * @returns {void}
 */
function terminateProcessTree(child) {
  if (!child.pid || child.exitCode !== null) return
  if (process.platform === 'win32') {
    spawnSync('taskkill', ['/pid', String(child.pid), '/t', '/f'], {
      stdio: 'ignore',
    })
    return
  }
  child.kill('SIGTERM')
}

/**
 * 执行 host 与 Linux 两条完整 Pester lane。
 *
 * @returns {Promise<number>}
 */
export async function main() {
  const prerequisite = checkDockerPrerequisites()
  if (!prerequisite.ok) {
    console.error(
      `[test:pwsh:all] ${prerequisite.reason}，未启动 host/linux 全量门禁。`,
    )
    console.error('[test:pwsh:all] 本机回退命令: pnpm test:pwsh:full')
    console.error(
      '[test:pwsh:all] Linux 覆盖请在 CI、WSL 或具备 Docker 的环境执行。',
    )
    return 1
  }

  const pnpm = buildPnpmCommand([
    'exec',
    'concurrently',
    '--group',
    '--names',
    'host,linux',
    '--prefix-colors',
    'blue,magenta',
    '--success',
    'all',
    'pnpm test:pwsh:full:assertions',
    'pnpm test:pwsh:linux:full',
  ])

  return await new Promise((resolve, reject) => {
    const child = spawn(pnpm.command, pnpm.args, {
      cwd: process.cwd(),
      env: process.env,
      stdio: 'inherit',
    })
    const handleSignal = () => terminateProcessTree(child)
    process.once('SIGINT', handleSignal)
    process.once('SIGTERM', handleSignal)
    child.once('error', reject)
    child.once('close', (code) => {
      process.removeListener('SIGINT', handleSignal)
      process.removeListener('SIGTERM', handleSignal)
      resolve(code ?? 1)
    })
  })
}

if (
  process.argv[1] &&
  import.meta.url === pathToFileURL(process.argv[1]).href
) {
  process.exit(await main())
}
