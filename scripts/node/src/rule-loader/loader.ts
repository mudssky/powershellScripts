/**
 * AI 编码规则加载器 - 规则加载器
 *
 * @description
 * 负责从 .trae/rules 目录加载和解析规则文件。
 */

import fs from 'node:fs/promises'
import path from 'node:path'
import glob from 'fast-glob'
import matter from 'gray-matter'

import type { LoadOptions, TraeRule, TraeRuleMetadata } from './types'
import {
  extractCategory,
  extractMatchPatterns,
  extractRuleName,
  generateRuleId,
  parseLooseYaml,
  RuleLoadError,
} from './utils'

/**
 * 默认规则目录
 */
const DEFAULT_RULES_DIR = '.trae/rules'

/**
 * 加载 Trae 规则
 *
 * @description
 * 从指定目录加载所有 Trae 规则文件。
 *
 * @param options - 加载选项
 * @returns 规则数组
 *
 * @throws {RuleLoadError} 规则目录不存在
 *
 * @example
 * ```ts
 * const rules = await loadRules({
 *   cwd: process.cwd(),
 *   onlyAlwaysApply: false,
 *   verbose: true
 * });
 * ```
 */
export async function loadRules(
  options: LoadOptions = {},
): Promise<TraeRule[]> {
  const cwd = options.cwd ?? process.cwd()
  const rulesDir = options.rulesDir
    ? path.resolve(cwd, options.rulesDir)
    : path.resolve(cwd, DEFAULT_RULES_DIR)

  // 检查目录是否存在
  try {
    await fs.access(rulesDir)
  } catch {
    throw new RuleLoadError(`规则目录不存在: ${rulesDir}`)
  }

  // 扫描所有 .md/.mdx 文件
  const files = await scanRuleFiles(rulesDir)

  if (options.verbose) {
    console.warn(`找到 ${files.length} 个规则文件`)
  }

  // 解析每个文件
  const rules: TraeRule[] = []
  const errors: Array<{ file: string; error: unknown }> = []

  for (const filePath of files) {
    try {
      const rule = await parseRuleFile(filePath, cwd)
      rules.push(rule)
    } catch (error) {
      errors.push({ file: filePath, error })
      if (options.verbose) {
        console.warn(`解析规则文件失败: ${filePath}`, error)
      }
    }
  }

  // 报告错误统计
  if (errors.length > 0 && options.verbose) {
    console.warn(`\n共有 ${errors.length} 个文件解析失败`)
  }

  // 应用过滤器
  const filteredRules = applyFilters(rules, options)

  return filteredRules
}

/**
 * 扫描规则文件
 *
 * @param rulesDir - 规则目录路径
 * @returns 文件路径数组
 */
async function scanRuleFiles(rulesDir: string): Promise<string[]> {
  return glob(['*.md', '*.mdx'], {
    cwd: rulesDir,
    absolute: true,
    onlyFiles: true,
  })
}

/**
 * 解析单个规则文件
 *
 * @param filePath - 文件绝对路径
 * @param cwd - 工作目录
 * @returns 规则对象
 * @throws {RuleParseError} 解析失败
 */
async function parseRuleFile(filePath: string, cwd: string): Promise<TraeRule> {
  const content = await fs.readFile(filePath, 'utf-8')

  // 使用 gray-matter 解析 frontmatter
  const { data, content: body } = matter(content, {
    engines: {
      yaml: parseLooseYaml,
    },
  })

  const metadata = data as TraeRuleMetadata
  const filename = path.basename(filePath)
  const relativePath = path.relative(cwd, filePath)

  // 处理 globs 字段（支持复数形式）
  const matchPatterns = extractMatchPatterns(metadata)

  // 默认 alwaysApply: true（无 frontmatter 时）
  const alwaysApply = metadata.alwaysApply ?? true

  const rule: TraeRule = {
    id: generateRuleId(filename),
    name: extractRuleName(generateRuleId(filename)),
    description: metadata.description || '无描述',
    alwaysApply,
    content: body.trim(),
    sourcePath: relativePath.split(path.sep).join('/'),
    matchPatterns,
    metadata,
    category: extractCategory(filename),
  }

  return rule
}

/**
 * 应用过滤器
 *
 * @param rules - 规则数组
 * @param options - 加载选项
 * @returns 过滤后的规则数组
 */
function applyFilters(rules: TraeRule[], options: LoadOptions): TraeRule[] {
  let filtered = rules

  // 只显示 alwaysApply
  if (options.onlyAlwaysApply) {
    filtered = filtered.filter((r) => r.alwaysApply)
  }

  return filtered
}
