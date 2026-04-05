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
printf '%s\\n' "/mnt/local/books/bookDisk"
`,
    )

    const result = runSource(workspace, ['status'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('bookDisk')
    expect(result.stdout).toContain('mounted: yes')
    expect(result.stdout).toContain('automount_state: active')
  })
})
