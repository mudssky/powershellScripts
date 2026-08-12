import { spawn, spawnSync } from 'node:child_process'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'
import { pathToFileURL } from 'node:url'

const cwd = process.cwd()

/**
 * 解析耗时报告命令行参数。
 *
 * @param {string[]} argv 命令行参数
 * @returns {{ filePath: string | null, command: string | null, nunitPath: string | null, jsonPath: string | null, lane: string, top: number | null }}
 */
export function parseArgs(argv = process.argv.slice(2)) {
  const parsed = {
    filePath: null,
    command: null,
    nunitPath: null,
    jsonPath: null,
    lane: 'single',
    top: null,
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]
    const value = argv[index + 1] ?? null
    if (arg === '--file') parsed.filePath = value
    else if (arg === '--command') parsed.command = value
    else if (arg === '--nunit') parsed.nunitPath = value
    else if (arg === '--json') parsed.jsonPath = value
    else if (arg === '--lane' && value) parsed.lane = value
    else if (arg === '--top') {
      const parsedTop = Number.parseInt(value ?? '', 10)
      if (parsedTop > 0) parsed.top = parsedTop
    } else continue
    index += 1
  }

  return parsed
}

/**
 * 从被测命令中读取显式指定的 Pester 版本。
 *
 * @param {string | null} command 被测命令文本
 * @returns {string | null}
 */
export function parsePesterVersion(command) {
  if (!command) return null

  const tokens = [...command.matchAll(/"(?:[^"\\]|\\.)*"|'[^']*'|[^\s]+/g)].map(
    (match) => match[0],
  )
  /**
   * 去除单个命令参数外围的成对引号。
   *
   * @param {string} value 命令参数
   * @returns {string}
   */
  const unquote = (value) => {
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      return value.slice(1, -1)
    }
    return value
  }

  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index]
    const inlineMatch = token.match(/^-PesterVersion:(.*)$/i)
    if (inlineMatch) {
      return unquote(inlineMatch[1] || tokens[index + 1] || '') || null
    }
    if (/^-PesterVersion$/i.test(token)) {
      return tokens[index + 1] ? unquote(tokens[index + 1]) : null
    }
  }
  return null
}

/**
 * 按 runner 的版本选择合同解析 artifact 中应记录的 Pester 版本。
 *
 * @param {string | null} command 被测命令文本
 * @param {string | undefined} environmentVersion 环境变量指定版本
 * @param {string | null} pinnedVersion 仓库固定版本
 * @param {string | null} installedVersion 已安装版本探测结果
 * @returns {string | null}
 */
export function resolvePesterVersion(
  command,
  environmentVersion,
  pinnedVersion,
  installedVersion,
) {
  const candidates = [
    parsePesterVersion(command),
    environmentVersion,
    pinnedVersion,
    installedVersion,
  ]
  for (const candidate of candidates) {
    const normalized = candidate?.trim()
    if (normalized) return normalized
  }
  return null
}

/**
 * 去除控制台 ANSI 转义码。
 *
 * @param {string} value 原始文本
 * @returns {string}
 */
export function stripAnsi(value) {
  // biome-ignore lint/complexity/useRegexLiterals: 字符串形式避免控制字符规则误判 ANSI ESC。
  return value.replace(new RegExp('\\x1B\\[[0-?]*[ -/]*[@-~]', 'g'), '')
}

/**
 * 将 Pester 持续时间转换为毫秒。
 *
 * @param {string} rawDuration 持续时间文本
 * @returns {number}
 */
export function durationToMs(rawDuration) {
  const match = rawDuration.trim().match(/^(\d+(?:\.\d+)?)\s*(ms|s|m)$/i)
  if (!match) return 0
  const value = Number.parseFloat(match[1])
  if (match[2].toLowerCase() === 'ms') return value
  if (match[2].toLowerCase() === 'm') return value * 60_000
  return value * 1000
}

/**
 * 从控制台日志提取文件级和阶段耗时。
 *
 * @param {string} text 控制台日志
 * @returns {{ files: Array<{ lane: string, path: string, durationMs: number }>, phases: { discoveryMs: number | null, runMs: number | null, coverageMs: number | null } }}
 */
