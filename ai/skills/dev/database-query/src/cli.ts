import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { cac } from 'cac'

import {
  ConfigError,
  createContextSnapshot,
  getEffectiveDefaults,
  loadConfig,
  resolveTarget,
} from './config.js'
import { checkSql } from './core.js'
import {
  createActionPlan,
  createClientPlan,
  createSqlExecutionPlan,
  formatExecutionPlan,
  isSqlDialect,
  PlanError,
  resolveLimit,
} from './planner.js'
import type {
  CheckResult,
  Dialect,
  ExecutionPlan,
  PermissionLevel,
  SdkExecutionPlan,
} from './types.js'

const DIALECTS = new Set<Dialect>(['postgres', 'mysql', 'sqlite'])
const LEVELS = new Set<PermissionLevel>([
  'readonly',
  'maintenance',
  'admin',
  'yolo',
])
const DEFAULT_STDOUT = console.log.bind(console)
const DEFAULT_STDERR = console.error.bind(console)

interface CliIo {
  stdout: (message: string) => void
  stderr: (message: string) => void
}

interface GlobalOptions {
  help?: boolean
}

interface CheckSqlOptions extends GlobalOptions {
  dialect?: string
  level?: string
  sql?: string
  file?: string
  maxLimit?: string | number
}

interface ConfigOptions extends GlobalOptions {
  config?: string
  instance?: string
  database?: string
  schema?: string
  collection?: string
  format?: string
  action?: string
  sql?: string
  file?: string
  level?: string
  limit?: string | number
  key?: string
  field?: string
  query?: string
  vector?: string
  verbose?: boolean
  printCommand?: boolean
  __clientPassthrough?: string[]
}

export class CliError extends Error {
  readonly exitCode: number

  /**
   * 创建可控退出错误。
   *
   * @param message 错误消息。
   * @param exitCode 进程退出码。
   */
  constructor(message: string, exitCode = 1) {
    super(message)
    this.exitCode = exitCode
  }
}

/**
 * 运行 database-query 统一 CLI。
 *
 * @param argv 进程参数，不包含 node 与脚本路径。
 * @param io 输出抽象，便于测试时捕获 stdout/stderr。
 * @returns 进程退出码。
 */
export async function runCli(
  argv: string[],
  io: CliIo = defaultIo(),
): Promise<number> {
  try {
    const clientPassthrough = extractClientPassthrough(argv)
    const cli = createCli(io)
    cli.parse(['node', 'database-query', ...argv], { run: false })
    if (clientPassthrough) {
      cli.options.__clientPassthrough = clientPassthrough
    }
    await cli.runMatchedCommand()
    return 0
  } catch (error) {
    if (isHelpError(error)) {
      return 0
    }

    if (
      error instanceof CliError ||
      error instanceof ConfigError ||
      error instanceof PlanError
    ) {
      io.stderr(error.message)
      return error.exitCode
    }

    io.stderr(error instanceof Error ? error.message : String(error))
    return 1
  }
}

/**
 * 格式化 SQL guard 检查结果。
 *
 * @param result 检查结果。
 * @returns 面向 CLI 的文本报告。
 */
export function formatResult(result: CheckResult): string {
  const lines = [
    `SQL guard: ${result.ok ? 'PASS' : 'BLOCK'}`,
    `dialect=${result.dialect} level=${result.level} kind=${result.kind} statements=${result.statementCount}`,
  ]

  if (result.level === 'yolo') {
    lines.push(
      'warning: yolo 层级只跳过静态阻断，危险操作执行仍需用户显式确认。',
    )
  }

  if (result.findings.length === 0) {
    lines.push('findings: none')
    return lines.join('\n')
  }

  lines.push('findings:')
  for (const finding of result.findings) {
    lines.push(`- [${finding.severity}] ${finding.code}: ${finding.message}`)
  }

  return lines.join('\n')
}

/**
 * 创建 database-query CLI 定义。
 *
 * @param io 输出抽象。
 * @returns 已配置的 cac CLI 实例。
 */
