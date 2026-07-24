import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  mockBin: string
  scriptPath: string
}

const workspaces: Workspace[] = []
const repoRoot = path.resolve(__dirname, '../../..')
const sourceScript = path.join(repoRoot, 'shell/shared.d/claude-profile.sh')

/**
 * 写入文本文件，并自动创建父目录。
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
 * 创建隔离工作区，避免测试污染真实 HOME 和项目目录。
 *
 * @returns 测试工作区路径集合。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'claude-profile-'))
  const home = path.join(root, 'home')
  const mockBin = path.join(root, 'mock-bin')

  fs.mkdirSync(home, { recursive: true })
  fs.mkdirSync(mockBin, { recursive: true })

  return { root, home, mockBin, scriptPath: sourceScript }
}

/**
 * 在隔离环境中执行 Bash 片段，并预先 source claude-profile。
 *
 * @param workspace 测试工作区。
 * @param body 要执行的 Bash 片段。
 * @returns execa 执行结果。
 */
async function runProfile(workspace: Workspace, body: string) {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    HOME: workspace.home,
    PATH: `${workspace.mockBin}:${process.env.PATH ?? ''}`,
  }
  // 宿主可能设置 VISUAL=true 等非编辑器值；open_editor 优先读 VISUAL。
  delete env.VISUAL
  delete env.EDITOR

  return execa(
    'bash',
    [
      '-c',
      [
        'set -euo pipefail',
        // 显式清掉 login profile 可能带回的编辑器变量（配合 env 删除双保险）
        'unset VISUAL EDITOR',
        `source "${workspace.scriptPath}"`,
        body,
      ].join('\n'),
    ],
    {
      cwd: workspace.root,
      env,
      extendEnv: false,
      reject: false,
    },
  )
}

/**
 * 写入一个 Claude profile JSON。
 *
 * @param workspace 测试工作区。
 * @param name profile 名称。
 * @param env profile env 对象。
 * @returns profile 文件路径。
 */
