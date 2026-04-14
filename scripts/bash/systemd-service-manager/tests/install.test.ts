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
    ], {
      SSM_TEST_EUID: '0',
    })

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
        SSM_TEST_EUID: '0',
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

  it('infers service kind when omitted for install dry-run', async () => {
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
      'api',
      '--project',
      projectRoot,
      '--dry-run',
    ], {
      SSM_TEST_EUID: '0',
    })

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('myapp-api.service')
  })

  it('can install and start a service in one step with --start', async () => {
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
    const systemctlLog = path.join(workspace.root, 'systemctl.log')

    const result = await runSource(
      workspace,
      ['install', 'api', '--project', projectRoot, '--start'],
      {
        SSM_TEST_EUID: '0',
        SSM_SYSTEMCTL_LOG: systemctlLog,
      },
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('installed=myapp-api.service')
    expect(result.stdout).toContain('started=myapp-api.service')
    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('daemon-reload')
    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('start myapp-api.service')
  })

  it('auto-elevates system-scope install when not root', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installMockCommand(
      workspace,
      'sudo',
      [
        '#!/usr/bin/env bash',
        'printf "%s\\n" "$*" >>"${SSM_SUDO_LOG}"',
        'if [[ "$1" == "--" ]]; then shift; fi',
        'SSM_TEST_EUID=0 exec "$@"',
      ].join('\n'),
    )
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
    const sudoLog = path.join(workspace.root, 'sudo.log')
    const systemctlLog = path.join(workspace.root, 'systemctl.log')

    const result = await runSource(
      workspace,
      ['install', 'api', '--project', projectRoot, '--start'],
      {
        SSM_TEST_EUID: '1000',
        SSM_SUDO_LOG: sudoLog,
        SSM_SYSTEMCTL_LOG: systemctlLog,
      },
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(sudoLog, 'utf8')).toContain(workspace.sourceEntry)
    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('daemon-reload')
    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('start myapp-api.service')
  })
})
