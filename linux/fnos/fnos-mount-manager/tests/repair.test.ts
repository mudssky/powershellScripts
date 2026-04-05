import fs from 'node:fs'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  ensureFakeDevice,
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

describe('fnos mount manager repair', () => {
  it('runs the unified repair flow and disables the legacy service in force mode', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s %s\\n' "$0" "$*" >> "${workspace.root}/systemctl.log"
cmd="\${1:-}"
shift || true
case "\${cmd}" in
  cat)
    printf '%s\\n' "ExecStart=/repo/linux/fnos/remount.sh"
    ;;
  *)
    exit 0
    ;;
esac
`,
    )
    installMockCommand(
      workspace,
      'mount',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${workspace.root}/mount.log"
exit 0
`,
    )
    installMockCommand(
      workspace,
      'fuser',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${workspace.root}/fuser.log"
exit 0
`,
    )

    const result = runSource(workspace, ['repair', '--force'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain(
      'Disabled legacy force-remount-disks.service',
    )
    expect(
      fs.readFileSync(`${workspace.root}/systemctl.log`, 'utf8'),
    ).toContain('disable --now force-remount-disks.service')
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '/mnt/local/books/bookDisk',
    )
  })
})
