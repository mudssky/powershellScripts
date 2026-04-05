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

describe('fnos mount manager alias', () => {
  it('creates a business bind alias for disks mounted elsewhere', () => {
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
    "/vol00/WDC WD40EZRZ-00GXCB0")
      printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
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
exit 0
`,
    )

    const result = runSource(workspace, ['alias'])

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '--bind /vol00/WDC WD40EZRZ-00GXCB0 /mnt/local/books/bookDisk',
    )
  })

  it('does not re-bind when the business alias is already synced', () => {
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
    "/vol00/WDC WD40EZRZ-00GXCB0")
      printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
      ;;
    "/mnt/local/books/bookDisk")
      printf '%s\\n' "/mnt/local/books/bookDisk"
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
      'stat',
      `#!/usr/bin/env bash
set -eu
path="\${2:-}"
case "\${path}" in
  "/vol00/WDC WD40EZRZ-00GXCB0"|"/mnt/local/books/bookDisk")
    printf '%s\\n' "42:7"
    ;;
  *)
    printf '%s\\n' "99:1"
    ;;
esac
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

    const result = runSource(workspace, ['alias'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout + result.stderr).toContain(
      'already exposes a business alias',
    )
  })

  it('fails with a clear reason when bind mount creation fails', () => {
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
      exit 1
      ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  case "\${3:-}" in
    "/vol00/WDC WD40EZRZ-00GXCB0")
      printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
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
exit 1
`,
    )

    const result = runSource(workspace, ['alias'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('bind mount failed')
  })

  it('accepts escaped findmnt source targets for model paths with spaces', () => {
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
      printf '%s\\n' "/vol00/WDC\\x20WD40EZRZ-00GXCB0"
      ;;
    *local-debut)
      printf '%s\\n' "/mnt/local/debutDisk"
      ;;
  esac
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  case "\${3:-}" in
    "/vol00/WDC WD40EZRZ-00GXCB0")
      printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
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
exit 0
`,
    )

    const result = runSource(workspace, ['alias'])

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(`${workspace.root}/mount.log`, 'utf8')).toContain(
      '--bind /vol00/WDC WD40EZRZ-00GXCB0 /mnt/local/books/bookDisk',
    )
  })
})
