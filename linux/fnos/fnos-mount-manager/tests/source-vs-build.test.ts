import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  ensureFakeDevice,
  installMockCommand,
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

  it('keeps reconcile help and no-op summary aligned across source and build outputs', () => {
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
  printf '%s\\n' "\${3:-}"
  exit 0
fi
exit 1
`,
    )

    expect(runBuild(workspace).exitCode).toBe(0)

    const sourceHelp = runSource(workspace, ['reconcile', '--help'])
    const binHelp = runBuilt(workspace, 'bin', ['reconcile', '--help'])
    const localHelp = runBuilt(workspace, 'local', ['reconcile', '--help'])
    const sourceRun = runSource(workspace, ['reconcile'])
    const binRun = runBuilt(workspace, 'bin', ['reconcile'])
    const localRun = runBuilt(workspace, 'local', ['reconcile'])

    expect(sourceHelp.exitCode).toBe(0)
    expect(binHelp.exitCode).toBe(0)
    expect(localHelp.exitCode).toBe(0)
    expect(binHelp.stdout).toBe(sourceHelp.stdout)
    expect(localHelp.stdout).toBe(sourceHelp.stdout)
    expect(sourceRun.exitCode).toBe(0)
    expect(binRun.exitCode).toBe(0)
    expect(localRun.exitCode).toBe(0)
    expect(binRun.stdout).toBe(sourceRun.stdout)
    expect(localRun.stdout).toBe(sourceRun.stdout)
    expect(binRun.stderr).toBe(sourceRun.stderr)
    expect(localRun.stderr).toBe(sourceRun.stderr)
  })
})