export function parseConsoleDurations(text) {
  const files = []
  const phases = { discoveryMs: null, runMs: null, coverageMs: null }
  const normalizedText = stripAnsi(text)
  const filePattern =
    /^(?:\[(?<lane>[^\]]+)\]\s+)?\[\+\]\s+(?<path>.+?)\s+(?<duration>\d+(?:\.\d+)?(?:ms|s|m))\s+\(/

  for (const line of normalizedText.split(/\r?\n/)) {
    const fileMatch = line.match(filePattern)
    if (fileMatch?.groups) {
      files.push({
        lane: fileMatch.groups.lane ?? 'single',
        path: fileMatch.groups.path.trim(),
        durationMs: durationToMs(fileMatch.groups.duration),
      })
    }

    const phasePatterns = [
      [
        'discoveryMs',
        /Discovery (?:finished|found .*?) in\s+(\d+(?:\.\d+)?(?:ms|s|m))/i,
      ],
      ['runMs', /Tests completed in\s+(\d+(?:\.\d+)?(?:ms|s|m))/i],
      [
        'coverageMs',
        /(?:Code Coverage result processed|Coverage processing finished) in\s+(\d+(?:\.\d+)?(?:ms|s|m))/i,
      ],
    ]
    for (const [key, pattern] of phasePatterns) {
      const match = line.match(pattern)
      if (match) phases[key] = durationToMs(match[1])
    }
  }

  files.sort((left, right) => right.durationMs - left.durationMs)
  return { files, phases }
}

/**
 * 解码 XML 属性中的基础实体。
 *
 * @param {string} value XML 属性值
 * @returns {string}
 */
function decodeXmlAttribute(value) {
  return value
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
}

/**
 * 从 NUnit3 XML 提取文件与测试用例耗时。
 *
 * @param {string} xml NUnit3 文本
 * @param {string} lane lane 名称
 * @returns {{ files: Array<{ lane: string, path: string, durationMs: number, result: string }>, testCases: Array<{ lane: string, name: string, className: string, durationMs: number, result: string }> }}
 */
export function parseNUnitDurations(xml, lane = 'single') {
  const files = []
  const testCases = []
  const tagPattern = /<(test-suite|test-case)\b([^>]*?)\/?>(?:\s*)/g

  for (const match of xml.matchAll(tagPattern)) {
    const tagName = match[1]
    const attributes = Object.fromEntries(
      [...match[2].matchAll(/([\w-]+)="([^"]*)"/g)].map((entry) => [
        entry[1],
        decodeXmlAttribute(entry[2]),
      ]),
    )
    const durationMs = Number.parseFloat(attributes.duration ?? '0') * 1000
    if (tagName === 'test-suite' && attributes.type === 'Assembly') {
      files.push({
        lane,
        path: attributes.fullname ?? attributes.name ?? '',
        durationMs,
        result: attributes.result ?? 'Unknown',
      })
    }
    if (tagName === 'test-case') {
      testCases.push({
        lane,
        name: attributes.fullname ?? attributes.name ?? '',
        className: attributes.classname ?? '',
        durationMs,
        result: attributes.result ?? 'Unknown',
      })
    }
  }

  files.sort((left, right) => right.durationMs - left.durationMs)
  testCases.sort((left, right) => right.durationMs - left.durationMs)
  return { files, testCases }
}

/**
 * 执行外部命令并透传输出。
 *
 * @param {string} command 命令文本
 * @param {NodeJS.ProcessEnv} env 子进程环境变量
 * @returns {Promise<{ exitCode: number, output: string }>}
 */
async function runCommand(command, env) {
  return await new Promise((resolve, reject) => {
    const child = spawn(command, {
      cwd,
      env,
      shell: true,
      stdio: ['inherit', 'pipe', 'pipe'],
    })
    let output = ''
    for (const [stream, target] of [
      [child.stdout, process.stdout],
      [child.stderr, process.stderr],
    ]) {
      stream.on('data', (chunk) => {
        const value = chunk.toString()
        output += value
        target.write(value)
      })
    }
    child.on('error', reject)
    child.on('close', (code) => resolve({ exitCode: code ?? 1, output }))
  })
}

/**
 * 打印 Top N 耗时表。
 *
 * @param {string} title 标题
 * @param {Array<{ lane: string, path?: string, name?: string, durationMs: number }>} rows 数据行
 * @param {number | null} top 最大行数
 * @returns {void}
 */
function printReport(title, rows, top) {
  const limitedRows = top ? rows.slice(0, top) : rows
  if (limitedRows.length === 0) return
  console.log(`\n=== ${title} ===`)
  for (const row of limitedRows) {
    console.log(
      `${row.lane.padEnd(8)} ${(row.durationMs / 1000).toFixed(3).padStart(10)}s  ${row.path ?? row.name}`,
    )
  }
}

