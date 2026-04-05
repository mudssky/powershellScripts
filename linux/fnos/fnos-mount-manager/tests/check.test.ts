import fs from 'node:fs'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  ensureFakeDevice,
  installMockCommand,
  readText,
  runSource,
  writeHomeFile,
} from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

function installCheckSystemctl(
  workspace: ReturnType<typeof createWorkspace>,
  loadState = 'not-found',
  legacyCat = '',
) {
  installMockCommand(
    workspace,
    'systemctl',
    `#!/usr/bin/env bash
set -eu
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  show)
    unit="\${1:-}"
    if [[ "\${unit}" == "force-remount-disks.service" ]]; then
      printf '%s\\n' "${loadState}"
    else
      printf '%s\\n' "active"
    fi
    ;;
  cat)
    printf '%s\\n' "${legacyCat}"
    ;;
  *)
    exit 0
    ;;
esac
`,
  )
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('fnos mount manager check', () => {
  it('passes when previews, devices and target managed block all match', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installCheckSystemctl(workspace)
    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')
    expect(runSource(workspace, ['generate']).exitCode).toBe(0)
    expect(
      runSource(workspace, ['apply', '--target', workspace.targetFstab])
        .exitCode,
    ).toBe(0)

    const result = runSource(workspace, [
      'check',
      '--target',
      workspace.targetFstab,
    ])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain('Check passed')
  })

  it('fails when a legacy shell mount snippet is still present', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installCheckSystemctl(
      workspace,
      'loaded',
      'ExecStart=/repo/linux/fnos/remount.sh',
    )
    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')
    writeHomeFile(workspace, '.bashrc', 'sudo mount -a\nls /mnt/local\n')
    expect(runSource(workspace, ['generate']).exitCode).toBe(0)
    expect(
      runSource(workspace, ['apply', '--target', workspace.targetFstab])
        .exitCode,
    ).toBe(0)

    const result = runSource(workspace, [
      'check',
      '--target',
      workspace.targetFstab,
    ])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain(
      'Legacy shell mount logic detected',
    )
    expect(result.stderr + result.stdout).toContain(
      'force-remount-disks.service',
    )
    expect(readText(workspace.targetFstab)).toContain(
      '# BEGIN FNOS MOUNT MANAGER',
    )
  })

  it('prints a managed block diff when the target block drifts from the local preview', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    installCheckSystemctl(workspace)
    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')
    expect(runSource(workspace, ['generate']).exitCode).toBe(0)
    expect(
      runSource(workspace, ['apply', '--target', workspace.targetFstab])
        .exitCode,
    ).toBe(0)

    const drifted = readText(workspace.targetFstab).replace(
      'UUID=local-debut /mnt/local/debutDisk ntfs nofail,uid=1000,gid=1000,umask=022,big_writes,x-systemd.device-timeout=45 0 0',
      'UUID=local-debut /mnt/local/debutDisk ntfs nofail,uid=1000,gid=1000,umask=022 0 0',
    )
    fs.writeFileSync(workspace.targetFstab, drifted, 'utf8')

    const result = runSource(workspace, [
      'check',
      '--target',
      workspace.targetFstab,
    ])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Managed block diff:')
    expect(result.stderr + result.stdout).toContain('--- local-preview')
    expect(result.stderr + result.stdout).toContain('+++ target-managed-block')
    expect(result.stderr + result.stdout).toContain('-UUID=local-debut /mnt/local/debutDisk ntfs nofail,uid=1000,gid=1000,umask=022,big_writes,x-systemd.device-timeout=45 0 0')
    expect(result.stderr + result.stdout).toContain('+UUID=local-debut /mnt/local/debutDisk ntfs nofail,uid=1000,gid=1000,umask=022 0 0')
  })
})
