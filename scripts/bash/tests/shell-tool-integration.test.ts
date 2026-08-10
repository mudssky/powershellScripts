import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  bin: string
  log: string
}

const repoRoot = path.resolve(__dirname, '../../..')
const carapaceScript = path.join(repoRoot, 'shell/shared.d/10-carapace.sh')
const atuinScript = path.join(repoRoot, 'shell/shared.d/90-atuin.sh')
const workspaces: Workspace[] = []

/**
 * 创建隔离的 Shell 工具测试工作区。
 *
 * @returns 临时 HOME、可执行目录和调用日志路径。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shell-tools-'))
  const home = path.join(root, 'home')
  const bin = path.join(root, 'bin')
  const log = path.join(root, 'calls.log')
  fs.mkdirSync(home, { recursive: true })
  fs.mkdirSync(bin, { recursive: true })
  const workspace = { root, home, bin, log }
  workspaces.push(workspace)
  return workspace
}

/**
 * 创建可记录参数并输出初始化脚本的工具替身。
 *
 * @param workspace 测试工作区。
 * @param name 工具命令名。
 * @param exportedVariable 初始化成功后写入的环境变量。
 * @param exitCode 工具退出码。
 * @returns 创建后的可执行文件路径。
 */
function writeTool(
  workspace: Workspace,
  name: 'carapace' | 'atuin',
  exportedVariable: string,
  exitCode = 0,
  initializationScript = `export ${exportedVariable}=1`,
): string {
  const file = path.join(workspace.bin, name)
  fs.writeFileSync(
    file,
    [
      '#!/bin/sh',
      `printf '${name} %s\\n' "$*" >> "$SHELL_TOOL_TEST_LOG"`,
      exitCode === 0 ? `printf '%s\\n' ${JSON.stringify(initializationScript)}` : '',
      `exit ${exitCode}`,
      '',
    ].join('\n'),
    { mode: 0o755 },
  )
  return file
}

/**
 * 在隔离环境中执行 Bash 或 Zsh。
 *
 * @param shell Shell 可执行文件。
 * @param workspace 测试工作区。
 * @param interactive 是否启用交互模式。
 * @param body 要执行的 Shell 代码。
 * @param inheritedShell 可选的继承 SHELL，用于验证当前进程 Shell 优先。
 * @returns execa 执行结果。
 */
async function runShell(
  shell: string,
  workspace: Workspace,
  interactive: boolean,
  body: string,
  inheritedShell?: string,
) {
  const name = path.basename(shell)
  const args = name === 'zsh'
    ? ['-f', interactive ? '-ic' : '-c', body]
    : ['--noprofile', '--norc', interactive ? '-ic' : '-c', body]

  return execa(shell, args, {
    cwd: workspace.root,
    env: {
      HOME: workspace.home,
      PATH: `${workspace.bin}:/usr/bin:/bin`,
      SHELL_TOOL_TEST_LOG: workspace.log,
      SHELL: inheritedShell ?? shell,
    },
    extendEnv: false,
    reject: false,
  })
}

/**
 * 返回当前环境可执行的目标 Shell。
 *
 * @returns Bash，以及本机存在时的 Zsh。
 */
