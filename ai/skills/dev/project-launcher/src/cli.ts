import { join, resolve } from 'node:path'
import { cac } from 'cac'

import { loadConfig, saveServiceToLocalConfig } from './config.js'
import { diagnosePlan } from './doctor.js'
import { formatPlan } from './format.js'
import {
  isRuntimeDirectoryIgnored,
  writeRuntimeGitignore,
} from './gitignore.js'
import { createLaunchPlan } from './planner.js'
import { NodeCommandRunner } from './runner.js'
import {
  createSessionMetadata,
  readSessionMetadata,
  validateSessionMetadata,
  writeSessionMetadata,
} from './session.js'
import {
  buildAttachCommand,
  executeTmuxPlan,
  killTmuxSession,
  tmuxSessionExists,
} from './tmux.js'
import type {
  CliIo,
  CommandRunner,
  OutputFormat,
  ProjectServiceConfig,
  ReloadMode,
} from './types.js'
import { CliError } from './types.js'

export interface CliRuntime {
  io: CliIo
  runner: CommandRunner
  cwd: string
}

const DEFAULT_IO: CliIo = {
  stdout: (message) => console.log(message),
  stderr: (message) => console.error(message),
}

/**
 * 运行 CLI。
 *
 * @param argv 命令行参数。
 * @param runtime 测试可注入的运行环境。
 * @returns 退出码。
 */
