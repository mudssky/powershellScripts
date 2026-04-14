import { afterEach, describe, expect, it } from 'vitest'
import fs from 'node:fs'
import path from 'node:path'
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
    expect(sourceHelp.stdout).toContain('--start           安装完成后立即启动目标 unit')
    expect(sourceHelp.stdout).toContain('start 前需要目标 unit 已经 install')
    expect(builtHelp.stdout).toBe(sourceHelp.stdout)
  })

  it('fails on unknown commands with a clear error', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runSource(workspace, ['unknown-command'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stderr + result.stdout).toContain('Unknown command')
  })

  it('lists declared services and timers from the built binary', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const build = await runBuild(workspace)
    expect(build.exitCode).toBe(0)

    const projectRoot = path.join(workspace.root, 'demo-app')
    fs.cpSync(
      path.join(workspace.managerHome, 'tests', 'fixtures', 'project-basic'),
      projectRoot,
      { recursive: true },
    )

    const result = await runBuilt(workspace, 'bin', [
      'list',
      '--project',
      projectRoot,
    ])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('Services')
    expect(result.stdout).toContain('- api')
    expect(result.stdout).toContain('Timers')
    expect(result.stdout).toContain('- cleanup')
    expect(result.stdout).toContain('- restart-api')
  })
})
