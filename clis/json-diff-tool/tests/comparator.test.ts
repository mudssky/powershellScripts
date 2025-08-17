import { describe, it, expect, beforeEach } from 'vitest'
import { JsonComparator } from '../src/comparator'
import { DiffResult, DiffType } from '../src/types'

describe('JsonComparator', () => {
  let comparator: JsonComparator

  beforeEach(() => {
    comparator = new JsonComparator()
  })

  describe('compare', () => {
    it('应该检测到相同的对象', () => {
      const obj1 = { name: 'test', value: 123 }
      const obj2 = { name: 'test', value: 123 }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(0)
    })

    it('应该检测到添加的属性', () => {
      const obj1 = { name: 'test' }
      const obj2 = { name: 'test', value: 123 }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.ADDED,
        newValue: 123,
      })
    })

    it('应该检测到删除的属性', () => {
      const obj1 = { name: 'test', value: 123 }
      const obj2 = { name: 'test' }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.REMOVED,
        oldValue: 123,
      })
    })

    it('应该检测到修改的属性', () => {
      const obj1 = { name: 'test', value: 123 }
      const obj2 = { name: 'test', value: 456 }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.MODIFIED,
        oldValue: 123,
        newValue: 456,
      })
    })

    it('应该检测到嵌套对象的变化', () => {
      const obj1 = { user: { name: 'Alice', age: 30 } }
      const obj2 = { user: { name: 'Alice', age: 31 } }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'user.age',
        type: DiffType.MODIFIED,
        oldValue: 30,
        newValue: 31,
      })
    })

    it('应该检测到数组的变化', () => {
      const obj1 = { items: [1, 2, 3] }
      const obj2 = { items: [1, 2, 4] }

      const results = comparator.compare([obj1, obj2])

      expect(results.length).toBeGreaterThan(0)
      expect(results.some((r) => r.path.includes('items')))
    })

    it('应该检测到数组长度变化', () => {
      const obj1 = { items: [1, 2, 3] }
      const obj2 = { items: [1, 2] }

      const results = comparator.compare([obj1, obj2])

      expect(results.length).toBeGreaterThan(0)
      expect(results.some((r) => r.path.includes('items')))
    })

    it('应该处理null值', () => {
      const obj1 = { value: null }
      const obj2 = { value: 'test' }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.MODIFIED,
        oldValue: null,
        newValue: 'test',
      })
    })

    it('应该处理undefined值', () => {
      const obj1 = { value: undefined }
      const obj2 = { value: 'test' }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.MODIFIED,
        oldValue: undefined,
        newValue: 'test',
      })
    })

    it('应该处理类型变化', () => {
      const obj1 = { value: 123 }
      const obj2 = { value: '123' }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'value',
        type: DiffType.MODIFIED,
        oldValue: 123,
        newValue: '123',
      })
    })
  })

  describe('边界情况测试', () => {
    it('应该处理空对象', () => {
      const obj1 = {}
      const obj2 = {}

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(0)
    })

    it('应该处理空数组', () => {
      const obj1 = { items: [] }
      const obj2 = { items: [] }

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(0)
    })

    it('应该处理复杂嵌套结构', () => {
      const obj1 = {
        users: [
          { id: 1, profile: { name: 'Alice', settings: { theme: 'dark' } } },
        ],
      }
      const obj2 = {
        users: [
          { id: 1, profile: { name: 'Alice', settings: { theme: 'light' } } },
        ],
      }

      const results = comparator.compare([obj1, obj2])

      expect(results.length).toBeGreaterThan(0)
      expect(results.some((r) => r.path.includes('theme')))
    })

    it('应该处理循环引用（基本处理）', () => {
      const obj1: any = { name: 'test' }
      obj1.self = obj1

      const obj2: any = { name: 'test' }
      obj2.self = obj2

      // 应该不抛出错误
      expect(() => {
        const results = comparator.compare([obj1, obj2])
      }).not.toThrow()
    })

    it('应该处理大型对象', () => {
      const createLargeObject = (size: number) => {
        const obj: any = {}
        for (let i = 0; i < size; i++) {
          obj[`key${i}`] = `value${i}`
        }
        return obj
      }

      const obj1 = createLargeObject(1000)
      const obj2 = createLargeObject(1000)
      obj2.key999 = 'modified'

      const results = comparator.compare([obj1, obj2])

      expect(results).toHaveLength(1)
      expect(results[0]).toMatchObject({
        path: 'key999',
        type: DiffType.MODIFIED,
      })
    })
  })

  describe('性能测试', () => {
    it('应该在合理时间内完成比较', () => {
      const createComplexObject = () => ({
        users: Array.from({ length: 100 }, (_, i) => ({
          id: i,
          name: `User${i}`,
          profile: {
            email: `user${i}@example.com`,
            settings: {
              theme: i % 2 === 0 ? 'dark' : 'light',
              notifications: i % 3 === 0,
            },
          },
        })),
      })

      const obj1 = createComplexObject()
      const obj2 = createComplexObject()
      obj2.users[50].name = 'Modified User'

      const startTime = Date.now()
      const results = comparator.compare([obj1, obj2])
      const endTime = Date.now()

      expect(endTime - startTime).toBeLessThan(1000) // 应该在1秒内完成
      expect(results.length).toBeGreaterThan(0)
    })
  })
})
