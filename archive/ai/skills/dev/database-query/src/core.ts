import type {
  CheckOptions,
  CheckResult,
  Finding,
  StatementKind,
} from './types.js'

const DDL_PATTERN =
  /\b(?:alter|create|drop|truncate|rename|reindex|vacuum\s+full|cluster|grant|revoke)\b/i
const DML_PATTERN = /\b(?:insert|update|delete|merge|replace|upsert)\b/i
const EXPORT_PATTERN =
  /\b(?:copy\s+.+\s+to|load\s+data|select\s+.+\s+into\s+outfile|into\s+dumpfile|\.dump|\.backup)\b/i
const TRANSACTION_PATTERN =
  /\b(?:begin|commit|rollback|savepoint|lock\s+table|for\s+update|for\s+share)\b/i
const DANGEROUS_FUNCTION_PATTERN =
  /\b(?:pg_sleep|pg_read_file|pg_write_file|pg_ls_dir|dblink|lo_import|lo_export|xp_cmdshell)\b/i

/**
 * 移除 SQL 注释与字符串字面量，便于执行保守的静态关键词检查。
 *
 * @param sql 原始 SQL 文本。
 * @returns 归一化后的 SQL 文本，字符串内容会被占位符替换。
 */
export function stripSqlNoise(sql: string): string {
  let output = ''
  let index = 0
  let inSingleQuote = false
  let inDoubleQuote = false
  let inLineComment = false
  let inBlockComment = false
  let dollarTag: string | null = null

  while (index < sql.length) {
    const current = sql[index]
    const next = sql[index + 1]

    if (inLineComment) {
      if (current === '\n') {
        inLineComment = false
        output += '\n'
      } else {
        output += ' '
      }
      index += 1
      continue
    }

    if (inBlockComment) {
      if (current === '*' && next === '/') {
        inBlockComment = false
        output += '  '
        index += 2
      } else {
        output += current === '\n' ? '\n' : ' '
        index += 1
      }
      continue
    }

    if (dollarTag) {
      if (sql.startsWith(dollarTag, index)) {
        output += ' '.repeat(dollarTag.length)
        index += dollarTag.length
        dollarTag = null
      } else {
        output += current === '\n' ? '\n' : ' '
        index += 1
      }
      continue
    }

    if (inSingleQuote) {
      if (current === "'" && next === "'") {
        output += '  '
        index += 2
      } else if (current === "'") {
        inSingleQuote = false
        output += ' '
        index += 1
      } else {
        output += current === '\n' ? '\n' : ' '
        index += 1
      }
      continue
    }

    if (inDoubleQuote) {
      if (current === '"' && next === '"') {
        output += '  '
        index += 2
      } else if (current === '"') {
        inDoubleQuote = false
        output += ' '
        index += 1
      } else {
        output += current === '\n' ? '\n' : ' '
        index += 1
      }
      continue
    }

    if (current === '-' && next === '-') {
      inLineComment = true
      output += '  '
      index += 2
      continue
    }

    if (current === '/' && next === '*') {
      inBlockComment = true
      output += '  '
      index += 2
      continue
    }

    if (current === "'") {
      inSingleQuote = true
      output += ' '
      index += 1
      continue
    }

    if (current === '"') {
      inDoubleQuote = true
      output += ' '
      index += 1
      continue
    }

    const dollarMatch = sql
      .slice(index)
      .match(/^\$[A-Za-z_][A-Za-z0-9_]*\$|^\$\$/)
    if (dollarMatch) {
      dollarTag = dollarMatch[0]
      output += ' '.repeat(dollarTag.length)
      index += dollarTag.length
      continue
    }

    output += current
    index += 1
  }

  return output
}

/**
 * 按 SQL 分号拆分语句，忽略注释和字符串内部的分号。
 *
 * @param sql 原始 SQL 文本。
 * @returns 非空 SQL 语句列表。
 */
export function splitSqlStatements(sql: string): string[] {
  const normalized = stripSqlNoise(sql)
  return normalized
    .split(';')
    .map((statement) => statement.trim())
    .filter(Boolean)
}

/**
 * 判断 SQL 是否属于只读查询。
 *
 * @param statement 已归一化的单条 SQL。
 * @returns 只读查询返回 true。
 */
export function isReadonlyQuery(statement: string): boolean {
  const compact = statement.trim().replace(/\s+/g, ' ')
  return /^(?:with\b[\s\S]+\bselect\b|select\b|explain\b[\s\S]*\bselect\b)/i.test(
    compact,
  )
}

/**
 * 判断 SQL 是否显式包含结果限制。
 *
 * @param statement 已归一化的单条 SQL。
 * @returns 包含 LIMIT / FETCH / TOP 时返回 true。
 */
export function hasResultLimit(statement: string): boolean {
  return (
    /\blimit\s+\d+\b/i.test(statement) ||
    /\bfetch\s+first\s+\d+\s+rows\b/i.test(statement) ||
    /\btop\s+\d+\b/i.test(statement)
  )
}

/**
 * 提取 LIMIT 数值，便于限制过大的查询。
 *
 * @param statement 已归一化的单条 SQL。
 * @returns LIMIT 数值；未设置时返回 null。
 */
export function extractLimit(statement: string): number | null {
  const match = statement.match(/\blimit\s+(\d+)\b/i)
  if (!match) {
    return null
  }

  return Number.parseInt(match[1], 10)
}

/**
 * 粗略识别语句类别，用于权限层级判断。
 *
 * @param statement 已归一化的单条 SQL。
 * @returns 语句类别。
 */
