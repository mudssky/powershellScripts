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

  it('explains when a device is already mounted at another target', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
exit 0
`,
    )
    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
  exit 0
fi
exit 1
`,
    )
    installMockCommand(
      workspace,
      'mount',
      `#!/usr/bin/env bash
set -eu
printf 'mount should not run\\n' >&2
exit 1
`,
    )

    const result = runSource(workspace, ['repair'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain(
      'device is already mounted at /vol00/WDC WD40EZRZ-00GXCB0',
    )
  })
})
