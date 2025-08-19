import { describe, it, expect, beforeAll, afterAll, beforeEach } from 'vitest'
import { FileParser } from '../src/parser'
import { promises as fs } from 'fs'
import * as path from 'path'

// 创建测试数据目录
const testDataDir = path.join(__dirname, 'data')

describe('FileParser', () => {
  let parser: FileParser

  beforeEach(() => {
    parser = new FileParser()
  })

  beforeAll(async () => {
    // 创建测试数据目录
    try {
      await fs.mkdir(testDataDir, { recursive: true })
    } catch (error) {
      // 目录可能已存在
    }

    // 创建测试文件
    const testFiles = {
      'test.json': JSON.stringify({ name: 'test', value: 123 }, null, 2),
      'test.jsonc': '// 这是注释\n{\n  "name": "test",\n  "value": 123\n}',
      'test.json5': "{\n  name: 'test',\n  value: 123,\n  // 注释\n}",
      'invalid.json': '{ "name": "test", "value": }',
      'test.txt': 'This is not a JSON file',
    }

    for (const [filename, content] of Object.entries(testFiles)) {
      await fs.writeFile(path.join(testDataDir, filename), content, 'utf8')
    }
  })

  afterAll(async () => {
    // 清理测试文件（保留我们手动创建的测试数据文件）
    try {
      const filesToClean = [
        'test.json',
        'test.jsonc',
        'test.json5',
        'invalid.json',
        'test.txt',
      ]
      for (const file of filesToClean) {
        try {
          await fs.unlink(path.join(testDataDir, file))
        } catch (error) {
          // 忽略文件不存在的错误
        }
      }
    } catch (error) {
      // 忽略清理错误
    }
  })

  describe('parseFile', () => {
    it('应该成功解析标准JSON文件', async () => {
      const filePath = path.join(testDataDir, 'test.json')
      const result = await parser.parseFile(filePath)

      expect(result).toEqual({
        name: 'test',
        value: 123,
      })
    })

    it('应该成功解析JSONC文件（带注释）', async () => {
      const filePath = path.join(testDataDir, 'test.jsonc')
      const result = await parser.parseFile(filePath)

      expect(result).toEqual({
        name: 'test',
        value: 123,
      })
    })

    it('应该成功解析JSON5文件', async () => {
      const filePath = path.join(testDataDir, 'test.json5')
      const result = await parser.parseFile(filePath)

      expect(result).toEqual({
        name: 'test',
        value: 123,
      })
    })

    it('应该在文件不存在时抛出错误', async () => {
      const filePath = path.join(testDataDir, 'nonexistent.json')

      await expect(parser.parseFile(filePath)).rejects.toThrow('File not found')
    })

    it('应该在JSON格式无效时抛出错误', async () => {
      const filePath = path.join(testDataDir, 'invalid.json')

      await expect(parser.parseFile(filePath)).rejects.toThrow()
    })

    it('应该在不支持的文件格式时抛出错误', async () => {
      const filePath = path.join(testDataDir, 'test.txt')

      await expect(parser.parseFile(filePath)).rejects.toThrow(
        'Invalid JSON syntax',
      )
    })
  })

  describe('getSupportedExtensions', () => {
    it('应该返回支持的文件扩展名列表', () => {
      const extensions = FileParser.getSupportedExtensions()

      expect(extensions).toContain('.json')
      expect(extensions).toContain('.jsonc')
      expect(extensions).toContain('.json5')
      expect(extensions.length).toBeGreaterThan(0)
    })
  })

  describe('isSupportedFormat', () => {
    it('应该正确识别支持的文件格式', () => {
      expect(FileParser.isSupportedFormat('test.json')).toBe(true)
      expect(FileParser.isSupportedFormat('test.jsonc')).toBe(true)
      expect(FileParser.isSupportedFormat('test.json5')).toBe(true)
      expect(FileParser.isSupportedFormat('/path/to/config.json')).toBe(true)
    })

    it('应该正确识别不支持的文件格式', () => {
      expect(FileParser.isSupportedFormat('test.txt')).toBe(false)
      expect(FileParser.isSupportedFormat('test.xml')).toBe(false)
      expect(FileParser.isSupportedFormat('test')).toBe(false)
      expect(FileParser.isSupportedFormat('')).toBe(false)
    })

    it('应该不区分大小写', () => {
      expect(FileParser.isSupportedFormat('test.JSON')).toBe(true)
      expect(FileParser.isSupportedFormat('test.JSONC')).toBe(true)
      expect(FileParser.isSupportedFormat('test.JSON5')).toBe(true)
    })
  })

  describe('边界情况测试', () => {
    it('应该处理空JSON对象', async () => {
      const emptyObjectPath = path.join(testDataDir, 'empty-object.json')
      const result = await parser.parseFile(emptyObjectPath)
      expect(result).toEqual({})
    })

    it('应该拒绝JSON数组（只接受对象）', async () => {
      const emptyArrayPath = path.join(testDataDir, 'empty-array.json')
      await expect(parser.parseFile(emptyArrayPath)).rejects.toThrow(
        'must contain a JSON object at root level',
      )
    })

    it('应该处理复杂嵌套结构', async () => {
      const complexData = {
        users: [
          {
            id: 1,
            name: 'Alice',
            settings: { theme: 'dark', notifications: true },
          },
          {
            id: 2,
            name: 'Bob',
            settings: { theme: 'light', notifications: false },
          },
        ],
        config: {
          version: '1.0.0',
          features: ['feature1', 'feature2'],
          metadata: null,
        },
      }

      const complexPath = path.join(testDataDir, 'complex.json')
      await fs.writeFile(
        complexPath,
        JSON.stringify(complexData, null, 2),
        'utf8',
      )

      const result = await parser.parseFile(complexPath)
      expect(result).toEqual(complexData)

      await fs.unlink(complexPath)
    })
  })
})
