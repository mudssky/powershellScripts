import { afterEach, describe, expect, it } from 'vitest'
import { cleanupWorkspace, createWorkspace, runSource } from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('schedule conversion', () => {
  it('converts cron to OnCalendar output', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runSource(workspace, ['debug-schedule', '0 3 * * *'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('OnCalendar=')
  })

  it('rejects unsupported cron syntax', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runSource(workspace, ['debug-schedule', '0 0 ? * *'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unsupported cron')
  })
})
