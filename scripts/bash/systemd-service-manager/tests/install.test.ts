import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  installMockCommand,
  runSource,
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

describe('install command', () => {
  it('prints generated unit names in dry-run mode without writing files', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installMockCommand(
      workspace,
      'systemd-analyze',
      '#!/usr/bin/env bash\nexit 0\n',
    )

    const projectRoot = path.join(
      workspace.managerHome,
      'tests',
      'fixtures',
      'project-basic',
    )

    const result = await runSource(workspace, [
      'install',
      'service',
      'api',
      '--project',
      projectRoot,
      '--dry-run',
    ])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('myapp-api.service')
    expect(fs.readdirSync(workspace.fakeSystemDir)).toHaveLength(0)
  })

  it('writes service and timer units to the selected scope', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installMockCommand(
      workspace,
      'systemd-analyze',
      '#!/usr/bin/env bash\nexit 0\n',
    )
    installMockCommand(
      workspace,
      'systemctl',
      '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"${SSM_SYSTEMCTL_LOG}"\nexit 0\n',
    )

    const projectRoot = path.join(
      workspace.managerHome,
      'tests',
      'fixtures',
      'project-basic',
    )

    const result = await runSource(
      workspace,
      ['install', 'timer', 'cleanup', '--project', projectRoot],
      {
        SSM_SYSTEMCTL_LOG: path.join(workspace.root, 'systemctl.log'),
      },
    )

    expect(result.exitCode).toBe(0)
    expect(
      fs.existsSync(path.join(workspace.fakeSystemDir, 'myapp-cleanup.timer')),
    ).toBe(true)
    expect(
      fs.existsSync(
        path.join(workspace.fakeSystemDir, 'myapp-task-cleanup.service'),
      ),
    ).toBe(true)
    expect(
      fs.readFileSync(path.join(workspace.root, 'systemctl.log'), 'utf8'),
    ).toContain('daemon-reload')
  })
})
