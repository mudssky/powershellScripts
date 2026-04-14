import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  installMockCommand,
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

describe('lifecycle commands', () => {
  it('routes start/enable/status to systemctl with system scope by default', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const systemctlLog = path.join(workspace.root, 'systemctl.log')
    installMockCommand(
      workspace,
      'systemctl',
      [
        '#!/usr/bin/env bash',
        'printf "%s\\n" "$*" >>"${SSM_SYSTEMCTL_LOG}"',
        'if [[ "$1" == "is-enabled" ]]; then printf "enabled\\n"; fi',
        'if [[ "$1" == "is-active" ]]; then printf "active\\n"; fi',
        'exit 0',
      ].join('\n'),
    )

    const projectRoot = path.join(
      workspace.managerHome,
      'tests',
      'fixtures',
      'project-basic',
    )

    await runSource(workspace, ['start', 'service', 'api', '--project', projectRoot], {
      SSM_SYSTEMCTL_LOG: systemctlLog,
    })
    await runSource(workspace, ['enable', 'service', 'api', '--project', projectRoot], {
      SSM_SYSTEMCTL_LOG: systemctlLog,
    })
    const status = await runSource(
      workspace,
      ['status', 'service', 'api', '--project', projectRoot],
      {
        SSM_SYSTEMCTL_LOG: systemctlLog,
      },
    )

    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('start myapp-api.service')
    expect(fs.readFileSync(systemctlLog, 'utf8')).toContain('enable myapp-api.service')
    expect(status.exitCode).toBe(0)
    expect(status.stdout).toContain('unit=myapp-api.service')
    expect(status.stdout).toContain('scope=system')
    expect(status.stdout).toContain('enabled=enabled')
    expect(status.stdout).toContain('active=active')
  })

  it('routes logs to journalctl --user for user-scoped services', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const journalLog = path.join(workspace.root, 'journalctl.log')
    installMockCommand(
      workspace,
      'journalctl',
      '#!/usr/bin/env bash\nprintf "%s\\n" "$*" >>"${SSM_JOURNALCTL_LOG}"\nexit 0\n',
    )

    const projectRoot = path.join(
      workspace.managerHome,
      'tests',
      'fixtures',
      'project-basic',
    )

    writeText(
      path.join(projectRoot, 'deploy/systemd/services/user-agent.conf'),
      [
        'DESCRIPTION=User Agent',
        "COMMAND=/usr/bin/env bash -lc 'sleep 10'",
        'SCOPE=user',
        '',
      ].join('\n'),
    )

    const result = await runSource(
      workspace,
      ['logs', 'service', 'user-agent', '--project', projectRoot, '--follow'],
      {
        SSM_JOURNALCTL_LOG: journalLog,
      },
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(journalLog, 'utf8')).toContain(
      '--user -u myapp-user-agent.service -f',
    )
  })
})
