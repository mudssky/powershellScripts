import { spawn } from 'node:child_process'

import type { CommandRunner, CommandRunnerResult } from './types.js'

export class NodeCommandRunner implements CommandRunner {
  /**
   * 运行外部命令并收集输出。
   *
   * @param command 命令名。
   * @param args 命令参数。
   * @param options 执行目录、环境和输入。
   * @returns 命令退出结果。
   */
  run(
    command: string,
    args: string[],
    options: { cwd?: string; env?: NodeJS.ProcessEnv; input?: string } = {},
  ): Promise<CommandRunnerResult> {
    return new Promise((resolve) => {
      const child = spawn(command, args, {
        cwd: options.cwd,
        env: { ...process.env, ...options.env },
        stdio: ['pipe', 'pipe', 'pipe'],
      })
      let stdout = ''
      let stderr = ''

      child.stdout.setEncoding('utf8')
      child.stderr.setEncoding('utf8')
      child.stdout.on('data', (chunk) => {
        stdout += chunk
      })
      child.stderr.on('data', (chunk) => {
        stderr += chunk
      })
      child.on('error', (error) => {
        resolve({ exitCode: 127, stdout, stderr: error.message })
      })
      child.on('close', (code) => {
        resolve({ exitCode: code ?? 1, stdout, stderr })
      })

      if (options.input) {
        child.stdin.write(options.input)
      }
      child.stdin.end()
    })
  }
}
