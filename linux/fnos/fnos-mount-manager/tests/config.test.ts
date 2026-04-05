import fs from 'node:fs'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  readText,
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

describe('fnos mount manager config + generate', () => {
  it('renders example and local preview blocks from shell config files', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = runSource(workspace, ['generate'])

    expect(result.exitCode).toBe(0)
    expect(readText(workspace.exampleFstab)).toContain(
      'LABEL=example-book /mnt/example/bookDisk ntfs',
    )
    expect(readText(workspace.localFstab)).toContain(
      'LABEL=local-book /mnt/local/books/bookDisk ntfs',
    )
    expect(readText(workspace.localFstab)).toContain('x-systemd.automount')
    expect(readText(workspace.localFstab)).toContain(
      'UUID=local-debut /mnt/local/debutDisk ntfs',
    )
  })

  it('fails fast when config contains an unsupported mount mode', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const invalidConfig = `${readText(workspace.localConfig)}\ndisk "brokenDisk" "LABEL:oops" mode=invalid\n`
    fs.writeFileSync(workspace.localConfig, invalidConfig, 'utf8')

    const result = runSource(workspace, ['generate', '--scope', 'local'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unsupported mount mode')
  })
})
