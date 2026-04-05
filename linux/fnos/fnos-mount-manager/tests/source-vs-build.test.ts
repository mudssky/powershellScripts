import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  runBuild,
  runBuilt,
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

describe('fnos mount manager source vs build parity', () => {
  it('keeps help output aligned across source, bin output and local sh output', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    expect(runBuild(workspace).exitCode).toBe(0)

    const sourceHelp = runSource(workspace, ['status', '--help'])
    const binHelp = runBuilt(workspace, 'bin', ['status', '--help'])
    const localHelp = runBuilt(workspace, 'local', ['status', '--help'])

    expect(sourceHelp.exitCode).toBe(0)
    expect(binHelp.exitCode).toBe(0)
    expect(localHelp.exitCode).toBe(0)
    expect(binHelp.stdout).toBe(sourceHelp.stdout)
    expect(localHelp.stdout).toBe(sourceHelp.stdout)
  })
})
