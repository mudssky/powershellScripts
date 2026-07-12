/**
 * Vitest 测试设置文件
 * 配置测试环境和全局设置
 */

import { afterEach, expect, vi } from 'vitest'

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      NODE_ENV: 'development' | 'production' | 'test'
    }
  }
}

// 设置环境变量
process.env.NODE_ENV = 'test'

// 清理所有模拟
afterEach(() => {
  vi.clearAllMocks()
})

// 扩展 Vitest 匹配器
interface CustomMatchers<R = unknown> {
  toBeValidJson(): R
  toContainAnsiColors(): R
}

declare module 'vitest' {
  // biome-ignore lint/suspicious/noExplicitAny: vitest 类型扩展需与内置声明保持一致
  interface Assertion<T = any> extends CustomMatchers<T> {}
  interface AsymmetricMatchersContaining extends CustomMatchers {}
}

// 自定义匹配器：检查是否为有效的 JSON
expect.extend({
  toBeValidJson(received: string) {
    try {
      JSON.parse(received)
      return {
        message: () => `Expected ${received} not to be valid JSON`,
        pass: true,
      }
    } catch (error) {
      return {
        message: () =>
          `Expected ${received} to be valid JSON, but got error: ${error}`,
        pass: false,
      }
    }
  },
})

// 自定义匹配器：检查是否包含 ANSI 颜色代码
expect.extend({
  toContainAnsiColors(received: string) {
    // biome-ignore lint/suspicious/noControlCharactersInRegex: <yanse>
    const ansiRegex = /\u001b\[[0-9;]*m/
    const hasAnsiColors = ansiRegex.test(received)

    return {
      message: () =>
        hasAnsiColors
          ? `Expected ${received} not to contain ANSI color codes`
          : `Expected ${received} to contain ANSI color codes`,
      pass: hasAnsiColors,
    }
  },
})
