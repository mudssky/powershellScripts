import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  shellDir: string
  profileSourceDir: string
  sharedDir: string
  bashDir: string
  zshDir: string
  profileConfigDir: string
  interactiveConfigDir: string
  scriptPath: string
}

type DeployOptions = {
  args?: string[]
  shell?: 'bash' | 'zsh'
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/deploy.sh')
const loginStart = '# >>> powershell-scripts login env >>>'
const loginEnd = '# <<< powershell-scripts login env <<<'
const interactiveStart = '# >>> powershell-scripts interactive env >>>'
const interactiveEnd = '# <<< powershell-scripts interactive env <<<'
const legacyLoader = '# Load modular configuration files from ~/.bashrc.d'

function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-deploy-'))
  const home = path.join(root, 'home')
  const shellDir = path.join(root, 'shell')
  const profileSourceDir = path.join(shellDir, 'profile.d')
  const sharedDir = path.join(shellDir, 'shared.d')
  const bashDir = path.join(shellDir, 'bash.d')
  const zshDir = path.join(shellDir, 'zsh.d')
  const profileConfigDir = path.join(home, '.profile.d')
  const interactiveConfigDir = path.join(home, '.bashrc.d')
  const scriptPath = path.join(shellDir, 'deploy.sh')

  for (const directory of [
    home,
    profileSourceDir,
    sharedDir,
    bashDir,
    zshDir,
  ]) {
    fs.mkdirSync(directory, { recursive: true })
  }
  fs.copyFileSync(sourceScript, scriptPath)
  fs.writeFileSync(
    path.join(profileSourceDir, '10-base.sh'),
    'export PROFILE_FIXTURE=loaded\n',
    'utf8',
  )
  fs.writeFileSync(
    path.join(sharedDir, '20-interactive.sh'),
    'export INTERACTIVE_FIXTURE=loaded\n',
    'utf8',
  )

  return {
    root,
    home,
    shellDir,
    profileSourceDir,
    sharedDir,
    bashDir,
    zshDir,
    profileConfigDir,
    interactiveConfigDir,
    scriptPath,
  }
}

async function runDeploy(
  workspace: Workspace,
  options: DeployOptions = {},
) {
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

function backupNames(workspace: Workspace): string[] {
  return fs
    .readdirSync(workspace.home)
    .filter((file) => file.endsWith('.bak'))
    .sort()
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) fs.rmSync(workspace.root, { recursive: true, force: true })
  }
})

