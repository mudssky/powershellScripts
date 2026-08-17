import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  sharedDir: string
  configDir: string
  scriptPath: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/deploy.sh')

/**
 * 创建隔离 HOME 与最小 shell 目录，避免部署测试读取真实本机配置。
 *
 * @returns 临时仓库、HOME 与部署路径。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-deploy-'))
  const home = path.join(root, 'home')
  const shellDir = path.join(root, 'shell')
  const sharedDir = path.join(shellDir, 'shared.d')
  const configDir = path.join(home, '.bashrc.d')
  const scriptPath = path.join(shellDir, 'deploy.sh')

  fs.mkdirSync(sharedDir, { recursive: true })
  fs.mkdirSync(home, { recursive: true })
  fs.copyFileSync(sourceScript, scriptPath)

  return { root, home, sharedDir, configDir, scriptPath }
}

/**
 * 在隔离 HOME 中执行 Bash 部署。
 *
 * @param workspace 临时部署工作区。
 * @returns deploy.sh 执行结果。
 */
async function runDeploy(workspace: Workspace) {
  return execa('bash', [workspace.scriptPath, '--shell', 'bash'], {
    cwd: workspace.root,
    env: {
      HOME: workspace.home,
      SHELL: '/bin/bash',
      PATH: process.env.PATH ?? '/usr/bin:/bin',
    },
    extendEnv: false,
    reject: false,
  })
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

describe('shell/deploy.sh', () => {
  it('deploys env.local.sh while excluding environment templates', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const activeEnv = path.join(workspace.sharedDir, 'env.local.sh')

    fs.writeFileSync(activeEnv, '# private environment fixture\n', 'utf8')
    fs.writeFileSync(
      path.join(workspace.sharedDir, 'env.local.sh.example'),
      '# committed template fixture\n',
      'utf8',
    )
    fs.writeFileSync(
      path.join(workspace.sharedDir, 'future.example.sh'),
      '# defensively excluded example fixture\n',
      'utf8',
    )
    fs.writeFileSync(
      path.join(workspace.sharedDir, 'future.sample.sh'),
      '# defensively excluded sample fixture\n',
      'utf8',
    )

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    expect(
      fs.realpathSync(path.join(workspace.configDir, 'env.local.sh')),
    ).toBe(fs.realpathSync(activeEnv))
    expect(
      fs.existsSync(path.join(workspace.configDir, 'env.local.sh.example')),
    ).toBe(false)
    expect(
      fs.existsSync(path.join(workspace.configDir, 'future.example.sh')),
    ).toBe(false)
    expect(
      fs.existsSync(path.join(workspace.configDir, 'future.sample.sh')),
    ).toBe(false)
  })

  it('removes a stale symlink left by the previous template name', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    fs.mkdirSync(workspace.configDir, { recursive: true })
    const staleLink = path.join(workspace.configDir, 'env.local.example.sh')
    const removedSource = path.join(
      workspace.sharedDir,
      'env.local.example.sh',
    )
    fs.symlinkSync(removedSource, staleLink)

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    expect(() => fs.lstatSync(staleLink)).toThrow()
  })
})
