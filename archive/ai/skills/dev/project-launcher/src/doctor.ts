import { constants } from 'node:fs'
import { access } from 'node:fs/promises'
import { createConnection } from 'node:net'
import { join } from 'node:path'

import type {
  CommandRunner,
  Diagnostic,
  LaunchPlan,
  PlannedService,
  ProjectDependencyConfig,
} from './types.js'

/**
 * 检查启动计划依赖。
 *
 * @param plan 启动计划。
 * @param options 命令执行器和依赖配置。
 * @returns 诊断列表。
 */
export async function diagnosePlan(
  plan: LaunchPlan,
  options: {
    runner: CommandRunner
    dependencies?: ProjectDependencyConfig[]
  },
): Promise<Diagnostic[]> {
  const diagnostics: Diagnostic[] = []
  diagnostics.push(
    ...(await diagnoseRequiredTools(plan.projectRoot, options.runner)),
  )
  diagnostics.push(...(await diagnosePorts(plan.services)))
  diagnostics.push(
    ...(await diagnoseDependencies(options.dependencies ?? [], options.runner)),
  )
  return diagnostics
}

/**
 * 检查 tmux、java 和构建工具。
 *
 * @param projectRoot 项目根目录。
 * @param runner 命令执行器。
 * @returns 诊断列表。
 */
export async function diagnoseRequiredTools(
  projectRoot: string,
  runner: CommandRunner,
): Promise<Diagnostic[]> {
  const diagnostics: Diagnostic[] = []
  const toolChecks = [
    { command: 'tmux', args: ['-V'], code: 'TMUX_MISSING' as const },
    { command: 'java', args: ['-version'], code: 'JAVA_MISSING' as const },
  ]

  for (const tool of toolChecks) {
    const result = await runner.run(tool.command, tool.args, {
      cwd: projectRoot,
    })
    if (result.exitCode !== 0) {
      diagnostics.push({
        code: tool.code,
        level: 'error',
        target: tool.command,
        message: `缺少必要命令: ${tool.command}`,
        detail: result.stderr || result.stdout,
      })
    }
  }

  const hasMavenWrapper = await canAccess(join(projectRoot, 'mvnw'))
  const hasGradleWrapper = await canAccess(join(projectRoot, 'gradlew'))
  if (!hasMavenWrapper && !hasGradleWrapper) {
    const maven = await runner.run('mvn', ['-v'], { cwd: projectRoot })
    const gradle = await runner.run('gradle', ['-v'], { cwd: projectRoot })
    if (maven.exitCode !== 0 && gradle.exitCode !== 0) {
      diagnostics.push({
        code: 'BUILD_TOOL_MISSING',
        level: 'error',
        message: '未找到 Maven/Gradle wrapper，也未找到全局 mvn 或 gradle。',
      })
    }
  }

  return diagnostics
}

/**
 * 检查服务端口占用。
 *
 * @param services 计划服务列表。
 * @returns 端口诊断。
 */
export async function diagnosePorts(
  services: PlannedService[],
): Promise<Diagnostic[]> {
  const diagnostics: Diagnostic[] = []
  for (const service of services) {
    for (const port of service.ports) {
      const inUse = await isPortInUse(port)
      if (inUse) {
        diagnostics.push({
          code: 'PORT_IN_USE',
          level: 'error',
          target: `${service.name}:${port}`,
          message: `端口已被占用: ${port}`,
        })
      }
    }
  }
  return diagnostics
}

/**
 * 检查外部依赖命令。
 *
 * @param dependencies 依赖配置。
 * @param runner 命令执行器。
 * @returns 诊断列表。
 */
export async function diagnoseDependencies(
  dependencies: ProjectDependencyConfig[],
  runner: CommandRunner,
): Promise<Diagnostic[]> {
  const diagnostics: Diagnostic[] = []
  for (const dependency of dependencies) {
    if (!dependency.checkCommand) {
      continue
    }
    const result = await runner.run('sh', ['-lc', dependency.checkCommand])
    if (result.exitCode !== 0) {
      diagnostics.push({
        code: 'DEPENDENCY_MISSING',
        level: 'warn',
        target: dependency.name,
        message: `依赖服务未就绪: ${dependency.name}`,
        detail: result.stderr || result.stdout,
      })
    }
  }
  return diagnostics
}

/**
 * 判断端口是否被占用。
 *
 * @param port 端口号。
 * @returns 占用时为 true。
 */
export function isPortInUse(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = createConnection({ port, host: '127.0.0.1' })
    socket.once('connect', () => {
      socket.destroy()
      resolve(true)
    })
    socket.once('error', () => {
      socket.destroy()
      resolve(false)
    })
  })
}

/**
 * 检查文件是否可访问。
 *
 * @param filePath 文件路径。
 * @returns 可访问时为 true。
 */
async function canAccess(filePath: string): Promise<boolean> {
  try {
    await access(filePath, constants.X_OK)
    return true
  } catch {
    return false
  }
}
