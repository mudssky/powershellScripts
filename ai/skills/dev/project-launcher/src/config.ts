import {
  copyFile,
  mkdir,
  readFile,
  rename,
  stat,
  writeFile,
} from 'node:fs/promises'
import { dirname, join, resolve } from 'node:path'

import type {
  LoadedConfig,
  ProjectLauncherConfig,
  ProjectServiceConfig,
} from './types.js'
import { CliError } from './types.js'

const PROJECT_LOCAL_CONFIG = 'project-launch.local.json'
const PROJECT_SHARED_CONFIG = 'project-launch.config.json'
const GLOBAL_CONFIG_DIR = 'project-launcher'

/**
 * 返回项目级配置候选路径。
 *
 * @param projectRoot 项目根目录。
 * @returns 按优先级排列的配置文件路径。
 */
export function getProjectConfigCandidates(projectRoot: string): string[] {
  return [
    join(projectRoot, PROJECT_LOCAL_CONFIG),
    join(projectRoot, PROJECT_SHARED_CONFIG),
  ]
}

/**
 * 返回用户级本机配置路径。
 *
 * @param env 环境变量集合。
 * @returns XDG 或 home 下的用户级 local JSON 路径。
 */
export function getGlobalLocalConfigPath(env = process.env): string {
  const base =
    env.XDG_CONFIG_HOME && env.XDG_CONFIG_HOME.trim().length > 0
      ? env.XDG_CONFIG_HOME
      : join(env.HOME ?? process.cwd(), '.config')

  return join(base, GLOBAL_CONFIG_DIR, PROJECT_LOCAL_CONFIG)
}

/**
 * 读取配置文件；没有配置时返回空配置。
 *
 * @param projectRoot 项目根目录。
 * @param options 显式配置路径和环境变量。
 * @returns 已加载配置及命中来源。
 */
export async function loadConfig(
  projectRoot: string,
  options: { configPath?: string; env?: NodeJS.ProcessEnv } = {},
): Promise<LoadedConfig> {
  if (options.configPath) {
    const configPath = resolve(projectRoot, options.configPath)
    return {
      path: configPath,
      config: await readConfigFile(configPath),
      source: 'explicit',
    }
  }

  for (const candidate of getProjectConfigCandidates(projectRoot)) {
    if (await exists(candidate)) {
      return {
        path: candidate,
        config: await readConfigFile(candidate),
        source: candidate.endsWith(PROJECT_LOCAL_CONFIG)
          ? 'project-local'
          : 'project-config',
      }
    }
  }

  const globalConfigPath = getGlobalLocalConfigPath(options.env)
  if (await exists(globalConfigPath)) {
    return {
      path: globalConfigPath,
      config: await readConfigFile(globalConfigPath),
      source: 'global-local',
    }
  }

  return { config: {}, source: 'none' }
}

/**
 * 读取并解析 JSON 配置。
 *
 * @param configPath 配置文件路径。
 * @returns 解析后的配置。
 */
export async function readConfigFile(
  configPath: string,
): Promise<ProjectLauncherConfig> {
  try {
    const raw = await readFile(configPath, 'utf8')
    return resolveEnvPlaceholders(JSON.parse(raw)) as ProjectLauncherConfig
  } catch (error) {
    if (error instanceof SyntaxError) {
      throw new CliError(
        'CONFIG_PARSE_ERROR',
        `配置文件不是有效 JSON: ${configPath}`,
      )
    }
    throw error
  }
}

/**
 * 把 `${env:NAME}` 占位符替换为环境变量值。
 *
 * @param value 任意 JSON 值。
 * @param env 环境变量集合。
 * @returns 替换后的 JSON 值。
 */
