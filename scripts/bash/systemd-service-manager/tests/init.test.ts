import fs from 'node:fs'
import path from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import {
  cleanupWorkspace,
  createWorkspace,
  readText,
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
})
