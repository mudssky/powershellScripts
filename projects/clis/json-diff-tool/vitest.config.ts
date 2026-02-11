import { resolve } from 'node:path'
import { defineConfig } from 'vitest/config'

process.env.FORCE_COLOR ??= '1'
delete process.env.NO_COLOR

export default defineConfig({
  test: {
    // 测试环境
    environment: 'node',

    // 测试文件匹配模式
    include: ['tests/**/*.{test,spec}.{js,mjs,cjs,ts,mts,cts,jsx,tsx}'],
    exclude: ['node_modules', 'dist', 'build'],

    // 全局设置
    globals: true,

    // 覆盖率配置
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      exclude: [
        'node_modules/',
        'tests/',
        'dist/',
        '**/*.d.ts',
        '**/*.config.*',
        '**/index.ts', // 入口文件通常只是导出，不需要测试
      ],
      thresholds: {
        global: {
          branches: 80,
          functions: 80,
          lines: 80,
          statements: 80,
        },
      },
    },

    // 测试超时
    testTimeout: 10000,

    // 设置文件
    setupFiles: ['./tests/setup.ts'],

    // 并发测试
    pool: 'threads',
    poolOptions: {
      threads: {
        singleThread: false,
      },
    },
  },

  // 解析配置
  resolve: {
    alias: {
      '@': resolve(__dirname, './src'),
    },
  },
})
