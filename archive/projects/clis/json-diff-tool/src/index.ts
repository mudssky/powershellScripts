#!/usr/bin/env node

/**
 * JSON差异比较工具主入口文件
 * 支持JSON、JSONC、JSON5格式的文件比较
 *
 * @author mudssky
 * @version 1.0.0
 */

import * as fs from 'node:fs/promises'
import { Command } from 'commander'
import { JsonComparator } from './comparator'
import { OutputFormatter } from './formatter'
import { FileParser } from './parser'
import { type CompareOptions, DiffType, OutputFormat } from './types'

// 创建命令行程序
const program = new Command()

program
  .name('json-diff')
  .description('Compare JSON, JSONC, and JSON5 files and show differences')
  .version('1.0.0')
  .showHelpAfterError()
  .showSuggestionAfterError()
  .argument('<files...>', 'JSON files to compare (minimum 2 files)')
  .option(
    '-o, --output <format>',
    'output format (table|json|yaml|tree)',
    'table',
  )
  .option('--output-file <path>', 'write output to file')
  .option('-u, --show-unchanged', 'show unchanged values', false)
  .option('-i, --ignore-order', 'ignore array order when comparing', false)
  .option('-d, --depth <number>', 'maximum depth for comparison', '10')
  .option('-f, --filter <pattern>', 'filter paths by pattern (regex)')
  .option('--no-color', 'disable colored output', false)
  .option('-s, --stats', 'show summary statistics', true)
  .option('-v, --verbose', 'verbose output', false)
  .action(async (files: string[], options) => {
    try {
      // 验证文件数量
      if (files.length < 2) {
        console.error('Error: At least 2 files are required for comparison')
        program.outputHelp()
        process.exit(1)
      }

      // 验证输出格式
      const validFormats = Object.values(OutputFormat)
      if (!validFormats.includes(options.output as OutputFormat)) {
        console.error(
          `Error: Invalid output format. Valid formats: ${validFormats.join(
            ', ',
          )}`,
        )
        program.outputHelp()
        process.exit(1)
      }

      const cliOptionsBase = {
        files,
        output: options.output as OutputFormat,
        showUnchanged: !!options.showUnchanged,
        ignoreOrder: !!options.ignoreOrder,
        depth: parseInt(options.depth, 10),
        verbose: !!options.verbose,
        noColor: !!options.noColor,
        stats: !!options.stats,
      }

      const cliOptions = {
        ...cliOptionsBase,
        ...(typeof options.filter === 'string' && options.filter
          ? { filter: options.filter as string }
          : {}),
        ...(typeof options.outputFile === 'string' && options.outputFile
          ? { outputFile: options.outputFile as string }
          : {}),
      }

      // 验证深度参数
      if (Number.isNaN(cliOptions.depth) || cliOptions.depth < 1) {
        console.error('Error: Depth must be a positive number')
        program.outputHelp()
        process.exit(1)
      }

      // 验证文件是否存在且为支持的格式
      await validateFiles(files)

      if (cliOptions.verbose) {
        console.log(`Comparing ${files.length} files:`)
        files.forEach((file, index) => {
          console.log(`  ${index + 1}. ${file}`)
        })
        console.log()
      }

      // 执行比较
      await performComparison(cliOptions)
    } catch (_error) {
      console.error(
        'Error:',
        _error instanceof Error ? _error.message : String(_error),
      )
      process.exit(1)
    }
  })

/**
 * 验证文件是否存在且为支持的格式
 * @param files 文件路径数组
 */
async function validateFiles(files: string[]): Promise<void> {
  for (const file of files) {
    try {
      const stats = await fs.stat(file)

      if (!stats.isFile()) {
        throw new Error(`Path is not a file: ${file}`)
      }

      if (!FileParser.isSupportedFormat(file)) {
        const supportedExts = FileParser.getSupportedExtensions().join(', ')
        console.warn(
          `Warning: File ${file} may not be a supported format. Supported extensions: ${supportedExts}`,
        )
      }
    } catch (error) {
      if (error instanceof Error && 'code' in error) {
        const nodeError = error as NodeJS.ErrnoException
        if (nodeError.code === 'ENOENT') {
          throw new Error(`File not found: ${file}`)
        }
      }
      throw error
    }
  }
}

/**
 * 执行文件比较
 * @param options CLI选项
 */
async function performComparison(options: {
  files: string[]
  output: OutputFormat
  showUnchanged: boolean
  ignoreOrder: boolean
  depth: number
  filter?: string
  verbose: boolean
  outputFile?: string
  noColor: boolean
  stats: boolean
}): Promise<void> {
  try {
    // 创建解析器和比较器
    const parser = new FileParser()
    const compareOptions: CompareOptions = {
      ignoreArrayOrder: options.ignoreOrder,
      maxDepth: options.depth,
    }
    const comparator = new JsonComparator(compareOptions)

    if (options.verbose) {
      console.log('Parsing files...')
    }

    // 解析所有文件
    const parsedFiles = await parser.parseFiles(options.files)
    const jsonObjects = parsedFiles.map((f) => f.content)

    if (options.verbose) {
      console.log('Performing comparison...')
    }

    // 执行比较
    const results = comparator.compare(jsonObjects)

    // 过滤结果
    let filteredResults = results

    // 按类型过滤
    if (!options.showUnchanged) {
      filteredResults = filteredResults.filter(
        (result) => result.type !== DiffType.UNCHANGED,
      )
    }

    // 按路径模式过滤
    if (options.filter) {
      try {
        const filterRegex = new RegExp(options.filter)
        filteredResults = JsonComparator.filterResults(filteredResults, {
          pathPattern: filterRegex,
        })
      } catch (_error) {
        console.error(`Error: Invalid filter pattern: ${options.filter}`)
        program.outputHelp()
        process.exit(1)
      }
    }

    // 输出结果
    const formatter = new OutputFormatter(!options.noColor)
    const output = formatter.format(
      filteredResults,
      options.output,
      options.files,
      options.stats,
    )

    if (options.outputFile) {
      await formatter.outputToFile(output, options.outputFile)
      if (options.verbose) {
        console.log(`Output written to: ${options.outputFile}`)
      }
    } else {
      console.log(output)
    }
  } catch (error) {
    throw new Error(
      `Comparison failed: ${
        error instanceof Error ? error.message : String(error)
      }`,
    )
  }
}

// 解析命令行参数
program.parse()

// 导出主程序用于测试
export { program }
