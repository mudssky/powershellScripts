/**
 * AI 编码规则加载器 - 输出格式化器
 *
 * @description
 * 将规则列表转换为不同格式的输出字符串。
 */

import type { TraeRule, FormatOptions } from './types.js'

/**
 * 格式化输出
 *
 * @description
 * 根据选项将规则列表格式化为指定格式的字符串。
 *
 * @param rules - 规则数组
 * @param options - 格式化选项
 * @returns 格式化后的字符串
 *
 * @example
 * ```ts
 * const output = formatOutput(rules, { format: 'markdown' });
 * console.log(output);
 * ```
 */
export function formatOutput(
  rules: TraeRule[],
  options: FormatOptions = {},
): string {
  const format = options.format ?? 'markdown'

  if (format === 'json') {
    return formatJson(rules, options)
  }

  return formatMarkdown(rules, options)
}

/**
 * Markdown 格式化器
 *
 * @description
 * 输出对 Claude Code 友好的 Markdown 格式。
 * - alwaysApply: true 的规则 → 完整内容
 * - alwaysApply: false 的规则 → 索引列表
 *
 * @param rules - 规则数组
 * @param options - 格式化选项
 * @returns Markdown 字符串
 */
export function formatMarkdown(
  rules: TraeRule[],
  options: FormatOptions = {},
): string {
  const sections: string[] = []

  // 分离全局规则和条件规则
  const globalRules = rules.filter((r) => r.alwaysApply)
  const conditionalRules = rules.filter((r) => !r.alwaysApply)

  // 输出全局规则
  if (globalRules.length > 0) {
    sections.push(formatGlobalRules(globalRules, options))
  }

  // 输出条件规则索引
  if (conditionalRules.length > 0) {
    sections.push(formatConditionalRules(conditionalRules, options))
  }

  return sections.join('\n\n')
}

/**
 * 格式化全局规则
 *
 * @param rules - 全局规则数组
 * @param options - 格式化选项
 * @returns Markdown 字符串
 */
function formatGlobalRules(rules: TraeRule[], options: FormatOptions): string {
  const includeHeader = options.includeHeader !== false

  const header = includeHeader
    ? '=== 🚨 CRITICAL GLOBAL RULES (MUST FOLLOW) ==='
    : ''

  const content = rules.map(formatSingleRule).join('\n\n')

  return [header, content].filter(Boolean).join('\n')
}

/**
 * 格式化单个规则
 *
 * @param rule - 规则对象
 * @returns Markdown 字符串
 */
function formatSingleRule(rule: TraeRule): string {
  return `### GLOBAL RULE (${rule.sourcePath}):\n${rule.content}`
}

/**
 * 格式化条件规则索引
 *
 * @param rules - 条件规则数组
 * @param options - 格式化选项
 * @returns Markdown 字符串
 */
function formatConditionalRules(
  rules: TraeRule[],
  options: FormatOptions,
): string {
  const includeHeader = options.includeHeader !== false

  const header = includeHeader
    ? '=== 📂 CONDITIONAL RULES INDEX ===\nClaude, please READ the specific rule file using `Read` tool if your task matches the criteria below:'
    : ''

  const items = rules.map(formatRuleIndex).join('\n')

  return [header, items].filter(Boolean).join('\n')
}

/**
 * 格式化规则索引项
 *
 * @param rule - 规则对象
 * @returns Markdown 字符串
 */
function formatRuleIndex(rule: TraeRule): string {
  const patterns = rule.matchPatterns?.join(', ') || '*'
  return `- Rule File: ${rule.sourcePath}\n  Match Files: ${patterns}\n  Trigger: ${rule.description}`
}

/**
 * JSON 格式化器
 *
 * @description
 * 输出结构化的 JSON 格式。
 *
 * @param rules - 规则数组
 * @param options - 格式化选项
 * @returns JSON 字符串
 */
export function formatJson(
  rules: TraeRule[],
  options: FormatOptions = {},
): string {
  const output = {
    version: '1.0.0',
    timestamp: new Date().toISOString(),
    totalRules: rules.length,
    globalRules: rules.filter((r) => r.alwaysApply).length,
    conditionalRules: rules.filter((r) => !r.alwaysApply).length,
    rules: rules.map((rule) => ({
      id: rule.id,
      name: rule.name,
      description: rule.description,
      alwaysApply: rule.alwaysApply,
      sourcePath: rule.sourcePath,
      matchPatterns: rule.matchPatterns,
      category: rule.category,
      contentLength: rule.content.length,
    })),
  }

  return JSON.stringify(output, null, 2)
}
