import { getAllowedActions, getEffectiveDefaults } from './config.js'
import type {
  DatabaseInstance,
  DatabaseQueryConfig,
  DatabaseType,
  Dialect,
  ExecutionPlan,
  ResolvedTarget,
} from './types.js'

export class PlanError extends Error {
  readonly exitCode: number

  /**
   * 创建执行计划错误。
   *
   * @param message 错误消息。
   * @param exitCode 进程退出码。
   */
  constructor(message: string, exitCode = 1) {
    super(message)
    this.exitCode = exitCode
  }
}

export interface SqlExecPlanOptions {
  sql: string
}

export interface ActionPlanOptions {
  action: string
  key?: string
  field?: string
  query?: string
  vector?: string
  limit?: number
}

/**
 * 为关系型数据库 SQL 执行创建底层 CLI 计划。
 *
 * @param target 已解析目标。
 * @param options SQL 执行参数。
 * @returns 执行计划。
 */
export function createSqlExecutionPlan(
  target: ResolvedTarget,
  options: SqlExecPlanOptions,
): ExecutionPlan {
  const databaseName = target.database?.name ?? target.instance.defaultDatabase
  if (!databaseName && target.instance.type !== 'sqlite') {
    throw new PlanError('关系型执行需要可确定的 database。')
  }

  if (target.instance.type === 'postgres') {
    return createPostgresPlan(target.instance, databaseName, options.sql)
  }

  if (target.instance.type === 'mysql') {
    return createMysqlPlan(target.instance, databaseName, options.sql)
  }

  if (target.instance.type === 'sqlite') {
    return createSqlitePlan(target.instance, options.sql)
  }

  throw new PlanError(`实例类型不是关系型数据库: ${target.instance.type}`)
}

/**
 * 为底层官方客户端创建凭据桥接计划。
 *
 * @param target 已解析目标。
 * @param passthrough 透传给底层 CLI 的参数。
 * @returns 执行计划。
 */
export function createClientPlan(
  target: ResolvedTarget,
  passthrough: string[],
): ExecutionPlan {
  const databaseName = target.database?.name ?? target.instance.defaultDatabase
  switch (target.instance.type) {
    case 'postgres':
      return createPostgresPlan(
        target.instance,
        databaseName,
        undefined,
        passthrough,
      )
    case 'mysql':
      return createMysqlPlan(
        target.instance,
        databaseName,
        undefined,
        passthrough,
      )
    case 'sqlite':
      return createSqlitePlan(target.instance, undefined, passthrough)
    case 'mongodb':
      return createMongoPlan(target.instance, databaseName, passthrough)
    case 'redis':
      return createRedisPlan(target.instance, passthrough)
    case 'milvus':
      return {
        tool: 'node',
        args: [],
        displayArgs: [],
        env: {},
        displayEnv: {},
        summary:
          'Milvus 首版没有通用底层 CLI 桥接，请使用 exec 的 Milvus 只读动作或官方 SDK。',
      }
    default:
      return assertNever(target.instance.type)
  }
}

/**
 * 为非 SQL 只读动作创建受控执行计划。
 *
 * @param config database-query 配置。
 * @param target 已解析目标。
 * @param options 动作参数。
 * @returns 执行计划或 SDK 动作摘要。
 */
export function createActionPlan(
  config: DatabaseQueryConfig,
  target: ResolvedTarget,
  options: ActionPlanOptions,
): ExecutionPlan {
  const allowedActions = getAllowedActions(config, target.instance)
  if (!allowedActions.includes(options.action)) {
    throw new PlanError(
      `动作 ${options.action} 不允许用于 ${target.instance.type}。允许动作: ${allowedActions.join(', ')}`,
    )
  }

  switch (target.instance.type) {
    case 'mongodb':
      return createMongoActionPlan(target, options)
    case 'redis':
      return createRedisActionPlan(target.instance, options)
    case 'milvus':
      return createMilvusActionPlan(target, options)
    default:
      throw new PlanError(
        `${target.instance.type} 的 exec 动作请使用 --sql 或 --file。`,
      )
  }
}

