/**
 * JSON深度比较算法模块
 * 实现对象、数组的递归比较，生成详细的差异报告
 *
 * @author mudssky
 */

import {
  type CompareOptions,
  type DiffResult,
  DiffType,
  type JsonObject,
  type JsonValue,
} from './types'

/**
 * JSON比较器类
 * 提供深度比较功能，支持复杂嵌套结构的差异检测
 */
export class JsonComparator {
  private options: CompareOptions

  constructor(options: CompareOptions = {}) {
    this.options = {
      ignoreArrayOrder: false,
      maxDepth: 100,
      caseSensitive: true,
      ignoreWhitespace: false,
      ...options,
    }
  }

  /**
   * 比较多个JSON对象
   * @param objects 要比较的JSON对象数组
   * @returns 差异结果数组
   */
  compare(objects: JsonObject[]): DiffResult[] {
    if (objects.length < 2) {
      throw new Error('At least two objects are required for comparison')
    }

    const results: DiffResult[] = []

    if (objects.length === 2) {
      const first = objects[0]
      const second = objects[1]
      if (first !== undefined && second !== undefined) {
        results.push(...this.deepCompare(first, second, ''))
      }
    } else {
      // 多个对象比较：以第一个为基准
      const baseObject = objects[0]
      if (baseObject === undefined) {
        return results
      }

      for (let i = 1; i < objects.length; i++) {
        const candidate = objects[i]
        if (candidate === undefined) continue
        const compareResults = this.deepCompare(baseObject, candidate, '')

        // 为每个比较结果添加文件索引信息
        compareResults.forEach((result) => {
          result.message = `Comparison between file 0 and file ${i}`
          results.push(result)
        })
      }
    }

    return results
  }

  /**
   * 深度比较两个值
   * @param obj1 第一个值
   * @param obj2 第二个值
   * @param path 当前路径
   * @param depth 当前深度
   * @returns 差异结果数组
   */
  deepCompare(
    obj1: JsonValue,
    obj2: JsonValue,
    path: string,
    depth: number = 0,
  ): DiffResult[] {
    const results: DiffResult[] = []

    // 检查深度限制
    const maxDepth = this.options.maxDepth ?? Number.POSITIVE_INFINITY
    if (depth > maxDepth) {
      results.push({
        path,
        type: DiffType.MODIFIED,
        oldValue: obj1,
        newValue: obj2,
        message: 'Maximum depth exceeded',
      })
      return results
    }

    // 处理null值
    if (obj1 === null && obj2 === null) {
      results.push({
        path,
        type: DiffType.UNCHANGED,
        oldValue: obj1,
        newValue: obj2,
      })
      return results
    }

    if (obj1 === null) {
      results.push({
        path,
        type: DiffType.MODIFIED,
        oldValue: obj1,
        newValue: obj2,
      })
      return results
    }

    if (obj2 === null) {
      results.push({
        path,
        type: DiffType.MODIFIED,
        oldValue: obj1,
        newValue: obj2,
      })
      return results
    }

    // 检查类型是否相同
    const type1 = this.getValueType(obj1)
    const type2 = this.getValueType(obj2)

    if (type1 !== type2) {
      results.push({
        path,
        type: DiffType.MODIFIED,
        oldValue: obj1,
        newValue: obj2,
        message: `Type changed from ${type1} to ${type2}`,
      })
      return results
    }

    // 根据类型进行比较
    switch (type1) {
      case 'object':
        results.push(
          ...this.compareObjects(
            obj1 as JsonObject,
            obj2 as JsonObject,
            path,
            depth + 1,
          ),
        )
        break
      case 'array':
        results.push(
          ...this.compareArrays(
            obj1 as JsonValue[],
            obj2 as JsonValue[],
            path,
            depth + 1,
          ),
        )
        break
      case 'string':
        results.push(
          ...this.compareStrings(obj1 as string, obj2 as string, path),
        )
        break
      default:
        // 基本类型比较
        if (obj1 !== obj2) {
          results.push({
            path,
            type: DiffType.MODIFIED,
            oldValue: obj1,
            newValue: obj2,
          })
        } else {
          results.push({
            path,
            type: DiffType.UNCHANGED,
            oldValue: obj1,
            newValue: obj2,
          })
        }
        break
    }

    return results
  }

