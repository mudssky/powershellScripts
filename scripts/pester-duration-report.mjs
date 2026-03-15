import { spawn } from 'node:child_process'
import { readFile } from 'node:fs/promises'
import path from 'node:path'

const cwd = process.cwd()
const args = process.argv.slice(2)

/**
 * 解析命令行参数。
 *
 * 支持两种模式：
 * - `--file <path>`：读取已有日志文件并生成排序报告
 * - `--command "<cmd>"`：执行命令、实时透传输出，并在结束后生成排序报告
 *
 * @returns {{ filePath: string | null, command: string | null, top: number | null }}
 */
function parseArgs() {
  /** @type {{ filePath: string | null, command: string | null, top: number | null }} */
  const parsed = {
    filePath: null,
    command: null,
    top: null,
  }

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index]
    if (arg === '--file') {
      parsed.filePath = args[index + 1] ?? null
      index += 1
      continue
    }

    if (arg === '--command') {
      parsed.command = args[index + 1] ?? null
      index += 1
      continue
    }

    if (arg === '--top') {
      const rawTop = args[index + 1] ?? ''
      const parsedTop = Number.parseInt(rawTop, 10)
      if (!Number.isNaN(parsedTop) && parsedTop > 0) {
        parsed.top = parsedTop
      }
      index += 1
      continue
    }
  }

  return parsed
}

/**
 * 去除控制台 ANSI 转义码，保证正则匹配稳定。
 *
 * @param {string} text
 * @returns {string}
 */
function stripAnsi(text) {
  return text.replace(/\u001B\[[0-9;]*m/g, '')
}

/**
 * 将 Pester 摘要中的持续时间转换为毫秒。
 *
 * @param {string} rawDuration
 * @returns {number}
 */
function durationToMs(rawDuration) {
  if (rawDuration.endsWith('ms')) {
    return Number.parseFloat(rawDuration.slice(0, -2))
  }

  return Number.parseFloat(rawDuration.slice(0, -1)) * 1000
}

/**
 * 从控制台日志中提取文件级 Pester 耗时。
 *
 * 支持：
 * - `pnpm test:pwsh:full`
 * - `pnpm test:pwsh:linux:full`
 * - `pnpm test:pwsh:all`（带 `[host]` / `[linux]` 前缀）
 *
 * @param {string} text
 * @returns {Array<{ lane: string, pathText: string, durationText: string, durationMs: number }>}
 */
function extractDurations(text) {
  const results = []
  const normalizedText = stripAnsi(text)
  const lines = normalizedText.split(/\r?\n/)
  const pattern =
    /^(?:\[(?<lane>[^\]]+)\]\s+)?\[\+\]\s+(?<path>.+?)\s+(?<duration>\d+(?:\.\d+)?(?:ms|s))\s+\(/

  for (const line of lines) {
    const match = line.match(pattern)
    if (!match?.groups) {
      continue
    }

    const lane = match.groups.lane ?? 'single'
    const pathText = match.groups.path.trim()
    const durationText = match.groups.duration
    results.push({
      lane,
      pathText,
      durationText,
      durationMs: durationToMs(durationText),
    })
  }

  return results.sort((left, right) => right.durationMs - left.durationMs)
}

/**
 * 以简单对齐格式打印排序报告。
 *
 * @param {Array<{ lane: string, pathText: string, durationText: string, durationMs: number }>} rows
 * @param {number | null} top
 */
function printReport(rows, top) {
  const limitedRows = top ? rows.slice(0, top) : rows
  if (limitedRows.length === 0) {
    console.error('[pester-duration-report] no Pester duration rows found')
    return
  }

  const laneWidth = Math.max(
    'lane'.length,
    ...limitedRows.map((row) => row.lane.length),
  )
  const durationWidth = Math.max(
    'duration'.length,
    ...limitedRows.map((row) => row.durationText.length),
  )

  console.log('\n=== Slowest Pester Files ===')
  console.log(
    `${'lane'.padEnd(laneWidth)}  ${'duration'.padEnd(durationWidth)}  path`,
  )

  for (const row of limitedRows) {
    console.log(
      `${row.lane.padEnd(laneWidth)}  ${row.durationText.padEnd(durationWidth)}  ${row.pathText}`,
    )
  }
}

/**
 * 执行外部命令并保留原始输出，同时把完整日志收集回来用于排序。
 *
 * @param {string} command
 * @returns {Promise<{ exitCode: number, output: string }>}
 */
async function runCommand(command) {
  return await new Promise((resolve, reject) => {
    const child = spawn(command, {
      cwd,
      shell: true,
      stdio: ['inherit', 'pipe', 'pipe'],
    })

    let output = ''

    child.stdout.on('data', (chunk) => {
      const text = chunk.toString()
      output += text
      process.stdout.write(text)
    })

    child.stderr.on('data', (chunk) => {
      const text = chunk.toString()
      output += text
      process.stderr.write(text)
    })

    child.on('error', reject)
    child.on('close', (code) => {
      resolve({
        exitCode: code ?? 1,
        output,
      })
    })
  })
}

const { filePath, command, top } = parseArgs()

if (!filePath && !command) {
  console.error(
    '[pester-duration-report] usage: node ./scripts/pester-duration-report.mjs --file <log> | --command "<cmd>" [--top 10]',
  )
  process.exit(1)
}

let exitCode = 0
let output = ''

if (command) {
  const result = await runCommand(command)
  exitCode = result.exitCode
  output = result.output
} else if (filePath) {
  const absolutePath = path.resolve(cwd, filePath)
  output = await readFile(absolutePath, 'utf8')
}

const rows = extractDurations(output)
printReport(rows, top)

process.exit(exitCode)