function writeProfile(
  workspace: Workspace,
  name: string,
  env: Record<string, string>,
): string {
  const profilePath = path.join(workspace.home, '.claude/profiles', `${name}.json`)
  writeText(profilePath, JSON.stringify({ env }, null, 2))
  return profilePath
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

describe('shell/shared.d/claude-profile.sh', () => {
  it('merges a profile into project local settings without removing existing fields', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeProfile(workspace, 'glm', {
      ANTHROPIC_API_KEY: 'sk-ant-secret-123456',
      ANTHROPIC_BASE_URL: 'http://127.0.0.1:34000',
      ANTHROPIC_MODEL: 'cc-glmplan-opus',
    })
    writeText(
      path.join(workspace.root, '.claude/settings.local.json'),
      JSON.stringify({
        permissions: { allow: ['Read(*)'] },
        env: {
          EXISTING_ONLY: 'keep-me',
          ANTHROPIC_BASE_URL: 'http://old.example',
        },
      }),
    )

    const result = await runProfile(workspace, 'claude-profile use glm')

    expect(result.exitCode).toBe(0)
    const settings = JSON.parse(
      fs.readFileSync(
        path.join(workspace.root, '.claude/settings.local.json'),
        'utf8',
      ),
    )
    expect(settings.permissions.allow).toEqual(['Read(*)'])
    expect(settings.env.EXISTING_ONLY).toBe('keep-me')
    expect(settings.env.ANTHROPIC_BASE_URL).toBe('http://127.0.0.1:34000')
    expect(settings.env.ANTHROPIC_MODEL).toBe('cc-glmplan-opus')
    expect(settings.env.CLAUDE_PROFILE_NAME).toBe('glm')
  })

  it('runs claude with profile env and session settings without creating project settings', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeProfile(workspace, 'glm', {
      ANTHROPIC_API_KEY: 'profile-key',
      ANTHROPIC_BASE_URL: 'http://profile.example',
    })
    writeText(
      path.join(workspace.mockBin, 'claude'),
      [
        '#!/usr/bin/env bash',
        'printf "%s\\n" "$ANTHROPIC_API_KEY" >"$CLAUDE_CAPTURE_ENV"',
        'printf "%s\\n" "$ANTHROPIC_BASE_URL" >>"$CLAUDE_CAPTURE_ENV"',
        'printf "%s\\n" "$CLAUDE_PROFILE_NAME" >>"$CLAUDE_CAPTURE_ENV"',
        'printf "%s\\n" "$@" >"$CLAUDE_CAPTURE_ARGS"',
        'cp "$2" "$CLAUDE_CAPTURE_SETTINGS"',
        '',
      ].join('\n'),
    )
    fs.chmodSync(path.join(workspace.mockBin, 'claude'), 0o755)

    const captureEnv = path.join(workspace.root, 'env.txt')
    const captureArgs = path.join(workspace.root, 'args.txt')
    const captureSettings = path.join(workspace.root, 'settings.json')
    const result = await runProfile(
      workspace,
      [
        `export CLAUDE_CAPTURE_ENV="${captureEnv}"`,
        `export CLAUDE_CAPTURE_ARGS="${captureArgs}"`,
        `export CLAUDE_CAPTURE_SETTINGS="${captureSettings}"`,
        'export ANTHROPIC_API_KEY=global-key',
        'claude-profile run glm --version',
      ].join('\n'),
    )

    expect(result.exitCode).toBe(0)
    expect(fs.existsSync(path.join(workspace.root, '.claude/settings.local.json'))).toBe(
      false,
    )
    expect(fs.readFileSync(captureEnv, 'utf8').trim().split('\n')).toEqual([
      'profile-key',
      'http://profile.example',
      'glm',
    ])
    const args = fs.readFileSync(captureArgs, 'utf8').trim().split('\n')
    expect(args[0]).toBe('--settings')
    expect(args[1]).toMatch(/claude-profile-settings\..+$/)
    expect(JSON.parse(fs.readFileSync(captureSettings, 'utf8'))).toEqual({
      env: {
        ANTHROPIC_API_KEY: 'profile-key',
        ANTHROPIC_BASE_URL: 'http://profile.example',
        CLAUDE_PROFILE_NAME: 'glm',
      },
    })
    expect(args[2]).toBe('--version')
  })

  it('creates a profile template and opens the configured editor', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    const editorLog = path.join(workspace.root, 'editor.log')
    writeText(
      path.join(workspace.mockBin, 'fake-editor'),
      ['#!/usr/bin/env bash', 'printf "%s\\n" "$1" >"$EDITOR_LOG"', ''].join(
        '\n',
      ),
    )
    fs.chmodSync(path.join(workspace.mockBin, 'fake-editor'), 0o755)

    const result = await runProfile(
      workspace,
      [
        `export EDITOR_LOG="${editorLog}"`,
        'export EDITOR=fake-editor',
        'claude-profile add official',
      ].join('\n'),
    )

    expect(result.exitCode).toBe(0)
    const profilePath = path.join(
      workspace.home,
      '.claude/profiles/official.json',
    )
    expect(fs.existsSync(profilePath)).toBe(true)
    expect(JSON.parse(fs.readFileSync(profilePath, 'utf8')).env).toMatchObject({
      ANTHROPIC_API_KEY: '',
      CLAUDE_CODE_EFFORT_LEVEL: 'max',
    })
    expect(fs.readFileSync(editorLog, 'utf8').trim()).toBe(profilePath)
  })

  it('does not overwrite project settings when the selected profile is invalid', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeText(
      path.join(workspace.home, '.claude/profiles/bad.json'),
      JSON.stringify({ env: { BAD_VALUE: 1 } }),
    )
    const settingsPath = path.join(workspace.root, '.claude/settings.local.json')
    writeText(settingsPath, JSON.stringify({ env: { EXISTING_ONLY: 'keep-me' } }))
    const before = fs.readFileSync(settingsPath, 'utf8')

    const result = await runProfile(workspace, 'claude-profile use bad')

    expect(result.exitCode).toBe(1)
    expect(fs.readFileSync(settingsPath, 'utf8')).toBe(before)
  })

  it('rejects multiline env values before invoking claude', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeText(
      path.join(workspace.home, '.claude/profiles/bad.json'),
      JSON.stringify({ env: { ANTHROPIC_API_KEY: 'line1\nline2' } }),
    )
    writeText(
      path.join(workspace.mockBin, 'claude'),
      ['#!/usr/bin/env bash', 'exit 42', ''].join('\n'),
    )
    fs.chmodSync(path.join(workspace.mockBin, 'claude'), 0o755)

    const result = await runProfile(workspace, 'claude-profile run bad --version')

    expect(result.exitCode).toBe(1)
    expect(result.stderr).toContain('profile JSON 非法')
  })

  it('lists profiles with masked API keys', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeProfile(workspace, 'official', {
      ANTHROPIC_API_KEY: 'sk-ant-very-secret',
      ANTHROPIC_MODEL: 'opus',
    })

    const result = await runProfile(workspace, 'claude-profile list')

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('official')
    expect(result.stdout).toContain('model=opus')
    expect(result.stdout).toContain('key=sk-a...cret')
    expect(result.stdout).not.toContain('sk-ant-very-secret')
  })

  it('shows current project profile summary with masked API key', async () => {
    const workspace = createWorkspace()
    workspaces.push(workspace)
    writeProfile(workspace, 'glm', {
      ANTHROPIC_API_KEY: 'sk-ant-current-secret',
      ANTHROPIC_BASE_URL: 'http://127.0.0.1:34000',
      ANTHROPIC_MODEL: 'cc-glmplan-opus',
    })

    const result = await runProfile(
      workspace,
      'claude-profile use glm >/dev/null && claude-profile current',
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('profile: glm')
    expect(result.stdout).toContain('ANTHROPIC_BASE_URL: http://127.0.0.1:34000')
    expect(result.stdout).toContain('ANTHROPIC_MODEL: cc-glmplan-opus')
    expect(result.stdout).toContain('ANTHROPIC_API_KEY: sk-a...cret')
    expect(result.stdout).not.toContain('sk-ant-current-secret')
  })
})
