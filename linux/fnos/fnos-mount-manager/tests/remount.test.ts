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

describe('fnos mount manager remount', () => {
  it('unmounts a wrong target and mounts the managed mountpoint', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    const stateFile = `${workspace.root}/mounted-elsewhere.state`
    fs.writeFileSync(stateFile, '1', 'utf8')

    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  if [[ -f "${stateFile}" ]]; then
    printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
    exit 0
  fi
  exit 1
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  exit 1
fi
exit 1
`,
    )
    installMockCommand(
      workspace,
      'umount',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${workspace.root}/umount.log"
rm -f "${stateFile}"
exit 0
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
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "$*" >> "${workspace.root}/systemctl.log"
exit 0
`,
    )

    const result = runSource(workspace, ['remount'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain(
      'device is mounted at /vol00/WDC WD40EZRZ-00GXCB0; remounting to /mnt/local/books/bookDisk',
    )
    expect(fs.readFileSync(`${workspace.root}/umount.log`, 'utf8')).toContain(
      '/vol00/WDC WD40EZRZ-00GXCB0',
    )
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '/mnt/local/books/bookDisk',
    )
  })

  it('succeeds without unmount when the disk is already at the managed target', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  case "\${3:-}" in
    *local-book)
      printf '%s\\n' "/mnt/local/books/bookDisk"
      ;;
    *local-debut)
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  case "\${3:-}" in
    "/mnt/local/books/bookDisk")
      printf '%s\\n' "/mnt/local/books/bookDisk"
      ;;
    "/mnt/local/debutDisk")
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
  esac
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

    const result = runSource(workspace, ['remount'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain(
      'bookDisk already mounted at /mnt/local/books/bookDisk',
    )
    expect(result.stdout + result.stderr).toContain(
      'debutDisk already mounted at /mnt/local/debutDisk',
    )
  })
})
