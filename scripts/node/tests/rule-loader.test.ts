/**
 * AI 编码规则加载器 - 单元测试
 *
 * @description
 * 测试规则加载器的核心功能：工具函数、加载器、格式化器
 */

import fs from 'node:fs/promises'
import path from 'node:path'
import { beforeAll, describe, expect, it } from 'vitest'
import { formatJson, formatMarkdown } from '../src/rule-loader/formatters'
import { loadRules } from '../src/rule-loader/loader'
// 导入被测试的模块
import {
  extractCategory,
  extractMatchPatterns,
  extractRuleName,
  generateRuleId,
  parseLooseYaml,
  RuleLoadError,
  RuleParseError,
} from '../src/rule-loader/utils'

// 测试 fixtures 目录
const FIXTURES_DIR = path.resolve(__dirname, './fixtures/rule-loader')

describe('rule-loader - 工具函数测试', () => {
  describe('parseLooseYaml', () => {
    it('应该解析布尔值', () => {
      const result = parseLooseYaml('alwaysApply: true')
      expect(result).toEqual({ alwaysApply: true })
    })

    it('应该解析小写布尔值', () => {
      const result = parseLooseYaml('alwaysApply: false')
      expect(result).toEqual({ alwaysApply: false })
    })

    it('应该解析逗号分隔的数组', () => {
      const result = parseLooseYaml('globs: *.js,*.ts')
      expect(result).toEqual({ globs: ['*.js', '*.ts'] })
    })

    it('应该解析带空格的数组', () => {
      const result = parseLooseYaml('globs: *.js, *.ts, *.tsx')
      expect(result).toEqual({ globs: ['*.js', '*.ts', '*.tsx'] })
    })

    it('应该解析带引号的字符串', () => {
      const result = parseLooseYaml('description: "测试规则"')
      expect(result).toEqual({ description: '测试规则' })
    })

    it('应该解析多行配置', () => {
      const result = parseLooseYaml(
        'alwaysApply: true\nglobs: *.js,*.ts\ndescription: "测试"',
      )
      expect(result).toEqual({
        alwaysApply: true,
        globs: ['*.js', '*.ts'],
        description: '测试',
      })
    })

    it('应该跳过空行和注释', () => {
      const result = parseLooseYaml(
        'alwaysApply: true\n# 这是注释\nglobs: *.js,*.ts',
      )
      expect(result).toEqual({
        alwaysApply: true,
        globs: ['*.js', '*.ts'],
      })
    })

    it('应该处理空值', () => {
      const result = parseLooseYaml('description:')
      expect(result).toEqual({ description: '' })
    })
  })

  describe('extractMatchPatterns', () => {
    it('应该从 glob 字段提取模式', () => {
      const result = extractMatchPatterns({ glob: '*.js,*.ts' })
      expect(result).toEqual(['*.js', '*.ts'])
    })

    it('应该从 globs 字段提取数组', () => {
      const result = extractMatchPatterns({ globs: ['*.js', '*.ts'] })
      expect(result).toEqual(['*.js', '*.ts'])
    })

    it('应该优先使用 globs 而不是 glob', () => {
      const result = extractMatchPatterns({
        glob: '*.js',
        globs: ['*.ts', '*.tsx'],
      })
      expect(result).toEqual(['*.ts', '*.tsx'])
    })

    it('应该在没有模式时返回 undefined', () => {
      const result = extractMatchPatterns({ alwaysApply: true })
      expect(result).toBeUndefined()
    })

    it('应该处理逗号分隔的字符串', () => {
      const result = extractMatchPatterns({ globs: '*.js, *.ts, *.tsx' })
      expect(result).toEqual(['*.js', '*.ts', '*.tsx'])
    })
  })

  describe('generateRuleId', () => {
    it('应该从 .md 文件名生成 ID', () => {
      const result = generateRuleId('00_core_constitution.md')
      expect(result).toBe('00_core_constitution')
    })

    it('应该从 .mdx 文件名生成 ID', () => {
      const result = generateRuleId('10_workflow_rules.mdx')
      expect(result).toBe('10_workflow_rules')
    })

    it('应该处理无扩展名的文件名', () => {
      const result = generateRuleId('custom_rule')
      expect(result).toBe('custom_rule')
    })
  })

  describe('extractRuleName', () => {
    it('应该将下划线分隔的 ID 转换为标题格式', () => {
      const result = extractRuleName('00_core_constitution')
      expect(result).toBe('00 Core Constitution')
    })

    it('应该将连字符分隔的 ID 转换为标题格式', () => {
      const result = extractRuleName('coding-standards-node')
      expect(result).toBe('Coding Standards Node')
    })

    it('应该处理单个单词', () => {
      const result = extractRuleName('custom')
      expect(result).toBe('Custom')
    })
  })

  describe('extractCategory', () => {
    it('应该提取文件名开头的数字分类', () => {
      const result = extractCategory('00_core_constitution.md')
      expect(result).toBe('00')
    })

    it('应该提取两位数字分类', () => {
      const result = extractCategory('10_workflow_rules.md')
      expect(result).toBe('10')
    })

    it('应该处理无数字前缀的文件名', () => {
      const result = extractCategory('custom_rule.md')
      expect(result).toBe('uncategorized')
    })

    it('应该处理以单个数字开头的文件名', () => {
      const result = extractCategory('1_custom_rule.md')
      expect(result).toBe('1')
    })
  })

  describe('RuleLoadError', () => {
    it('应该创建带有消息的错误', () => {
      const error = new RuleLoadError('测试错误')
      expect(error.message).toBe('测试错误')
      expect(error.name).toBe('RuleLoadError')
    })

    it('应该支持错误链', () => {
      const cause = new Error('原始错误')
      const error = new RuleLoadError('包装错误', cause)
      expect(error.cause).toBe(cause)
    })
  })

  describe('RuleParseError', () => {
    it('应该创建包含文件路径的错误', () => {
      const error = new RuleParseError('解析失败', '/path/to/file.md')
      expect(error.message).toContain('解析失败')
      expect(error.message).toContain('/path/to/file.md')
      expect(error.name).toBe('RuleParseError')
      expect(error.filePath).toBe('/path/to/file.md')
    })

    it('应该支持错误链', () => {
      const cause = new Error('语法错误')
      const error = new RuleParseError('解析失败', '/path/to/file.md', cause)
      expect(error.cause).toBe(cause)
    })
  })
})

