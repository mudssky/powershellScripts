import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  installMockCommand,
  runBuild,
  runBuilt,
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

function installServiceSystemctlMock(
  workspace: ReturnType<typeof createWorkspace>,
  legacyExecStart = 'ExecStart=/repo/linux/fnos/remount.sh',
) {
  installMockCommand(
    workspace,
    'systemctl',
    `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${workspace.root}/systemctl.log"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  show)
    if [[ "\${1:-}" == "force-remount-disks.service" ]]; then
      printf '%s\\n' "loaded"
    else
      printf '%s\\n' "active"
    fi
    ;;
  cat)
    printf '%s\\n' "${legacyExecStart}"
    ;;
  *)
    exit 0
    ;;
esac
`,
  )
}

describe('fnos mount manager service install', () => {
  it('installs and enables the reconcile boot service from the source entry', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const unitDir = path.join(workspace.root, 'systemd', 'system')
    const unitPath = path.join(unitDir, 'fnos-mount-manager-reconcile.service')

    installServiceSystemctlMock(workspace)

    const result = runSource(
      workspace,
      ['install-reconcile-service'],
      { FNOS_MANAGER_SYSTEMD_UNIT_DIR: unitDir },
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(unitPath, 'utf8')).toContain(
      `ExecStart=/usr/bin/env bash "${workspace.sourceEntry}" reconcile`,
    )
    expect(fs.readFileSync(`${workspace.root}/systemctl.log`, 'utf8')).toContain(
      'daemon-reload',
    )
    expect(fs.readFileSync(`${workspace.root}/systemctl.log`, 'utf8')).toContain(
      'enable fnos-mount-manager-reconcile.service',
    )
    expect(fs.readFileSync(`${workspace.root}/systemctl.log`, 'utf8')).toContain(
      'disable --now force-remount-disks.service',
    )
  })

  it('can start the new reconcile service immediately after enabling it', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const unitDir = path.join(workspace.root, 'systemd', 'system')

    installServiceSystemctlMock(workspace, '')

    const result = runSource(
      workspace,
      ['install-reconcile-service', '--start-now'],
      { FNOS_MANAGER_SYSTEMD_UNIT_DIR: unitDir },
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(`${workspace.root}/systemctl.log`, 'utf8')).toContain(
      'start fnos-mount-manager-reconcile.service',
    )
  })

  it('uses the built binary path when the built entry installs the service', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const unitDir = path.join(workspace.root, 'systemd', 'system')
    const unitPath = path.join(unitDir, 'fnos-mount-manager-reconcile.service')

    installServiceSystemctlMock(workspace, '')
    expect(runBuild(workspace).exitCode).toBe(0)

    const result = runBuilt(
      workspace,
      'bin',
      ['install-reconcile-service'],
      { FNOS_MANAGER_SYSTEMD_UNIT_DIR: unitDir },
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(unitPath, 'utf8')).toContain(
      `ExecStart=/usr/bin/env bash "${workspace.builtBin}" reconcile`,
    )
  })
})