/**
 * 格式化执行计划。
 *
 * @param plan 执行计划。
 * @returns 可读的脱敏计划文本。
 */
export function formatExecutionPlan(plan: ExecutionPlan): string {
  const command = [plan.tool, ...plan.displayArgs].filter(Boolean).join(' ')
  const lines = [`plan: ${plan.summary}`]
  if (command.trim()) {
    lines.push(`command: ${command}`)
  }

  const envEntries = Object.entries(plan.displayEnv)
  if (envEntries.length > 0) {
    lines.push(
      `env: ${envEntries.map(([key, value]) => `${key}=${value}`).join(' ')}`,
    )
  }

  return lines.join('\n')
}

/**
 * 判断数据库类型是否属于关系型 SQL 方言。
 *
 * @param type 数据库类型。
 * @returns 属于 PostgreSQL/MySQL/SQLite 时返回 true。
 */
export function isSqlDialect(type: DatabaseType): type is Dialect {
  return type === 'postgres' || type === 'mysql' || type === 'sqlite'
}

/**
 * 限制执行动作使用的 limit。
 *
 * @param config database-query 配置。
 * @param requested 用户请求的 limit。
 * @returns 生效的 limit。
 */
export function resolveLimit(
  config: DatabaseQueryConfig,
  requested?: number,
): number {
  const defaults = getEffectiveDefaults(config)
  const limit = requested ?? defaults.limit
  if (limit > defaults.maxLimit) {
    throw new PlanError(`limit ${limit} 超过配置上限 ${defaults.maxLimit}。`)
  }

  return limit
}

/**
 * 创建 PostgreSQL CLI 计划。
 *
 * @param instance 数据库实例。
 * @param databaseName 数据库名。
 * @param sql 可选 SQL。
 * @param passthrough 透传参数。
 * @returns 执行计划。
 */
function createPostgresPlan(
  instance: DatabaseInstance,
  databaseName: string | undefined,
  sql?: string,
  passthrough: string[] = [],
): ExecutionPlan {
  if (!databaseName) {
    throw new PlanError('PostgreSQL 需要 database。')
  }

  const args = [
    ...optionalPair('-h', instance.host),
    ...optionalPair('-p', instance.port?.toString()),
    ...optionalPair('-U', instance.username),
    '-d',
    databaseName,
    ...passthrough,
    ...optionalPair('-c', sql),
  ]

  return {
    tool: 'psql',
    args,
    displayArgs: args,
    env: instance.password ? { PGPASSWORD: instance.password } : {},
    displayEnv: instance.password ? { PGPASSWORD: '<redacted>' } : {},
    summary: `PostgreSQL ${instance.id}/${databaseName}`,
  }
}

/**
 * 创建 MySQL CLI 计划。
 *
 * @param instance 数据库实例。
 * @param databaseName 数据库名。
 * @param sql 可选 SQL。
 * @param passthrough 透传参数。
 * @returns 执行计划。
 */
function createMysqlPlan(
  instance: DatabaseInstance,
  databaseName: string | undefined,
  sql?: string,
  passthrough: string[] = [],
): ExecutionPlan {
  if (!databaseName) {
    throw new PlanError('MySQL 需要 database。')
  }

  const args = [
    ...optionalPair('--host', instance.host),
    ...optionalPair('--port', instance.port?.toString()),
    ...optionalPair('--user', instance.username),
    '--database',
    databaseName,
    ...passthrough,
    ...optionalPair('--execute', sql),
  ]

  return {
    tool: 'mysql',
    args,
    displayArgs: args,
    env: instance.password ? { MYSQL_PWD: instance.password } : {},
    displayEnv: instance.password ? { MYSQL_PWD: '<redacted>' } : {},
    summary: `MySQL ${instance.id}/${databaseName}`,
  }
}

