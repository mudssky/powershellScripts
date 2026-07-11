import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  osReleasePath: string
  procVersionPath: string
}

const repoRoot = path.resolve(__dirname, '../../..')
const workspaces: Workspace[] = []

/**
 * 写入文本文件并创建父目录。
 *
 * @param filePath 目标路径。
 * @param content 文件内容。
 * @returns 无返回值。
 */
function writeText(filePath: string, content: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content, 'utf8')
}

/**
 * 创建 Linux 安装脚本使用的隔离平台夹具。
 *
 * @param distributionId os-release 的 ID。
 * @param procVersion proc version 内容。
 * @returns 临时 HOME 与平台文件路径。
 */
function createWorkspace(
  distributionId = 'ubuntu',
  procVersion = 'Linux version 6.8.0-generic',
): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'linux-pipeline-'))
  const home = path.join(root, 'home')
  const osReleasePath = path.join(root, 'os-release')
  const procVersionPath = path.join(root, 'proc-version')
  fs.mkdirSync(home, { recursive: true })
  writeText(
    osReleasePath,
    `ID=${distributionId}\nID_LIKE=${distributionId === 'arch' ? 'arch' : 'debian'}\n`,
  )
  writeText(procVersionPath, `${procVersion}\n`)
  const workspace = { root, home, osReleasePath, procVersionPath }
  workspaces.push(workspace)
  return workspace
}

/**
 * 返回脚本共享的 Linux 平台覆盖环境。
 *
 * @param workspace 临时平台夹具。
 * @param extra 额外环境变量。
 * @returns 可传给 execa 的环境变量对象。
 */