  /**
   * 比较两个对象
   * @param obj1 第一个对象
   * @param obj2 第二个对象
   * @param path 当前路径
   * @param depth 当前深度
   * @returns 差异结果数组
   */
  private compareObjects(
    obj1: JsonObject,
    obj2: JsonObject,
    path: string,
    depth: number,
  ): DiffResult[] {
    const results: DiffResult[] = []
    const keys1 = Object.keys(obj1)
    const keys2 = Object.keys(obj2)
    const allKeys = new Set([...keys1, ...keys2])

    for (const key of allKeys) {
      const newPath = path ? `${path}.${key}` : key
      const hasKey1 = key in obj1
      const hasKey2 = key in obj2

      if (hasKey1 && hasKey2) {
        const v1 = obj1[key]
        const v2 = obj2[key]
        if (v1 === undefined && v2 === undefined) {
          results.push({ path: newPath, type: DiffType.UNCHANGED })
        } else if (v1 === undefined && v2 !== undefined) {
          results.push({
            path: newPath,
            type: DiffType.MODIFIED,
            oldValue: undefined,
            newValue: v2,
          })
        } else if (v1 !== undefined && v2 === undefined) {
          results.push({
            path: newPath,
            type: DiffType.MODIFIED,
            oldValue: v1,
            newValue: undefined,
          })
        } else {
          results.push(
            ...this.deepCompare(
              v1 as JsonValue,
              v2 as JsonValue,
              newPath,
              depth,
            ),
          )
        }
      } else if (hasKey1 && !hasKey2) {
        const v1 = obj1[key]
        if (v1 !== undefined) {
          results.push({
            path: newPath,
            type: DiffType.REMOVED,
            oldValue: v1,
          })
        }
      } else if (!hasKey1 && hasKey2) {
        const v2 = obj2[key]
        if (v2 !== undefined) {
          results.push({
            path: newPath,
            type: DiffType.ADDED,
            newValue: v2,
          })
        }
      }
    }

    return results
  }

  /**
   * 比较两个数组
   * @param arr1 第一个数组
   * @param arr2 第二个数组
   * @param path 当前路径
   * @param depth 当前深度
   * @returns 差异结果数组
   */
  compareArrays(
    arr1: JsonValue[],
    arr2: JsonValue[],
    path: string,
    depth: number,
  ): DiffResult[] {
    const results: DiffResult[] = []

    if (this.options.ignoreArrayOrder) {
      // 忽略数组顺序的比较
      results.push(...this.compareArraysIgnoreOrder(arr1, arr2, path))
    } else {
      // 按索引顺序比较
      results.push(...this.compareArraysByIndex(arr1, arr2, path, depth))
    }

    return results
  }

  /**
   * 按索引顺序比较数组
   * @param arr1 第一个数组
   * @param arr2 第二个数组
   * @param path 当前路径
   * @param depth 当前深度
   * @returns 差异结果数组
   */
  private compareArraysByIndex(
    arr1: JsonValue[],
    arr2: JsonValue[],
    path: string,
    depth: number,
  ): DiffResult[] {
    const results: DiffResult[] = []
    const maxLength = Math.max(arr1.length, arr2.length)

    for (let i = 0; i < maxLength; i++) {
      const newPath = `${path}[${i}]`

      if (i < arr1.length && i < arr2.length) {
        const v1 = arr1[i]
        const v2 = arr2[i]
        if (v1 !== undefined && v2 !== undefined) {
          results.push(...this.deepCompare(v1, v2, newPath, depth))
        }
      } else if (i < arr1.length) {
        const v1 = arr1[i]
        if (v1 !== undefined) {
          results.push({
            path: newPath,
            type: DiffType.REMOVED,
            oldValue: v1,
          })
        }
      } else {
        const v2 = arr2[i]
        if (v2 !== undefined) {
          results.push({
            path: newPath,
            type: DiffType.ADDED,
            newValue: v2,
          })
        }
      }
    }

    return results
  }