/**
 * 创建 SQLite CLI 计划。
 *
 * @param instance 数据库实例。
 * @param sql 可选 SQL。
 * @param passthrough 透传参数。
 * @returns 执行计划。
 */
function createSqlitePlan(
  instance: DatabaseInstance,
  sql?: string,
  passthrough: string[] = [],
): ExecutionPlan {
  if (!instance.path) {
    throw new PlanError('SQLite instance 必须配置 path。')
  }

  const args = [instance.path, ...passthrough, ...optionalValue(sql)]
  return {
    tool: 'sqlite3',
    args,
    displayArgs: args,
    env: {},
    displayEnv: {},
    summary: `SQLite ${instance.id}`,
  }
}

/**
 * 创建 MongoDB CLI 计划。
 *
 * @param instance 数据库实例。
 * @param databaseName 数据库名。
 * @param passthrough 透传参数。
 * @returns 执行计划。
 */
function createMongoPlan(
  instance: DatabaseInstance,
  databaseName: string | undefined,
  passthrough: string[],
): ExecutionPlan {
  const uri = instance.uri ?? instance.url
  if (!uri) {
    throw new PlanError('MongoDB instance 必须配置 uri。')
  }

  const args = [withDatabaseInUri(uri, databaseName), ...passthrough]
  return {
    tool: 'mongosh',
    args,
    displayArgs: [redactUri(args[0]), ...passthrough],
    env: {},
    displayEnv: {},
    summary: `MongoDB ${instance.id}${databaseName ? `/${databaseName}` : ''}`,
  }
}

/**
 * 创建 Redis CLI 计划。
 *
 * @param instance 数据库实例。
 * @param passthrough 透传参数。
 * @returns 执行计划。
 */
function createRedisPlan(
  instance: DatabaseInstance,
  passthrough: string[],
): ExecutionPlan {
  if (!instance.url) {
    throw new PlanError('Redis instance 必须配置 url。')
  }

  const args = ['-u', instance.url, ...passthrough]
  return {
    tool: 'redis-cli',
    args,
    displayArgs: ['-u', redactUri(instance.url), ...passthrough],
    env: {},
    displayEnv: {},
    summary: `Redis ${instance.id}`,
  }
}

/**
 * 创建 MongoDB 只读动作计划。
 *
 * @param target 已解析目标。
 * @param options 动作参数。
 * @returns 执行计划。
 */
function createMongoActionPlan(
  target: ResolvedTarget,
  options: ActionPlanOptions,
): ExecutionPlan {
  const databaseName = target.database?.name ?? target.instance.defaultDatabase
  const limit = options.limit ?? 50
  const collection = target.collection ?? options.key
  let evalScript: string

  if (options.action === 'list-collections') {
    evalScript = 'db.getCollectionNames().join("\\n")'
  } else if (options.action === 'count') {
    requireValue(collection, 'MongoDB count 需要 collection 或 --key。')
    evalScript = `db.getCollection(${JSON.stringify(collection)}).countDocuments(${options.query ?? '{}'})`
  } else if (options.action === 'find') {
    requireValue(collection, 'MongoDB find 需要 collection 或 --key。')
    evalScript = `JSON.stringify(db.getCollection(${JSON.stringify(collection)}).find(${options.query ?? '{}'}).limit(${limit}).toArray(), null, 2)`
  } else {
    throw new PlanError(`不支持的 MongoDB 动作: ${options.action}`)
  }

  return createMongoPlan(target.instance, databaseName, [
    '--quiet',
    '--eval',
    evalScript,
  ])
}

/**
 * 创建 Redis 只读动作计划。
 *
 * @param instance Redis 实例。
 * @param options 动作参数。
 * @returns 执行计划。
 */
function createRedisActionPlan(
  instance: DatabaseInstance,
  options: ActionPlanOptions,
): ExecutionPlan {
  const action = options.action.toUpperCase()
  const args = buildRedisActionArgs(action, options)
  return createRedisPlan(instance, args)
}

