/**
 * AI 编码规则加载器 - CLI 配置
 *
 * @description
 * 使用 Commander.js 配置命令行接口。
 */

import { Command } from 'commander'
import { formatOutput } from './formatters'
import { loadRules } from './loader'
import type { CliOptions } from './types'
import { RuleLoadError } from './utils'

/**
 * 创建 CLI 命令
 *
 * @description
 * 配置并返回 Commander 实例。
 *
 * @returns Commander 实例
 */
export function createCli(): Command {
  const program = new Command()

  program
    .name('rule-loader')
    .description('AI 编码规则加载器 - 加载项目规则供 AI 工具使用')
    .version('1.0.0')

  program
    .option('-f, --format <type>', '输出格式 (markdown, json)', 'markdown')
    .option('--filter-apply', '只显示 alwaysApply 规则')
    .option('-v, --verbose', '详细输出')
    .action(async (options: CliOptions) => {
      try {
        await run(options)
      } catch (error) {
        if (error instanceof RuleLoadError) {
          console.error(`错误: ${error.message}`)
          if (options.verbose && error.cause) {
            console.error(error.cause)
          }
          process.exit(1)
        } else if (error instanceof Error) {
          console.error(`错误: ${error.message}`)
          process.exit(1)
        } else {
          console.error('未知错误')
          process.exit(1)
        }
      }
    })

  return program
}

/**
 * 运行主逻辑
 *
 * @description
 * 根据选项加载规则并格式化输出。
 *
 * @param options - CLI 选项
 */
async function run(options: CliOptions): Promise<void> {
  // 加载规则
  const rules = await loadRules({
    onlyAlwaysApply: options.filterApply,
    verbose: options.verbose,
  })

  // 格式化输出
  const output = formatOutput(rules, {
    format: options.format,
    includeHeader: true,
    cwd: process.cwd(),
  })

  // 输出结果
  console.log(output)
}

/**
 * 主入口函数
 *
 * @description
 * 用于直接调用，而非通过 CLI。
 *
 * @param argv - 命令行参数数组
 * @returns Promise
 */
export async function main(argv: string[] = process.argv): Promise<void> {
  const cli = createCli()
  await cli.parseAsync(argv)
}
