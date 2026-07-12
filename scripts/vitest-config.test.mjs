import { describe, expect, it } from 'vitest'

import rootVitestConfig from '../vitest.config.ts'

describe('root Vitest config', () => {
  it('excludes the repository cold archive', () => {
    expect(rootVitestConfig.test?.exclude).toContain('archive/**')
  })
})
