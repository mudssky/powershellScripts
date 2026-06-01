import { existsSync, readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { extname, join, resolve } from 'node:path'
import { pathToFileURL } from 'node:url'

import type {
  ConfigDefaults,
  ContextInstance,
  ContextSnapshot,
  DatabaseEntry,
  DatabaseInstance,
  DatabaseQueryConfig,
  DatabaseType,
  LoadedConfig,
  OutputFormat,
  PermissionLevel,
  ResolvedTarget,
  SecretStatus,
} from './types.js'

const DEFAULT_CONFIG_FILES = [
  'database-query.local.mjs',
  'database-query.local.js',
  'database-query.local.json',
  'database-query.config.mjs',
  'database-query.config.js',
  'database-query.config.json',
]

const GLOBAL_CONFIG_DIRECTORY_NAME = 'database-query'

const DEFAULT_LIMIT = 50
const DEFAULT_MAX_LIMIT = 1000
const DEFAULT_PERMISSION_LEVEL: PermissionLevel = 'readonly'
const DEFAULT_OUTPUT_FORMAT: OutputFormat = 'text'

const DEFAULT_ALLOWED_ACTIONS: Record<DatabaseType, string[]> = {
  postgres: ['sql'],
  mysql: ['sql'],
  sqlite: ['sql'],
  mongodb: ['list-collections', 'count', 'find'],
  redis: ['ping', 'info', 'scan', 'type', 'ttl', 'get', 'hget', 'lrange'],
  milvus: ['list-collections', 'describe-collection', 'query', 'search'],
}

const SECRET_FIELDS = ['password', 'uri', 'url', 'token'] as const

export class ConfigError extends Error {
  readonly exitCode: number

  /**
   * 创建可控配置错误。
   *
   * @param message 错误消息。
   * @param exitCode 进程退出码。
   */
  constructor(message: string, exitCode = 1) {
    super(message)
    this.exitCode = exitCode
  }
}

export interface TargetOptions {
  instance?: string
  database?: string
  schema?: string
  collection?: string
  requireDatabase?: boolean
}

/**
 * 加载 database-query 配置。
 *
 * @param configPath 显式配置文件路径；未传时按项目级、全局默认文件名查找。
 * @returns 已解析并替换环境变量占位符的配置。
 */
export async function loadConfig(configPath?: string): Promise<LoadedConfig> {
  const resolvedPath = configPath ? resolve(configPath) : findDefaultConfig()
  if (!resolvedPath) {
    throw new ConfigError(
      `未找到配置文件。请提供 --config，或在当前目录、${getGlobalConfigDirectory()} 创建 ${DEFAULT_CONFIG_FILES.join(' / ')}。`,
    )
  }

  const extension = extname(resolvedPath)
  let rawConfig: unknown

  if (extension === '.json') {
    rawConfig = JSON.parse(readFileSync(resolvedPath, 'utf8'))
  } else if (extension === '.mjs' || extension === '.js') {
    const imported = await import(pathToFileURL(resolvedPath).href)
    rawConfig = imported.default ?? imported.config
  } else {
    throw new ConfigError(`不支持的配置格式: ${extension}`)
  }

  const config = resolveEnvPlaceholders(rawConfig) as DatabaseQueryConfig
  validateConfig(config, resolvedPath)

  return { path: resolvedPath, config }
}

/**
 * 获取带默认值的全局策略。
 *
 * @param config database-query 配置。
 * @returns 合并默认值后的策略。
 */
export function getEffectiveDefaults(config: DatabaseQueryConfig) {
  const defaults = config.defaults ?? {}
  return {
    defaultInstance: defaults.defaultInstance,
    limit: defaults.limit ?? DEFAULT_LIMIT,
    maxLimit: defaults.maxLimit ?? DEFAULT_MAX_LIMIT,
    permissionLevel: defaults.permissionLevel ?? DEFAULT_PERMISSION_LEVEL,
    outputFormat: defaults.outputFormat ?? DEFAULT_OUTPUT_FORMAT,
    redactFields: defaults.redactFields ?? [...SECRET_FIELDS],
    allowedActions: mergeAllowedActions(defaults),
  }
}

/**
 * 解析 instance、database、schema、collection 目标。
 *
 * @param config database-query 配置。
 * @param options 目标选择参数。
 * @returns 唯一确定的目标。
 */
export function resolveTarget(
  config: DatabaseQueryConfig,
  options: TargetOptions,
): ResolvedTarget {
  const defaults = getEffectiveDefaults(config)
  const instance = resolveByName(
    config.instances,
    options.instance,
    defaults.defaultInstance,
    'instance',
    (item) => item.id,
  )
  const databases = instance.databases ?? []
  const database = resolveOptionalDatabase(instance, databases, options)
  const schema = resolveNamespace(
    database?.schemas ?? [],
    options.schema,
    database?.defaultSchema,
    'schema',
  )
  const collection = resolveNamespace(
    database?.collections ?? [],
    options.collection,
    database?.defaultCollection,
    'collection',
  )

  return { instance, database, schema, collection }
}

/**
 * 创建脱敏上下文快照，供 agent 查询前读取。
 *
 * @param loaded 已加载配置。
 * @param instanceId 可选实例过滤。
 * @returns 脱敏上下文。
 */
export function createContextSnapshot(
  loaded: LoadedConfig,
  instanceId?: string,
): ContextSnapshot {
  const defaults = getEffectiveDefaults(loaded.config)
  const instances = instanceId
    ? [
        resolveByName(
          loaded.config.instances,
          instanceId,
          undefined,
          'instance',
          (item) => item.id,
        ),
      ]
    : loaded.config.instances

  return {
    configPath: loaded.path,
    defaults,
    instances: instances.map((instance) =>
      createContextInstance(instance, defaults.allowedActions),
    ),
  }
}

/**
 * 获取指定数据库类型允许的动作。
 *
 * @param config database-query 配置。
 * @param instance 目标实例。
 * @returns 动作名称列表。
 */
export function getAllowedActions(
  config: DatabaseQueryConfig,
  instance: DatabaseInstance,
): string[] {
  const defaults = getEffectiveDefaults(config)
  return instance.allowedActions ?? defaults.allowedActions[instance.type] ?? []
}

/**
 * 将配置值中的 `${env:NAME}` 占位符替换为环境变量。
 *
 * @param value 待解析的任意配置值。
 * @returns 替换后的配置值。
 */
export function resolveEnvPlaceholders(value: unknown): unknown {
  if (typeof value === 'string') {
    const fullMatch = value.match(/^\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}$/)
    if (fullMatch) {
      const envValue = process.env[fullMatch[1]]
      if (envValue === undefined) {
        throw new ConfigError(`缺少环境变量: ${fullMatch[1]}`)
      }
      return envValue
    }

    return value.replace(
      /\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g,
      (_match, name: string) => {
        const envValue = process.env[name]
        if (envValue === undefined) {
          throw new ConfigError(`缺少环境变量: ${name}`)
        }
        return envValue
      },
    )
  }

  if (Array.isArray(value)) {
    return value.map((item) => resolveEnvPlaceholders(item))
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        resolveEnvPlaceholders(entry),
      ]),
    )
  }

  return value
}

