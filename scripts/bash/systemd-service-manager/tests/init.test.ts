import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  readText,
  runBuild,
  runCommand,
  runSource,
} from './test-utils'

const workspaces: ReturnType<typeof createWorkspace>[] = []

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      cleanupWorkspace(workspace)
    }
  }
})

describe('init command', () => {
  it('creates deploy/systemd with actual files, examples, and README', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const projectRoot = path.join(workspace.root, 'demo-app')
    fs.mkdirSync(projectRoot, { recursive: true })

    const result = await runSource(workspace, ['init', '--project', projectRoot])

    expect(result.exitCode).toBe(0)
    expect(
      fs.existsSync(path.join(projectRoot, 'deploy/systemd/README.md')),
    ).toBe(true)
    expect(
      fs.existsSync(
        path.join(projectRoot, 'deploy/systemd/project.conf.example'),
      ),
    ).toBe(true)
    expect(
      fs.existsSync(path.join(projectRoot, 'deploy/systemd/project.conf')),
    ).toBe(true)
    expect(
      fs.existsSync(
        path.join(projectRoot, 'deploy/systemd/services/api.conf.example'),
      ),
    ).toBe(true)
    expect(
      fs.existsSync(path.join(projectRoot, 'deploy/systemd/timers/cleanup.conf')),
    ).toBe(true)
    expect(readText(path.join(projectRoot, 'deploy/systemd/README.md'))).toContain(
      'DEFAULT_SCOPE=system',
    )
  })

  it('can init from a copied standalone script without colocated templates', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)

    const build = await runBuild(workspace)
    expect(build.exitCode).toBe(0)

    const portableRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'ssm-portable-'))
    const portableScript = path.join(portableRoot, 'systemd-service-manager.sh')
    const projectRoot = path.join(portableRoot, 'demo-app')

    fs.copyFileSync(workspace.builtLocal, portableScript)
    fs.chmodSync(portableScript, 0o755)
    fs.mkdirSync(projectRoot, { recursive: true })

    const result = await runCommand(
      'bash',
      [portableScript, 'init', '--project', projectRoot],
      workspace,
      { HOME: workspace.home },
    )

    expect(result.exitCode).toBe(0)
    expect(
      fs.existsSync(path.join(projectRoot, 'deploy/systemd/project.conf')),
    ).toBe(true)
    expect(
      fs.existsSync(
        path.join(projectRoot, 'deploy/systemd/services/api.conf.example'),
      ),
    ).toBe(true)
    expect(readText(path.join(projectRoot, 'deploy/systemd/README.md'))).toContain(
      'DEFAULT_SCOPE=system',
    )

    fs.rmSync(portableRoot, { recursive: true, force: true })
  })
})
