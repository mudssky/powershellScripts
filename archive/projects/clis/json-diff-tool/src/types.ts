/**
 * 支持的文件格式类型
 */
export enum SupportedFormat {
  JSON = 'json',
  JSONC = 'jsonc',
  JSON5 = 'json5',
}

/**
 * JSON对象类型
 */
export type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonObject
  | JsonArray
export interface JsonObject {
  [key: string]: JsonValue
}
export interface JsonArray extends Array<JsonValue> {}

/**
 * 差异类型枚举
 */
export enum DiffType {
  ADDED = 'added',
  REMOVED = 'removed',
  MODIFIED = 'modified',
  UNCHANGED = 'unchanged',
}

/**
 * 差异项接口
 */
export interface DiffItem {
  path: string
  type: DiffType
  oldValue?: JsonValue
  newValue?: JsonValue
  fileIndex?: number // 用于多文件比较时标识文件
}

/**
 * 比较结果接口
 */
export interface ComparisonResult {
  files: string[]
  differences: DiffItem[]
  summary: {
    added: number
    removed: number
    modified: number
    unchanged: number
  }
}

/**
 * 输出格式类型
 */
export enum OutputFormat {
  TABLE = 'table',
  JSON = 'json',
  YAML = 'yaml',
  TREE = 'tree',
}

/**
 * 命令行选项接口
 */
export interface CliOptions {
  files: string[]
  output?: OutputFormat
  showUnchanged?: boolean
  ignoreOrder?: boolean
  depth?: number
  filter?: string
  verbose?: boolean
}

/**
 * 解析器配置接口
 */
export interface ParserConfig {
  strict?: boolean
  allowTrailingComma?: boolean
  allowComments?: boolean
}

/**
 * 差异结果接口
 */
export interface DiffResult {
  path: string
  type: DiffType
  oldValue?: JsonValue | undefined
  newValue?: JsonValue | undefined
  message?: string
}

/**
 * 比较选项接口
 */
export interface CompareOptions {
  ignoreArrayOrder?: boolean
  maxDepth?: number
  caseSensitive?: boolean
  ignoreWhitespace?: boolean
}