describe('rule-loader - 格式化器测试', () => {
  const mockRules = [
    {
      id: '00_global',
      name: '00 Global',
      description: '全局规则',
      alwaysApply: true,
      content: '# 全局规则内容\n这是必须遵循的规则。',
      sourcePath: '.trae/rules/00_global.md',
      matchPatterns: undefined,
      metadata: {},
      category: '00',
    },
    {
      id: '10_conditional',
      name: '10 Conditional',
      description: '条件规则',
      alwaysApply: false,
      content: '# 条件规则内容\n这是特定文件的规则。',
      sourcePath: '.trae/rules/10_conditional.md',
      matchPatterns: ['*.js', '*.ts'],
      metadata: {},
      category: '10',
    },
  ]

  describe('formatMarkdown', () => {
    it('应该输出全局规则的完整内容', () => {
      const result = formatMarkdown(mockRules)
      expect(result).toContain('=== 🚨 CRITICAL GLOBAL RULES (AGENT MODE) ===')
      expect(result).toContain('### GLOBAL RULE (.trae/rules/00_global.md):')
      expect(result).toContain('# 全局规则内容')
      expect(result).toContain('这是必须遵循的规则。')
    })

    it('应该输出条件规则的索引', () => {
      const result = formatMarkdown(mockRules)
      expect(result).toContain(
        '=== 📂 CONDITIONAL RULES INDEX (DYNAMIC CONTEXT) ===',
      )
      expect(result).toContain(
        "If the user's request involves the files/topics below, you **MUST** first execute `Read`",
      )
      expect(result).toContain('- Rule File: .trae/rules/10_conditional.md')
      expect(result).toContain('Match Files: *.js, *.ts')
      expect(result).toContain('Trigger: 条件规则')
    })

    it('应该支持禁用标题', () => {
      const result = formatMarkdown(mockRules, { includeHeader: false })
      expect(result).not.toContain('=== 🚨 CRITICAL GLOBAL RULES')
      expect(result).not.toContain(
        '=== 📂 CONDITIONAL RULES INDEX (DYNAMIC CONTEXT) ===',
      )
    })

    it('应该只包含全局规则', () => {
      const globalOnly = mockRules.filter((r) => r.alwaysApply)
      const result = formatMarkdown(globalOnly)
      expect(result).toContain('GLOBAL RULE')
      expect(result).not.toContain('CONDITIONAL RULES INDEX')
    })

    it('应该只包含条件规则', () => {
      const conditionalOnly = mockRules.filter((r) => !r.alwaysApply)
      const result = formatMarkdown(conditionalOnly)
      expect(result).not.toContain('CRITICAL GLOBAL RULES')
      expect(result).toContain('CONDITIONAL RULES INDEX')
    })

    it('应该处理空数组', () => {
      const result = formatMarkdown([])
      expect(result).toBe('')
    })
  })

  describe('formatJson', () => {
    it('应该输出有效的 JSON', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed).toBeDefined()
    })

    it('应该包含版本和时间戳', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed.version).toBe('1.0.0')
      expect(parsed.timestamp).toBeDefined()
      expect(typeof parsed.timestamp).toBe('string')
    })

    it('应该统计规则数量', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed.totalRules).toBe(2)
      expect(parsed.globalRules).toBe(1)
      expect(parsed.conditionalRules).toBe(1)
    })

    it('应该包含规则详情', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed.rules).toHaveLength(2)
      expect(parsed.rules[0]).toMatchObject({
        id: '00_global',
        name: '00 Global',
        description: '全局规则',
        alwaysApply: true,
        sourcePath: '.trae/rules/00_global.md',
        category: '00',
        contentLength: expect.any(Number),
      })
    })

    it('应该包含匹配模式', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed.rules[1].matchPatterns).toEqual(['*.js', '*.ts'])
    })

    it('不应该包含完整的规则内容', () => {
      const result = formatJson(mockRules)
      const parsed = JSON.parse(result)
      expect(parsed.rules[0].content).toBeUndefined()
      expect(parsed.rules[0].contentLength).toBeDefined()
    })
  })
})

