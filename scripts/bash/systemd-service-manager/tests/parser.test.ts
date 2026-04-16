import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  runSource,
  writeText,
} from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('config parsing', () => {
  it('merges project env and service env with .env.local winning', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const projectRoot = path.join(workspace.root, 'demo-app')
    fs.cpSync(
      path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic'),
      projectRoot,
      { recursive: true },
    )
    writeText(
      path.join(projectRoot, 'deploy/systemd/project.env.local'),
      ['APP_NAME=demo-local', ''].join('\n'),
    )
    writeText(
      path.join(projectRoot, 'deploy/systemd/services/api.env.local'),
      ['APP_PORT=3100', ''].join('\n'),
    )

    const result = await runSource(
      workspace,
      ['list', '--project', projectRoot],
      { SSM_DEBUG_DUMP_CONFIG: '1' },
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('project=myapp')
    expect(result.stdout).toContain('scope=system')
    expect(result.stdout).toContain('APP_PORT=3100')
    expect(result.stdout).toContain('APP_NAME=demo-local')
  })

  it('fails when a timer points to a missing service target', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const projectRoot = path.join(workspace.root, 'demo-app')
    fs.cpSync(
      path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic'),
      projectRoot,
      { recursive: true },
    )
    writeText(
      path.join(projectRoot, 'deploy/systemd/project.env.local'),
      ['APP_NAME=demo-local', ''].join('\n'),
    )
    writeText(
      path.join(projectRoot, 'deploy/systemd/services/api.env.local'),
      ['APP_PORT=3100', ''].join('\n'),
    )

    writeText(
      path.join(projectRoot, 'deploy/systemd/timers/bad.conf'),
      [
        'DESCRIPTION=Broken timer',
        'TARGET_TYPE=service',
        'TARGET_NAME=missing',
        'ACTION=restart',
        'SCHEDULE=@daily',
        '',
      ].join('\n'),
    )

    const result = await runSource(workspace, [
      'install',
      'timer',
      'bad',
      '--project',
      projectRoot,
      '--dry-run',
    ])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('TARGET_NAME')
    expect(result.stderr + result.stdout).toContain('missing')
  })
})
