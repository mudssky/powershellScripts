import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  configRoot: string
  scriptPath: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/shared.d/package-sources.sh')

/**
 * 创建 package source shell 测试工作区。
 *
 * @returns 隔离 HOME、配置根和待测脚本路径。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'package-sources-sh-'))
  const home = path.join(root, 'home')
  const configRoot = path.join(home, '.config')
  fs.mkdirSync(configRoot, { recursive: true })
  return { root, home, configRoot, scriptPath: sourceScript }
}

/**
 * 返回当前环境可执行的共享 shell。
 *
 * @returns 至少包含 bash；本机存在时追加 zsh。
 */
function getAvailableShells(): string[] {
  const shells = ['bash']
  if (fs.existsSync('/bin/zsh')) {
    shells.push('/bin/zsh')
  }
  return shells
}

/**
 * 在指定 shell 中 source package source snippet。
 *
 * @param shell shell 可执行文件。
 * @param workspace 隔离工作区。
 * @param body source 后执行的命令。
 * @returns execa 执行结果。
 */
async function runShell(shell: string, workspace: Workspace, body: string) {
  return execa(
    shell,
    ['-c', ['set -eu', `source "${workspace.scriptPath}"`, body].join('\n')],
    {
      cwd: workspace.root,
      env: {
        ...process.env,
        HOME: workspace.home,
        XDG_CONFIG_HOME: workspace.configRoot,
      },
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

describe('shell/shared.d/package-sources.sh', () => {
  for (const shell of getAvailableShells()) {
    it(`loads only strict HTTPS exports in ${path.basename(shell)}`, async () => {
      const workspace = createWorkspace()
      workspaces.push(workspace)
      const managedPath = path.join(
        workspace.configRoot,
        'powershellScripts/package-sources.env',
      )
      const maliciousPath = path.join(workspace.root, 'should-not-exist')
      fs.mkdirSync(path.dirname(managedPath), { recursive: true })
      fs.writeFileSync(
        managedPath,
        [
          '# powershellScripts package source: brew begin',
          'export HOMEBREW_BOTTLE_DOMAIN="https://mirror.example/bottles"',
          'export RUSTUP_DIST_SERVER="https://mirror.example/rustup"',
          `touch "${maliciousPath}"`,
          'export INVALID_HTTP="http://insecure.example"',
          'export UNRELATED_SOURCE="https://unrelated.example"',
          '# powershellScripts package source: brew end',
          '',
        ].join('\n'),
        'utf8',
      )

      const result = await runShell(
        shell,
        workspace,
        `printf "%s\n%s\ninvalid=%s\nunrelated=%s\n" "$HOMEBREW_BOTTLE_DOMAIN" "$RUSTUP_DIST_SERVER" "\${INVALID_HTTP-}" "\${UNRELATED_SOURCE-}"`,
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout.trim().split('\n')).toEqual([
        'https://mirror.example/bottles',
        'https://mirror.example/rustup',
        'invalid=',
        'unrelated=',
      ])
      expect(fs.existsSync(maliciousPath)).toBe(false)
    })
  }

  it('does nothing when the managed env file does not exist', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runShell(
      'bash',
      workspace,
      `printf "%s" "\${HOMEBREW_BOTTLE_DOMAIN-}"`,
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toBe('')
  })
})
