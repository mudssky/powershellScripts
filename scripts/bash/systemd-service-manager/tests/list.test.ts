import path from 'node:path'
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

describe('list command', () => {
  it('prints service and timer summaries with commands and schedules', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const projectRoot = path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic')

    const result = await runSource(workspace, ['list', '--project', projectRoot])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('Services')
    expect(result.stdout).toContain("- api | scope=system | restart=always/3s | command=/usr/bin/env bash -lc 'node server.js'")
    expect(result.stdout).toContain('Timers')
    expect(result.stdout).toContain('- cleanup | scope=system | schedule=0 3 * * * | target=task | command=/usr/bin/find /tmp/myapp -type f -mtime +7 -delete')
    expect(result.stdout).toContain('- restart-api | scope=system | schedule=@daily | target=service:api | action=restart')
  })

  it('prints stable JSON with null fields for missing values', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const projectRoot = path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic')

    const result = await runSource(workspace, ['list', '--project', projectRoot, '--json'])

    expect(result.exitCode).toBe(0)
    const items = JSON.parse(result.stdout)
    expect(items).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          type: 'service',
          name: 'api',
          scope: 'system',
          command: "/usr/bin/env bash -lc 'node server.js'",
          restart: 'always',
          restartSec: '3s',
          schedule: null,
          targetType: null,
          targetName: null,
          action: null,
        }),
        expect.objectContaining({
          type: 'timer',
          name: 'cleanup',
          scope: 'system',
          command: '/usr/bin/find /tmp/myapp -type f -mtime +7 -delete',
          schedule: '0 3 * * *',
          targetType: 'task',
          targetName: null,
          action: null,
        }),
      ]),
    )
  })
})