function createCli(io: CliIo) {
  const cli = cac('database-query')

  cli
    .command('context', '输出脱敏数据库上下文。')
    .option('--config <path>', '配置文件路径。')
    .option('--instance <id>', '聚焦指定实例。')
    .option('--format <format>', '输出格式：text 或 json。', {
      default: 'text',
    })
    .action(async (options: ConfigOptions) => {
      const loaded = await loadConfig(options.config)
      const snapshot = createContextSnapshot(loaded, options.instance)
      io.stdout(
        options.format === 'json'
          ? JSON.stringify(snapshot, null, 2)
          : formatContext(snapshot),
      )
    })

  cli
    .command('check-sql', '静态检查关系型 SQL。')
    .option('--dialect <dialect>', 'SQL 方言：postgres、mysql 或 sqlite。', {
      default: 'postgres',
    })
    .option(
      '--level <level>',
      '权限层级：readonly、maintenance、admin 或 yolo。',
      {
        default: 'readonly',
      },
    )
    .option('--sql <sql>', '直接传入 SQL 文本。')
    .option('--file <path>', '从文件读取 SQL。')
    .option('--max-limit <number>', '允许的最大 LIMIT。', {
      default: '1000',
    })
    .action((options: CheckSqlOptions) => {
      const result = runCheckSql(options)
      io.stdout(formatResult(result))
      if (!result.ok) {
        throw new CliError('SQL guard 阻断执行。', 2)
      }
    })

  cli.command('doctor', '检查底层客户端可用性。').action(async () => {
    io.stdout(await formatDoctor())
  })

  cli
    .command('exec', '执行受控数据库动作。')
    .option('--config <path>', '配置文件路径。')
    .option('--instance <id>', '目标实例。')
    .option('--database <name>', '目标数据库。')
    .option('--schema <name>', '目标 schema。')
    .option('--collection <name>', '目标 collection。')
    .option('--sql <sql>', '关系型 SQL 文本。')
    .option('--file <path>', '从文件读取关系型 SQL。')
    .option('--level <level>', 'SQL guard 权限层级。')
    .option('--action <name>', 'MongoDB/Redis/Milvus 只读动作。')
    .option('--limit <number>', '动作 limit。')
    .option('--key <key>', 'Redis key 或 collection 名称。')
    .option('--field <field>', 'Redis hash field。')
    .option('--query <json>', 'MongoDB/Milvus 查询条件。')
    .option('--vector <json>', 'Milvus search 向量。')
    .option('--verbose', '执行前打印脱敏执行计划。')
    .option('--print-command', '只打印脱敏执行计划，不执行。')
    .action(async (options: ConfigOptions) => {
      await runExec(options, io)
    })

  cli
    .command('client [...args]', '使用配置凭据启动底层官方客户端。', {
      allowUnknownOptions: true,
    })
    .option('--config <path>', '配置文件路径。')
    .option('--instance <id>', '目标实例。')
    .option('--database <name>', '目标数据库。')
    .option('--schema <name>', '目标 schema。')
    .option('--collection <name>', '目标 collection。')
    .option('--print-command', '只打印脱敏启动计划，不启动客户端。')
    .action(async (args: string[], options: ConfigOptions) => {
      await runClient(options.__clientPassthrough ?? args, options, io)
    })

  cli.help()
  return patchHelpOutput(cli, io)
}

/**
 * 执行 check-sql 子命令。
 *
 * @param options CLI 选项。
 * @returns 检查结果。
 */
function runCheckSql(options: CheckSqlOptions): CheckResult {
  const normalizedOptions = {
    dialect: parseDialect(options.dialect ?? 'postgres'),
    level: parseLevel(options.level ?? 'readonly'),
    maxLimit: parsePositiveInteger(
      String(options.maxLimit ?? 1000),
      'max-limit',
    ),
  }
  const sql = readSqlInput(options)
  return checkSql(sql, normalizedOptions)
}

/**
 * 执行受控 exec 子命令。
 *
 * @param options CLI 选项。
 * @param io 输出抽象。
 * @returns 无返回值。
 */
