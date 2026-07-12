import { spawnSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { mkdir, writeFile } from 'node:fs/promises'
import { basename, dirname, resolve } from 'node:path'
import { cac } from 'cac'

import {
  ConfigError,
  createContextSnapshot,
  findDefaultConfigPath,
  getConfigSearchPaths,
  getEffectiveDefaults,
  getGlobalLocalConfigPath,
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
  DatabaseEntry,
  DatabaseInstance,
  DatabaseQueryConfig,
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

type ToolOrigin = 'native' | 'windows-exe'

interface ToolProbeResult {
  name: string
  command?: string
  origin?: ToolOrigin
  version?: string
}

interface ToolRunResult {
  ok: boolean
  output?: string
}

type ToolRunner = (command: string, args: string[]) => ToolRunResult

interface ProcessRunResult {
  status: number | null
  stdout: string
  stderr: string
  error?: Error
}

type ProcessRunner = (
  command: string,
  args: string[],
  env: NodeJS.ProcessEnv,
) => ProcessRunResult

interface DiscoverDatabasesSummary {
  configPath: string
  instance: string
  type: 'postgres' | 'mysql'
  connectionDatabase?: string
  discovered: string[]
  selected: string[]
  write: boolean
  backupPath?: string
  updatedPath?: string
}

interface CliIo {
  stdout: (message: string) => void
  stderr: (message: string) => void
}

interface GlobalOptions {
  help?: boolean
}

interface HelpSection {
  title?: string
  body: string
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

interface ConfigCommandOptions extends GlobalOptions {
  config?: string
  database?: string
  exclude?: string
  format?: string
  global?: boolean
  include?: string
  instance?: string
  write?: boolean
}

interface InitConfigOptions extends GlobalOptions {
  global?: boolean
  path?: string
  print?: boolean
  force?: boolean
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
    if (tryOutputHelp(argv, cli, io)) {
      return 0
    }

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
    .command('config <action>', '输出配置文件查找路径或当前配置。')
    .option('--config <path>', '显式配置文件路径。')
    .option('--instance <id>', '目标实例。')
    .option('--database <name>', 'PostgreSQL 发现连接库。')
    .option('--include <patterns>', '逗号分隔的库名 glob 白名单。')
    .option('--exclude <patterns>', '逗号分隔的库名 glob 排除列表。')
    .option('--write', '将发现结果写回本机 local JSON 配置。')
    .option('--global', '强制读取并写回 XDG 全局 local JSON 配置。')
    .option('--format <format>', '输出格式：text 或 json。', {
      default: 'text',
    })
    .action(async (action: string, options: ConfigCommandOptions) => {
      await runConfigCommand(action, options, io)
    })

  cli
    .command('init-config', '生成最小 database-query 配置模板。')
    .option('--global', '写入 XDG 用户级全局配置路径。')
    .option('--path <path>', '写入指定配置路径。')
    .option('--print', '只打印模板，不写文件。')
    .option('--force', '允许覆盖已有配置文件。')
    .action(async (options: InitConfigOptions) => {
      await runInitConfig(options, io)
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

  cli.help((sections) => {
    io.stdout(formatHelpSections(sections))
    return []
  })
  return patchHelpOutput(cli, io)
}

/**
 * 生成最小配置模板并按需写入文件。
 *
 * @param options CLI 选项。
 * @param io 输出抽象。
 * @returns 无返回值。
 */
async function runInitConfig(
  options: InitConfigOptions,
  io: CliIo,
): Promise<void> {
  const content = createMinimalConfigTemplate()
  if (options.print) {
    io.stdout(content)
    return
  }

  const targetPath = resolveInitConfigPath(options)
  await mkdir(dirname(targetPath), { recursive: true, mode: 0o700 })
  await writeFile(targetPath, content, {
    flag: options.force ? 'w' : 'wx',
    mode: 0o600,
  }).catch((error: NodeJS.ErrnoException) => {
    if (error.code === 'EEXIST') {
      throw new CliError(
        `配置文件已存在: ${targetPath}。如需覆盖请传 --force。`,
      )
    }
    throw error
  })
  io.stdout(`created: ${targetPath}`)
}

/**
 * 解析 init-config 的写入目标。
 *
 * @param options CLI 选项。
 * @returns 配置文件绝对路径。
 */
function resolveInitConfigPath(options: InitConfigOptions): string {
  if (options.path && options.global) {
    throw new CliError('--path 与 --global 只能选择一个。')
  }

  if (options.path) {
    return resolve(options.path)
  }

  if (options.global) {
    return getGlobalLocalConfigPath()
  }

  throw new CliError('请传 --global、--path <path> 或 --print。')
}

/**
 * 创建不含真实密钥的最小 database-query 配置模板。
 *
 * @returns 格式化 JSON 字符串。
 */
function createMinimalConfigTemplate(): string {
  return `${JSON.stringify(
    {
      defaults: {
        defaultInstance: 'local-postgres',
      },
      instances: [
        {
          id: 'local-postgres',
          type: 'postgres',
          environment: 'local',
          host: 'localhost',
          port: 5432,
          username: '$' + '{env:DB_LOCAL_POSTGRES_USER}',
          password: '$' + '{env:DB_LOCAL_POSTGRES_PASSWORD}',
          defaultDatabase: 'app',
          readonly: true,
        },
        {
          id: 'local-mysql',
          type: 'mysql',
          environment: 'local',
          host: 'localhost',
          port: 3306,
          username: '$' + '{env:DB_LOCAL_MYSQL_USER}',
          password: '$' + '{env:DB_LOCAL_MYSQL_PASSWORD}',
          defaultDatabase: 'app',
          readonly: true,
        },
      ],
    },
    null,
    2,
  )}\n`
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
  const resolvedPlan = resolvePlanTool(plan)

  if (options.verbose || options.printCommand) {
    options.io.stdout(formatExecutionPlan(resolvedPlan))
  }

  if (options.printCommand) {
    return
  }

  if (resolvedPlan.sdk) {
    const result = await runSdkPlan(resolvedPlan.sdk)
    options.io.stdout(JSON.stringify(result, null, 2))
    return
  }

  if (resolvedPlan.args.length === 0) {
    options.io.stdout(resolvedPlan.summary)
    return
  }

  const result = spawnSync(resolvedPlan.tool, resolvedPlan.args, {
    env: { ...process.env, ...resolvedPlan.env },
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
    throw new CliError(
      `${resolvedPlan.tool} 退出码: ${result.status}`,
      result.status,
    )
  }
}

/**
 * 将执行计划中的底层命令解析为当前环境可用命令。
 *
 * @param plan 原始执行计划。
 * @returns 使用可用命令名的执行计划。
 */
function resolvePlanTool(plan: ExecutionPlan): ExecutionPlan {
  if (plan.sdk || plan.args.length === 0) {
    return plan
  }

  const result = probeTool(plan.tool)
  if (!result.command || result.command === plan.tool) {
    return plan
  }

  return {
    ...plan,
    tool: result.command,
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
 * 执行配置元信息子命令。
 *
 * @param action 子动作名称。
 * @param options CLI 选项。
 * @param io 输出抽象。
 * @returns 无返回值。
 */
async function runConfigCommand(
  action: string,
  options: ConfigCommandOptions,
  io: CliIo,
): Promise<void> {
  if (action === 'paths') {
    const paths = getConfigSearchPaths()
    io.stdout(
      options.format === 'json'
        ? JSON.stringify(paths, null, 2)
        : formatConfigPaths(paths),
    )
    return
  }

  if (action === 'current') {
    const current = resolveCurrentConfigPath(options.config)
    io.stdout(
      options.format === 'json'
        ? JSON.stringify(current, null, 2)
        : formatCurrentConfig(current),
    )
    if (!current.path) {
      throw new CliError('未找到配置文件。', 1)
    }
    return
  }

  if (action === 'discover-databases') {
    const summary = await runDiscoverDatabases(options)
    io.stdout(
      options.format === 'json'
        ? JSON.stringify(summary, null, 2)
        : formatDiscoverDatabasesSummary(summary),
    )
    return
  }

  throw new CliError(`不支持的 config action: ${action}`)
}

/**
 * 格式化配置查找路径。
 *
 * @param paths 配置查找路径摘要。
 * @returns 人类可读文本。
 */
function formatConfigPaths(
  paths: ReturnType<typeof getConfigSearchPaths>,
): string {
  return [
    'database-query config paths:',
    `projectDirectory: ${paths.projectDirectory}`,
    `globalDirectory: ${paths.globalDirectory}`,
    `globalLocalConfigPath: ${paths.globalLocalConfigPath}`,
    `filenames: ${paths.filenames.join(', ')}`,
    'searchOrder:',
    ...paths.projectCandidates.map((path) => `- ${path}`),
    ...paths.globalCandidates.map((path) => `- ${path}`),
  ].join('\n')
}

/**
 * 解析当前应使用的配置路径，不读取配置内容。
 *
 * @param configPath 显式配置文件路径。
 * @returns 当前配置路径摘要。
 */
function resolveCurrentConfigPath(configPath?: string): {
  mode: 'explicit' | 'default'
  path: string | undefined
  globalDirectory: string
  globalLocalConfigPath: string
  searchOrder: string[]
} {
  const explicitPath = configPath ? resolve(configPath) : undefined
  const resolvedPath = explicitPath ?? findDefaultConfigPath()
  const paths = getConfigSearchPaths()

  return {
    mode: explicitPath ? 'explicit' : 'default',
    path: resolvedPath,
    globalDirectory: paths.globalDirectory,
    globalLocalConfigPath: paths.globalLocalConfigPath,
    searchOrder: [...paths.projectCandidates, ...paths.globalCandidates],
  }
}

/**
 * 格式化当前配置路径。
 *
 * @param current 当前配置路径摘要。
 * @returns 人类可读文本。
 */
function formatCurrentConfig(
  current: ReturnType<typeof resolveCurrentConfigPath>,
): string {
  const lines = [
    'database-query config current:',
    `mode: ${current.mode}`,
    `path: ${current.path ?? '<not-found>'}`,
  ]

  if (!current.path) {
    lines.push(
      `hint: 请提供 --config，或创建 ${current.globalLocalConfigPath}。`,
    )
  }

  return lines.join('\n')
}

/**
 * 执行数据库候选发现命令。
 *
 * @param options CLI 配置子命令选项。
 * @returns 发现与可选写回摘要。
 */
async function runDiscoverDatabases(
  options: ConfigCommandOptions,
): Promise<DiscoverDatabasesSummary> {
  if (options.config && options.global) {
    throw new CliError('--config 与 --global 只能选择一个。')
  }

  const configPath = options.global
    ? getGlobalLocalConfigPath()
    : options.config
  const loaded = await loadConfig(configPath)
  const resolvedConfigPath = loaded.path
  if (!resolvedConfigPath) {
    throw new CliError('无法确定配置文件路径。')
  }

  const target = resolveTarget(loaded.config, {
    instance: options.instance,
  })
  const instance = target.instance
  if (instance.type !== 'postgres' && instance.type !== 'mysql') {
    throw new CliError(
      `config discover-databases 暂不支持 ${instance.type} 实例。首版仅支持 PostgreSQL 与 MySQL。`,
    )
  }

  const { plan, connectionDatabase } = createDiscoverDatabasesPlan(
    instance,
    options.database,
  )
  const output = runDiscoveryPlan(plan)
  const discovered = filterSystemDatabases(
    instance.type,
    parseDatabaseListOutput(output),
  )
  const selected = applyDatabaseFilters(discovered, {
    include: options.include,
    exclude: options.exclude,
  })

  const summary: DiscoverDatabasesSummary = {
    configPath: resolvedConfigPath,
    instance: instance.id,
    type: instance.type,
    connectionDatabase,
    discovered,
    selected,
    write: Boolean(options.write),
  }

  if (options.write) {
    const writeResult = await writeDiscoveredDatabases({
      configPath: resolvedConfigPath,
      instanceId: instance.id,
      databases: selected,
      connectionDatabase,
    })
    summary.backupPath = writeResult.backupPath
    summary.updatedPath = writeResult.updatedPath
  }

  return summary
}

/**
 * 创建关系型数据库候选发现执行计划。
 *
 * @param instance 数据库实例。
 * @param explicitDatabase PostgreSQL 发现连接库覆盖值。
 * @returns 执行计划与实际连接库。
 */
function createDiscoverDatabasesPlan(
  instance: DatabaseInstance,
  explicitDatabase?: string,
): { plan: ExecutionPlan; connectionDatabase?: string } {
  if (instance.type === 'postgres') {
    const connectionDatabase =
      explicitDatabase ?? instance.defaultDatabase ?? 'postgres'
    const args = [
      ...optionalArgPair('-h', instance.host),
      ...optionalArgPair('-p', instance.port?.toString()),
      ...optionalArgPair('-U', instance.username),
      '-d',
      connectionDatabase,
      '-A',
      '-t',
      '-c',
      'select datname from pg_database where not datistemplate order by datname;',
    ]

    return {
      connectionDatabase,
      plan: {
        tool: 'psql',
        args,
        displayArgs: args,
        env: instance.password ? { PGPASSWORD: instance.password } : {},
        displayEnv: instance.password ? { PGPASSWORD: '<redacted>' } : {},
        summary: `PostgreSQL ${instance.id} discover databases`,
      },
    }
  }

  const args = [
    ...optionalArgPair('--host', instance.host),
    ...optionalArgPair('--port', instance.port?.toString()),
    ...optionalArgPair('--user', instance.username),
    '--batch',
    '--skip-column-names',
    '--execute',
    'SHOW DATABASES;',
  ]

  return {
    plan: {
      tool: 'mysql',
      args,
      displayArgs: args,
      env: instance.password ? { MYSQL_PWD: instance.password } : {},
      displayEnv: instance.password ? { MYSQL_PWD: '<redacted>' } : {},
      summary: `MySQL ${instance.id} discover databases`,
    },
  }
}

/**
 * 执行数据库发现计划并返回 stdout。
 *
 * @param plan 执行计划。
 * @param runner 进程执行抽象，便于测试替换。
 * @returns 底层客户端 stdout。
 */
function runDiscoveryPlan(
  plan: ExecutionPlan,
  runner: ProcessRunner = runProcess,
): string {
  const resolvedPlan = resolvePlanTool(plan)
  const result = runner(resolvedPlan.tool, resolvedPlan.args, {
    ...process.env,
    ...resolvedPlan.env,
  })

  if (result.error) {
    throw new CliError(result.error.message)
  }
  if (result.status && result.status !== 0) {
    const stderr = result.stderr.trim()
    throw new CliError(
      `${resolvedPlan.tool} 退出码: ${result.status}${stderr ? `\n${stderr}` : ''}`,
      result.status,
    )
  }

  return result.stdout
}

/**
 * 执行底层进程并捕获输出。
 *
 * @param command 命令名。
 * @param args 参数列表。
 * @param env 子进程环境变量。
 * @returns 进程执行结果。
 */
function runProcess(
  command: string,
  args: string[],
  env: NodeJS.ProcessEnv,
): ProcessRunResult {
  const result = spawnSync(command, args, {
    env,
    encoding: 'utf8',
    stdio: 'pipe',
  })

  return {
    status: result.status,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    error: result.error,
  }
}

/**
 * 解析底层客户端输出中的数据库名称。
 *
 * @param output 底层客户端 stdout。
 * @returns 去重排序后的数据库名称。
 */
export function parseDatabaseListOutput(output: string): string[] {
  return uniqueSorted(
    output
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter(Boolean),
  )
}

/**
 * 过滤数据库类型对应的系统库。
 *
 * @param type 数据库类型。
 * @param databases 原始数据库名称。
 * @returns 过滤系统库后的数据库名称。
 */
export function filterSystemDatabases(
  type: 'postgres' | 'mysql',
  databases: string[],
): string[] {
  const excluded =
    type === 'postgres'
      ? new Set(['template0', 'template1'])
      : new Set(['information_schema', 'mysql', 'performance_schema', 'sys'])

  return databases.filter((database) => !excluded.has(database))
}

/**
 * 按 include / exclude glob 过滤数据库名称。
 *
 * @param databases 数据库名称列表。
 * @param options 过滤参数。
 * @returns 过滤后的数据库名称。
 */
export function applyDatabaseFilters(
  databases: string[],
  options: { include?: string; exclude?: string },
): string[] {
  const include = parsePatternList(options.include)
  const exclude = parsePatternList(options.exclude)

  return databases.filter((database) => {
    const included =
      include.length === 0 ||
      include.some((pattern) => matchesGlob(database, pattern))
    const excluded = exclude.some((pattern) => matchesGlob(database, pattern))
    return included && !excluded
  })
}

/**
 * 将发现到的数据库合并写回本机 local JSON 配置。
 *
 * @param options 写回参数。
 * @returns 备份路径和更新路径。
 */
async function writeDiscoveredDatabases(options: {
  configPath: string
  instanceId: string
  databases: string[]
  connectionDatabase?: string
}): Promise<{ backupPath: string; updatedPath: string }> {
  assertWritableLocalJsonConfig(options.configPath)

  const rawContent = readFileSync(options.configPath, 'utf8')
  const rawConfig = JSON.parse(rawContent) as DatabaseQueryConfig
  const updatedConfig = mergeDiscoveredDatabasesIntoConfig(rawConfig, {
    instanceId: options.instanceId,
    databases: options.databases,
    connectionDatabase: options.connectionDatabase,
  })
  const backupPath = createBackupPath(options.configPath)

  await writeFile(backupPath, rawContent, { flag: 'wx', mode: 0o600 })
  await writeFile(
    options.configPath,
    `${JSON.stringify(updatedConfig, null, 2)}\n`,
  )

  return { backupPath, updatedPath: options.configPath }
}

/**
 * 合并发现到的数据库到配置对象。
 *
 * @param config 原始配置对象。
 * @param options 合并参数。
 * @returns 合并后的配置对象。
 */
export function mergeDiscoveredDatabasesIntoConfig(
  config: DatabaseQueryConfig,
  options: {
    instanceId: string
    databases: string[]
    connectionDatabase?: string
  },
): DatabaseQueryConfig {
  const instances = config.instances.map((instance) => {
    if (instance.id !== options.instanceId) {
      return instance
    }

    const byName = new Map<string, DatabaseEntry>()
    for (const database of instance.databases ?? []) {
      byName.set(database.name, database)
    }
    for (const database of options.databases) {
      if (!byName.has(database)) {
        byName.set(database, { name: database })
      }
    }

    const updated: DatabaseInstance = {
      ...instance,
      databases: [...byName.values()].sort((left, right) =>
        left.name.localeCompare(right.name),
      ),
    }

    if (
      !updated.defaultDatabase &&
      options.connectionDatabase &&
      options.databases.includes(options.connectionDatabase)
    ) {
      updated.defaultDatabase = options.connectionDatabase
    }

    return updated
  })

  return { ...config, instances }
}

/**
 * 校验配置文件是否允许自动写回。
 *
 * @param configPath 配置文件路径。
 * @returns 无返回值。
 */
function assertWritableLocalJsonConfig(configPath: string): void {
  const fileName = basename(configPath)
  if (!fileName.endsWith('.local.json')) {
    throw new CliError(
      `自动写回只支持 *.local.json 本机私有配置: ${configPath}`,
    )
  }
}

/**
 * 创建同目录配置备份路径。
 *
 * @param configPath 配置文件路径。
 * @returns 不存在的备份文件路径。
 */
function createBackupPath(configPath: string): string {
  const timestamp = formatLocalTimestamp(new Date())
  let candidate = `${configPath}.${timestamp}.bak`
  let index = 1
  while (existsSync(candidate)) {
    candidate = `${configPath}.${timestamp}-${index}.bak`
    index += 1
  }
  return candidate
}

/**
 * 格式化本地时间戳用于备份文件名。
 *
 * @param date 时间对象。
 * @returns `YYYY-MM-DD_HH-mm-ss` 格式时间戳。
 */
function formatLocalTimestamp(date: Date): string {
  const pad = (value: number) => value.toString().padStart(2, '0')
  return [
    date.getFullYear(),
    '-',
    pad(date.getMonth() + 1),
    '-',
    pad(date.getDate()),
    '_',
    pad(date.getHours()),
    '-',
    pad(date.getMinutes()),
    '-',
    pad(date.getSeconds()),
  ].join('')
}

/**
 * 格式化数据库发现摘要。
 *
 * @param summary 发现摘要。
 * @returns 人类可读文本。
 */
function formatDiscoverDatabasesSummary(
  summary: DiscoverDatabasesSummary,
): string {
  const lines = [
    'database-query config discover-databases:',
    `configPath: ${summary.configPath}`,
    `instance: ${summary.instance}`,
    `type: ${summary.type}`,
    `connectionDatabase: ${summary.connectionDatabase ?? '<none>'}`,
    `discovered: ${summary.discovered.length ? summary.discovered.join(', ') : '<none>'}`,
    `selected: ${summary.selected.length ? summary.selected.join(', ') : '<none>'}`,
    `write: ${summary.write ? 'yes' : 'no'}`,
  ]

  if (summary.backupPath) {
    lines.push(`backupPath: ${summary.backupPath}`)
  }
  if (summary.updatedPath) {
    lines.push(`updatedPath: ${summary.updatedPath}`)
  }
  if (!summary.write) {
    lines.push('hint: 传 --write 写回本机 *.local.json 配置。')
  }

  return lines.join('\n')
}

/**
 * 拆分逗号分隔的 glob 模式。
 *
 * @param value CLI 输入。
 * @returns 模式列表。
 */
function parsePatternList(value: string | undefined): string[] {
  return (value ?? '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

/**
 * 判断文本是否匹配简单 glob。
 *
 * @param value 待匹配文本。
 * @param pattern glob 模式，支持 `*` 与 `?`。
 * @returns 匹配时返回 true。
 */
function matchesGlob(value: string, pattern: string): boolean {
  const regex = new RegExp(
    `^${pattern
      .split('')
      .map((char) => {
        if (char === '*') {
          return '.*'
        }
        if (char === '?') {
          return '.'
        }
        return char.replace(/[\\^$+?.()|[\]{}]/g, '\\$&')
      })
      .join('')}$`,
  )
  return regex.test(value)
}

/**
 * 对字符串列表去重排序。
 *
 * @param values 原始字符串列表。
 * @returns 去重排序后的列表。
 */
function uniqueSorted(values: string[]): string[] {
  return [...new Set(values)].sort((left, right) => left.localeCompare(right))
}

/**
 * 按存在性添加命令参数键值对。
 *
 * @param key 参数名。
 * @param value 参数值。
 * @returns 参数片段。
 */
function optionalArgPair(key: string, value: string | undefined): string[] {
  return value ? [key, value] : []
}

/**
 * 格式化 doctor 检查结果。
 *
 * @returns doctor 文本。
 */
async function formatDoctor(): Promise<string> {
  const tools = ['psql', 'mysql', 'sqlite3', 'mongosh', 'redis-cli']
  const lines = [
    'database-query doctor:',
    'install policy: 不自动安装底层客户端；agent 应根据当前平台、权限和 PATH 自行选择安装方式。',
  ]

  for (const tool of tools) {
    const result = probeTool(tool)
    if (result.command) {
      lines.push(
        `- ${tool}: ok (${result.origin}) command=${result.command}${result.version ? ` version="${result.version}"` : ''}`,
      )
    } else {
      lines.push(`- ${tool}: missing`)
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
 * 探测底层客户端命令，WSL 场景下原生命令缺失时尝试 `.exe`。
 *
 * @param name 客户端命令基础名称。
 * @param runner 命令执行抽象，便于测试模拟 PATH。
 * @returns 客户端探测结果。
 */
export function probeTool(
  name: string,
  runner: ToolRunner = runToolVersion,
): ToolProbeResult {
  const nativeResult = runner(name, ['--version'])
  if (nativeResult.ok) {
    return {
      name,
      command: name,
      origin: 'native',
      version: firstOutputLine(nativeResult.output),
    }
  }

  const windowsCommand = `${name}.exe`
  const windowsResult = runner(windowsCommand, ['--version'])
  if (windowsResult.ok) {
    return {
      name,
      command: windowsCommand,
      origin: 'windows-exe',
      version: firstOutputLine(windowsResult.output),
    }
  }

  return { name }
}

/**
 * 运行客户端版本命令。
 *
 * @param command 客户端命令。
 * @param args 命令参数。
 * @returns 命令是否可运行及版本输出。
 */
function runToolVersion(command: string, args: string[]): ToolRunResult {
  const result = spawnSync(command, args, {
    encoding: 'utf8',
    stdio: 'pipe',
  })

  return {
    ok: !result.error && result.status === 0,
    output: result.stdout || result.stderr || undefined,
  }
}

/**
 * 获取命令输出第一行。
 *
 * @param output 原始命令输出。
 * @returns 去空白后的第一行。
 */
function firstOutputLine(output: string | undefined): string | undefined {
  return output
    ?.split(/\r?\n/)
    .map((line) => line.trim())
    .find(Boolean)
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
  const patchOutputHelp = (target: { outputHelp: () => void }) => {
    const originalOutputHelp = target.outputHelp.bind(target)
    target.outputHelp = () => {
      captureConsoleLog(io, originalOutputHelp)
    }
  }

  patchOutputHelp(cli)
  patchOutputHelp(cli.globalCommand)
  for (const command of cli.commands) {
    patchOutputHelp(command)
  }

  return cli
}

/**
 * 在解析前直接输出 help，避免 cac 内部 console 输出被并发测试污染。
 *
 * @param argv CLI 参数。
 * @param cli cac CLI。
 * @param io 输出抽象。
 * @returns 已输出 help 时返回 true。
 */
function tryOutputHelp(
  argv: string[],
  cli: ReturnType<typeof cac>,
  io: CliIo,
): boolean {
  if (!argv.includes('--help') && !argv.includes('-h')) {
    return false
  }

  captureConsoleLog(io, () => {
    cli.parse(['node', 'database-query', ...argv], { run: false })
  })
  return true
}

/**
 * 格式化 cac 生成的帮助片段。
 *
 * @param sections cac 生成的帮助片段。
 * @returns 完整帮助文本。
 */
function formatHelpSections(sections: HelpSection[]): string {
  return sections
    .map((section) =>
      section.title ? `${section.title}:\n${section.body}` : section.body,
    )
    .join('\n\n')
}

/**
 * 在第三方 CLI 库只支持 console 输出时，短暂转接到当前 IO。
 *
 * @param io 输出抽象。
 * @param callback 需要捕获 console.log 的同步回调。
 * @returns 无返回值。
 */
function captureConsoleLog(io: CliIo, callback: () => void): void {
  const originalLog = console.log
  console.log = (...values) => io.stdout(values.map(String).join(' '))
  try {
    callback()
  } finally {
    console.log = originalLog
  }
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
