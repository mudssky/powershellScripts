import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

type Workspace = {
  root: string
  home: string
  bin: string
  brewPrefix: string
  log: string
}

const repoRoot = path.resolve(__dirname, '../../..')
const atuinScript = path.join(repoRoot, 'shell/shared.d/90-atuin.sh')
const autosuggestionsScript = path.join(repoRoot, 'shell/zsh.d/95-zsh-autosuggestions.zsh')
const syntaxHighlightingScript = path.join(repoRoot, 'shell/zsh.d/zzz-zsh-syntax-highlighting.zsh')
const workspaces: Workspace[] = []

/**
 * 创建隔离的 Zsh 插件测试工作区。
 *
 * @returns 临时 HOME、命令目录、Homebrew 前缀和调用日志路径。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'zsh-plugins-'))
  const workspace = {
    root,
    home: path.join(root, 'home'),
    bin: path.join(root, 'bin'),
    brewPrefix: path.join(root, 'homebrew'),
    log: path.join(root, 'calls.log'),
  }
  fs.mkdirSync(workspace.home, { recursive: true })
  fs.mkdirSync(workspace.bin, { recursive: true })
  workspaces.push(workspace)
  return workspace
}

/**
 * 创建输出 Atuin Zsh 初始化脚本的替身。
 *
 * @param workspace 测试工作区。
 * @returns 创建后的 atuin 可执行文件路径。
 */
function writeAtuin(workspace: Workspace): string {
  const file = path.join(workspace.bin, 'atuin')
  const initialization = [
    'function atuin-search() { :; }',
    'zle -N atuin-search',
    'bindkey "^R" atuin-search',
    'export ATUIN_TEST_LOADED=1',
  ].join('; ')
  fs.writeFileSync(
    file,
    [
      '#!/bin/sh',
      'printf "atuin %s\\n" "$*" >> "$SHELL_TOOL_TEST_LOG"',
      `printf '%s\\n' ${JSON.stringify(initialization)}`,
      '',
    ].join('\n'),
    { mode: 0o755 },
  )
  return file
}

/**
 * 在临时 Homebrew 前缀写入插件脚本。
 *
 * @param workspace 测试工作区。
 * @param relativePath 相对 Homebrew 前缀的插件路径。
 * @param content 插件脚本内容。
 * @returns 创建后的插件文件路径。
 */
function writePlugin(workspace: Workspace, relativePath: string, content: string): string {
  const file = path.join(workspace.brewPrefix, relativePath)
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, `${content}\n`)
  return file
}

/**
 * 在隔离环境中执行 Zsh。
 *
 * @param workspace 测试工作区。
 * @param interactive 是否启用交互模式。
 * @param body 要执行的 Zsh 代码。
 * @returns Zsh 进程执行结果。
 */