describe('shell/deploy.sh snippet synchronization', () => {
  it('synchronizes profile and interactive directories while excluding templates', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const activeEnv = path.join(workspace.sharedDir, 'env.local.sh')
    fs.writeFileSync(activeEnv, '# private fixture\n', 'utf8')
    fs.writeFileSync(
      path.join(workspace.profileSourceDir, 'future.example.sh'),
      '# template\n',
      'utf8',
    )
    fs.writeFileSync(
      path.join(workspace.sharedDir, 'future.sample.sh'),
      '# template\n',
      'utf8',
    )

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    expect(
      fs.realpathSync(path.join(workspace.profileConfigDir, '10-base.sh')),
    ).toBe(fs.realpathSync(path.join(workspace.profileSourceDir, '10-base.sh')))
    expect(
      fs.realpathSync(
        path.join(workspace.interactiveConfigDir, 'env.local.sh'),
      ),
    ).toBe(fs.realpathSync(activeEnv))
    expect(
      fs.existsSync(path.join(workspace.profileConfigDir, 'future.example.sh')),
    ).toBe(false)
    expect(
      fs.existsSync(path.join(workspace.interactiveConfigDir, 'future.sample.sh')),
    ).toBe(false)
  })

  it('applies --exclude to both startup layers and removes stale links', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    fs.mkdirSync(workspace.profileConfigDir, { recursive: true })
    fs.mkdirSync(workspace.interactiveConfigDir, { recursive: true })
    fs.symlinkSync(
      path.join(workspace.profileSourceDir, 'removed.sh'),
      path.join(workspace.profileConfigDir, 'removed.sh'),
    )
    fs.symlinkSync(
      path.join(workspace.sharedDir, 'node.sh'),
      path.join(workspace.interactiveConfigDir, 'node.sh'),
    )

    const result = await runDeploy(workspace, { args: ['--exclude', '10-*'] })

    expect(result.exitCode).toBe(0)
    expect(fs.existsSync(path.join(workspace.profileConfigDir, '10-base.sh'))).toBe(
      false,
    )
    expect(() =>
      fs.lstatSync(path.join(workspace.profileConfigDir, 'removed.sh')),
    ).toThrow()
    expect(() =>
      fs.lstatSync(path.join(workspace.interactiveConfigDir, 'node.sh')),
    ).toThrow()
  })

  it('keeps the file system untouched in dry-run mode', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runDeploy(workspace, { args: ['--dry-run'] })

    expect(result.exitCode).toBe(0)
    expect(result.stderr).toContain('创建目录')
    expect(result.stderr).toContain('创建软链接')
    expect(result.stderr).toContain('有效 login profile')
    expect(fs.existsSync(workspace.profileConfigDir)).toBe(false)
    expect(fs.existsSync(workspace.interactiveConfigDir)).toBe(false)
    expect(fs.existsSync(path.join(workspace.home, '.profile'))).toBe(false)
    expect(fs.existsSync(path.join(workspace.home, '.bashrc'))).toBe(false)
    expect(backupNames(workspace)).toHaveLength(0)
  })
})

describe('shell/deploy.sh login profile selection and migration', () => {
  for (const [existing, expected] of [
    [[], '.profile'],
    [['.profile'], '.profile'],
    [['.bash_login', '.profile'], '.bash_login'],
    [['.bash_profile', '.bash_login', '.profile'], '.bash_profile'],
  ] as const) {
    it(`selects ${expected} when candidates are ${existing.join(', ') || 'absent'}`, async () => {
      const workspace = createWorkspace()
      workspaces.push(workspace)
      for (const name of existing) {
        fs.writeFileSync(path.join(workspace.home, name), `# user ${name}\n`, 'utf8')
      }

      const result = await runDeploy(workspace)

      expect(result.exitCode).toBe(0)
      const target = fs.readFileSync(path.join(workspace.home, expected), 'utf8')
      expect(target.split(loginStart)).toHaveLength(2)
      expect(target.split(loginEnd)).toHaveLength(2)
      expect(target).toContain('$HOME/.profile.d/')
      for (const name of ['.bash_profile', '.bash_login', '.profile']) {
        if (name !== expected && fs.existsSync(path.join(workspace.home, name))) {
          expect(fs.readFileSync(path.join(workspace.home, name), 'utf8')).not.toContain(
            loginStart,
          )
        }
      }
    })
  }

  it('migrates the managed block to a newly higher-priority profile', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    await runDeploy(workspace)
    fs.writeFileSync(path.join(workspace.home, '.bash_profile'), '# preferred\n', 'utf8')

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    expect(
      fs.readFileSync(path.join(workspace.home, '.bash_profile'), 'utf8'),
    ).toContain(loginStart)
    expect(fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')).not.toContain(
      loginStart,
    )
    expect(backupNames(workspace).some((name) => name.startsWith('.profile.'))).toBe(
      true,
    )
  })

  it('replaces a login block in place while preserving user content before and after it', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const original = [
      '# user top',
      'export EDITOR=vim',
      loginStart,
      'export STALE_MANAGED=1',
      loginEnd,
      '# user bottom',
      '',
    ].join('\n')
    fs.writeFileSync(path.join(workspace.home, '.profile'), original, 'utf8')

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    const updated = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')
    expect(updated.startsWith('# user top\nexport EDITOR=vim\n')).toBe(true)
    expect(updated.endsWith('# user bottom\n')).toBe(true)
    expect(updated).not.toContain('STALE_MANAGED')
    const backups = backupNames(workspace).filter((name) =>
      name.startsWith('.profile.'),
    )
    expect(backups).toHaveLength(1)
    expect(fs.readFileSync(path.join(workspace.home, backups[0]), 'utf8')).toBe(
      original,
    )
  })

  it('repairs a missing end marker and preserves content before the block', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    fs.writeFileSync(
      path.join(workspace.home, '.profile'),
      ['# user top', 'export EDITOR=vim', loginStart, 'export STALE=1', ''].join(
        '\n',
      ),
      'utf8',
    )

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    const profile = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')
    expect(profile.startsWith('# user top\nexport EDITOR=vim\n')).toBe(true)
    expect(profile).not.toContain('STALE')
    expect(profile.split(loginStart)).toHaveLength(2)
    expect(profile.split(loginEnd)).toHaveLength(2)
  })

  it('targets .zprofile for zsh without creating a Bash login profile', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runDeploy(workspace, { shell: 'zsh' })

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(path.join(workspace.home, '.zprofile'), 'utf8')).toContain(
      '$HOME/.profile.d/',
    )
    expect(fs.existsSync(path.join(workspace.home, '.profile'))).toBe(false)
  })
})

