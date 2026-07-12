import { basename, join, resolve } from 'node:path'

import { redactEnv } from './config.js'
import {
  discoverProject,
  sanitizeServiceName,
  serviceFromCommand,
} from './discovery.js'
import type {
  Diagnostic,
  DiscoveryResult,
  LaunchPlan,
  LoadedConfig,
  PlannedService,
  ReloadMode,
  ServiceCandidate,
} from './types.js'

export interface PlanOptions {
  action: LaunchPlan['action']
  projectRoot: string
  loadedConfig: LoadedConfig
  serviceNames?: string[]
  all?: boolean
  commandService?: {
    name: string
    command: string
    port?: number
    reload?: ReloadMode
  }
  allowParallelBuild?: boolean
}

/**
 * 生成启动计划。
 *
 * @param options 计划输入。
 * @returns 启动计划。
 */
export async function createLaunchPlan(
  options: PlanOptions,
): Promise<LaunchPlan> {
  const discovery = await discoverProject(
    options.projectRoot,
    options.loadedConfig.config,
  )
  const extra = options.commandService
    ? [serviceFromCommand(options.projectRoot, options.commandService)]
    : []
  const candidates = [...discovery.services, ...extra]
  const diagnostics: Diagnostic[] = []
  const selection = selectServices(candidates, {
    names: options.serviceNames,
    all: options.all,
    action: options.action,
  })

  diagnostics.push(...selection.diagnostics)

  if (hasParallelBuildRisk(selection.services) && !options.allowParallelBuild) {
    diagnostics.push({
      code: 'PARALLEL_BUILD_RISK',
      level: 'warn',
      message:
        '检测到多个服务包含构建/编译准备命令；默认将串行准备，需并发时传 --allow-parallel-build。',
    })
  }

  const session = resolveSessionName(
    options.projectRoot,
    options.loadedConfig.config.defaults?.sessionName,
  )
  const services = selection.services.map((service, index) =>
    toPlannedService(service, index),
  )

  return {
    ok: !diagnostics.some((item) => item.level === 'error'),
    action: options.action,
    projectRoot: options.projectRoot,
    session,
    attachCommand: `tmux attach -t ${shellQuote(session)}`,
    services,
    ignored: discovery.ignored,
    diagnostics,
    metadataPath: join(
      options.projectRoot,
      '.project-launcher',
      'session.json',
    ),
    configPath: options.loadedConfig.path,
    selectionRequired: selection.selectionRequired,
  }
}

/**
 * 根据服务名或 all 参数选择服务。
 *
 * @param candidates 可用候选。
 * @param options 选择参数。
 * @returns 被选服务和诊断。
 */
export function selectServices(
  candidates: ServiceCandidate[],
  options: {
    names?: string[]
    all?: boolean
    action: LaunchPlan['action']
  },
): {
  services: ServiceCandidate[]
  diagnostics: Diagnostic[]
  selectionRequired: boolean
} {
  const diagnostics: Diagnostic[] = []
  const names = options.names ?? []

  if (names.length > 0) {
    const services = candidates.filter((candidate) =>
      names.includes(candidate.name),
    )
    const missing = names.filter(
      (name) => !candidates.some((candidate) => candidate.name === name),
    )
    for (const name of missing) {
      diagnostics.push({
        code: 'UNKNOWN_SERVICE',
        level: 'error',
        message: `未找到服务: ${name}`,
        target: name,
      })
    }
    return { services, diagnostics, selectionRequired: false }
  }

  if (options.all) {
    return { services: candidates, diagnostics, selectionRequired: false }
  }

  if (candidates.length === 1) {
    return {
      services: candidates,
      diagnostics,
      selectionRequired: false,
    }
  }

  if (candidates.length > 1) {
    diagnostics.push({
      code: 'MULTI_SERVICE_SELECTION_REQUIRED',
      level: options.action === 'start' ? 'error' : 'warn',
      message:
        '发现多个服务候选，未传 --service 或 --all；默认只输出计划，不启动全部候选。',
    })
    return { services: [], diagnostics, selectionRequired: true }
  }

  if (options.action === 'start') {
    diagnostics.push({
      code: 'NO_SERVICE_CANDIDATE',
      level: 'error',
      message:
        '没有可启动服务。可先运行 plan 查看发现结果，或使用 --name 与 --command 指定一次性命令。',
    })
  }

  return { services: [], diagnostics, selectionRequired: false }
}

/**
 * 转换为计划服务。
 *
 * @param service 服务候选。
 * @param index pane 序号。
 * @returns 计划服务。
 */
function toPlannedService(
  service: ServiceCandidate,
  index: number,
): PlannedService {
  const pane = `dev.${index}`
  return {
    name: service.name,
    cwd: service.cwd,
    command: service.command,
    displayCommand: service.command,
    port: service.port,
    ports: service.ports,
    prepare: service.prepare,
    env: service.env,
    displayEnv: redactEnv(service.env),
    pane,
    source: service.source,
  }
}

/**
 * 判断服务计划是否有并发构建风险。
 *
 * @param services 服务候选。
 * @returns 存在风险时为 true。
 */
export function hasParallelBuildRisk(services: ServiceCandidate[]): boolean {
  return (
    services.filter((service) =>
      service.prepare.some((command) =>
        /\b(compile|build|package|classes)\b/.test(command),
      ),
    ).length > 1
  )
}

/**
 * 生成默认 tmux session 名。
 *
 * @param projectRoot 项目根目录。
 * @param explicit 显式 session 名。
 * @returns session 名称。
 */
export function resolveSessionName(
  projectRoot: string,
  explicit?: string,
): string {
  if (explicit) {
    return explicit
  }
  return `pl-${sanitizeServiceName(basename(resolve(projectRoot)))}`
}

/**
 * shell 参数引用。
 *
 * @param value 原始值。
 * @returns 可用于 shell 的值。
 */
export function shellQuote(value: string): string {
  if (/^[A-Za-z0-9_./:-]+$/.test(value)) {
    return value
  }
  return `'${value.replace(/'/g, `'\\''`)}'`
}

/**
 * 用于测试的发现结果摘要。
 *
 * @param discovery 发现结果。
 * @returns 服务名和忽略模块名。
 */
export function summarizeDiscovery(discovery: DiscoveryResult): {
  services: string[]
  ignored: string[]
} {
  return {
    services: discovery.services.map((service) => service.name),
    ignored: discovery.ignored.map((item) => item.name),
  }
}
