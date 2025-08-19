import { describe, it, expect, beforeEach, beforeAll, afterAll } from 'vitest'
import { OutputFormatter } from '../src/formatter'
import { DiffResult, DiffType, OutputFormat } from '../src/types'
import { promises as fs } from 'fs'
import * as path from 'path'

describe('OutputFormatter', () => {
  let formatter: OutputFormatter
  let sampleDiffResult: DiffResult

  beforeEach(() => {
    formatter = new OutputFormatter()

    sampleDiffResult = {
      differences: [
        {
          path: 'name',
          type: DiffType.MODIFIED,
          oldValue: 'Alice',
          newValue: 'Bob',
        },
        {
          path: 'age',
          type: DiffType.ADDED,
          oldValue: undefined,
          newValue: 25,
        },
        {
          path: 'email',
          type: DiffType.REMOVED,
          oldValue: 'alice@example.com',
          newValue: undefined,
        },
        {
          path: 'settings.theme',
          type: DiffType.MODIFIED,
          oldValue: 'dark',
          newValue: 'light',
        },
      ],
      summary: {
        total: 4,
        added: 1,
        removed: 1,
        modified: 2,
      },
    }
  })

  describe('format', () => {
    it('应该格式化为表格格式', () => {
      const noColorFormatter = new OutputFormatter(false)
      const result = noColorFormatter.format(
        sampleDiffResult.differences,
        OutputFormat.TABLE,
      )

      expect(result).toContain('Path')
      expect(result).toContain('Type')
      expect(result).toContain('Old Value')
      expect(result).toContain('New Value')
      expect(result).toContain('name')
      expect(result).toContain('MODIFIED')
      expect(result).toContain('Alice')
      expect(result).toContain('Bob')
    })

    it('应该格式化为JSON格式', () => {
      const result = formatter.format(
        sampleDiffResult.differences,
        OutputFormat.JSON,
      )

      expect(() => JSON.parse(result)).not.toThrow()

      const parsed = JSON.parse(result)
      expect(parsed.differences).toHaveLength(4)
      expect(parsed.summary.total).toBe(4)
    })

    it('应该格式化为YAML格式', () => {
      const result = formatter.format(
        sampleDiffResult.differences,
        OutputFormat.YAML,
      )

      expect(result).toContain('differences:')
      expect(result).toContain('summary:')
      expect(result).toContain('path: name')
      expect(result).toContain('type: modified')
    })

    it('应该格式化为树形格式', () => {
      const result = formatter.format(
        sampleDiffResult.differences,
        OutputFormat.TREE,
      )

      expect(result).toContain('├──')
      expect(result).toContain('└──')
      expect(result).toContain('name')
      expect(result).toContain('settings')
    })
  })

  describe('formatAsTable', () => {
    it('应该创建正确的表格结构', () => {
      const result = formatter.formatAsTable(sampleDiffResult.differences)

      expect(result).toContain('┌')
      expect(result).toContain('┐')
      expect(result).toContain('└')
      expect(result).toContain('┘')
      expect(result).toContain('│')
    })

    it('应该处理空差异列表', () => {
      const result = formatter.formatAsTable([])

      expect(result).toContain('No differences found')
    })

    it('应该正确显示不同类型的差异', () => {
      const noColorFormatter = new OutputFormatter(false)
      const result = noColorFormatter.formatAsTable(
        sampleDiffResult.differences,
      )

      expect(result).toContain('MODIFIED')
      expect(result).toContain('ADDED')
      expect(result).toContain('REMOVED')
    })
  })

  describe('formatAsJson', () => {
    it('应该生成有效的JSON', () => {
      const result = formatter.formatAsJson(sampleDiffResult.differences)

      expect(() => JSON.parse(result)).not.toThrow()
    })

    it('应该包含所有必要字段', () => {
      const result = formatter.formatAsJson(sampleDiffResult.differences)
      const parsed = JSON.parse(result)

      expect(parsed).toHaveProperty('differences')
      expect(parsed).toHaveProperty('summary')
      expect(parsed.differences).toBeInstanceOf(Array)
      expect(parsed.summary).toHaveProperty('total')
      expect(parsed.summary).toHaveProperty('added')
      expect(parsed.summary).toHaveProperty('removed')
      expect(parsed.summary).toHaveProperty('modified')
    })

    it('应该正确格式化差异对象', () => {
      const result = formatter.formatAsJson(sampleDiffResult.differences)
      const parsed = JSON.parse(result)

      const firstDiff = parsed.differences[0]
      expect(firstDiff).toHaveProperty('path')
      expect(firstDiff).toHaveProperty('type')
      expect(firstDiff).toHaveProperty('oldValue')
      expect(firstDiff).toHaveProperty('newValue')
    })
  })

  describe('formatAsYaml', () => {
    it('应该生成有效的YAML', () => {
      const result = formatter.formatAsYaml(sampleDiffResult.differences)

      expect(result).toContain('differences:')
      expect(result).toContain('summary:')
      expect(result).toContain('- path:')
    })

    it('应该正确缩进嵌套结构', () => {
      const result = formatter.formatAsYaml(sampleDiffResult.differences)

      expect(result).toMatch(/^differences:/m)
      expect(result).toMatch(/^  - path:/m)
      expect(result).toMatch(/^    type:/m)
    })
  })

  describe('formatAsTree', () => {
    it('应该创建树形结构', () => {
      const result = formatter.formatAsTree(sampleDiffResult.differences)

      expect(result).toContain('├──')
      expect(result).toContain('└──')
    })

    it('应该正确处理嵌套路径', () => {
      const nestedDiffs = [
        {
          path: 'user.profile.name',
          type: DiffType.MODIFIED,
          oldValue: 'Alice',
          newValue: 'Bob',
        },
        {
          path: 'user.profile.age',
          type: DiffType.ADDED,
          oldValue: undefined,
          newValue: 25,
        },
        {
          path: 'user.settings.theme',
          type: DiffType.MODIFIED,
          oldValue: 'dark',
          newValue: 'light',
        },
      ]

      const result = formatter.formatAsTree(nestedDiffs)

      expect(result).toContain('user')
      expect(result).toContain('profile')
      expect(result).toContain('settings')
      expect(result).toContain('name')
      expect(result).toContain('age')
      expect(result).toContain('theme')
    })

    it('应该处理数组索引', () => {
      const arrayDiffs = [
        {
          path: 'items[0]',
          type: DiffType.MODIFIED,
          oldValue: 1,
          newValue: 2,
        },
        {
          path: 'items[1].name',
          type: DiffType.ADDED,
          oldValue: undefined,
          newValue: 'test',
        },
      ]

      const result = formatter.formatAsTree(arrayDiffs)

      expect(result).toContain('items')
      expect(result).toContain('[0]')
      expect(result).toContain('[1]')
    })
  })

  describe('formatStatistics', () => {
    it('应该显示统计信息', () => {
      const noColorFormatter = new OutputFormatter(false)
      const result = noColorFormatter.formatStatistics(
        sampleDiffResult.differences,
      )

      expect(result).toContain('Summary')
      expect(result).toContain('  Total differences: 4')
      expect(result).toContain('  Added: 1')
      expect(result).toContain('  Removed: 1')
      expect(result).toContain('  Modified: 2')
    })

    it('应该使用颜色标识不同类型', () => {
      const result = formatter.formatStatistics(sampleDiffResult.differences)

      // 检查是否包含ANSI颜色代码
      expect(result).toMatch(/\u001b\[\d+m/) // ANSI颜色代码模式
    })
  })

  describe('outputToFile', () => {
    const testOutputDir = path.join(__dirname, 'output')

    beforeAll(async () => {
      try {
        await fs.mkdir(testOutputDir, { recursive: true })
      } catch (error) {
        // 目录可能已存在
      }
    })

    afterAll(async () => {
      try {
        await fs.rmdir(testOutputDir, { recursive: true })
      } catch (error) {
        // 忽略清理错误
      }
    })

    it('应该将输出写入文件', async () => {
      const outputPath = path.join(testOutputDir, 'test-output.json')
      const content = formatter.formatAsJson(sampleDiffResult.differences)

      await formatter.outputToFile(content, outputPath)

      const fileExists = await fs
        .access(outputPath)
        .then(() => true)
        .catch(() => false)
      expect(fileExists).toBe(true)

      const fileContent = await fs.readFile(outputPath, 'utf8')
      expect(fileContent).toBe(content)
    })

    it('应该创建不存在的目录', async () => {
      const nestedPath = path.join(
        testOutputDir,
        'nested',
        'deep',
        'output.txt',
      )
      const content = 'test content'

      await formatter.outputToFile(content, nestedPath)

      const fileExists = await fs
        .access(nestedPath)
        .then(() => true)
        .catch(() => false)
      expect(fileExists).toBe(true)
    })

    it('应该移除颜色代码', async () => {
      const outputPath = path.join(testOutputDir, 'no-colors.txt')
      const coloredContent = formatter.formatStatistics(
        sampleDiffResult.differences,
      )

      await formatter.outputToFile(coloredContent, outputPath)

      const fileContent = await fs.readFile(outputPath, 'utf8')
      expect(fileContent).not.toMatch(/\u001b\[\d+m/) // 不应包含ANSI颜色代码
    })
  })

  describe('边界情况测试', () => {
    it('应该处理空差异结果', () => {
      const emptyResult: DiffResult = {
        differences: [],
        summary: {
          total: 0,
          added: 0,
          removed: 0,
          modified: 0,
        },
      }

      expect(() =>
        formatter.format(emptyResult.differences, OutputFormat.TABLE),
      ).not.toThrow()
      expect(() =>
        formatter.format(emptyResult.differences, OutputFormat.JSON),
      ).not.toThrow()
      expect(() =>
        formatter.format(emptyResult.differences, OutputFormat.YAML),
      ).not.toThrow()
      expect(() =>
        formatter.format(emptyResult.differences, OutputFormat.TREE),
      ).not.toThrow()
    })

    it('应该处理特殊字符', () => {
      const specialCharsResult: DiffResult = {
        differences: [
          {
            path: 'special\"chars',
            type: DiffType.MODIFIED,
            oldValue: 'old\nvalue\twith\"quotes',
            newValue: 'new\nvalue\twith\"quotes',
          },
        ],
        summary: {
          total: 1,
          added: 0,
          removed: 0,
          modified: 1,
        },
      }

      expect(() =>
        formatter.format(specialCharsResult.differences, OutputFormat.JSON),
      ).not.toThrow()

      const jsonResult = formatter.formatAsJson(specialCharsResult.differences)
      expect(() => JSON.parse(jsonResult)).not.toThrow()
    })

    it('应该处理长路径', () => {
      const longPathResult: DiffResult = {
        differences: [
          {
            path: 'very.long.nested.path.with.many.levels.and.more.levels.property',
            type: DiffType.MODIFIED,
            oldValue: 'old',
            newValue: 'new',
          },
        ],
        summary: {
          total: 1,
          added: 0,
          removed: 0,
          modified: 1,
        },
      }

      expect(() =>
        formatter.format(longPathResult.differences, OutputFormat.TABLE),
      ).not.toThrow()
      expect(() =>
        formatter.format(longPathResult.differences, OutputFormat.TREE),
      ).not.toThrow()
    })

    it('应该处理大型值', () => {
      const largeValue = 'x'.repeat(1000)
      const largeValueResult: DiffResult = {
        differences: [
          {
            path: 'largeValue',
            type: DiffType.MODIFIED,
            oldValue: largeValue,
            newValue: largeValue + 'modified',
          },
        ],
        summary: {
          total: 1,
          added: 0,
          removed: 0,
          modified: 1,
        },
      }

      expect(() =>
        formatter.format(largeValueResult.differences, OutputFormat.TABLE),
      ).not.toThrow()
      expect(() =>
        formatter.format(largeValueResult.differences, OutputFormat.JSON),
      ).not.toThrow()
    })
  })
})
