import fs from 'node:fs/promises'
import path from 'node:path'
import inquirer from 'inquirer'
import { diffString } from 'json-diff'
import type { Installer, InstallerOptions } from './types'

interface ClaudeConfig {
  hooks?: {
    SessionStart?: Array<{
      matcher: string
      hooks: Array<{
        type: string
        command: string
      }>
    }>
    UserCommand?: Array<{
      matcher: string
      hooks: Array<{
        type: string
        command: string
      }>
    }>
    [key: string]: unknown
  }
  [key: string]: unknown
}

const TARGET_HOOKS = {
  hooks: {
    SessionStart: [
      {
        matcher: 'startup',
        hooks: [
          {
            type: 'command',
            command: "echo '项目启动，加载 Trae 规则...' && rule-loader",
          },
        ],
      },
      {
        matcher: 'clear',
        hooks: [
          {
            type: 'command',
            command:
              "echo '上下文已清空，正在重新加载 Trae 规则...' && rule-loader",
          },
        ],
      },
      {
        matcher: 'compact',
        hooks: [
          {
            type: 'command',
            command: 'rule-loader',
          },
        ],
      },
    ],
    UserCommand: [
      {
        matcher: '/reload-rules',
        hooks: [
          {
            type: 'command',
            command: 'rule-loader', // 手动再次注入
          },
        ],
      },
    ],
  },
}

export class ClaudeInstaller implements Installer {
  name = 'claude'

  async install(options: InstallerOptions): Promise<void> {
    const configPath = path.resolve(options.cwd, '.claude', 'settings.json')
    if (options.verbose) {
      console.log(`正在检查 Claude Code 配置: ${configPath}`)
    }

    let currentConfig: ClaudeConfig = {}

    try {
      const content = await fs.readFile(configPath, 'utf-8')
      currentConfig = JSON.parse(content)
    } catch (error: unknown) {
      if (
        error &&
        typeof error === 'object' &&
        'code' in error &&
        error.code !== 'ENOENT'
      ) {
        throw error
      }
      // File doesn't exist, start with empty object
    }

    const newConfig = this.mergeConfig(currentConfig, TARGET_HOOKS)

    // Check if there are changes
    const diff = diffString(currentConfig, newConfig)

    if (!diff) {
      if (options.verbose) {
        console.log('配置已是最新，无需修改。')
      }
      return
    }

    if (options.verbose || !options.force) {
      console.log('检测到配置变更:')
      console.log(diff)
    }

    if (options.force) {
      await this.writeConfig(configPath, newConfig, options.verbose)
      return
    }

    const { confirm } = await inquirer.prompt([
      {
        type: 'confirm',
        name: 'confirm',
        message: '确认应用以上变更吗?',
        default: true,
      },
    ])

    if (confirm) {
      await this.writeConfig(configPath, newConfig, true)
    } else {
      console.log('已取消操作。')
    }
  }

  private mergeConfig(
    current: ClaudeConfig,
    target: typeof TARGET_HOOKS,
  ): ClaudeConfig {
    const result = JSON.parse(JSON.stringify(current)) as ClaudeConfig // Deep copy

    if (!result.hooks) {
      result.hooks = {}
    }

    // Merge SessionStart
    if (!result.hooks.SessionStart) {
      result.hooks.SessionStart = []
    }
    for (const hook of target.hooks.SessionStart) {
      if (!this.hasHook(result.hooks.SessionStart, hook)) {
        result.hooks.SessionStart.push(hook)
      }
    }

    // Merge UserCommand
    if (!result.hooks.UserCommand) {
      result.hooks.UserCommand = []
    }
    for (const hook of target.hooks.UserCommand) {
      if (!this.hasHook(result.hooks.UserCommand, hook)) {
        result.hooks.UserCommand.push(hook)
      }
    }

    return result
  }

  private hasHook(list: unknown[], hook: unknown): boolean {
    return list.some((item) => JSON.stringify(item) === JSON.stringify(hook))
  }

  private async writeConfig(
    filePath: string,
    config: ClaudeConfig,
    verbose?: boolean,
  ): Promise<void> {
    const dir = path.dirname(filePath)
    await fs.mkdir(dir, { recursive: true })
    await fs.writeFile(filePath, JSON.stringify(config, null, 2), 'utf-8')
    if (verbose) {
      console.log(`配置已写入: ${filePath}`)
    }
  }
}