export function resolveEnvPlaceholders(
  value: unknown,
  env = process.env,
): unknown {
  if (typeof value === 'string') {
    return value.replace(/\$\{env:([A-Za-z_][A-Za-z0-9_]*)\}/g, (_, name) => {
      return env[name] ?? ''
    })
  }

  if (Array.isArray(value)) {
    return value.map((item) => resolveEnvPlaceholders(item, env))
  }

  if (value && typeof value === 'object') {
    return Object.fromEntries(
      Object.entries(value).map(([key, entry]) => [
        key,
        resolveEnvPlaceholders(entry, env),
      ]),
    )
  }

  return value
}

/**
 * 写入或更新本机私有服务配置。
 *
 * @param projectRoot 项目根目录。
 * @param service 要保存的服务配置。
 * @param options 是否覆盖已有同名服务。
 * @returns 写入路径和备份路径。
 */
export async function saveServiceToLocalConfig(
  projectRoot: string,
  service: ProjectServiceConfig,
  options: { overwrite?: boolean; now?: Date } = {},
): Promise<{ configPath: string; backupPath?: string }> {
  const configPath = join(projectRoot, PROJECT_LOCAL_CONFIG)
  const existing = (await exists(configPath))
    ? await readConfigFile(configPath)
    : {}
  const services = existing.services ?? []
  const serviceIndex = services.findIndex((item) => item.name === service.name)

  if (serviceIndex >= 0 && !options.overwrite) {
    throw new CliError(
      'CONFIG_PARSE_ERROR',
      `本机配置已存在同名服务: ${service.name}。需要覆盖时传 --overwrite。`,
    )
  }

  const nextServices = [...services]
  if (serviceIndex >= 0) {
    nextServices[serviceIndex] = service
  } else {
    nextServices.push(service)
  }

  const nextConfig: ProjectLauncherConfig = {
    ...existing,
    services: nextServices,
  }

  await mkdir(dirname(configPath), { recursive: true })
  const backupPath = (await exists(configPath))
    ? await backupFile(configPath, options.now)
    : undefined
  const tempPath = `${configPath}.tmp`
  await writeFile(tempPath, `${JSON.stringify(nextConfig, null, 2)}\n`, 'utf8')
  await rename(tempPath, configPath)

  return { configPath, backupPath }
}

/**
 * 创建同目录时间戳备份。
 *
 * @param filePath 待备份文件。
 * @param now 当前时间，测试可注入。
 * @returns 备份文件路径。
 */
export async function backupFile(filePath: string, now = new Date()) {
  const stamp = formatBackupTimestamp(now)
  const backupPath = `${filePath}.${stamp}.bak`
  await copyFile(filePath, backupPath)
  return backupPath
}

/**
 * 格式化备份时间戳。
 *
 * @param value 当前时间。
 * @returns 适合文件名的本地时间戳。
 */
export function formatBackupTimestamp(value: Date): string {
  const pad = (input: number) => String(input).padStart(2, '0')
  return (
    [value.getFullYear(), pad(value.getMonth() + 1), pad(value.getDate())].join(
      '-',
    ) +
    '_' +
    [
      pad(value.getHours()),
      pad(value.getMinutes()),
      pad(value.getSeconds()),
    ].join('-')
  )
}

/**
 * 判断路径是否存在。
 *
 * @param filePath 目标路径。
 * @returns 存在时为 true。
 */
export async function exists(filePath: string): Promise<boolean> {
  try {
    await stat(filePath)
    return true
  } catch {
    return false
  }
}

/**
 * 脱敏环境变量输出。
 *
 * @param env 服务环境变量。
 * @returns 适合展示的环境变量。
 */
export function redactEnv(env: Record<string, string>): Record<string, string> {
  return Object.fromEntries(
    Object.entries(env).map(([key, value]) => [
      key,
      isSensitiveKey(key) ? '<redacted>' : value,
    ]),
  )
}

/**
 * 判断变量名是否可能包含敏感值。
 *
 * @param key 环境变量名。
 * @returns 敏感变量返回 true。
 */
export function isSensitiveKey(key: string): boolean {
  return /(password|passwd|token|secret|key|cookie|credential|dsn|uri|url)/i.test(
    key,
  )
}
