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

type DeployOptions = {
  args?: string[]
  shell?: 'bash' | 'zsh'
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/deploy.sh')
const markerStart = '# >>> powershell-scripts login env >>>'
const markerEnd = '# <<< powershell-scripts login env <<<'

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
 * @param options 目标 shell 与额外参数。
 * @returns deploy.sh 执行结果。
 */
async function runDeploy(workspace: Workspace, options: DeployOptions = {}) {
  const shell = options.shell ?? 'bash'
  return execa(
    'bash',
    [workspace.scriptPath, '--shell', shell, ...(options.args ?? [])],
    {
      cwd: workspace.root,
      env: {
        HOME: workspace.home,
        SHELL: shell === 'zsh' ? '/bin/zsh' : '/bin/bash',
        PATH: process.env.PATH ?? '/usr/bin:/bin',
      },
      extendEnv: false,
      reject: false,
    },
  )
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

describe('shell/deploy.sh login profile managed block', () => {
  it('writes a managed brew and fnm block into the bash login profile', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    expect(fs.existsSync(path.join(workspace.home, '.profile'))).toBe(true)
    const profile = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')
    // 空 HOME 首次写入：整份文件就是受管块。
    expect(profile.startsWith(`${markerStart}\n`)).toBe(true)
    expect(profile.split(markerStart)).toHaveLength(2)
    expect(profile.split(markerEnd)).toHaveLength(2)
    // brew 探测候选与 shared.d/homebrew.sh 一致，fnm 依赖 brew 恢复的 PATH。
    expect(profile).toContain('/home/linuxbrew/.linuxbrew')
    expect(profile).toContain('eval "$(fnm env)"')
    const brewSection = profile.indexOf('-- Homebrew')
    const fnmSection = profile.indexOf('-- fnm')
    expect(brewSection).toBeGreaterThan(0)
    expect(fnmSection).toBeGreaterThan(brewSection)
    expect(profile.indexOf(markerEnd)).toBeGreaterThan(fnmSection)
    // 新建文件不需要备份。
    expect(
      fs.readdirSync(workspace.home).filter((file) => file.endsWith('.bak')),
    ).toHaveLength(0)
  })

  it('replaces the managed block in place while keeping surrounding user content', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const original = [
      '# user top',
      'export EDITOR=vim',
      markerStart,
      'export STALE_MANAGED=1',
      markerEnd,
      '# user bottom',
      '',
    ].join('\n')
    fs.writeFileSync(path.join(workspace.home, '.profile'), original, 'utf8')

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    const updated = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')
    // marker 外用户内容原样保留，包括位置关系。
    expect(updated.startsWith('# user top\nexport EDITOR=vim\n')).toBe(true)
    expect(updated.endsWith('# user bottom\n')).toBe(true)
    // marker 之间旧段整段废弃并只保留一份新块。
    expect(updated).not.toContain('STALE_MANAGED')
    expect(updated.split(markerStart)).toHaveLength(2)
    expect(updated.split(markerEnd)).toHaveLength(2)
    expect(updated).toContain('eval "$(fnm env)"')
    // 写前生成时间戳 .bak，且内容等于写前文件。
    const backups = fs
      .readdirSync(workspace.home)
      .filter((file) => /^\.profile\.\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}\.bak$/.test(file))
    expect(backups).toHaveLength(1)
    expect(fs.readFileSync(path.join(workspace.home, backups[0]), 'utf8')).toBe(original)
  })

  it('is idempotent: rerunning adds no duplicate block or extra backup', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    await runDeploy(workspace)
    const snapshot = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')

    const second = await runDeploy(workspace)

    expect(second.exitCode).toBe(0)
    expect(second.stderr).toContain('已是最新')
    expect(fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')).toBe(snapshot)
    expect(
      fs.readdirSync(workspace.home).filter((file) => file.endsWith('.bak')),
    ).toHaveLength(0)
  })

  it('supports --dry-run without touching the login profile', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runDeploy(workspace, { args: ['--dry-run'] })

    expect(result.exitCode).toBe(0)
    expect(result.stderr).toMatch(/\[DRY\].*受管登录环境块/)
    expect(fs.existsSync(path.join(workspace.home, '.profile'))).toBe(false)
    expect(fs.existsSync(path.join(workspace.home, '.zprofile'))).toBe(false)
  })

  it('targets ~/.zprofile when deploying for zsh', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runDeploy(workspace, { shell: 'zsh' })

    expect(result.exitCode).toBe(0)
    expect(fs.existsSync(path.join(workspace.home, '.profile'))).toBe(false)
    const zprofile = fs.readFileSync(path.join(workspace.home, '.zprofile'), 'utf8')
    expect(zprofile).toContain(markerStart)
    expect(zprofile).toContain('eval "$(fnm env)"')
  })
})