export async function runCli(
  argv: string[],
  runtime: Partial<CliRuntime> = {},
): Promise<number> {
  const io = runtime.io ?? DEFAULT_IO
  const runner = runtime.runner ?? new NodeCommandRunner()
  const cwd = runtime.cwd ?? process.cwd()
  const cli = cac('project-launcher')

  cli.option('--cwd <path>', '项目根目录。').help()

  cli
    .command('plan', '发现项目并输出启动计划。')
    .option('--config <path>', '配置文件路径。')
    .option('--service <name>', '指定服务，支持逗号分隔。')
    .option('--all', '选择全部服务。')
    .option('--format <format>', '输出格式：text 或 json。', {
      default: 'text',
    })
    .option('--allow-parallel-build', '允许并发构建。')
    .action(async (options: Record<string, unknown>) => {
      const plan = await preparePlan('plan', options, { cwd, runner })
      await warnGitignore(plan, io)
      io.stdout(formatPlan(plan, parseFormat(options.format)))
    })

  cli
    .command('doctor', '检查启动依赖、端口和外部依赖。')
    .option('--config <path>', '配置文件路径。')
    .option('--service <name>', '指定服务，支持逗号分隔。')
    .option('--all', '选择全部服务。')
    .option('--format <format>', '输出格式：text 或 json。', {
      default: 'text',
    })
    .action(async (options: Record<string, unknown>) => {
      const plan = await preparePlan('doctor', options, { cwd, runner })
      plan.diagnostics.push(
        ...(await diagnosePlan(plan, {
          runner,
          dependencies: (
            await loadConfigForOptions(options, cwd)
          ).config.dependencies,
        })),
      )
      await warnGitignore(plan, io)
      io.stdout(formatPlan(plan, parseFormat(options.format)))
    })

  cli
    .command('start', '通过 tmux 启动服务。')
    .option('--config <path>', '配置文件路径。')
    .option('--service <name>', '指定服务，支持逗号分隔。')
    .option('--all', '选择全部服务。')
    .option('--name <name>', '一次性命令的服务名。')
    .option('--command <command>', '一次性启动命令。')
    .option('--port <port>', '一次性命令端口。')
    .option('--save', '把一次性命令保存到 project-launch.local.json。')
    .option('--overwrite', '保存同名服务时覆盖。')
    .option('--replace', '同名 tmux session 冲突时显式停止并重建。')
    .option('--attach', '启动后直接 attach 进入 tmux。')
    .option('--format <format>', '输出格式：text 或 json。', {
      default: 'text',
    })
    .option('--reload <mode>', '热重载模式：auto、off 或 command。', {
      default: 'auto',
    })
    .option('--allow-parallel-build', '允许并发构建。')
    .action(async (options: Record<string, unknown>) => {
      const commandOverride = parseCommandOverride(options)
      if (options.save && !commandOverride) {
        throw new CliError(
          'CONFIG_PARSE_ERROR',
          '--save 需要同时提供 --name 和 --command。',
        )
      }

      const plan = await preparePlan('start', options, { cwd, runner })
      const loadedConfig = await loadConfigForOptions(options, cwd)

      if (options.save && commandOverride) {
        const port = parsePort(options.port)
        await saveServiceToLocalConfig(
          resolveProjectRoot(cwd, options.cwd),
          {
            name: commandOverride.name,
            command: commandOverride.command,
            port,
          } satisfies ProjectServiceConfig,
          { overwrite: Boolean(options.overwrite) },
        )
      }

      plan.diagnostics.push(
        ...(await diagnosePlan(plan, {
          runner,
          dependencies: loadedConfig.config.dependencies,
        })),
      )
      await warnGitignore(plan, io)

      if (!plan.ok || plan.diagnostics.some((item) => item.level === 'error')) {
        io.stdout(formatPlan(plan, parseFormat(options.format)))
        return
      }

      const metadata = await readSessionMetadata(plan.metadataPath)
      const metadataCheck = validateSessionMetadata(metadata, plan)
      const existingSession = await tmuxSessionExists(
        plan.session,
        runner,
        plan.projectRoot,
      )
      if (existingSession) {
        if (metadataCheck.ok) {
          io.stdout(formatPlan(plan, parseFormat(options.format)))
          if (options.attach) {
            const attach = buildAttachCommand(plan.session)
            await runner.run(attach.command, attach.args, {
              cwd: plan.projectRoot,
            })
          }
          return
        }

        if (!options.replace) {
          throw new CliError(
            'SESSION_CONFLICT',
            `同名 tmux session 已存在但不能安全复用: ${metadataCheck.reason}。需要重建时传 --replace。`,
          )
        }

        await killTmuxSession(plan.session, runner, plan.projectRoot)
      }

      await executePrepareCommands(plan, runner)
      await executeTmuxPlan(plan, runner)
      await writeSessionMetadata(plan.metadataPath, createSessionMetadata(plan))

      io.stdout(formatPlan(plan, parseFormat(options.format)))

      if (options.attach) {
        const attach = buildAttachCommand(plan.session)
        await runner.run(attach.command, attach.args, { cwd: plan.projectRoot })
      }
    })

  cli
    .command('attach', '进入当前项目 tmux session。')
    .option('--print', '只打印 attach 命令。')
    .action(async (options: Record<string, unknown>) => {
      const projectRoot = resolveProjectRoot(cwd, options.cwd)
      const metadata = await readSessionMetadata(
        join(projectRoot, '.project-launcher', 'session.json'),
      )
      if (!metadata) {
        throw new CliError('SESSION_CONFLICT', '未找到 session 元数据。')
      }
      const attach = buildAttachCommand(metadata.session)
      if (options.print) {
        io.stdout(attach.display)
        return
      }
      await runner.run(attach.command, attach.args, { cwd: projectRoot })
    })

  cli
    .command('stop', '停止当前项目 tmux session。')
    .option('--force', '缺少完整元数据时仍尝试停止。')
    .action(async (options: Record<string, unknown>) => {
      const projectRoot = resolveProjectRoot(cwd, options.cwd)
      const metadata = await readSessionMetadata(
        join(projectRoot, '.project-launcher', 'session.json'),
      )
      if (!metadata && !options.force) {
        throw new CliError(
          'SESSION_CONFLICT',
          '未找到 session 元数据。需要强制停止时传 --force。',
        )
      }
      const session = metadata?.session
      if (!session) {
        throw new CliError('SESSION_CONFLICT', '--force 仍需要可识别 session。')
      }
      await killTmuxSession(session, runner, projectRoot)
      io.stdout(`Stopped ${session}`)
    })

  cli
    .command('init', '初始化项目启动器辅助配置。')
    .option('--write-gitignore', '写入 .project-launcher/ 忽略规则。')
    .action(async (options: Record<string, unknown>) => {
      const projectRoot = resolveProjectRoot(cwd, options.cwd)
      if (!options.writeGitignore) {
        const ignored = await isRuntimeDirectoryIgnored(projectRoot)
        io.stdout(
          ignored
            ? '.project-launcher/ 已被 .gitignore 忽略。'
            : '未写入任何文件；如需忽略运行态目录，传 --write-gitignore。',
        )
        return
      }
      const changed = await writeRuntimeGitignore(projectRoot)
      io.stdout(changed ? '已写入 .project-launcher/' : '忽略规则已存在。')
    })

  try {
    cli.parse(['node', 'project-launcher', ...argv], { run: false })
    await cli.runMatchedCommand()
    return 0
  } catch (error) {
    if (error instanceof CliError) {
      io.stderr(error.message)
      return error.exitCode
    }
    io.stderr(error instanceof Error ? error.message : String(error))
    return 1
  }
}

