import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  buildScript: string
  binDir: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')

/**
 * 写入测试夹具文件，并自动创建父目录。
 *
 * @param filePath 目标文件路径。
 * @param content 文件内容。
 * @returns 无返回值。
 */
function writeText(filePath: string, content: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content, 'utf8')
}

/**
 * 创建最小化临时仓库，用于隔离验证 Bash 构建入口。
 *
 * @returns 包含仓库根目录、构建脚本路径与 bin 目录路径的工作区信息。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'bash-build-'))
  const buildScript = path.join(root, 'scripts/bash/build.sh')
  const binDir = path.join(root, 'bin')

  fs.mkdirSync(path.dirname(buildScript), { recursive: true })
  fs.copyFileSync(path.join(repoRoot, 'scripts/bash/build.sh'), buildScript)
  fs.chmodSync(buildScript, 0o755)

  writeText(
    path.join(root, 'scripts/bash/systemd-service-manager/build.sh'),
    [
      '#!/usr/bin/env bash',
      'set -Eeuo pipefail',
      'mkdir -p "$(cd "$(dirname "$0")/../../.." && pwd)/bin"',
      'printf "#!/usr/bin/env bash\\necho ssm\\n" >"$(cd "$(dirname "$0")/../../.." && pwd)/bin/systemd-service-manager"',
      'chmod +x "$(cd "$(dirname "$0")/../../.." && pwd)/bin/systemd-service-manager"',
      'printf "fake systemd build complete\\n"',
      '',
    ].join('\n'),
  )
  fs.chmodSync(path.join(root, 'scripts/bash/systemd-service-manager/build.sh'), 0o755)

  writeText(
    path.join(root, 'scripts/bash/aliyun-oss-put.sh'),
    ['#!/usr/bin/env bash', 'printf "aliyun\\n"', ''].join('\n'),
  )

  return { root, buildScript, binDir }
}

/**
 * 运行临时仓库中的 Bash 构建入口。
 *
 * @param workspace 临时工作区。
 * @param args 传递给构建脚本的命令行参数。
 * @returns execa 执行结果，包含 stdout、stderr 与退出码。
 */
async function runBuild(workspace: Workspace, args: string[] = []) {
  return execa('bash', [workspace.buildScript, ...args], {
    cwd: workspace.root,
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

describe('scripts/bash/build.sh', () => {
  it('lists build and copy targets with stable metadata', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--list'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('name=systemd-service-manager')
    expect(result.stdout).toContain('type=build')
    expect(result.stdout).toContain('source=scripts/bash/systemd-service-manager/build.sh')
    expect(result.stdout).toContain('output=<managed-by-target-build>')
    expect(result.stdout).toContain('name=aliyun-oss-put')
    expect(result.stdout).toContain('type=copy')
    expect(result.stdout).toContain('source=scripts/bash/aliyun-oss-put.sh')
    expect(result.stdout).toContain('output=bin/aliyun-oss-put')
  })

  it('copies single-file shell scripts into bin without the .sh suffix', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--only', 'aliyun-oss-put'])

    expect(result.exitCode).toBe(0)
    const outputPath = path.join(workspace.binDir, 'aliyun-oss-put')
    expect(fs.existsSync(outputPath)).toBe(true)
    expect(fs.readFileSync(outputPath, 'utf8')).toContain('printf "aliyun')
    expect(fs.statSync(outputPath).mode & 0o111).not.toBe(0)
    expect(result.stdout).toContain('args=--only aliyun-oss-put')
    expect(result.stdout).toContain('ACTION aliyun-oss-put copy source -> bin/aliyun-oss-put')
    expect(result.stdout).toContain('SUMMARY total=1 success=1 failed=0 skipped=0')
  })

  it('runs build targets and prints parsed jobs and task summaries', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const result = await runBuild(workspace, ['--jobs', '1'])

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('args=--jobs 1')
    expect(result.stdout).toContain('jobs=1 source=--jobs')
    expect(result.stdout).toContain('targets=2')
    expect(result.stdout).toContain('START systemd-service-manager type=build')
    expect(result.stdout).toContain('ACTION systemd-service-manager run build.sh')
    expect(result.stdout).toContain('DONE systemd-service-manager exit=0')
    expect(result.stdout).toContain('START aliyun-oss-put type=copy')
    expect(result.stdout).toContain('SUMMARY total=2 success=2 failed=0 skipped=0')
    expect(fs.existsSync(path.join(workspace.binDir, 'systemd-service-manager'))).toBe(true)
    expect(fs.existsSync(path.join(workspace.binDir, 'aliyun-oss-put'))).toBe(true)
  })

  it('returns non-zero with a failure summary for invalid targets', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    fs.rmSync(path.join(workspace.root, 'scripts/bash/aliyun-oss-put.sh'))

    const result = await runBuild(workspace, ['--only', 'aliyun-oss-put'])

    expect(result.exitCode).not.toBe(0)
    expect(result.stdout + result.stderr).toContain('FAIL aliyun-oss-put')
    expect(result.stdout + result.stderr).toContain('SUMMARY total=1 success=0 failed=1 skipped=0')
    expect(result.stdout + result.stderr).toContain('log=')
  })
})