async function runExec(options: ConfigOptions, io: CliIo): Promise<void> {
  const loaded = await loadConfig(options.config)
  const target = resolveTarget(loaded.config, {
    instance: options.instance,
    database: options.database,
    schema: options.schema,
    collection: options.collection,
    requireDatabase: Boolean(options.sql || options.file || options.action),
  })
  let plan: ExecutionPlan

  if (isSqlDialect(target.instance.type)) {
    const sql = readSqlInput(options)
    const defaults = getEffectiveDefaults(loaded.config)
    const result = checkSql(sql, {
      dialect: target.instance.type,
      level: parseLevel(options.level ?? defaults.permissionLevel),
      maxLimit: defaults.maxLimit,
    })

    if (options.verbose || options.printCommand || !result.ok) {
      io.stdout(formatResult(result))
    }

    if (!result.ok) {
      throw new CliError('SQL guard 阻断执行。', 2)
    }

    plan = createSqlExecutionPlan(target, { sql })
  } else {
    if (!options.action) {
      throw new CliError('非关系型 exec 必须提供 --action。')
    }

    plan = createActionPlan(loaded.config, target, {
      action: options.action,
      key: options.key,
      field: options.field,
      query: options.query,
      vector: options.vector,
      limit: options.limit
        ? resolveLimit(
            loaded.config,
            parsePositiveInteger(String(options.limit), 'limit'),
          )
        : resolveLimit(loaded.config),
    })
  }

  await runPlan(plan, {
    io,
    verbose: options.verbose,
    printCommand: options.printCommand,
  })
}

/**
 * 执行凭据桥接 client 子命令。
 *
 * @param passthrough 透传到底层 CLI 的参数。
 * @param options CLI 选项。
 * @param io 输出抽象。
 * @returns 无返回值。
 */
async function runClient(
  passthrough: string[],
  options: ConfigOptions,
  io: CliIo,
): Promise<void> {
  const loaded = await loadConfig(options.config)
  const target = resolveTarget(loaded.config, {
    instance: options.instance,
    database: options.database,
    schema: options.schema,
    collection: options.collection,
  })
  const plan = createClientPlan(target, passthrough)
  await runPlan(plan, {
    io,
    verbose: true,
    printCommand: options.printCommand,
  })
}

/**
 * 执行或打印执行计划。
 *
 * @param plan 执行计划。
 * @param options 执行选项。
 * @returns 无返回值。
 */
async function runPlan(
  plan: ExecutionPlan,
  options: {
    io: CliIo
    verbose?: boolean
    printCommand?: boolean
  },
): Promise<void> {
  if (options.verbose || options.printCommand) {
    options.io.stdout(formatExecutionPlan(plan))
  }

  if (options.printCommand) {
    return
  }

  if (plan.sdk) {
    const result = await runSdkPlan(plan.sdk)
    options.io.stdout(JSON.stringify(result, null, 2))
    return
  }

  if (plan.args.length === 0) {
    options.io.stdout(plan.summary)
    return
  }

  const result = spawnSync(plan.tool, plan.args, {
    env: { ...process.env, ...plan.env },
    encoding: 'utf8',
    stdio: 'pipe',
  })

  if (result.stdout) {
    options.io.stdout(result.stdout.trimEnd())
  }
  if (result.stderr) {
    options.io.stderr(result.stderr.trimEnd())
  }
  if (result.error) {
    throw new CliError(result.error.message)
  }
  if (result.status && result.status !== 0) {
    throw new CliError(`${plan.tool} 退出码: ${result.status}`, result.status)
  }
}

/**
 * 执行 SDK 计划。
 *
 * @param plan SDK 执行计划。
 * @returns SDK 原始返回值。
 */
async function runSdkPlan(plan: SdkExecutionPlan): Promise<unknown> {
  if (plan.provider === 'milvus') {
    return runMilvusPlan(plan)
  }

  throw new CliError(`不支持的 SDK provider: ${plan.provider}`)
}

/**
 * 执行 Milvus 只读 SDK 动作。
 *
 * @param plan Milvus SDK 执行计划。
 * @returns Milvus SDK 返回值。
 */
async function runMilvusPlan(plan: SdkExecutionPlan): Promise<unknown> {
  const sdkName = '@zilliz/milvus2-sdk-node'
  const { MilvusClient } = await import(sdkName).catch(() => {
    throw new CliError(
      '缺少 @zilliz/milvus2-sdk-node。请在 skill 或项目环境安装该 SDK 后再执行 Milvus 动作。',
    )
  })
  const client = new MilvusClient({
    address: plan.address,
    token: plan.token,
  })

  if (plan.action === 'list-collections') {
    return client.showCollections()
  }

  if (plan.action === 'describe-collection') {
    requireCliValue(
      plan.collection,
      'Milvus describe-collection 需要 collection。',
    )
    return client.describeCollection({ collection_name: plan.collection })
  }

  if (plan.action === 'query') {
    requireCliValue(plan.collection, 'Milvus query 需要 collection。')
    return client.query({
      collection_name: plan.collection,
      filter: plan.query,
      limit: plan.limit,
    })
  }

  if (plan.action === 'search') {
    requireCliValue(plan.collection, 'Milvus search 需要 collection。')
    requireCliValue(plan.vector, 'Milvus search 需要 --vector JSON 数组。')
    return client.search({
      collection_name: plan.collection,
      data: [JSON.parse(plan.vector)],
      filter: plan.query,
      limit: plan.limit,
    })
  }

  throw new CliError(`不支持的 Milvus 动作: ${plan.action}`)
}

