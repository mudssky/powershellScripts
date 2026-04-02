#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

/**
 * 执行命令并返回文本结果。
 * 这里统一走 Git CLI，避免额外引入依赖，也便于和当前暂存区状态保持一致。
 *
 * @param {string} command 可执行文件名
 * @param {string[]} args 命令参数
 * @returns {{ status: number, stdout: string, stderr: string, error?: Error }}
 */
function runCapture(command, args) {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })

  return {
    status: result.status ?? 1,
    stdout: (result.stdout ?? '').toString().trim(),
    stderr: (result.stderr ?? '').toString().trim(),
    error: result.error,
  }
}

/**
 * 获取当前暂存区中的 Markdown 文件。
 * 仅关注提交会带走的内容，避免 whole-repo 扫描把所有文件路径都塞回命令行。
 *
 * @returns {string[]}
 */
function getStagedMarkdownFiles() {
  const result = runCapture('git', [
    '-c',
    'core.quotePath=false',
    'diff',
    '--cached',
    '--name-only',
    '--diff-filter=ACMR',
    '--',
    '*.md',
  ])

  if (result.error) {
    throw result.error
  }

  if (result.status !== 0) {
    throw new Error(result.stderr || 'failed to list staged markdown files')
  }

  return result.stdout.length === 0 ? [] : result.stdout.split(/\r?\n/).filter(Boolean)
}

/**
 * 将暂存的 Markdown 折算为 rumdl 扫描目标：
 * - 根目录文件直接保留文件路径，避免把仓库根目录 `.` 整体纳入扫描
 * - 目录层级更深的文件压缩为“两级目录”目标，尽量缩短参数列表，
 *   同时避免直接回退到顶级目录导致扫描范围过大
 * - 仅有一级目录的文件保留文件路径，避免把整个一级目录都扫进去
 *
 * @param {string[]} stagedFiles 暂存的 Markdown 文件
 * @returns {string[]}
 */
function buildRumdlTargets(stagedFiles) {
  /** @type {Set<string>} */
  const targets = new Set()

  for (const stagedFile of stagedFiles) {
    const normalizedPath = stagedFile.replace(/\\/g, '/')
    const pathSegments = normalizedPath.split('/')

    if (pathSegments.length === 1) {
      targets.add(normalizedPath)
      continue
    }

    if (pathSegments.length === 2) {
      targets.add(normalizedPath)
      continue
    }

    targets.add(`${pathSegments[0]}/${pathSegments[1]}`)
  }

  return [...targets].sort()
}

/**
 * 通过 Node 直接执行仓库内的 rumdl JS 包装入口，避免 Windows 下 `pnpm.cmd`
 * 或 `.cmd` 包装器的兼容性差异影响 pre-commit 链路。
 *
 * @param {string[]} rumdlArgs rumdl 参数
 * @returns {import('node:child_process').SpawnSyncReturns<Buffer>}
 */
function runRumdl(rumdlArgs) {
  const rumdlEntrypoint = path.resolve('node_modules/rumdl/bin/rumdl')
  if (!fs.existsSync(rumdlEntrypoint)) {
    throw new Error(`rumdl entrypoint not found: ${rumdlEntrypoint}`)
  }

  return spawnSync(process.execPath, [rumdlEntrypoint, ...rumdlArgs], {
    stdio: 'inherit',
  })
}

const stagedMarkdownFiles = getStagedMarkdownFiles()
if (stagedMarkdownFiles.length === 0) {
  process.exit(0)
}

const rumdlTargets = buildRumdlTargets(stagedMarkdownFiles)
const rumdlResult = runRumdl(['check', '--fix', '--', ...rumdlTargets])

if (rumdlResult.error) {
  throw rumdlResult.error
}

process.exit(rumdlResult.status ?? 1)
