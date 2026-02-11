#!/usr/bin/env node

import fs from 'node:fs'
import path from 'node:path'
import { spawnSync } from 'node:child_process'

const args = process.argv.slice(2)
const outputDirArgIndex = args.findIndex((arg) => arg === '--output-dir')

const outputDir =
  outputDirArgIndex >= 0 && args[outputDirArgIndex + 1]
    ? args[outputDirArgIndex + 1]
    : process.env.QA_BENCHMARK_DIR ?? 'artifacts/qa-benchmarks'

const now = new Date()
const nowIso = now.toISOString()
const safeTimestamp = nowIso.replaceAll(':', '-').replaceAll('.', '-')

const cwd = process.cwd()
const absoluteOutputDir = path.resolve(cwd, outputDir)
const samplesPath = path.join(absoluteOutputDir, `qa-benchmark-${safeTimestamp}.json`)
const latestPath = path.join(absoluteOutputDir, 'latest.json')
const summaryPath = path.join(absoluteOutputDir, 'summary.md')

const scenarios = [
  {
    key: 'cold_all_v1',
    label: 'cold(all) V1',
    command: ['pnpm', ['qa:all']],
  },
  {
    key: 'cold_all_v2',
    label: 'cold(all) V2',
    command: ['pnpm', ['turbo:qa:all']],
  },
  {
    key: 'warm_all_v1',
    label: 'warm(all) V1',
    command: ['pnpm', ['qa:all']],
  },
  {
    key: 'warm_all_v2',
    label: 'warm(all) V2',
    command: ['pnpm', ['turbo:qa:all']],
  },
  {
    key: 'changed_pr_v1',
    label: 'changed(PR) V1',
    command: ['pnpm', ['qa']],
  },
  {
    key: 'changed_pr_v2',
    label: 'changed(PR) V2',
    command: ['pnpm', ['turbo:qa']],
  },
]

const baseEnv = {
  ...process.env,
  FORCE_COLOR: process.env.FORCE_COLOR ?? '1',
}

function stripAnsi(input) {
  return input.replace(/\u001B\[[0-9;]*m/g, '')
}

function runScenario(scenario) {
  const [command, commandArgs] = scenario.command

  const start = process.hrtime.bigint()
  const result = spawnSync(command, commandArgs, {
    cwd,
    env: baseEnv,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  })
  const end = process.hrtime.bigint()

  const durationMs = Number(end - start) / 1_000_000
  const stdout = (result.stdout ?? '').toString()
  const stderr = (result.stderr ?? '').toString()

  const combinedOutput = stripAnsi(`${stdout}\n${stderr}`)
  const cacheSummaryMatch = combinedOutput.match(/Cached:\s+([^\n\r]+)/)

  let failedTask = null
  if ((result.status ?? 1) !== 0) {
    const failedTaskMatch = combinedOutput.match(/(^|\n)Failed:\s+([^\n\r]+)/)
    failedTask = failedTaskMatch ? failedTaskMatch[2].trim() : null
  }

  const cacheSummary = cacheSummaryMatch ? cacheSummaryMatch[1].trim() : null

  return {
    key: scenario.key,
    label: scenario.label,
    command: [command, ...commandArgs].join(' '),
    exitCode: result.status ?? 1,
    durationMs,
    cacheSummary,
    failedTask,
  }
}

function toSummaryMarkdown(report) {
  const lines = []

  lines.push('# QA Benchmark Summary')
  lines.push('')
  lines.push(`- generatedAt: ${report.generatedAt}`)
  lines.push(`- gitRef: ${report.gitRef}`)
  lines.push(`- baseRef: ${report.baseRef ?? 'not-found'}`)
  lines.push(`- benchmarkVersion: ${report.benchmarkVersion}`)
  lines.push('')
  lines.push('| 场景 | 命令 | 退出码 | 耗时(ms) | 缓存命中摘要 | 失败任务 |')
  lines.push('|---|---|---:|---:|---|---|')

  for (const sample of report.samples) {
    lines.push(
      `| ${sample.label} | \`${sample.command}\` | ${sample.exitCode} | ${sample.durationMs.toFixed(2)} | ${sample.cacheSummary ?? 'N/A'} | ${sample.failedTask ?? 'N/A'} |`,
    )
  }

  return `${lines.join('\n')}\n`
}

function getGitRef() {
  const result = spawnSync('git', ['rev-parse', '--short', 'HEAD'], {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  })

  if (result.status !== 0) {
    return 'unknown'
  }

  return (result.stdout ?? '').toString().trim()
}

function resolveBaseRef() {
  const candidates = [
    process.env.QA_BASE_REF,
    'origin/master',
    'origin/main',
    'master',
    'main',
    'HEAD~1',
  ].filter(Boolean)

  for (const ref of candidates) {
    const check = spawnSync('git', ['rev-parse', '--verify', '--quiet', ref], {
      cwd,
      stdio: 'ignore',
    })

    if (check.status === 0) {
      return ref
    }
  }

  return null
}

fs.mkdirSync(absoluteOutputDir, { recursive: true })

const report = {
  benchmarkVersion: 1,
  generatedAt: nowIso,
  gitRef: getGitRef(),
  baseRef: resolveBaseRef(),
  samples: scenarios.map(runScenario),
}

fs.writeFileSync(samplesPath, JSON.stringify(report, null, 2))
fs.writeFileSync(latestPath, JSON.stringify(report, null, 2))
fs.writeFileSync(summaryPath, toSummaryMarkdown(report))

console.log(`[qa:benchmark] report: ${path.relative(cwd, samplesPath)}`)
console.log(`[qa:benchmark] latest: ${path.relative(cwd, latestPath)}`)
console.log(`[qa:benchmark] summary: ${path.relative(cwd, summaryPath)}`)
