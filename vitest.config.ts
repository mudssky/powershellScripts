import { configDefaults, defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    // 冷归档只保留历史内容，不应被根级 Vitest 发现或执行。
    exclude: [...configDefaults.exclude, 'archive/**'],
  },
})