/**
 * 按项目级优先、全局兜底的顺序查找配置。
 *
 * @returns 找到的绝对路径；未找到返回 undefined。
 */
function findDefaultConfig(): string | undefined {
  return (
    findConfigInDirectory(process.cwd()) ??
    findConfigInDirectory(getGlobalConfigDirectory())
  )
}

/**
 * 在指定目录按默认文件名查找配置。
 *
 * @param directory 待查找配置的目录。
 * @returns 找到的绝对路径；未找到返回 undefined。
 */
function findConfigInDirectory(directory: string): string | undefined {
  for (const file of DEFAULT_CONFIG_FILES) {
    const candidate = resolve(directory, file)
    if (existsSync(candidate)) {
      return candidate
    }
  }

  return undefined
}

/**
 * 解析 agent 无关的用户级 database-query 配置目录。
 *
 * @returns XDG 规范下的 database-query 用户配置目录。
 */
export function getGlobalConfigDirectory(): string {
  const xdgConfigHome = process.env.XDG_CONFIG_HOME?.trim()
  const baseDirectory = xdgConfigHome
    ? xdgConfigHome
    : join(homedir(), '.config')
  return resolve(baseDirectory, GLOBAL_CONFIG_DIRECTORY_NAME)
}

/**
 * 获取默认全局本机私有配置文件路径。
 *
 * @returns XDG 用户配置目录下的 database-query.local.json 路径。
 */
export function getGlobalLocalConfigPath(): string {
  return resolve(getGlobalConfigDirectory(), 'database-query.local.json')
}

/**
 * 进行轻量配置结构校验。
 *
 * @param config 待校验配置。
 * @param configPath 配置文件路径，用于错误提示。
 * @returns 无返回值。
 */
function validateConfig(config: DatabaseQueryConfig, configPath: string): void {
  if (!config || typeof config !== 'object') {
    throw new ConfigError(`配置文件不是对象: ${configPath}`)
  }

  if (!Array.isArray(config.instances) || config.instances.length === 0) {
    throw new ConfigError('配置必须包含至少一个 instances[]。')
  }

  const ids = new Set<string>()
  for (const instance of config.instances) {
    if (!instance.id || !instance.type) {
      throw new ConfigError('每个 instance 必须包含 id 与 type。')
    }

    if (ids.has(instance.id)) {
      throw new ConfigError(`重复的 instance id: ${instance.id}`)
    }
    ids.add(instance.id)
  }
}