  /**
   * 忽略顺序比较数组
   * @param arr1 第一个数组
   * @param arr2 第二个数组
   * @param path 当前路径
   * @param depth 当前深度
   * @returns 差异结果数组
   */
  private compareArraysIgnoreOrder(
    arr1: JsonValue[],
    arr2: JsonValue[],
    path: string,
  ): DiffResult[] {
    const results: DiffResult[] = []

    const arr1Strings = arr1.map((item) => JSON.stringify(item))
    const arr2Strings = arr2.map((item) => JSON.stringify(item))

    const freq2 = new Map<string, number>()
    arr2Strings.forEach((s) => {
      freq2.set(s, (freq2.get(s) ?? 0) + 1)
    })

    const removedIndices: number[] = []
    arr1Strings.forEach((s, i) => {
      const count = freq2.get(s) ?? 0
      if (count > 0) {
        freq2.set(s, count - 1)
      } else {
        removedIndices.push(i)
      }
    })

    const freq1 = new Map<string, number>()
    arr1Strings.forEach((s) => {
      freq1.set(s, (freq1.get(s) ?? 0) + 1)
    })
    const addedIndices: number[] = []
    arr2Strings.forEach((s, i) => {
      const count = freq1.get(s) ?? 0
      if (count > 0) {
        freq1.set(s, count - 1)
      } else {
        addedIndices.push(i)
      }
    })

    removedIndices.forEach((index) => {
      const v1 = arr1[index]
      if (v1 !== undefined) {
        results.push({
          path: `${path}[${index}]`,
          type: DiffType.REMOVED,
          oldValue: v1,
        })
      }
    })

    addedIndices.forEach((index) => {
      const v2 = arr2[index]
      if (v2 !== undefined) {
        results.push({
          path: `${path}[${index}]`,
          type: DiffType.ADDED,
          newValue: v2,
        })
      }
    })

    return results
  }

  /**
   * 比较两个字符串
   * @param str1 第一个字符串
   * @param str2 第二个字符串
   * @param path 当前路径
   * @returns 差异结果数组
   */
  private compareStrings(
    str1: string,
    str2: string,
    path: string,
  ): DiffResult[] {
    const results: DiffResult[] = []

    let value1 = str1
    let value2 = str2

    // 处理忽略空白字符的选项
    if (this.options.ignoreWhitespace) {
      value1 = str1.trim()
      value2 = str2.trim()
    }

    // 处理大小写敏感的选项
    if (!this.options.caseSensitive) {
      value1 = value1.toLowerCase()
      value2 = value2.toLowerCase()
    }

    if (value1 !== value2) {
      results.push({
        path,
        type: DiffType.MODIFIED,
        oldValue: str1,
        newValue: str2,
      })
    } else {
      results.push({
        path,
        type: DiffType.UNCHANGED,
        oldValue: str1,
        newValue: str2,
      })
    }

    return results
  }

  /**
   * 获取值的类型
   * @param value 要检查的值
   * @returns 值的类型字符串
   */
  private getValueType(value: JsonValue): string {
    if (value === null) {
      return 'null'
    }

    if (Array.isArray(value)) {
      return 'array'
    }

    return typeof value
  }

  /**
   * 过滤差异结果
   * @param results 差异结果数组
   * @param filter 过滤条件
   * @returns 过滤后的结果数组
   */
  static filterResults(
    results: DiffResult[],
    filter: {
      types?: DiffType[]
      pathPattern?: RegExp
      maxDepth?: number
    },
  ): DiffResult[] {
    return results.filter((result) => {
      // 按类型过滤
      if (filter.types && !filter.types.includes(result.type)) {
        return false
      }

      // 按路径模式过滤
      if (filter.pathPattern && !filter.pathPattern.test(result.path)) {
        return false
      }

      // 按深度过滤
      if (filter.maxDepth !== undefined) {
        const depth = result.path.split('.').length - 1
        if (depth > filter.maxDepth) {
          return false
        }
      }

      return true
    })
  }
}