describe('rule-loader - 加载器测试', () => {
  beforeAll(async () => {
    // 创建测试 fixtures
    await fs.mkdir(FIXTURES_DIR, { recursive: true })

    // 创建测试规则文件
    await fs.writeFile(
      path.join(FIXTURES_DIR, '00_global.md'),
      `---
alwaysApply: true
description: 全局测试规则
---

# 全局规则
这是全局规则内容。`,
    )

    await fs.writeFile(
      path.join(FIXTURES_DIR, '10_conditional.md'),
      `---
globs: *.js,*.ts
description: 条件测试规则
---

# 条件规则
这是条件规则内容。`,
    )

    await fs.writeFile(
      path.join(FIXTURES_DIR, 'no_frontmatter.md'),
      `# 无 Frontmatter 规则
这个规则没有 frontmatter，应该默认 alwaysApply 为 true。`,
    )

    await fs.writeFile(
      path.join(FIXTURES_DIR, 'explicit_false.md'),
      `---
alwaysApply: false
description: 显式禁用
---

# 显式禁用规则
即使没有 glob，也应该是 alwaysApply: false。`,
    )
  })

  describe('loadRules', () => {
    it('应该加载所有规则', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      expect(rules).toHaveLength(4)
    })

    it('应该解析 frontmatter', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const globalRule = rules.find((r) => r.id === '00_global')
      expect(globalRule).toBeDefined()
      expect(globalRule?.alwaysApply).toBe(true)
      expect(globalRule?.description).toBe('全局测试规则')
    })

    it('应该自动推断 alwaysApply (有 glob 默认为 false)', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const conditionalRule = rules.find((r) => r.id === '10_conditional')
      expect(conditionalRule).toBeDefined()
      expect(conditionalRule?.matchPatterns).toEqual(['*.js', '*.ts'])
      expect(conditionalRule?.alwaysApply).toBe(false)
    })

    it('应该默认 alwaysApply 为 true（无 frontmatter）', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const noFrontmatterRule = rules.find((r) => r.id === 'no_frontmatter')
      expect(noFrontmatterRule).toBeDefined()
      expect(noFrontmatterRule?.alwaysApply).toBe(true)
    })

    it('应该尊重显式 alwaysApply: false', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const explicitFalseRule = rules.find((r) => r.id === 'explicit_false')
      expect(explicitFalseRule).toBeDefined()
      expect(explicitFalseRule?.alwaysApply).toBe(false)
    })

    it('应该支持过滤 alwaysApply 规则', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
        onlyAlwaysApply: true,
      })
      expect(rules).toHaveLength(2) // 00_global 和 no_frontmatter
      expect(rules.every((r) => r.alwaysApply)).toBe(true)
    })

    it('应该正确提取规则元数据', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const rule = rules.find((r) => r.id === '00_global')
      expect(rule).toMatchObject({
        id: '00_global',
        name: '00 Global',
        category: '00',
        sourcePath: expect.stringContaining('00_global.md'),
      })
    })

    it('应该在目录不存在时抛出错误', async () => {
      await expect(
        loadRules({
          rulesDir: '/nonexistent/directory',
        }),
      ).rejects.toThrow(RuleLoadError)
    })

    it('应该提取规则内容（不含 frontmatter）', async () => {
      const rules = await loadRules({
        rulesDir: FIXTURES_DIR,
      })
      const rule = rules.find((r) => r.id === '00_global')
      expect(rule?.content).toBe('# 全局规则\n这是全局规则内容。')
      expect(rule?.content).not.toContain('---')
      expect(rule?.content).not.toContain('alwaysApply:')
    })
  })
})
