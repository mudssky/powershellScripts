import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  scriptPath: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/shared.d/path.sh')

/**
 * 创建隔离工作区，避免 PATH 测试污染真实 shell 环境。
 *
 * @returns 测试工作区路径集合。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'path-sh-'))
  return { root, scriptPath: sourceScript }
}

/**
 * 创建带有 shell/shared.d/path.sh 的临时仓库结构。
 *
 * @returns 测试工作区路径集合。
 */
function createFixtureRepository(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'path-sh-fixture-'))
  const scriptPath = path.join(root, 'shell/shared.d/path.sh')
  fs.mkdirSync(path.dirname(scriptPath), { recursive: true })
  fs.copyFileSync(sourceScript, scriptPath)
  return { root, scriptPath }
}

/**
 * 在隔离环境中 source path.sh 并输出最终 PATH 条目。
 *
 * @param workspace 测试工作区。
 * @param initialPath 初始 PATH 字符串。
 * @returns Bash 执行结果。
 */
async function runPathScript(workspace: Workspace, initialPath: string) {
  return execa(
    'bash',
    [
      '-lc',
      [
        'set -euo pipefail',
        `export PATH="${initialPath}"`,
        `source "${workspace.scriptPath}"`,
        'printf "%s\\n" "$PATH"',
      ].join('\n'),
    ],
    {
      cwd: workspace.root,
      env: {
        ...process.env,
        HOME: path.join(workspace.root, 'home'),
      },
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

describe('shell/shared.d/path.sh', () => {
  it('adds repository bin path even when bin directory does not exist yet', async () => {
    const workspace = createFixtureRepository()
    workspaces.push(workspace)

    const result = await runPathScript(workspace, '/usr/bin')
    const entries = result.stdout.trim().split(':')
    const expectedBin = path.join(fs.realpathSync(workspace.root), 'bin')

    expect(fs.existsSync(expectedBin)).toBe(false)
    expect(entries).toContain(expectedBin)
  })

  it('adds this repository bin path from the real shared script', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runPathScript(workspace, '/usr/bin')
    const entries = result.stdout.trim().split(':')
    const expectedBin = path.join(fs.realpathSync(repoRoot), 'bin')

    expect(entries).toContain(expectedBin)
  })

  it('keeps repository bin path idempotent when sourced repeatedly', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const expectedBin = path.join(fs.realpathSync(repoRoot), 'bin')
    const result = await execa(
      'bash',
      [
        '-lc',
        [
          'set -euo pipefail',
          'export PATH="/usr/bin"',
          `source "${workspace.scriptPath}"`,
          `source "${workspace.scriptPath}"`,
          'printf "%s\\n" "$PATH"',
        ].join('\n'),
      ],
      {
        cwd: workspace.root,
        env: {
          ...process.env,
          HOME: path.join(workspace.root, 'home'),
        },
      },
    )

    const entries = result.stdout.trim().split(':')
    expect(entries.filter((entry) => entry === expectedBin)).toHaveLength(1)
  })
})
