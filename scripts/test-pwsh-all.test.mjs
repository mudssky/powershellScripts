import { describe, expect, it, vi } from 'vitest'

import { checkDockerPrerequisites } from './test-pwsh-all.mjs'

describe('test:pwsh:all Docker preflight', () => {
  it('依次验证 CLI、daemon 与 Compose', () => {
    const run = vi.fn(() => ({ status: 0 }))

    expect(checkDockerPrerequisites(run)).toEqual({ ok: true, reason: '' })
    expect(run.mock.calls).toEqual([
      ['docker', ['--version']],
      ['docker', ['info']],
      ['docker', ['compose', 'version']],
    ])
  })

  it.each([
    { failedCall: 1, reason: 'Docker CLI 不可用' },
    { failedCall: 2, reason: 'Docker daemon 不可用' },
    { failedCall: 3, reason: 'Docker Compose plugin 不可用' },
  ])('第 $failedCall 个检查失败时快速返回原因', ({ failedCall, reason }) => {
    let callCount = 0
    const result = checkDockerPrerequisites(() => {
      callCount += 1
      return { status: callCount === failedCall ? 1 : 0 }
    })

    expect(result).toEqual({ ok: false, reason })
    expect(callCount).toBe(failedCall)
  })
})