/**
 * 格式化上下文快照。
 *
 * @param snapshot 脱敏上下文。
 * @returns 人类可读文本。
 */
function formatContext(
  snapshot: ReturnType<typeof createContextSnapshot>,
): string {
  const lines = [
    `config: ${snapshot.configPath ?? '<unknown>'}`,
    `defaults: instance=${snapshot.defaults.defaultInstance ?? '<auto>'} limit=${snapshot.defaults.limit} maxLimit=${snapshot.defaults.maxLimit} level=${snapshot.defaults.permissionLevel}`,
  ]

  for (const instance of snapshot.instances) {
    lines.push(
      `- ${instance.id} (${instance.type}) defaultDatabase=${instance.defaultDatabase ?? '<auto>'} actions=${instance.allowedActions.join(', ')}`,
    )
    for (const database of instance.databases) {
      const namespaces = [
        database.schemas?.length ? `schemas=${database.schemas.join(',')}` : '',
        database.collections?.length
          ? `collections=${database.collections.join(',')}`
          : '',
      ]
        .filter(Boolean)
        .join(' ')
      lines.push(`  - ${database.name}${namespaces ? ` ${namespaces}` : ''}`)
    }
  }

  return lines.join('\n')
}

/**
 * 格式化 doctor 检查结果。
 *
 * @returns doctor 文本。
 */
async function formatDoctor(): Promise<string> {
  const tools = ['psql', 'mysql', 'sqlite3', 'mongosh', 'redis-cli']
  const lines = ['database-query doctor:']

  for (const tool of tools) {
    const result = spawnSync(tool, ['--version'], {
      encoding: 'utf8',
      stdio: 'pipe',
    })
    lines.push(`- ${tool}: ${result.error ? 'missing' : 'ok'}`)
    if (result.error) {
      lines.push(...formatInstallHints(tool))
    }
  }

  const milvusSdkAvailable = await hasMilvusSdk()
  lines.push(
    `- @zilliz/milvus2-sdk-node: ${milvusSdkAvailable ? 'ok' : 'missing'} (Milvus exec actions)`,
  )
  if (!milvusSdkAvailable) {
    lines.push(...formatInstallHints('@zilliz/milvus2-sdk-node'))
  }
  lines.push('install reference: references/client-installation.md')

  return lines.join('\n')
}

/**
 * 检查 Milvus Node SDK 是否可动态加载。
 *
 * @returns SDK 可用时返回 true。
 */
async function hasMilvusSdk(): Promise<boolean> {
  const sdkName = '@zilliz/milvus2-sdk-node'
  try {
    await import(sdkName)
    return true
  } catch {
    return false
  }
}

/**
 * 返回带缩进的工具安装提示。
 *
 * @param tool 工具名。
 * @returns 安装提示行。
 */
function formatInstallHints(tool: string): string[] {
  const hints: Record<string, string[]> = {
    psql: [
      '  install: Windows: winget install PostgreSQL.PostgreSQL 或 scoop install postgresql',
      '  install: macOS: brew install libpq',
      '  install: Debian/Ubuntu: sudo apt-get install postgresql-client',
    ],
    mysql: [
      '  install: Windows: winget install Oracle.MySQL 或 scoop install mysql',
      '  install: macOS: brew install mysql-client',
      '  install: Debian/Ubuntu: sudo apt-get install mysql-client',
    ],
    sqlite3: [
      '  install: Windows: winget install SQLite.SQLite 或 scoop install sqlite',
      '  install: macOS: brew install sqlite',
      '  install: Debian/Ubuntu: sudo apt-get install sqlite3',
    ],
    mongosh: [
      '  install: Windows: winget install MongoDB.Shell 或 scoop install mongosh',
      '  install: macOS: brew install mongosh',
      '  install: Debian/Ubuntu: 按 MongoDB 官方仓库安装 mongodb-mongosh',
    ],
    'redis-cli': [
      '  install: Windows: 优先使用 WSL/容器内 redis-tools，或 scoop install redis',
      '  install: macOS: brew install redis',
      '  install: Debian/Ubuntu: sudo apt-get install redis-tools',
    ],
    '@zilliz/milvus2-sdk-node': [
      '  install: 在运行 database-query.js 的 skill/项目目录安装 @zilliz/milvus2-sdk-node',
      '  install: pnpm add @zilliz/milvus2-sdk-node 或 npm install @zilliz/milvus2-sdk-node',
    ],
  }

  return hints[tool] ?? ['  install: 查看 references/client-installation.md']
}