describe('shell/deploy.sh interactive loader', () => {
  it('migrates the legacy loader and preserves surrounding user content', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const legacy = [
      '# user top',
      legacyLoader,
      'if [ -d "$HOME/.bashrc.d" ]; then',
      '    for rc in "$HOME/.bashrc.d/"*.sh; do',
      '        if [ -f "$rc" ]; then',
      '            source "$rc"',
      '        fi',
      '    done',
      'fi',
      '# user bottom',
      '',
    ].join('\n')
    fs.writeFileSync(path.join(workspace.home, '.bashrc'), legacy, 'utf8')

    const result = await runDeploy(workspace)

    expect(result.exitCode).toBe(0)
    const bashrc = fs.readFileSync(path.join(workspace.home, '.bashrc'), 'utf8')
    expect(bashrc).not.toContain(legacyLoader)
    expect(bashrc.startsWith('# user top\n')).toBe(true)
    expect(bashrc.endsWith('# user bottom\n')).toBe(true)
    expect(bashrc.split(interactiveStart)).toHaveLength(2)
    expect(bashrc.split(interactiveEnd)).toHaveLength(2)
    expect(bashrc.indexOf('$HOME/.profile.d/')).toBeLessThan(
      bashrc.indexOf('$HOME/.bashrc.d/'),
    )
  })

  it('loads profile snippets in non-interactive rc execution without interactive pollution', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    await runDeploy(workspace)

    const result = await execa(
      'bash',
      [
        '-c',
        `. "${path.join(workspace.home, '.bashrc')}"; printf '%s:%s' "\${PROFILE_FIXTURE-}" "\${INTERACTIVE_FIXTURE-}"`,
      ],
      {
        env: { HOME: workspace.home, PATH: process.env.PATH ?? '/usr/bin:/bin' },
        extendEnv: false,
      },
    )

    expect(result.stdout).toBe('loaded:')
  })

  it('is idempotent and creates no backup when managed content is unchanged', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const first = await runDeploy(workspace)
    expect(first.exitCode).toBe(0)
    const profile = fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')
    const bashrc = fs.readFileSync(path.join(workspace.home, '.bashrc'), 'utf8')

    const second = await runDeploy(workspace)

    expect(second.exitCode).toBe(0)
    expect(second.stderr).toContain('已是最新')
    expect(fs.readFileSync(path.join(workspace.home, '.profile'), 'utf8')).toBe(profile)
    expect(fs.readFileSync(path.join(workspace.home, '.bashrc'), 'utf8')).toBe(bashrc)
    expect(backupNames(workspace)).toHaveLength(0)
  })
})