async function runZsh(workspace: Workspace, interactive: boolean, body: string) {
  return execa('/bin/zsh', ['-f', interactive ? '-ic' : '-c', body], {
    cwd: workspace.root,
    env: {
      HOME: workspace.home,
      PATH: `${workspace.bin}:/usr/bin:/bin`,
      POWERSHELL_SCRIPTS_HOMEBREW_PREFIX: workspace.brewPrefix,
      SHELL_TOOL_TEST_LOG: workspace.log,
      SHELL: '/bin/zsh',
    },
    extendEnv: false,
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

const describeZsh = fs.existsSync('/bin/zsh') ? describe : describe.skip

describeZsh('Zsh 交互插件集成', () => {
  it('非交互式 Zsh 不加载插件', async () => {
    const workspace = createWorkspace()
    writePlugin(
      workspace,
      'share/zsh-autosuggestions/zsh-autosuggestions.zsh',
      'print -r -- autosuggestions >> "$SHELL_TOOL_TEST_LOG"',
    )
    writePlugin(
      workspace,
      'share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh',
      'print -r -- syntax-highlighting >> "$SHELL_TOOL_TEST_LOG"',
    )

    const result = await runZsh(
      workspace,
      false,
      `source "${autosuggestionsScript}"; source "${syntaxHighlightingScript}"`,
    )

    expect(result.exitCode).toBe(0)
    expect(fs.existsSync(workspace.log)).toBe(false)
  })

  it('Atuin 后加载 Autosuggestions 且 Syntax Highlighting 最后加载', async () => {
    const workspace = createWorkspace()
    writeAtuin(workspace)
    writePlugin(
      workspace,
      'share/zsh-autosuggestions/zsh-autosuggestions.zsh',
      [
        'print -r -- autosuggestions >> "$SHELL_TOOL_TEST_LOG"',
        'function _zsh_autosuggest_start() { :; }',
        'function autosuggest-accept() { :; }',
        'zle -N autosuggest-accept',
      ].join('\n'),
    )
    writePlugin(
      workspace,
      'share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh',
      [
        'print -r -- syntax-highlighting >> "$SHELL_TOOL_TEST_LOG"',
        'function _zsh_highlight() { :; }',
      ].join('\n'),
    )

    const result = await runZsh(
      workspace,
      true,
      [
        'up_before="$(bindkey "^[[A")"',
        `source "${atuinScript}"`,
        `source "${autosuggestionsScript}"`,
        `source "${syntaxHighlightingScript}"`,
        `source "${autosuggestionsScript}"`,
        `source "${syntaxHighlightingScript}"`,
        'up_after="$(bindkey "^[[A")"',
        'printf "ctrl-r=%s\\n" "$(bindkey "^R")"',
        'printf "up-preserved=%s\\n" "$([[ "$up_before" == "$up_after" ]] && print 1 || print 0)"',
        'printf "plugins=%s,%s\\n" "${__powershell_scripts_zsh_autosuggestions_initialized:-0}" "${__powershell_scripts_zsh_syntax_highlighting_initialized:-0}"',
        'printf "functions=%s,%s\\n" "$+functions[_zsh_autosuggest_start]" "$+functions[_zsh_highlight]"',
      ].join('; '),
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('ctrl-r="^R" atuin-search')
    expect(result.stdout).toContain('up-preserved=1')
    expect(result.stdout).toContain('plugins=1,1')
    expect(result.stdout).toContain('functions=1,1')
    expect(fs.readFileSync(workspace.log, 'utf8').trim().split('\n')).toEqual([
      'atuin init zsh --disable-up-arrow',
      'autosuggestions',
      'syntax-highlighting',
    ])
  })

  it('Autosuggestions 加载失败时安静降级且不阻断 Syntax Highlighting', async () => {
    const workspace = createWorkspace()
    writePlugin(
      workspace,
      'share/zsh-autosuggestions/zsh-autosuggestions.zsh',
      'print -r -- "autosuggestions failed" >&2; return 1',
    )
    writePlugin(
      workspace,
      'share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh',
      'function _zsh_highlight() { :; }; print -r -- syntax-highlighting >> "$SHELL_TOOL_TEST_LOG"',
    )

    const result = await runZsh(
      workspace,
      true,
      [
        `source "${autosuggestionsScript}"`,
        `source "${syntaxHighlightingScript}"`,
        'printf "%s,%s" "${__powershell_scripts_zsh_autosuggestions_initialized:-0}" "${__powershell_scripts_zsh_syntax_highlighting_initialized:-0}"',
      ].join('; '),
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('0,1')
    expect(result.stderr).not.toContain('autosuggestions failed')
    expect(fs.readFileSync(workspace.log, 'utf8').trim()).toBe('syntax-highlighting')
  })

  it('插件已由用户配置加载时不重复 source', async () => {
    const workspace = createWorkspace()
    writePlugin(
      workspace,
      'share/zsh-autosuggestions/zsh-autosuggestions.zsh',
      'print -r -- unexpected-autosuggestions >> "$SHELL_TOOL_TEST_LOG"',
    )
    writePlugin(
      workspace,
      'share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh',
      'print -r -- unexpected-highlighting >> "$SHELL_TOOL_TEST_LOG"',
    )

    const result = await runZsh(
      workspace,
      true,
      [
        'function _zsh_autosuggest_start() { :; }',
        'function _zsh_highlight() { :; }',
        `source "${autosuggestionsScript}"`,
        `source "${syntaxHighlightingScript}"`,
        'printf "%s,%s" "${__powershell_scripts_zsh_autosuggestions_initialized:-0}" "${__powershell_scripts_zsh_syntax_highlighting_initialized:-0}"',
      ].join('; '),
    )

    expect(result.exitCode).toBe(0)
    expect(result.stdout).toContain('1,1')
    expect(fs.existsSync(workspace.log)).toBe(false)
  })
  it('模块化加载器按 Atuin、Autosuggestions、prompt、Syntax Highlighting 排序', async () => {
    const workspace = createWorkspace()
    const configDir = path.join(workspace.home, '.bashrc.d')
    fs.mkdirSync(configDir, { recursive: true })
    writeAtuin(workspace)
    writePlugin(
      workspace,
      'share/zsh-autosuggestions/zsh-autosuggestions.zsh',
      'function _zsh_autosuggest_start() { :; }; print -r -- autosuggestions >> "$SHELL_TOOL_TEST_LOG"',
    )
    writePlugin(
      workspace,
      'share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh',
      'function _zsh_highlight() { :; }; print -r -- syntax-highlighting >> "$SHELL_TOOL_TEST_LOG"',
    )
    fs.symlinkSync(atuinScript, path.join(configDir, '90-atuin.sh'))
    fs.symlinkSync(autosuggestionsScript, path.join(configDir, '95-zsh-autosuggestions.sh'))
    fs.writeFileSync(path.join(configDir, 'zz-prompt.sh'), 'print -r -- prompt >> "$SHELL_TOOL_TEST_LOG"\n')
    fs.symlinkSync(syntaxHighlightingScript, path.join(configDir, 'zzz-zsh-syntax-highlighting.sh'))

    const result = await runZsh(
      workspace,
      true,
      `for rc in "${configDir}"/*.sh; do source "$rc"; done`,
    )

    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(workspace.log, 'utf8').trim().split('\n')).toEqual([
      'atuin init zsh --disable-up-arrow',
      'autosuggestions',
      'prompt',
      'syntax-highlighting',
    ])
  })
})
