import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

const repoRoot = path.resolve(__dirname, '../../..')
const workspaces: string[] = []

/**
 * 创建 Linux 平台探测夹具。
 *
 * @param distributionId 发行版 ID。
 * @param procVersion 内核版本文本。
 * @returns 夹具路径。
 */
function createLinuxFixture(
  distributionId = 'ubuntu',
  procVersion = 'Linux version 6.8.0-generic',
) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ansible-host-prep-'))
  const osReleasePath = path.join(root, 'os-release')
  const procVersionPath = path.join(root, 'proc-version')
  fs.writeFileSync(
    osReleasePath,
    `ID=${distributionId}\nID_LIKE=${distributionId === 'arch' ? 'arch' : 'debian'}\n`,
  )
  fs.writeFileSync(procVersionPath, `${procVersion}\n`)
  workspaces.push(root)
  return { root, osReleasePath, procVersionPath }
}

afterEach(() => {
  while (workspaces.length > 0) {
    fs.rmSync(workspaces.pop()!, { recursive: true, force: true })
  }
})

describe('Ansible managed host preparation', () => {
  it('Linux preview outputs one JSON document without applying changes', async () => {
    const fixture = createLinuxFixture()
    const result = await execa(
      'bash',
      [
        path.join(repoRoot, 'linux/bootstrap/prepare-ansible-host.sh'),
        '--output-format',
        'json',
      ],
      {
        env: {
          ...process.env,
          POWERSHELL_SCRIPTS_UNAME_S: 'Linux',
          POWERSHELL_SCRIPTS_OS_RELEASE_PATH: fixture.osReleasePath,
          POWERSHELL_SCRIPTS_PROC_VERSION_PATH: fixture.procVersionPath,
          POWERSHELL_SCRIPTS_ARCHITECTURE: 'x86_64',
          POWERSHELL_SCRIPTS_ANSIBLE_PREP_SYSTEMD: '1',
          POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_INSTALLED: '1',
          POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_IP: '100.100.10.20',
          WSL_INTEROP: undefined,
          WSL_DISTRO_NAME: undefined,
        },
        reject: false,
      },
    )

    expect(result.exitCode).toBe(0)
    const document = JSON.parse(result.stdout)
    expect(document.Platform).toBe('Linux')
    expect(document.Operation).toBe('Preview')
    expect(document.Status).toBe('Preview')
    expect(document.TailscaleIPv4).toBe('100.100.10.20')
    expect(document.NextCommands).toContain(
      `ssh ${os.userInfo().username}@100.100.10.20`,
    )
  })

  it('Linux WSL fixture returns complete manual management guidance', async () => {
    const fixture = createLinuxFixture(
      'ubuntu',
      'Linux version 6.6.87.2-microsoft-standard-WSL2',
    )
    const result = await execa(
      'bash',
      [
        path.join(repoRoot, 'linux/bootstrap/prepare-ansible-host.sh'),
        '--output-format',
        'json',
      ],
      {
        env: {
          ...process.env,
          POWERSHELL_SCRIPTS_UNAME_S: 'Linux',
          POWERSHELL_SCRIPTS_OS_RELEASE_PATH: fixture.osReleasePath,
          POWERSHELL_SCRIPTS_PROC_VERSION_PATH: fixture.procVersionPath,
          POWERSHELL_SCRIPTS_ARCHITECTURE: 'x86_64',
        },
        reject: false,
      },
    )

    expect(result.exitCode).toBe(10)
    const document = JSON.parse(result.stdout)
    expect(document.Status).toBe('Blocked')
    expect(document.ManualSteps[0].VerifyCommand).toContain('wsl.exe -l -v')
  })

  it.runIf(fs.existsSync('/bin/zsh'))(
    'macOS preview emits login manual steps when Tailscale has no IP',
    async () => {
      const result = await execa(
        '/bin/zsh',
        [
          path.join(repoRoot, 'macos/bootstrap/prepare-ansible-host.zsh'),
          '--output-format',
          'json',
        ],
        {
          env: {
            ...process.env,
            POWERSHELL_SCRIPTS_UNAME_S: 'Darwin',
            POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_INSTALLED: '1',
            POWERSHELL_SCRIPTS_ANSIBLE_PREP_REMOTE_LOGIN: '1',
            POWERSHELL_SCRIPTS_ANSIBLE_PREP_TAILSCALE_IP: '',
            POWERSHELL_SCRIPTS_ANSIBLE_PREP_PYTHON_PATH: '/usr/bin/python3',
          },
          reject: false,
        },
      )

      expect(result.exitCode).toBe(0)
      const document = JSON.parse(result.stdout)
      expect(document.Platform).toBe('macOS')
      expect(document.Status).toBe('Preview')
      expect(document.ManualSteps.map((step: { Name: string }) => step.Name)).toContain(
        'LoginTailscale',
      )
      expect(document.ManualSteps[0]).toHaveProperty('Location')
      expect(document.ManualSteps[0]).toHaveProperty('VerifyCommand')
    },
  )
})
