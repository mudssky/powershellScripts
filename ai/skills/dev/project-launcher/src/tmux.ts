import { shellQuote } from './planner.js'
import type { CommandRunner, LaunchPlan } from './types.js'

export interface TmuxCommand {
  command: string
  args: string[]
  display: string
}

/**
 * 生成 tmux 启动命令。
 *
 * @param plan 启动计划。
 * @returns tmux 命令序列。
 */
export function buildTmuxCommands(plan: LaunchPlan): TmuxCommand[] {
  const commands: TmuxCommand[] = []
  const session = plan.session
  commands.push(
    command('tmux', ['new-session', '-d', '-s', session, '-n', 'dev']),
  )

  plan.services.forEach((service, index) => {
    if (index > 0) {
      commands.push(command('tmux', ['split-window', '-t', `${session}:dev`]))
    }
    commands.push(
      command('tmux', [
        'send-keys',
        '-t',
        `${session}:dev.${index}`,
        `cd ${shellQuote(service.cwd)} && ${service.command}`,
        'C-m',
      ]),
    )
  })

  if (plan.services.length > 1) {
    commands.push(
      command('tmux', ['select-layout', '-t', `${session}:dev`, 'tiled']),
    )
  }

  return commands
}

/**
 * 执行 tmux 启动命令。
 *
 * @param plan 启动计划。
 * @param runner 命令执行器。
 * @returns 执行结果。
 */
export async function executeTmuxPlan(
  plan: LaunchPlan,
  runner: CommandRunner,
): Promise<void> {
  for (const tmuxCommand of buildTmuxCommands(plan)) {
    const result = await runner.run(tmuxCommand.command, tmuxCommand.args, {
      cwd: plan.projectRoot,
    })
    if (result.exitCode !== 0) {
      throw new Error(result.stderr || `tmux 命令失败: ${tmuxCommand.display}`)
    }
  }
}

/**
 * 检查 tmux session 是否存在。
 *
 * @param session tmux session 名。
 * @param runner 命令执行器。
 * @param cwd 执行目录。
 * @returns session 存在时为 true。
 */
export async function tmuxSessionExists(
  session: string,
  runner: CommandRunner,
  cwd: string,
): Promise<boolean> {
  const result = await runner.run('tmux', ['has-session', '-t', session], {
    cwd,
  })
  return result.exitCode === 0
}

/**
 * 停止指定 tmux session。
 *
 * @param session tmux session 名。
 * @param runner 命令执行器。
 * @param cwd 执行目录。
 * @returns 无返回值。
 */
export async function killTmuxSession(
  session: string,
  runner: CommandRunner,
  cwd: string,
): Promise<void> {
  const result = await runner.run('tmux', ['kill-session', '-t', session], {
    cwd,
  })
  if (result.exitCode !== 0) {
    throw new Error(result.stderr || `停止 tmux session 失败: ${session}`)
  }
}

/**
 * 生成 attach 命令。
 *
 * @param session tmux session 名。
 * @returns attach 命令对象。
 */
export function buildAttachCommand(session: string): TmuxCommand {
  return command('tmux', ['attach', '-t', session])
}

/**
 * 创建命令对象。
 *
 * @param commandName 命令名。
 * @param args 参数列表。
 * @returns 命令对象。
 */
function command(commandName: string, args: string[]): TmuxCommand {
  return {
    command: commandName,
    args,
    display: [commandName, ...args.map(shellQuote)].join(' '),
  }
}