/**
 * 合并内置允许动作与配置允许动作。
 *
 * @param defaults 配置默认策略。
 * @returns 每种数据库类型允许的动作列表。
 */
function mergeAllowedActions(
  defaults: ConfigDefaults,
): Record<DatabaseType, string[]> {
  return {
    ...DEFAULT_ALLOWED_ACTIONS,
    ...(defaults.allowedActions ?? {}),
  }
}

/**
 * 按显式值、默认值、单候选顺序解析唯一对象。
 *
 * @param items 候选对象。
 * @param explicitName 显式名称。
 * @param defaultName 默认名称。
 * @param label 错误提示中的目标标签。
 * @param getName 取名函数。
 * @returns 唯一候选。
 */
function resolveByName<T>(
  items: T[],
  explicitName: string | undefined,
  defaultName: string | undefined,
  label: string,
  getName: (item: T) => string,
): T {
  const wanted = explicitName ?? defaultName
  if (wanted) {
    const found = items.find((item) => getName(item) === wanted)
    if (!found) {
      throw new ConfigError(
        `未找到 ${label}: ${wanted}。可选值: ${items.map(getName).join(', ')}`,
      )
    }
    return found
  }

  if (items.length === 1) {
    return items[0]
  }

  throw new ConfigError(
    `无法唯一确定 ${label}。请显式指定，可选值: ${items.map(getName).join(', ')}`,
  )
}

/**
 * 解析实例下的数据库目标。
 *
 * @param instance 目标实例。
 * @param databases 候选数据库。
 * @param options 目标选择参数。
 * @returns 数据库目标；无数据库需求时返回 undefined。
 */
function resolveOptionalDatabase(
  instance: DatabaseInstance,
  databases: DatabaseEntry[],
  options: TargetOptions,
): DatabaseEntry | undefined {
  if (databases.length === 0) {
    const databaseName = options.database ?? instance.defaultDatabase
    if (databaseName) {
      return { name: databaseName }
    }

    if (options.requireDatabase) {
      throw new ConfigError(
        `instance ${instance.id} 需要 database。请提供 --database，或配置 defaultDatabase。`,
      )
    }
    return undefined
  }

  if (options.requireDatabase || options.database || instance.defaultDatabase) {
    return resolveByName(
      databases,
      options.database,
      instance.defaultDatabase,
      'database',
      (item) => item.name,
    )
  }

  return databases.length === 1 ? databases[0] : undefined
}

/**
 * 解析 schema 或 collection 命名空间。
 *
 * @param values 候选命名空间。
 * @param explicitName 显式名称。
 * @param defaultName 默认名称。
 * @param label 错误提示标签。
 * @returns 命名空间名称；没有候选时返回 undefined。
 */
function resolveNamespace(
  values: string[],
  explicitName: string | undefined,
  defaultName: string | undefined,
  label: string,
): string | undefined {
  if (values.length === 0) {
    if (explicitName || defaultName) {
      throw new ConfigError(`当前 database 未配置 ${label} 候选。`)
    }
    return undefined
  }

  if (!explicitName && !defaultName && values.length > 1) {
    return undefined
  }

  return resolveByName(values, explicitName, defaultName, label, (item) => item)
}

/**
 * 创建单个实例的脱敏上下文。
 *
 * @param instance 数据库实例。
 * @param allowedActions 默认允许动作。
 * @returns 脱敏后的实例上下文。
 */
function createContextInstance(
  instance: DatabaseInstance,
  allowedActions: Record<DatabaseType, string[]>,
): ContextInstance {
  return {
    id: instance.id,
    type: instance.type,
    environment: instance.environment,
    readonly: instance.readonly,
    defaultDatabase: instance.defaultDatabase,
    databases: instance.databases ?? [],
    allowedActions:
      instance.allowedActions ?? allowedActions[instance.type] ?? [],
    secretStatus: getSecretStatus(instance),
  }
}

/**
 * 获取凭据字段可用性，不返回真实值。
 *
 * @param instance 数据库实例。
 * @returns 凭据字段状态。
 */
function getSecretStatus(
  instance: DatabaseInstance,
): Record<string, SecretStatus> {
  const status: Record<string, SecretStatus> = {}
  for (const field of SECRET_FIELDS) {
    if (field in instance) {
      status[field] = instance[field] ? 'present' : 'missing'
    }
  }

  if (Object.keys(status).length === 0) {
    status.none = 'notRequired'
  }

  return status
}
