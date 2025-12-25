#!/usr/bin/env node
/**
 * AI 编码规则加载器 - 主入口
 *
 * @description
 * 用于加载 AI 编码工具（如 Trae、Claude Code）的项目规则。
 *
 * @usage
 * ```bash
 * # 加载所有规则（Markdown 格式）
 * rule-loader
 *
 * # 只显示全局规则
 * rule-loader --filter-apply
 *
 * # JSON 格式输出
 * rule-loader --format json
 * ```
 */

// 导出 main 函数供其他模块使用
export { main } from './cli.js'

// 导出类型和工具供其他模块使用
export * from './types.js'
export * from './loader.js'
export * from './formatters.js'
export * from './utils.js'

// 当直接运行此文件时，执行 CLI
import { main } from './cli.js'

main().catch((error) => {
  console.error('致命错误:', error)
  process.exit(1)
})
