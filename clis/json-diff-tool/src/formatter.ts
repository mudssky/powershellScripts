/**
 * 输出格式化模块
 * 提供多种输出格式的格式化器，包括表格、JSON、YAML、树形结构等
 * 使用chalk提供彩色输出，使用cli-table3生成美观的表格
 *
 * @author mudssky
 */

import chalk from 'chalk'
import Table from 'cli-table3'
import * as yaml from 'js-yaml'
import { type DiffResult, DiffType, OutputFormat } from './types'

/**
 * 输出格式化器类
 * 提供多种格式的差异结果输出
 */
export class OutputFormatter {
  private colorEnabled: boolean

  constructor(colorEnabled: boolean = true) {
    this.colorEnabled = colorEnabled
  }

  /**
   * 根据输出格式格式化差异结果
   * @param diffs 差异结果数组
   * @param format 输出格式
   * @param files 比较的文件列表
   * @param showStats 是否显示统计信息
   * @returns 格式化后的字符串
   */
  format(
    diffs: DiffResult[],
    format: OutputFormat,
    files: string[] = [],
    showStats: boolean = true,
  ): string {
    switch (format) {
      case OutputFormat.TABLE:
        return this.formatAsTable(diffs, showStats)
      case OutputFormat.JSON:
        return this.formatAsJson(diffs, files, showStats)
      case OutputFormat.YAML:
        return this.formatAsYaml(diffs, files, showStats)
      case OutputFormat.TREE:
        return this.formatAsTree(diffs, showStats)
      default:
        throw new Error(`Unsupported output format: ${format}`)
    }
  }

  /**
   * 格式化为表格输出
   * @param diffs 差异结果数组
   * @param showStats 是否显示统计信息
   * @returns 表格格式字符串
   */
  formatAsTable(diffs: DiffResult[], showStats: boolean = true): string {
    if (diffs.length === 0) {
      return this.colorize('No differences found.', 'info')
    }

    const table = new Table({
      head: [
        this.colorize('Type', 'header'),
        this.colorize('Path', 'header'),
        this.colorize('Old Value', 'header'),
        this.colorize('New Value', 'header'),
      ],
      colWidths: [12, 40, 25, 25],
      wordWrap: true,
      wrapOnWordBoundary: false,
    })

    diffs.forEach((diff) => {
      const typeCell = this.colorizeByType(diff.type.toUpperCase(), diff.type)
      const pathCell = this.colorize(diff.path || '', 'path')
      const oldValueCell = this.formatValue(
        diff.oldValue,
        diff.type === DiffType.REMOVED,
      )
      const newValueCell = this.formatValue(
        diff.newValue,
        diff.type === DiffType.ADDED,
      )

      table.push([typeCell, pathCell, oldValueCell, newValueCell])
    })

    let result = table.toString()

    if (showStats) {
      result += '\n' + this.formatStatistics(diffs)
    }

    return result
  }

  /**
   * 格式化为JSON输出
   * @param diffs 差异结果数组
   * @param files 比较的文件列表
   * @param showStats 是否显示统计信息
   * @returns JSON格式字符串
   */
  formatAsJson(
    diffs: DiffResult[],
    files: string[] = [],
    showStats: boolean = true,
  ): string {
    const output: any = {
      files,
      timestamp: new Date().toISOString(),
      differences: diffs,
    }

    if (showStats) {
      output.summary = this.getStatistics(diffs)
    }

    return JSON.stringify(output, null, 2)
  }

  /**
   * 格式化为YAML输出
   * @param diffs 差异结果数组
   * @param files 比较的文件列表
   * @param showStats 是否显示统计信息
   * @returns YAML格式字符串
   */
  formatAsYaml(
    diffs: DiffResult[],
    files: string[] = [],
    showStats: boolean = true,
  ): string {
    const output: any = {
      files,
      timestamp: new Date().toISOString(),
      differences: diffs,
    }

    if (showStats) {
      output.summary = this.getStatistics(diffs)
    }

    return yaml.dump(output, {
      indent: 2,
      lineWidth: 120,
      noRefs: true,
    })
  }

