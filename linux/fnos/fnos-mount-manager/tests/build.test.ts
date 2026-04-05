import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  readText,
  runBuild,
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

describe('fnos mount manager build', () => {
  it('builds both the bin artifact and the fnos local copy', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = runBuild(workspace)

    expect(result.exitCode).toBe(0)
    expect(readText(workspace.builtBin)).toContain('FNOS_MANAGER_STANDALONE=1')
    expect(readText(workspace.builtLocal)).toContain(
      'FNOS_MANAGER_STANDALONE=1',
    )
    expect(readText(workspace.builtBin)).toBe(readText(workspace.builtLocal))
  })
})