/**
 * 读取外部工具版本；工具不可用时返回 null。
 *
 * @param {string} command 命令名
 * @param {string[]} args 命令参数
 * @returns {string | null}
 */
function readToolVersion(command, args) {
  const result = spawnSync(command, args, {
    cwd,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'ignore'],
  })
  if (result.status !== 0) return null
  const value = result.stdout.trim()
  return value || null
}

/**
 * 执行 CLI 主流程。
 *
 * @param {string[]} argv 命令行参数
 * @returns {Promise<number>}
 */
export async function main(argv = process.argv.slice(2)) {
  const options = parseArgs(argv)
  if (!options.filePath && !options.command) {
    console.error(
      '[pester-duration-report] usage: --file <log> | --command "<cmd>" [--nunit <xml>] [--json <json>] [--lane host] [--top 10]',
    )
    return 1
  }

  const timestamp = new Date()
    .toISOString()
    .replaceAll(':', '-')
    .replaceAll('.', '-')
  const reportDirectory = path.resolve(cwd, 'tests/reports')
  const nunitPath = path.resolve(
    cwd,
    options.nunitPath ??
      path.join(reportDirectory, `pester-duration-${timestamp}.xml`),
  )
  const jsonPath = path.resolve(
    cwd,
    options.jsonPath ??
      path.join(reportDirectory, `pester-duration-${timestamp}.json`),
  )
  await mkdir(path.dirname(jsonPath), { recursive: true })

  const startedAt = new Date()
  let output = ''
  let exitCode = 0
  if (options.command) {
    const result = await runCommand(options.command, {
      ...process.env,
      PESTER_RESULT_PATH: nunitPath,
    })
    output = result.output
    exitCode = result.exitCode
  } else {
    output = await readFile(path.resolve(cwd, options.filePath), 'utf8')
  }
  const endedAt = new Date()

  let pinnedPesterVersion = null
  try {
    pinnedPesterVersion = await readFile(
      path.resolve(cwd, '.pester-version'),
      'utf8',
    )
  } catch {
    // 非仓库目录中的独立 reporter 调用允许回退到已安装版本探测。
  }
  const requestedPesterVersion = resolvePesterVersion(
    options.command,
    process.env.PWSH_PESTER_VERSION,
    pinnedPesterVersion,
    null,
  )
  const installedPesterVersion = requestedPesterVersion
    ? null
    : readToolVersion('pwsh', [
        '-NoProfile',
        '-Command',
        '(Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1).Version.ToString()',
      ])

  const consoleData = parseConsoleDurations(output)
  let nunitData = { files: [], testCases: [] }
  try {
    nunitData = parseNUnitDurations(
      await readFile(nunitPath, 'utf8'),
      options.lane,
    )
  } catch {
    // 失败命令或纯日志分析允许没有 NUnit 文件，artifact 仍保留控制台阶段信息。
  }
  const hasMultipleConsoleLanes =
    new Set(consoleData.files.map((file) => file.lane)).size > 1
  const files = hasMultipleConsoleLanes
    ? consoleData.files
    : nunitData.files.length > 0
      ? nunitData.files
      : consoleData.files
  const artifact = {
    schemaVersion: 1,
    command: options.command,
    lane: options.lane,
    platform: process.platform,
    architecture: process.arch,
    nodeVersion: process.version,
    pwshVersion: readToolVersion('pwsh', [
      '-NoProfile',
      '-Command',
      '$PSVersionTable.PSVersion.ToString()',
    ]),
    pesterVersion: resolvePesterVersion(
      options.command,
      process.env.PWSH_PESTER_VERSION,
      pinnedPesterVersion,
      installedPesterVersion,
    ),
    startedAt: startedAt.toISOString(),
    endedAt: endedAt.toISOString(),
    elapsedMs: endedAt.getTime() - startedAt.getTime(),
    exitCode,
    phases: consoleData.phases,
    nunitPath,
    files,
    testCases: nunitData.testCases,
  }
  await writeFile(jsonPath, `${JSON.stringify(artifact, null, 2)}\n`, 'utf8')

  printReport('Slowest Pester Files', files, options.top)
  printReport('Slowest Pester Test Cases', nunitData.testCases, options.top)
  console.log(`\n[pester-duration-report] artifact=${jsonPath}`)
  return exitCode
}

const isDirectRun =
  process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href
if (isDirectRun) process.exit(await main())