/**
 * 创建 Milvus SDK 动作摘要计划。
 *
 * @param target 已解析目标。
 * @param options 动作参数。
 * @returns SDK 执行摘要。
 */
function createMilvusActionPlan(
  target: ResolvedTarget,
  options: ActionPlanOptions,
): ExecutionPlan {
  const address = target.instance.address ?? target.instance.uri
  if (!address) {
    throw new PlanError('Milvus instance 必须配置 address 或 uri。')
  }

  return {
    tool: 'node',
    args: [],
    displayArgs: [],
    env: {},
    displayEnv: target.instance.token ? { MILVUS_TOKEN: '<redacted>' } : {},
    summary: `Milvus ${target.instance.id} SDK action=${options.action} collection=${target.collection ?? options.key ?? '<none>'}`,
    sdk: {
      provider: 'milvus',
      action: options.action,
      address,
      token: target.instance.token,
      collection: target.collection ?? options.key,
      query: options.query,
      vector: options.vector,
      limit: options.limit ?? 50,
    },
  }
}

/**
 * 构建 Redis 只读动作参数。
 *
 * @param action Redis 动作。
 * @param options 动作参数。
 * @returns redis-cli 参数。
 */
function buildRedisActionArgs(
  action: string,
  options: ActionPlanOptions,
): string[] {
  switch (action) {
    case 'PING':
    case 'INFO':
      return [action]
    case 'SCAN':
      return options.key ? ['SCAN', '0', 'MATCH', options.key] : ['SCAN', '0']
    case 'TYPE':
    case 'TTL':
    case 'GET':
      requireValue(options.key, `${action} 需要 --key。`)
      return [action, options.key]
    case 'HGET':
      requireValue(options.key, 'HGET 需要 --key。')
      requireValue(options.field, 'HGET 需要 --field。')
      return [action, options.key, options.field]
    case 'LRANGE':
      requireValue(options.key, 'LRANGE 需要 --key。')
      return [
        action,
        options.key,
        '0',
        String(Math.max((options.limit ?? 50) - 1, 0)),
      ]
    default:
      throw new PlanError(`不支持的 Redis 动作: ${action.toLowerCase()}`)
  }
}

/**
 * 追加可选参数对。
 *
 * @param flag 参数名。
 * @param value 参数值。
 * @returns 参数数组。
 */
function optionalPair(flag: string, value?: string): string[] {
  return value ? [flag, value] : []
}

/**
 * 追加可选位置参数。
 *
 * @param value 参数值。
 * @returns 参数数组。
 */
function optionalValue(value?: string): string[] {
  return value ? [value] : []
}

/**
 * 校验必填字符串。
 *
 * @param value 待校验值。
 * @param message 缺失时报错消息。
 * @returns 无返回值。
 */
function requireValue(
  value: string | undefined,
  message: string,
): asserts value is string {
  if (!value) {
    throw new PlanError(message)
  }
}

/**
 * 将 database 写入 MongoDB URI。
 *
 * @param uri 原始 URI。
 * @param databaseName 数据库名。
 * @returns 带数据库路径的 URI。
 */
function withDatabaseInUri(uri: string, databaseName?: string): string {
  if (!databaseName) {
    return uri
  }

  const parsed = new URL(uri)
  parsed.pathname = `/${databaseName}`
  return parsed.toString()
}

/**
 * 脱敏 URI 中的用户名密码。
 *
 * @param uri 原始 URI。
 * @returns 脱敏 URI。
 */
function redactUri(uri: string): string {
  try {
    const parsed = new URL(uri)
    if (parsed.username) {
      parsed.username = '<redacted>'
    }
    if (parsed.password) {
      parsed.password = '<redacted>'
    }
    return parsed.toString()
  } catch {
    return '<redacted-uri>'
  }
}

/**
 * 穷尽类型检查。
 *
 * @param value 不应出现的值。
 * @returns 永不返回。
 */
function assertNever(value: never): never {
  throw new PlanError(`不支持的数据库类型: ${value}`)
}
