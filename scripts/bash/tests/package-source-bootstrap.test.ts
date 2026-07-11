import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  configPath: string
  capturePath: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const bootstrapScript = path.join(
  repoRoot,
  'scripts/bash/package-source-bootstrap.sh',
)

/**
 * 创建 Stage 0 helper 测试工作区。
 *
 * @returns 配置与命令输出均隔离的工作区。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'source-bootstrap-'))
  const configPath = path.join(root, 'bootstrap.env')
  const capturePath = path.join(root, 'capture.txt')
  fs.writeFileSync(
    configPath,
    [
      'HOMEBREW_BREW_GIT_REMOTE=https://mirror.example/git/homebrew/brew.git',
      'HOMEBREW_CORE_GIT_REMOTE=https://mirror.example/git/homebrew/homebrew-core.git',
      'HOMEBREW_API_DOMAIN=https://mirror.example/homebrew-bottles/api',
      'HOMEBREW_BOTTLE_DOMAIN=https://mirror.example/homebrew-bottles',
      '',
    ].join('\n'),
    'utf8',
  )
  return { root, configPath, capturePath }
}

/**
 * 执行 Stage 0 helper，并用子命令记录 Homebrew 环境变量。
 *
 * @param workspace 隔离工作区。
 * @param mode Direct、China 或 Auto。
 * @param probeOverride Auto 测试探测覆盖。
 * @returns execa 执行结果。
 */
async function runBootstrap(
  workspace: Workspace,
  mode: 'Direct' | 'China' | 'Auto',
  probeOverride?: 'healthy' | 'unhealthy',
) {
  return execa(
    'bash',
    [
      bootstrapScript,
      '--mode',
      mode,
      '--target',
      'brew',
      '--config',
      workspace.configPath,
      '--',
      'bash',
      '-c',
      `printf "%s" "\${HOMEBREW_BOTTLE_DOMAIN-}" > "$CAPTURE_PATH"`,
    ],
    {
      cwd: workspace.root,
      env: {
        ...process.env,
        CAPTURE_PATH: workspace.capturePath,
        POWERSHELL_SCRIPTS_BOOTSTRAP_PROBE_RESULT: probeOverride,
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

describe('scripts/bash/package-source-bootstrap.sh', () => {
  it('Direct runs the command without mirror variables', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBootstrap(workspace, 'Direct')

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(workspace.capturePath, 'utf8')).toBe('')
  })

  it('China injects configured Homebrew mirror variables', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBootstrap(workspace, 'China')

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(workspace.capturePath, 'utf8')).toBe(
      'https://mirror.example/homebrew-bottles',
    )
  })

  it('Auto keeps official source when the probe is healthy', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBootstrap(workspace, 'Auto', 'healthy')

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(workspace.capturePath, 'utf8')).toBe('')
  })

  it('Auto temporarily injects mirrors when the official probe fails', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBootstrap(workspace, 'Auto', 'unhealthy')

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(workspace.capturePath, 'utf8')).toBe(
      'https://mirror.example/homebrew-bottles',
    )
  })
})
