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

describe('fnos mount manager cli', () => {
  it('shows top-level help from the source entry and built binary', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    expect(runBuild(workspace).exitCode).toBe(0)

    const sourceHelp = runSource(workspace, ['help'])
    const builtHelp = runBuilt(workspace, 'bin', ['help'])

    expect(sourceHelp.exitCode).toBe(0)
    expect(builtHelp.exitCode).toBe(0)
    expect(sourceHelp.stdout).toContain(
      'Usage: fnos-mount-manager <command> [options]',
    )
    expect(builtHelp.stdout).toBe(sourceHelp.stdout)
  })

  it('fails on unknown commands with a clear error', () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = runSource(workspace, ['unknown-command'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unknown command')
  })
})