  /**
   * 格式化为树形输出
   * @param diffs 差异结果数组
   * @param showStats 是否显示统计信息
   * @returns 树形格式字符串
   */
  formatAsTree(diffs: DiffResult[], showStats: boolean = true): string {
    if (diffs.length === 0) {
      return this.colorize('No differences found.', 'info')
    }

    let result = this.colorize('\nDifferences Tree:', 'header') + '\n'

    // 按路径分组构建树形结构
    const tree = this.buildTree(diffs)
    result += this.renderTree(tree)

    if (showStats) {
      result += '\n' + this.formatStatistics(diffs)
    }

    return result
  }

  /**
   * 构建树形结构
   * @param diffs 差异结果数组
   * @returns 树形结构对象
   */
  private buildTree(diffs: DiffResult[]): TreeNode {
    const root: TreeNode = { name: 'root', children: new Map(), diffs: [] }

    diffs.forEach((diff) => {
      const path = diff.path || ''
      const parts = path.split('.')
      let current = root

      parts.forEach((part, index) => {
        if (!current.children.has(part)) {
          current.children.set(part, {
            name: part,
            children: new Map(),
            diffs: [],
          })
        }
        current = current.children.get(part)!

        // 如果是最后一个部分，添加差异
        if (index === parts.length - 1) {
          current.diffs.push(diff)
        }
      })
    })

    return root
  }

  /**
   * 渲染树形结构
   * @param node 树节点
   * @param prefix 前缀字符串
   * @param isLast 是否为最后一个节点
   * @returns 渲染后的字符串
   */
  private renderTree(
    node: TreeNode,
    prefix: string = '',
    isLast: boolean = true,
  ): string {
    let result = ''

    if (node.name !== 'root') {
      const connector = isLast ? '└── ' : '├── '
      const nodePrefix = prefix + connector

      // 显示节点名称和差异
      if (node.diffs.length > 0) {
        const diff = node.diffs[0] // 取第一个差异作为代表
        // biome-ignore lint/style/noNonNullAssertion: <ss>
        const typeSymbol = this.getTypeSymbol(diff!.type)
        // biome-ignore lint/style/noNonNullAssertion: <ss>
        const coloredSymbol = this.colorizeByType(typeSymbol, diff!.type)
        result +=
          nodePrefix +
          coloredSymbol +
          ' ' +
          this.colorize(node.name, 'path') +
          '\n'

        // 显示值的变化
        const valuePrefix = prefix + (isLast ? '    ' : '│   ')
        node.diffs.forEach((d) => {
          if (d.oldValue !== undefined) {
            result +=
              valuePrefix +
              this.colorize('- ', 'removed') +
              this.formatValue(d.oldValue, true) +
              '\n'
          }
          if (d.newValue !== undefined) {
            result +=
              valuePrefix +
              this.colorize('+ ', 'added') +
              this.formatValue(d.newValue, true) +
              '\n'
          }
        })
      } else {
        result += nodePrefix + this.colorize(node.name, 'path') + '\n'
      }
    }

    // 渲染子节点
    const children = Array.from(node.children.values())
    children.forEach((child, index) => {
      const isChildLast = index === children.length - 1
      const childPrefix =
        node.name === 'root' ? prefix : prefix + (isLast ? '    ' : '│   ')
      result += this.renderTree(child, childPrefix, isChildLast)
    })

    return result
  }

  /**
   * 获取差异类型的符号
   * @param type 差异类型
   * @returns 类型符号
   */
  private getTypeSymbol(type: DiffType): string {
    switch (type) {
      case DiffType.ADDED:
        return '+'
      case DiffType.REMOVED:
        return '-'
      case DiffType.MODIFIED:
        return '~'
      case DiffType.UNCHANGED:
        return '='
      default:
        return '?'
    }
  }

  /**
   * 根据类型着色
   * @param text 要着色的文本
   * @param type 差异类型
   * @returns 着色后的文本
   */
  private colorizeByType(text: string, type: DiffType): string {
    if (!this.colorEnabled) {
      return text
    }

    switch (type) {
      case DiffType.ADDED:
        return chalk.green(text)
      case DiffType.REMOVED:
        return chalk.red(text)
      case DiffType.MODIFIED:
        return chalk.yellow(text)
      case DiffType.UNCHANGED:
        return chalk.gray(text)
      default:
        return text
    }
  }

