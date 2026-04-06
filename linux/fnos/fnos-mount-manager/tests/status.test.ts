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

describe('fnos mount manager status', () => {
  it('reports disk state, mount state and automount state', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "active"
`,
    )
    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  printf '%s\\n' "/mnt/local/books/bookDisk"
  exit 0
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  printf '%s\\n' "/mnt/local/books/bookDisk"
  exit 0
fi
exit 0
`,
    )

    const result = runSource(workspace, ['status'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('bookDisk')
    expect(result.stdout).toContain('classification: mounted_expected')
    expect(result.stdout).toContain('mounted: yes')
    expect(result.stdout).toContain('automount_state: active')
  })

  it('reports when a disk is mounted at a different target', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "inactive"
`,
    )
    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  exit 1
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  printf '%s\\n' "/vol00/WDC WD40EZRZ-00GXCB0"
  exit 0
fi
exit 0
`,
    )

    const result = runSource(workspace, ['status'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('classification: mounted_elsewhere')
    expect(result.stdout).toContain('mounted: no')
    expect(result.stdout).toContain(
      'mounted_elsewhere: /vol00/WDC WD40EZRZ-00GXCB0',
    )
  })

  it('decodes escaped findmnt targets before printing mounted_elsewhere', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "inactive"
`,
    )
    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-M" ]]; then
  exit 1
fi
if [[ "\${1:-}" == "-rn" && "\${2:-}" == "-S" ]]; then
  printf '%s\\n' "/vol00/WDC\\x20WD40EZRZ-00GXCB0"
  exit 0
fi
exit 0
`,
    )

    const result = runSource(workspace, ['status'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain(
      'mounted_elsewhere: /vol00/WDC WD40EZRZ-00GXCB0',
    )
  })

  it('continues printing later disks when the first device is not mounted', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    ensureFakeDevice(workspace, 'LABEL:local-book')
    ensureFakeDevice(workspace, 'UUID:local-debut')

    installMockCommand(
      workspace,
      'systemctl',
      `#!/usr/bin/env bash
set -eu
printf '%s\\n' "inactive"
`,
    )
    installMockCommand(
      workspace,
      'findmnt',
      `#!/usr/bin/env bash
set -eu
exit 1
`,
    )

    const result = runSource(workspace, ['status'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('bookDisk')
    expect(result.stdout).toContain('classification: not_mounted')
    expect(result.stdout).toContain('debutDisk')
  })
})