function linuxEnv(
  workspace: Workspace,
  extra: Record<string, string | undefined> = {},
) {
  return {
    ...process.env,
    HOME: workspace.home,
    SHELL: '/bin/bash',
    POWERSHELL_SCRIPTS_UNAME_S: 'Linux',
    POWERSHELL_SCRIPTS_ARCHITECTURE: 'x86_64',
    POWERSHELL_SCRIPTS_OS_RELEASE_PATH: workspace.osReleasePath,
    POWERSHELL_SCRIPTS_PROC_VERSION_PATH: workspace.procVersionPath,
    WSL_INTEROP: undefined,
    WSL_DISTRO_NAME: undefined,
    ...extra,
  }
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

describe('Linux Stage 0 pipeline', () => {
  it('prints shallow clone and Stage 1 handoff in remote dry-run mode', async () => {
    const workspace = createWorkspace()
    const isolatedLinux = path.join(workspace.root, 'remote/linux')
    fs.mkdirSync(path.join(isolatedLinux, 'lib'), { recursive: true })
    fs.copyFileSync(
      path.join(repoRoot, 'linux/00quickstart.sh'),
      path.join(isolatedLinux, '00quickstart.sh'),
    )
    fs.copyFileSync(
      path.join(repoRoot, 'linux/lib/install-common.sh'),
      path.join(isolatedLinux, 'lib/install-common.sh'),
    )
    const repoDir = path.join(workspace.root, 'target repo')

    const result = await execa(
      'bash',
      [
        path.join(isolatedLinux, '00quickstart.sh'),
        '--repo-url',
        'https://example.invalid/config.git',
        '--repo-dir',
        repoDir,
        '--preset',
        'Full',
        '--dry-run',
      ],
      { env: linuxEnv(workspace), reject: false },
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('git clone --depth=1')
    expect(result.stdout).toContain('https://example.invalid/config.git')
    expect(result.stdout).toContain('01installHomeBrew.sh')
    expect(result.stdout).toContain('02installPowerShell.sh')
    expect(result.stdout).toContain('-Preset Full')
    expect(fs.existsSync(repoDir)).toBe(false)
  })

  it('blocks China before apt when a Stage 0 prerequisite is missing', async () => {
    const workspace = createWorkspace()
    const result = await execa(
      'bash',
      [path.join(repoRoot, 'linux/00quickstart.sh'), '--network-mode', 'China'],
      {
        env: linuxEnv(workspace, {
          POWERSHELL_SCRIPTS_FORCE_MISSING_APT_PREREQUISITES: '1',
        }),
        reject: false,
      },
    )

    expect(result.exitCode).toBe(10)
    expect(result.stderr).toContain('没有可恢复的 Stage 0 adapter')
  })

  it('previews the complete apt prerequisite set in Direct mode', async () => {
    const workspace = createWorkspace()
    const result = await execa(
      'bash',
      [path.join(repoRoot, 'linux/00quickstart.sh'), '--dry-run'],
      {
        env: linuxEnv(workspace, {
          POWERSHELL_SCRIPTS_FORCE_MISSING_APT_PREREQUISITES: '1',
        }),
        reject: false,
      },
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain(
      'apt-get install -y ca-certificates curl git build-essential',
    )
  })

  it('previews Linuxbrew and PowerShell without installing', async () => {
    const workspace = createWorkspace()
    const brew = await execa(
      'bash',
      [path.join(repoRoot, 'linux/01installHomeBrew.sh'), '--dry-run'],
      {
        env: linuxEnv(workspace, {
          POWERSHELL_SCRIPTS_FORCE_MISSING_BREW: '1',
        }),
        reject: false,
      },
    )
    const pwsh = await execa(
      'bash',
      [path.join(repoRoot, 'linux/02installPowerShell.sh'), '--dry-run'],
      {
        env: linuxEnv(workspace, {
          POWERSHELL_SCRIPTS_FORCE_MISSING_PWSH: '1',
        }),
        reject: false,
      },
    )

    expect(brew.exitCode).toBe(0)
    expect(brew.stdout + brew.stderr).toContain('下载 Homebrew 官方安装器')
    expect(pwsh.exitCode).toBe(0)
    expect(pwsh.stdout).toContain('最新稳定版下载 amd64 deb')
  })

  it('blocks non-Direct PowerShell bootstrap without a local package', async () => {
    const workspace = createWorkspace()
    const result = await execa(
      'bash',
      [
        path.join(repoRoot, 'linux/02installPowerShell.sh'),
        '--network-mode',
        'Auto',
      ],
      {
        env: linuxEnv(workspace, {
          POWERSHELL_SCRIPTS_FORCE_MISSING_PWSH: '1',
        }),
        reject: false,
      },
    )

    expect(result.exitCode).toBe(10)
    expect(result.stderr).toContain('请提供本地 deb 或预装 PowerShell 7')
  })
})

describe('Linux Stage 1 shell wrappers', () => {
  it('passes the distro and transaction to the PowerShell source helper', async () => {
    const workspace = createWorkspace('debian')
    const fakeBin = path.join(workspace.root, 'bin')
    const capturePath = path.join(workspace.root, 'pwsh-args.txt')
    writeText(
      path.join(fakeBin, 'pwsh'),
      [
        '#!/usr/bin/env bash',
        'printf "%s\\n" "$@" >"$CAPTURE_PATH"',
        'printf \'{"SchemaVersion":1,"ExitCode":0,"TransactionId":"tx-linux","Rollback":"restore"}\\n\'',
        '',
      ].join('\n'),
    )
    fs.chmodSync(path.join(fakeBin, 'pwsh'), 0o755)

    const result = await execa(
      'bash',
      [
        path.join(repoRoot, 'linux/03configureSources.sh'),
        '--network-mode',
        'China',
        '--transaction-id',
        'tx-linux',
        '--output-format',
        'json',
        '--dry-run',
      ],
      {
        env: linuxEnv(workspace, {
          PATH: `${fakeBin}:${process.env.PATH ?? ''}`,
          CAPTURE_PATH: capturePath,
        }),
        reject: false,
      },
    )

    expect(result.exitCode).toBe(0)
    expect(JSON.parse(result.stdout).TransactionId).toBe('tx-linux')
    const args = fs.readFileSync(capturePath, 'utf8')
    expect(args).toContain('-DistributionTarget\ndebian')
    expect(args).toContain('-NetworkMode\nChina')
    expect(args).toContain('-TransactionId\ntx-linux')
    expect(args).toContain('-WhatIf')
  })

  it('deploys shell config in dry-run with a temporary HOME', async () => {
    const workspace = createWorkspace()
    const result = await execa(
      'bash',
      [
        path.join(repoRoot, 'linux/04deployShellConfig.sh'),
        '--preset',
        'Core',
        '--shell',
        'bash',
        '--dry-run',
      ],
      { env: linuxEnv(workspace), reject: false },
    )

    expect(result.exitCode).toBe(0)
    expect(result.stderr).toContain('检测到目标 shell: bash')
    expect(fs.existsSync(path.join(workspace.home, '.bashrc'))).toBe(false)
    expect(fs.existsSync(path.join(workspace.home, '.bashrc.d'))).toBe(false)
  })

  it('loads Linuxbrew from the managed shell fragment without eval output', async () => {
    const workspace = createWorkspace()
    const prefix = path.join(workspace.home, '.linuxbrew')
    writeText(path.join(prefix, 'bin/brew'), '#!/usr/bin/env bash\nexit 0\n')
    fs.chmodSync(path.join(prefix, 'bin/brew'), 0o755)

    const result = await execa(
      'bash',
      [
        '-c',
        `source "${path.join(repoRoot, 'shell/shared.d/homebrew.sh')}"; printf '%s\\n%s' "$HOMEBREW_PREFIX" "$PATH"`,
      ],
      { env: linuxEnv(workspace), reject: false },
    )

    expect(result.exitCode).toBe(0)
    const [reportedPrefix, reportedPath] = result.stdout.split('\n')
    expect(reportedPrefix).toBe(prefix)
    expect(reportedPath.split(':')).toContain(path.join(prefix, 'bin'))
  })

  it('declares Linux support for the shared brew source target', () => {
    const catalog = JSON.parse(
      fs.readFileSync(
        path.join(repoRoot, 'config/network/package-sources.json'),
        'utf8',
      ),
    )

    expect(catalog.targets.brew.platforms).toContain('macos')
    expect(catalog.targets.brew.platforms).toContain('linux')
  })
})