export function classifyStatement(statement: string): StatementKind {
  if (EXPORT_PATTERN.test(statement)) {
    return 'export'
  }

  if (DDL_PATTERN.test(statement)) {
    return 'ddl'
  }

  if (DML_PATTERN.test(statement)) {
    return 'write'
  }

  if (TRANSACTION_PATTERN.test(statement)) {
    return 'transaction'
  }

  if (isReadonlyQuery(statement)) {
    return 'readonly'
  }

  if (/^(?:explain|analyze|show|describe|pragma)\b/i.test(statement)) {
    return 'maintenance'
  }

  return 'unknown'
}

/**
 * 检查 SQL 文本是否满足指定权限层级的安全策略。
 *
 * @param sql 原始 SQL 文本。
 * @param options 检查选项。
 * @returns 检查结果，包含是否通过、语句类别和风险列表。
 */
export function checkSql(sql: string, options: CheckOptions): CheckResult {
  const statements = splitSqlStatements(sql)
  const normalizedStatements = statements.map((statement) => statement.trim())
  const findings: Finding[] = []

  if (normalizedStatements.length === 0) {
    findings.push({
      code: 'EMPTY_SQL',
      message: 'SQL 内容为空。',
      severity: 'block',
    })
  }

  if (normalizedStatements.length > 1) {
    findings.push({
      code: 'MULTI_STATEMENT',
      message: '检测到多条 SQL 语句。请拆分后逐条检查和执行。',
      severity: 'block',
    })
  }

  const firstStatement = normalizedStatements[0] ?? ''
  const kind = firstStatement ? classifyStatement(firstStatement) : 'unknown'

  if (firstStatement && DANGEROUS_FUNCTION_PATTERN.test(firstStatement)) {
    findings.push({
      code: 'DANGEROUS_FUNCTION',
      message: '检测到危险函数或扩展命令，请人工审查执行意图。',
      severity: 'block',
    })
  }

  if (firstStatement) {
    addLevelFindings(findings, firstStatement, kind, options)
  }

  if (
    options.level === 'yolo' &&
    findings.length === 0 &&
    kind !== 'readonly'
  ) {
    findings.push({
      code: 'YOLO_REVIEW',
      message: `${kind} 类型语句已进入 yolo 风险接管模式，执行前仍需用户显式确认。`,
      severity: 'warn',
    })
  }

  const effectiveFindings =
    options.level === 'yolo'
      ? findings.map((finding) => ({
          ...finding,
          severity:
            finding.code === 'EMPTY_SQL' ? finding.severity : ('warn' as const),
        }))
      : findings
  const ok = effectiveFindings.every((finding) => finding.severity !== 'block')

  return {
    ok,
    level: options.level,
    dialect: options.dialect,
    statementCount: normalizedStatements.length,
    kind,
    findings: effectiveFindings,
  }
}

/**
 * 根据权限层级追加语句类型相关的风险结论。
 *
 * @param findings 待写入的风险列表。
 * @param statement 已归一化的单条 SQL。
 * @param kind SQL 语句类别。
 * @param options 检查选项。
 * @returns 无返回值，结果写入 `findings`。
 */
function addLevelFindings(
  findings: Finding[],
  statement: string,
  kind: StatementKind,
  options: CheckOptions,
): void {
  if (kind === 'unknown') {
    findings.push({
      code: 'UNKNOWN_STATEMENT',
      message: '无法确认语句类型。请人工确认后使用更高权限层级。',
      severity: options.level === 'admin' ? 'warn' : 'block',
    })
    return
  }

  if (kind === 'readonly') {
    addReadonlyFindings(findings, statement, options)
    return
  }

  if (options.level === 'readonly') {
    findings.push({
      code: 'READONLY_FORBIDDEN',
      message: `readonly 层级禁止执行 ${kind} 类型语句。`,
      severity: 'block',
    })
    return
  }

  if (options.level === 'maintenance') {
    const allowed = kind === 'maintenance' || kind === 'transaction'
    findings.push({
      code: allowed ? 'MAINTENANCE_REVIEW' : 'MAINTENANCE_FORBIDDEN',
      message: allowed
        ? `${kind} 类型语句需要人工确认目标实例、数据库和影响范围。`
        : `maintenance 层级禁止执行 ${kind} 类型语句。`,
      severity: allowed ? 'warn' : 'block',
    })
    return
  }

  if (options.level === 'admin') {
    findings.push({
      code: kind === 'export' ? 'ADMIN_EXPORT_REVIEW' : 'ADMIN_REVIEW',
      message: `${kind} 类型语句需要用户显式确认目标实例、数据库、操作和影响范围。`,
      severity: kind === 'export' ? 'block' : 'warn',
    })
  }
}

/**
 * 追加只读查询的结果集限制相关风险结论。
 *
 * @param findings 待写入的风险列表。
 * @param statement 已归一化的单条 SQL。
 * @param options 检查选项。
 * @returns 无返回值，结果写入 `findings`。
 */
function addReadonlyFindings(
  findings: Finding[],
  statement: string,
  options: CheckOptions,
): void {
  if (!hasResultLimit(statement)) {
    findings.push({
      code: 'MISSING_LIMIT',
      message: '只读查询缺少 LIMIT / FETCH / TOP 限制，请限制结果集大小。',
      severity: options.level === 'readonly' ? 'block' : 'warn',
    })
    return
  }

  const limit = extractLimit(statement)
  if (limit !== null && limit > options.maxLimit) {
    findings.push({
      code: 'LIMIT_TOO_LARGE',
      message: `LIMIT ${limit} 超过当前上限 ${options.maxLimit}，请缩小结果集。`,
      severity: options.level === 'readonly' ? 'block' : 'warn',
    })
  }
}