function getAvailableShells(): string[] {
  const shells = ['/bin/bash']
  if (fs.existsSync('/bin/zsh')) {
    shells.push('/bin/zsh')
  }
  return shells
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

describe('Carapace 与 Atuin 共享 Shell 初始化', () => {
  for (const shell of getAvailableShells()) {
    const shellName = path.basename(shell)

    it(`非交互式 ${shellName} 不调用工具`, async () => {
      const workspace = createWorkspace()
      writeTool(workspace, 'carapace', 'CARAPACE_TEST_LOADED')
      writeTool(workspace, 'atuin', 'ATUIN_TEST_LOADED')

      const result = await runShell(
        shell,
        workspace,
        false,
        `source "${carapaceScript}"; source "${atuinScript}"`,
      )

      expect(result.exitCode).toBe(0)
      expect(fs.existsSync(workspace.log)).toBe(false)
    })

    it(`交互式 ${shellName} 缺少 Carapace 时安静降级`, async () => {
      const workspace = createWorkspace()

      const result = await runShell(
        shell,
        workspace,
        true,
        [
          `source "${carapaceScript}"`,
          'printf "%s" "${__powershell_scripts_carapace_initialized:-0}"',
        ].join('; '),
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('0')
      expect(fs.existsSync(workspace.log)).toBe(false)
    })

    it(`交互式 ${shellName} 使用正确参数且重复 source 只初始化一次`, async () => {
      const workspace = createWorkspace()
      writeTool(workspace, 'carapace', 'CARAPACE_TEST_LOADED')
      writeTool(workspace, 'atuin', 'ATUIN_TEST_LOADED')

      const result = await runShell(
        shell,
        workspace,
        true,
        [
          `source "${carapaceScript}"`,
          `source "${atuinScript}"`,
          `source "${carapaceScript}"`,
          `source "${atuinScript}"`,
          'printf "%s %s" "${CARAPACE_TEST_LOADED:-0}" "${ATUIN_TEST_LOADED:-0}"',
        ].join('; '),
      )

      const expectedAtuinShell = shellName === 'zsh' ? 'zsh' : 'bash'
      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('1 1')
      expect(fs.readFileSync(workspace.log, 'utf8').trim().split('\n')).toEqual([
        `carapace _carapace ${expectedAtuinShell}`,
        `atuin init ${expectedAtuinShell} --disable-up-arrow`,
      ])
    })

    it(`交互式 ${shellName} 忽略继承的相反 SHELL`, async () => {
      const workspace = createWorkspace()
      writeTool(workspace, 'carapace', 'CARAPACE_TEST_LOADED')
      const expectedShell = shellName === 'zsh' ? 'zsh' : 'bash'
      const inheritedShell = shellName === 'zsh' ? '/bin/bash' : '/bin/zsh'

      const result = await runShell(
        shell,
        workspace,
        true,
        [
          `source "${carapaceScript}"`,
          'printf "%s" "${CARAPACE_TEST_LOADED:-0}"',
        ].join('; '),
        inheritedShell,
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('1')
      expect(fs.readFileSync(workspace.log, 'utf8').trim()).toBe(
        `carapace _carapace ${expectedShell}`,
      )
    })

    it(`Carapace 生成脚本失败时 ${shellName} 安静降级且不标记成功`, async () => {
      const workspace = createWorkspace()
      writeTool(
        workspace,
        'carapace',
        'CARAPACE_TEST_LOADED',
        0,
        'printf "carapace eval failed\\n" >&2; false',
      )
      writeTool(workspace, 'atuin', 'ATUIN_TEST_LOADED')

      const result = await runShell(
        shell,
        workspace,
        true,
        [
          `source "${carapaceScript}"`,
          `source "${atuinScript}"`,
          'printf "%s %s" "${__powershell_scripts_carapace_initialized:-0}" "${ATUIN_TEST_LOADED:-0}"',
        ].join('; '),
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('0 1')
      expect(result.stderr).not.toContain('carapace eval failed')
      expect(fs.readFileSync(workspace.log, 'utf8')).toContain('atuin init')
    })

    it(`Carapace 失败不阻断 ${shellName} 的 Atuin 初始化`, async () => {
      const workspace = createWorkspace()
      writeTool(workspace, 'carapace', 'CARAPACE_TEST_LOADED', 1)
      writeTool(workspace, 'atuin', 'ATUIN_TEST_LOADED')

      const result = await runShell(
        shell,
        workspace,
        true,
        [
          `source "${carapaceScript}"`,
          `source "${atuinScript}"`,
          'printf "%s %s" "${CARAPACE_TEST_LOADED:-0}" "${ATUIN_TEST_LOADED:-0}"',
        ].join('; '),
      )

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('0 1')
      expect(fs.readFileSync(workspace.log, 'utf8')).toContain('atuin init')
    })
  }
})