/**
 * 准备计划。
 *
 * @param action 当前动作。
 * @param options CLI 选项。
 * @param runtime 运行环境。
 * @returns 启动计划。
 */
async function preparePlan(
  action: 'plan' | 'doctor' | 'start',
  options: Record<string, unknown>,
  runtime: Pick<CliRuntime, 'cwd' | 'runner'>,
) {
  const projectRoot = resolveProjectRoot(runtime.cwd, options.cwd)
  const loadedConfig = await loadConfigForOptions(options, runtime.cwd)
  const commandOverride = parseCommandOverride(options)
  return createLaunchPlan({
    action,
    projectRoot,
    loadedConfig,
    serviceNames: parseServiceNames(options.service),
    all: Boolean(options.all),
    commandService: commandOverride
      ? {
          ...commandOverride,
          port: parsePort(options.port),
          reload: parseReload(options.reload),
        }
      : undefined,
    allowParallelBuild: Boolean(options.allowParallelBuild),
  })
}

/**
 * 加载配置。
 *
 * @param options CLI 选项。
 * @param cwd 当前目录。
 * @returns 已加载配置。
 */
async function loadConfigForOptions(
  options: Record<string, unknown>,
  cwd: string,
) {
  const projectRoot = resolveProjectRoot(cwd, options.cwd)
  return loadConfig(projectRoot, {
    configPath: typeof options.config === 'string' ? options.config : undefined,
  })
}

/**
 * 解析项目根目录。
 *
 * @param cwd 当前目录。
 * @param option 显式 cwd。
 * @returns 项目根目录。
 */
function resolveProjectRoot(cwd: string, option: unknown): string {
  return resolve(cwd, typeof option === 'string' ? option : '.')
}

/**
 * 解析输出格式。
 *
 * @param value 原始值。
 * @returns 输出格式。
 */
function parseFormat(value: unknown): OutputFormat {
  return value === 'json' ? 'json' : 'text'
}

/**
 * 解析服务名列表。
 *
 * @param value 原始值。
 * @returns 服务名列表。
 */
function parseServiceNames(value: unknown): string[] | undefined {
  if (typeof value !== 'string' || value.trim().length === 0) {
    return undefined
  }
  return value
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean)
}

/**
 * 解析一次性命令参数。
 *
 * @param options CLI 选项。
 * @returns 一次性命令或 undefined。
 */
function parseCommandOverride(
  options: Record<string, unknown>,
): { name: string; command: string } | undefined {
  if (typeof options.name === 'string' && typeof options.command === 'string') {
    return { name: options.name, command: options.command }
  }
  return undefined
}

/**
 * 解析端口。
 *
 * @param value 原始值。
 * @returns 端口或 undefined。
 */
function parsePort(value: unknown): number | undefined {
  if (value === undefined) {
    return undefined
  }
  const parsed = Number(value)
  return Number.isInteger(parsed) ? parsed : undefined
}

/**
 * 解析热重载模式。
 *
 * @param value 原始值。
 * @returns 热重载模式。
 */
function parseReload(value: unknown): ReloadMode | undefined {
  if (value === 'auto' || value === 'off' || value === 'command') {
    return value
  }
  return undefined
}

/**
 * 输出 gitignore 运行态目录提示。
 *
 * @param plan 启动计划。
 * @param io 输出接口。
 * @returns 无返回值。
 */
async function warnGitignore(
  plan: { projectRoot: string; diagnostics: unknown[] },
  io: CliIo,
) {
  if (!(await isRuntimeDirectoryIgnored(plan.projectRoot))) {
    io.stderr(
      '提示: 建议将 .project-launcher/ 加入 .gitignore，可执行 project-launcher init --write-gitignore。',
    )
  }
}

/**
 * 串行执行服务 prepare 命令。
 *
 * @param plan 启动计划。
 * @param runner 命令执行器。
 * @returns 无返回值。
 */
async function executePrepareCommands(
  plan: Awaited<ReturnType<typeof createLaunchPlan>>,
  runner: CommandRunner,
): Promise<void> {
  for (const service of plan.services) {
    for (const prepare of service.prepare) {
      const result = await runner.run('sh', ['-lc', prepare], {
        cwd: service.cwd,
        env: service.env,
      })
      if (result.exitCode !== 0) {
        throw new CliError(
          'PREPARE_FAILED',
          `服务 ${service.name} 的 prepare 命令失败: ${prepare}\n${result.stderr || result.stdout}`,
        )
      }
    }
  }
}
