/**
 * AI 编码规则加载器 - 类型定义
 *
 * @description
 * 定义了用于加载和处理 AI 编码工具（如 Trae）项目规则的核心类型。
 */

/**
 * Trae 规则元数据
 *
 * @description
 * 从规则文件的 Frontmatter 中解析的元数据。
 *
 * @example
 * ```yaml
 * ---
 * alwaysApply: false
 * globs: *.js,*.ts
 * description: Node.js 编码规范
 * ---
 * ```
 */
export interface TraeRuleMetadata {
  /**
   * 是否全局应用（所有文件都遵循）
   *
   * @default true
   *
   * @description
   * - `true`: 规则适用于所有文件，应输出完整内容
   * - `false`: 规则仅适用于匹配 glob 模式的文件，应输出索引
   *
   * **注意**: 无 Frontmatter 时默认为 `true`
   */
  alwaysApply?: boolean

  /**
   * 文件匹配模式（单数形式）
   *
   * @description
   * 逗号分隔的 glob 模式字符串。优先级低于 `globs`。
   *
   * @example "*.js,*.ts"
   */
  glob?: string

  /**
   * 文件匹配模式（复数形式）
   *
   * @description
   * 支持数组或逗号分隔的字符串。优先级高于 `glob`。
   *
   * @example ["*.js", "*.ts"] 或 "*.js,*.ts"
   */
  globs?: string | string[]

  /**
   * 规则描述
   *
   * @description
   * 简短描述规则的用途和适用场景。
   */
  description?: string

  /**
   * 其他自定义字段
   *
   * @description
   * 允许在 Frontmatter 中添加任意自定义元数据。
   */
  [key: string]: unknown
}

/**
 * 规则数据结构
 *
 * @description
 * 表示从规则文件解析出的完整规则信息。
 */
export interface TraeRule {
  /**
   * 规则唯一标识符
   *
   * @description
   * 从文件名提取（不含扩展名）。
   *
   * @example "00_core_constitution"
   */
  id: string

  /**
   * 规则名称
   *
   * @description
   * 从文件名提取并格式化的可读名称。
   *
   * @example "Core Constitution"
   */
  name: string

  /**
   * 规则描述
   *
   * @description
   * 来自 Frontmatter 或默认值。
   */
  description: string

  /**
   * 是否全局应用
   *
   * @description
   * `true` 时输出完整内容，`false` 时仅输出索引。
   */
  alwaysApply: boolean

  /**
   * 规则内容（Markdown 格式）
   *
   * @description
   * Frontmatter 之后的 Markdown 正文。
   */
  content: string

  /**
   * 源文件路径
   *
   * @description
   * 相对于项目根目录的文件路径。
   *
   * @example ".trae/rules/00_core_constitution.md"
   */
  sourcePath: string

  /**
   * 文件匹配模式列表
   *
   * @description
   * 从 `globs` 或 `glob` 字段解析出的数组。
   *
   * @example ["*.js", "*.ts"]
   */
  matchPatterns?: string[]

  /**
   * 原始元数据
   *
   * @description
   * 保留完整的 Frontmatter 数据。
   */
  metadata: TraeRuleMetadata

  /**
   * 规则分类
   *
   * @description
   * 从文件名编号前缀提取（如 "00", "10", "20"）。
   *
   * @example "00" 或 "uncategorized"
   */
  category?: string
}

/**
 * 规则加载选项
 *
 * @description
 * 控制规则加载行为的选项。
 */
export interface LoadOptions {
  /**
   * 工作目录
   *
   * @default process.cwd()
   *
   * @description
   * 规则文件和输出的基准路径。
   */
  cwd?: string

  /**
   * 规则目录路径
   *
   * @default ".trae/rules"
   *
   * @description
   * 相对于 `cwd` 的规则文件目录。
   */
  rulesDir?: string

  /**
   * 仅加载全局应用规则
   *
   * @default false
   *
   * @description
   * 为 `true` 时，过滤出 `alwaysApply: true` 的规则。
   */
  onlyAlwaysApply?: boolean

  /**
   * 详细输出模式
   *
   * @default false
   *
   * @description
   * 为 `true` 时，输出解析过程中的警告和错误信息。
   */
  verbose?: boolean
}

/**
 * 输出格式选项
 *
 * @description
 * 控制规则输出格式的选项。
 */
export interface FormatOptions {
  /**
   * 输出格式类型
   *
   * @default "markdown"
   *
   * @description
   * - `markdown`: 对 AI 工具友好的 Markdown 格式
   * - `json`: 结构化的 JSON 格式
   */
  format?: 'markdown' | 'json'

  /**
   * 是否包含头部信息
   *
   * @default true
   *
   * @description
   * 为 `true` 时，包含分隔线和标题等装饰性内容。
   */
  includeHeader?: boolean

  /**
   * 当前工作目录
   *
   * @description
   * 用于生成 [System Info] 中的 Project Root。
   */
  cwd?: string

  /**
   * 规则目录
   *
   * @description
   * 用于生成 [System Info] 中的 Rule Base。
   */
  rulesDir?: string
}

/**
 * CLI 命令选项
 *
 * @description
 * 命令行接口接受的参数选项。
 */
export interface CliOptions {
  /**
   * 输出格式
   *
   * @default "markdown"
   */
  format?: 'markdown' | 'json'

  /**
   * 仅显示全局应用规则
   *
   * @default false
   */
  filterApply?: boolean

  /**
   * 详细输出
   *
   * @default false
   */
  verbose?: boolean
}
