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

describe('systemd service manager cli', () => {
  it('shows top-level help from the source entry and built binary', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const build = await runBuild(workspace)
    expect(build.exitCode).toBe(0)

    const sourceHelp = await runSource(workspace, ['help'])
    const builtHelp = await runBuilt(workspace, 'bin', ['help'])

    expect(sourceHelp.exitCode).toBe(0)
    expect(builtHelp.exitCode).toBe(0)
    expect(sourceHelp.stdout).toContain(
      'Usage: systemd-service-manager <command> [options]',
    )
    expect(sourceHelp.stdout).toContain('init       初始化当前项目的 deploy/systemd 模板骨架')
    expect(sourceHelp.stdout).toContain('install    渲染并安装 service/timer unit 到 systemd')
    expect(sourceHelp.stdout).toContain('--project <path>  指定项目根目录')
    expect(sourceHelp.stdout).toContain('--dry-run         只预览将执行的操作')
    expect(builtHelp.stdout).toBe(sourceHelp.stdout)
  })

  it('fails on unknown commands with a clear error', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runSource(workspace, ['unknown-command'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unknown command')
  })
})