  /**
   * 通用着色方法
   * @param text 要着色的文本
   * @param style 样式类型
   * @returns 着色后的文本
   */
  private colorize(text: string, style: string): string {
    if (!this.colorEnabled) {
      return text
    }

    switch (style) {
      case 'header':
        return chalk.bold.cyan(text)
      case 'path':
        return chalk.blue(text)
      case 'info':
        return chalk.cyan(text)
      case 'added':
        return chalk.green(text)
      case 'removed':
        return chalk.red(text)
      case 'modified':
        return chalk.yellow(text)
      case 'stats':
        return chalk.bold(text)
      default:
        return text
    }
  }

  /**
   * 格式化值用于显示
   * @param value 要格式化的值
   * @param highlight 是否高亮显示
   * @returns 格式化后的字符串
   */
  private formatValue(value: any, highlight: boolean = false): string {
    if (value === undefined) {
      return ''
    }

    if (value === null) {
      const text = 'null'
      return highlight ? this.colorize(text, 'modified') : text
    }

    let text: string

    if (typeof value === 'string') {
      // 截断长字符串并添加引号
      const truncated =
        value.length > 20 ? `${value.substring(0, 17)}...` : value
      text = `"${truncated}"`
    } else if (typeof value === 'object') {
      const str = JSON.stringify(value)
      text = str.length > 20 ? `${str.substring(0, 17)}...` : str
    } else {
      text = String(value)
    }

    return highlight
      ? this.colorize(text, highlight ? 'modified' : 'info')
      : text
  }

  /**
   * 格式化统计信息
   * @param diffs 差异结果数组
   * @returns 格式化后的统计信息字符串
   */
  formatStatistics(diffs: DiffResult[]): string {
    const stats = this.getStatistics(diffs)

    let result = '\n' + this.colorize('Summary:', 'stats') + '\n'
    result += `  Total differences: ${this.colorize(
      stats.total.toString(),
      'info',
    )}\n`
    result += `  ${this.colorize('Added:', 'added')} ${stats.added}\n`
    result += `  ${this.colorize('Removed:', 'removed')} ${stats.removed}\n`
    result += `  ${this.colorize('Modified:', 'modified')} ${stats.modified}`

    if (stats.unchanged > 0) {
      result += `\n  ${this.colorize('Unchanged:', 'info')} ${stats.unchanged}`
    }

    return result
  }

  /**
   * 获取统计信息
   * @param diffs 差异结果数组
   * @returns 统计信息对象
   */
  private getStatistics(diffs: DiffResult[]): {
    total: number
    added: number
    removed: number
    modified: number
    unchanged: number
  } {
    const stats = {
      total: diffs.length,
      added: 0,
      removed: 0,
      modified: 0,
      unchanged: 0,
    }

    diffs.forEach((diff) => {
      switch (diff.type) {
        case DiffType.ADDED:
          stats.added++
          break
        case DiffType.REMOVED:
          stats.removed++
          break
        case DiffType.MODIFIED:
          stats.modified++
          break
        case DiffType.UNCHANGED:
          stats.unchanged++
          break
      }
    })

    return stats
  }

  /**
   * 输出到文件
   * @param content 要输出的内容
   * @param filePath 输出文件路径
   */
  async outputToFile(content: string, filePath: string): Promise<void> {
    const fs = await import('fs/promises')
    const path = await import('path')

    // 确保目录存在
    const dir = path.dirname(filePath)
    await fs.mkdir(dir, { recursive: true })

    // 写入文件（移除颜色代码）
    const cleanContent = this.stripColors(content)
    await fs.writeFile(filePath, cleanContent, 'utf8')
  }

  /**
   * 移除颜色代码
   * @param text 包含颜色代码的文本
   * @returns 移除颜色代码后的文本
   */
  private stripColors(text: string): string {
    // 移除ANSI颜色代码
    // biome-ignore lint/suspicious/noControlCharactersInRegex: <ss>
    return text.replace(/\u001b\[[0-9;]*m/g, '')
  }

  /**
   * 设置颜色输出开关
   * @param enabled 是否启用颜色
   */
  setColorEnabled(enabled: boolean): void {
    this.colorEnabled = enabled
  }
}

/**
 * 树节点接口
 */
interface TreeNode {
  name: string
  children: Map<string, TreeNode>
  diffs: DiffResult[]
}

// 导出默认实例
export const defaultFormatter = new OutputFormatter()
