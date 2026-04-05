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

describe('fnos mount manager apply', () => {
  it('merges the managed block into a target fstab while preserving other entries', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    expect(runSource(workspace, ['generate']).exitCode).toBe(0)

    const result = runSource(workspace, [
      'apply',
      '--target',
      workspace.targetFstab,
    ])

    expect(result.exitCode).toBe(0)
    const targetContent = readText(workspace.targetFstab)
    expect(targetContent).toContain(
      'UUID=root-disk / ext4 errors=remount-ro 0 1',
    )
    expect(targetContent).toContain('# BEGIN FNOS MOUNT MANAGER')
    expect(targetContent).toContain(
      'LABEL=local-book /mnt/local/books/bookDisk ntfs',
    )
  })

  it('refuses to apply when the local preview is stale', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    expect(runSource(workspace, ['generate']).exitCode).toBe(0)

    fs.appendFileSync(
      workspace.localConfig,
      '\ndisk "newDisk" "LABEL:new-disk"\n',
    )
    const before = readText(workspace.targetFstab)

    const result = runSource(workspace, [
      'apply',
      '--target',
      workspace.targetFstab,
    ])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Local preview is stale')
    expect(readText(workspace.targetFstab)).toBe(before)
  })
})
