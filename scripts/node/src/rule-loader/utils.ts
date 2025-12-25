/**
 * AI 编码规则加载器 - 工具函数
 *
 * @description
 * 提供 YAML 解析和错误处理等工具函数。
 */

/**
 * 宽松的 YAML 解析器
 *
 * @description
 * 用于处理 gray-matter 的 frontmatter。支持非标准格式：
 * - 无引号的 glob 模式（如 `*.js,*.ts`）
 * - 布尔值（true/false）
 * - 逗号分隔的数组
 *
 * @param str - YAML 字符串
 * @returns 解析后的对象
 *
 * @example
 * ```ts
 * parseLooseYaml("alwaysApply: true\nglobs: *.js,*.ts")
 * // => { alwaysApply: true, globs: ["*.js", "*.ts"] }
 * ```
 */
export function parseLooseYaml(str: string): Record<string, unknown> {
  const result: Record<string, unknown> = {}

  str.split(/\r?\n/).forEach((line) => {
    // 跳过空行和注释
    if (!line || line.trim().startsWith('#')) {
      return
    }

    const idx = line.indexOf(':')
    if (idx <= 0) {
      return
    }

    const key = line.slice(0, idx).trim()
    let val = line.slice(idx + 1).trim()

    // 空值处理
    if (!val) {
      result[key] = ''
      return
    }

    // 布尔值转换
    if (/^(true|false)$/i.test(val)) {
      result[key] = val.toLowerCase() === 'true'
      return
    }

    // 数组转换（逗号分隔）
    if (val.includes(',')) {
      result[key] = val.split(',').map((v) => v.trim())
      return
    }

    // 移除引号
    if (/^(["']).*\1$/.test(val)) {
      val = val.slice(1, -1)
    }

    result[key] = val
  })

  return result
}

/**
 * 规则加载错误
 *
 * @description
 * 规则加载过程中发生的错误。
 */
export class RuleLoadError extends Error {
  /**
   * @param message - 错误消息
   * @param cause - 原始错误对象
   */
  constructor(
    message: string,
    public readonly cause?: unknown,
  ) {
    super(message)
    this.name = 'RuleLoadError'
  }
}

/**
 * 规则解析错误
 *
 * @description
 * 解析单个规则文件时发生的错误。
 */
export class RuleParseError extends RuleLoadError {
  /**
   * @param message - 错误消息
   * @param filePath - 规则文件路径
   * @param cause - 原始错误对象
   */
  constructor(
    message: string,
    public readonly filePath: string,
    cause?: unknown,
  ) {
    super(`${message} (文件: ${filePath})`, cause)
    this.name = 'RuleParseError'
  }
}

/**
 * 提取匹配模式
 *
 * @description
 * 从元数据中提取 glob 匹配模式，支持 `glob` 和 `globs` 字段。
 *
 * @param metadata - 规则元数据
 * @returns 匹配模式数组，如果没有则返回 undefined
 *
 * @example
 * ```ts
 * extractMatchPatterns({ glob: "*.js,*.ts" })
 * // => ["*.js", "*.ts"]
 *
 * extractMatchPatterns({ globs: ["*.js", "*.ts"] })
 * // => ["*.js", "*.ts"]
 * ```
 */
export function extractMatchPatterns(
  metadata: Record<string, unknown>,
): string[] | undefined {
  const patterns = metadata.globs ?? metadata.glob
  if (!patterns) {
    return undefined
  }

  if (Array.isArray(patterns)) {
    return patterns.map((p) => String(p))
  }

  return String(patterns)
    .split(',')
    .map((p) => p.trim())
}

/**
 * 从文件名生成规则 ID
 *
 * @param filename - 文件名（含扩展名）
 * @returns 规则 ID
 *
 * @example
 * ```ts
 * generateRuleId("00_core_constitution.md")
 * // => "00_core_constitution"
 * ```
 */
export function generateRuleId(filename: string): string {
  return filename.replace(/\.(md|mdx)$/, '')
}

/**
 * 从规则 ID 生成可读名称
 *
 * @param ruleId - 规则 ID
 * @returns 格式化的名称
 *
 * @example
 * ```ts
 * extractRuleName("00_core_constitution")
 * // => "Core Constitution"
 * ```
 */
export function extractRuleName(ruleId: string): string {
  return ruleId
    .split(/[-_]/)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ')
}

/**
 * 从文件名提取分类
 *
 * @description
 * 从文件名开头的数字前缀提取分类。
 *
 * @param filename - 文件名
 * @returns 分类编号或 "uncategorized"
 *
 * @example
 * ```ts
 * extractCategory("00_core_constitution.md")
 * // => "00"
 *
 * extractCategory("custom_rule.md")
 * // => "uncategorized"
 * ```
 */
export function extractCategory(filename: string): string {
  const match = filename.match(/^(\d+)_/)
  return match ? match[1] : 'uncategorized'
}