/**
 * 校验 CLI 必填字符串。
 *
 * @param value 待校验值。
 * @param message 缺失时报错消息。
 * @returns 无返回值。
 */
function requireCliValue(
  value: string | undefined,
  message: string,
): asserts value is string {
  if (!value) {
    throw new CliError(message)
  }
}

/**
 * 从 `--sql` 或 `--file` 读取待检查 SQL。
 *
 * @param options CLI 选项。
 * @returns SQL 文本。
 */
function readSqlInput(options: Pick<CheckSqlOptions, 'sql' | 'file'>): string {
  if (options.sql && options.file) {
    throw new CliError('只能指定 --sql 或 --file 其中一个。')
  }

  if (options.sql) {
    return options.sql
  }

  if (options.file) {
    return readFileSync(options.file, 'utf8')
  }

  throw new CliError('请通过 --sql 或 --file 提供 SQL。')
}

/**
 * 解析并校验 SQL 方言。
 *
 * @param value CLI 输入的方言名称。
 * @returns 受支持的 SQL 方言。
 */
function parseDialect(value: string): Dialect {
  if (!DIALECTS.has(value as Dialect)) {
    throw new CliError(`不支持的 dialect: ${value}`)
  }

  return value as Dialect
}

/**
 * 解析并校验权限层级。
 *
 * @param value CLI 输入的权限层级。
 * @returns 受支持的权限层级。
 */
function parseLevel(value: string): PermissionLevel {
  if (!LEVELS.has(value as PermissionLevel)) {
    throw new CliError(`不支持的 level: ${value}`)
  }

  return value as PermissionLevel
}

/**
 * 解析正整数参数。
 *
 * @param value CLI 输入的数字文本。
 * @param label 参数名。
 * @returns 正整数。
 */
function parsePositiveInteger(value: string, label: string): number {
  const parsed = Number.parseInt(value, 10)
  if (!Number.isInteger(parsed) || parsed <= 0) {
    throw new CliError(`--${label} 必须是正整数。`)
  }

  return parsed
}

/**
 * 让 cac 内置 help 使用当前 IO 抽象。
 *
 * @param cli cac CLI。
 * @param io 输出抽象。
 * @returns cac CLI。
 */
function patchHelpOutput<T extends ReturnType<typeof cac>>(
  cli: T,
  io: CliIo,
): T {
  const originalOutputHelp = cli.outputHelp.bind(cli)
  cli.outputHelp = () => {
    const originalLog = console.log
    console.log = (...values) => io.stdout(values.map(String).join(' '))
    try {
      originalOutputHelp()
    } finally {
      console.log = originalLog
    }
  }

  return cli
}

/**
 * 提取 client 子命令 `--` 后透传参数。
 *
 * @param argv 原始 CLI 参数。
 * @returns 透传参数；非 client 或未透传时返回 undefined。
 */
function extractClientPassthrough(argv: string[]): string[] | undefined {
  if (argv[0] !== 'client') {
    return undefined
  }

  const separatorIndex = argv.indexOf('--')
  if (separatorIndex < 0) {
    return undefined
  }

  return argv.slice(separatorIndex + 1)
}

/**
 * 判断 cac help 抛出的退出信号。
 *
 * @param error 捕获的错误。
 * @returns 是 help 退出信号时返回 true。
 */
function isHelpError(error: unknown): boolean {
  return Boolean(
    error &&
      typeof error === 'object' &&
      'message' in error &&
      String((error as Error).message).includes('CACError'),
  )
}

/**
 * 创建默认 CLI IO。
 *
 * @returns 使用原始 console 输出函数的 IO 抽象。
 */
function defaultIo(): CliIo {
  return {
    stdout: DEFAULT_STDOUT,
    stderr: DEFAULT_STDERR,
  }
}
