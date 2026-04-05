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

describe('fnos mount manager backfill', () => {
  it('mounts only not-mounted disks onto their business mountpoints', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    const bookStateFile = `${workspace.root}/book-mounted.state`

    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  case "\${3:-}" in
    *local-book)
      if [[ -f "${bookStateFile}" ]]; then
        printf '%s\\n' "/mnt/local/books/bookDisk"
      else
        exit 1
      fi
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
      if [[ -f "${bookStateFile}" ]]; then
        printf '%s\\n' "/mnt/local/books/bookDisk"
      else
        exit 1
      fi
      ;;
    "/mnt/local/debutDisk")
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
    *)
      exit 1
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
printf '%s\\n' "$*" >> "${workspace.root}/mount.log"
if [[ "\${1:-}" == "/mnt/local/books/bookDisk" ]]; then
  touch "${bookStateFile}"
fi
exit 0
`,
    )

    const result = runSource(workspace, ['backfill'])

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '/mnt/local/books/bookDisk',
    )
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).not.toContain(
      '/mnt/local/debutDisk',
    )
  })

  it('does not remount disks that are already mounted elsewhere', () => {
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
      printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
      ;;
    *local-debut)
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  case "\${3:-}" in
    "/mnt/local/debutDisk")
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
    *)
      exit 1
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

    const result = runSource(workspace, ['backfill'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain(
      'Skipping bookDisk: disk is already mounted at /vol00/WDC WD40EZRZ-00GXCB0',
    )
  })

  it('continues processing later not-mounted disks when one backfill fails', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    const debutStateFile = `${workspace.root}/debut-mounted.state`

    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  case "\${3:-}" in
    *local-book)
      exit 1
      ;;
    *local-debut)
      if [[ -f "${debutStateFile}" ]]; then
        printf '%s\\n' "/mnt/local/debutDisk"
      else
        exit 1
      fi
      ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  case "\${3:-}" in
    "/mnt/local/debutDisk")
      if [[ -f "${debutStateFile}" ]]; then
        printf '%s\\n' "/mnt/local/debutDisk"
      else
        exit 1
      fi
      ;;
    *)
      exit 1
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
printf '%s\\n' "$*" >> "${workspace.root}/mount.log"
if [[ "\${1:-}" == "/mnt/local/books/bookDisk" ]]; then
  exit 1
fi
touch "${debutStateFile}"
exit 0
`,
    )

    const result = runSource(workspace, ['backfill'])

    expect(result.exitCode).not.toBe(0)
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '/mnt/local/books/bookDisk',
    )
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '/mnt/local/debutDisk',
    )
  })
})
