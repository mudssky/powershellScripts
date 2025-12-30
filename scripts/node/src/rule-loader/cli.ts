/**
 * AI 编码规则加载器 - CLI 配置
 *
 * @description
 * 使用 Commander.js 配置命令行接口。
 */

import { Command } from 'commander'
import path from 'path'
import { AntigravityConverter } from './converters/antigravity'
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
    .command('convert')
    .description('将规则转换为其他格式')
    .option('-t, --target <type>', '目标格式 (antigravity)', 'antigravity')
    .option('-o, --output <dir>', '输出目录')
    .option('-s, --source <dir>', '源规则目录')
    .option('-v, --verbose', '详细输出')
    .action(async (options) => {
      try {
        const cwd = process.cwd()
        // 1. 加载规则
        const rules = await loadRules({
          cwd,
          rulesDir: options.source,
          verbose: options.verbose,
        })

        // 2. 确定输出目录
        let outputDir = options.output
        if (!outputDir) {
          if (options.target === 'antigravity') {
            outputDir = path.resolve(cwd, '.agent/rules')
          } else {
            throw new Error('必须指定输出目录')
          }
        } else {
          outputDir = path.resolve(cwd, outputDir)
        }

        // 3. 执行转换
        if (options.target === 'antigravity') {
          const converter = new AntigravityConverter()
          await converter.convert(rules, outputDir)
          console.log(`成功转换 ${rules.length} 条规则到: ${outputDir}`)
        } else {
          console.error(`不支持的目标格式: ${options.target}`)
          process.exit(1)
        }
      } catch (error) {
        console.error('转换失败:', error)
        process.exit(1)
      }
    })

  program
    .command('load', { isDefault: true })
    .description('加载并输出规则 (默认命令)')
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
