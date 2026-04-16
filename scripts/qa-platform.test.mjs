import { describe, expect, it } from 'vitest'

import { shouldRunLinuxOnlyQa } from './qa-platform.mjs'

// 根目录 CI 直接运行 Vitest，因此这个平台判定用例也要使用 Vitest API，
// 避免文件名匹配后被 Vitest 扫描到却因未注册套件而报 `No test suite found`。
describe('shouldRunLinuxOnlyQa', () => {
  it('returns true on linux', () => {
    expect(shouldRunLinuxOnlyQa('linux')).toBe(true)
  })

  it('returns false on non-linux platforms', () => {
    expect(shouldRunLinuxOnlyQa('win32')).toBe(false)
    expect(shouldRunLinuxOnlyQa('darwin')).toBe(false)
  })
})
