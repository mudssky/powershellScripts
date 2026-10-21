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
const sourceScript = path.join(repoRoot, 'shell/shared.d/ai.sh')
const workspaces: Workspace[] = []

/**
 * 创建隔离的 agent-task 测试工作区。
 *
 * @returns 临时根目录、HOME、PATH 目录和调用日志路径。
 */
function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'agent-task-'))
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
 * 将字符串编码为可嵌入 Shell 命令的单个参数。
 *
 * @param value 原始参数值。
 * @returns Shell 单引号形式的安全字面量。
 */
function shellQuote(value: string): string {
  return `'${value.replaceAll("'", `'"'"'`)}'`
}

/**
 * 创建记录环境变量、参数边界和指定退出码的宿主替身。
 *
 * @param workspace 测试工作区。
 * @param name 宿主命令名。
 * @returns 创建后的可执行文件路径。
 */
function writeFakeHost(
  workspace: Workspace,
  name: 'pi' | 'omp' | 'codex',
): string {
  const file = path.join(workspace.bin, name)
  fs.writeFileSync(
    file,
    [
      '#!/bin/sh',
      '{',
      '  printf "command=%s\\n" "$(basename "$0")"',
      '  printf "profile=%s\\n" "$(cat "$HOME/profile" 2>/dev/null)"',
      '  printf "argc=%s\\n" "$#"',
      '  index=0',
      '  for argument in "$@"; do',
      '    printf "arg[%s]=<%s>\\n" "$index" "$argument"',
      '    index=$((index + 1))',
      '  done',
      '} >> "$AGENT_TASK_TEST_LOG"',
      'exit "${AGENT_TASK_TEST_EXIT_CODE:-0}"',
      '',
    ].join('\n'),
    { mode: 0o755 },
  )
  return file
}

/**
 * 创建供 pi-mode 显式加载的本地 Web 扩展占位文件。
 *
 * @param workspace 测试工作区。
 * @param agentDir 可选的 Pi agentDir；默认使用 HOME 下标准路径。
 * @returns Web 扩展入口绝对路径。
 */
function writeWebExtension(
  workspace: Workspace,
  agentDir = path.join(workspace.home, '.pi/agent'),
): string {
  const file = path.join(agentDir, 'npm/node_modules/pi-web-access/index.ts')
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(file, 'export default function () {}\n')
  return file
}

/**
 * 格式化 fake host 应写入的稳定调用日志。
 *
 * @param command 宿主命令名。
 * @param profile Pi 持久化 profile；其它宿主传空字符串。
 * @param args 预期收到的 argv。
 * @returns 与 fake host 输出一致的日志文本。
 */
function formatFakeHostLog(
  command: string,
  profile: string,
  args: string[],
): string {
  return [
    `command=${command}`,
    `profile=${profile}`,
    `argc=${args.length}`,
    ...args.map((argument, index) => `arg[${index}]=<${argument}>`),
    '',
  ].join('\n')
}

/**
 * 创建覆盖 cwd、祖先与 Git 根的项目 Skill 目录树。
 *
 * @param workspace 测试工作区。
 * @returns 执行 cwd 与 project mode 应生成的固定参数。
 */
async function createProjectSkillTree(
  workspace: Workspace,
): Promise<{ cwd: string; fixedArgs: string[] }> {
  const repo = path.join(workspace.root, 'repo')
  const cwd = path.join(repo, 'packages/demo')
  const directories = [
    path.join(cwd, '.pi/skills'),
    path.join(cwd, '.agents/skills'),
    path.join(repo, 'packages/.agents/skills'),
    path.join(repo, '.agents/skills'),
    path.join(repo, '.pi/skills'),
    path.join(workspace.root, '.agents/skills'),
  ]

  for (const directory of directories) {
    fs.mkdirSync(directory, { recursive: true })
  }
  await execa('git', ['init', '-q', repo])

  const physicalCwd = fs.realpathSync(cwd)
  const physicalRepo = fs.realpathSync(repo)
  return {
    cwd,
    fixedArgs: [
      '--no-skills',
      '--skill',
      path.join(physicalCwd, '.pi/skills'),
      '--skill',
      path.join(physicalCwd, '.agents/skills'),
      '--skill',
      path.join(physicalRepo, 'packages/.agents/skills'),
      '--skill',
      path.join(physicalRepo, '.agents/skills'),
    ],
  }
}

/**
 * 在隔离环境中 source ai.sh 并执行测试命令。
 *
 * @param shell Shell 可执行文件。
 * @param workspace 测试工作区。
 * @param body 要执行的 Shell 代码。
 * @param extraEnv 可选的额外环境变量。
 * @returns execa 执行结果。
 */
async function runShell(
  shell: string,
  workspace: Workspace,
  body: string,
  extraEnv: NodeJS.ProcessEnv = {},
) {
  const shellName = path.basename(shell)
  const args =
    shellName === 'zsh'
      ? ['-f', '-c', `source ${shellQuote(sourceScript)}\n${body}`]
      : [
          '--noprofile',
          '--norc',
          '-c',
          `source ${shellQuote(sourceScript)}\n${body}`,
        ]

  return execa(shell, args, {
    cwd: workspace.root,
    env: {
      HOME: workspace.home,
      PATH: `${workspace.bin}:/usr/bin:/bin`,
      AGENT_TASK_TEST_LOG: workspace.log,
      ...extraEnv,
    },
    extendEnv: false,
    reject: false,
  })
}

/**
 * 返回当前机器可用于兼容性验证的 Shell。
 *
 * @returns Bash，以及存在时的 Zsh。
 */
function getAvailableShells(): string[] {
  const shells = ['/bin/bash']
  if (fs.existsSync('/bin/zsh')) {
    shells.push('/bin/zsh')
  }
  return shells
}

/**
 * 读取宿主替身的调用日志。
 *
 * @param workspace 测试工作区。
 * @returns 日志文本；宿主未执行时返回空字符串。
 */
function readLog(workspace: Workspace): string {
  return fs.existsSync(workspace.log)
    ? fs.readFileSync(workspace.log, 'utf8')
    : ''
}

afterEach(() => {
  while (workspaces.length > 0) {
    const workspace = workspaces.pop()
    if (workspace) {
      fs.rmSync(workspace.root, { recursive: true, force: true })
    }
  }
})

/** 创建模拟原生 profile 切换的 helper，失败时禁止启动宿主。 */
function writeProfileHelper(
  workspace: Workspace,
  agentDir = path.join(workspace.home, '.pi/agent'),
) {
  const file = path.join(agentDir, 'scripts/sync_config.py')
  fs.mkdirSync(path.dirname(file), { recursive: true })
  fs.writeFileSync(
    file,
    `import os, pathlib, sys
assert sys.argv[1] == "profile"
if os.environ.get("PROFILE_FAIL"):
    sys.exit(37)
pathlib.Path(os.environ["HOME"], "profile").write_text(sys.argv[2])
`,
  )
}

describe('shell/shared.d/ai.sh agent-task', () => {
  for (const shell of getAvailableShells()) {
    const shellName = path.basename(shell)
    for (const profile of ['default', 'sol']) {
      for (const host of ['pi', 'omp'] as const) {
        for (const mode of host === 'pi'
          ? ['full', 'project', 'no-skill']
          : ['full', 'no-skill']) {
          it(`${shellName} ${host} ${profile}/${mode} 切换子任务预设并保留主模型和参数边界`, async () => {
            const workspace = createWorkspace()
            writeFakeHost(workspace, host)
            writeProfileHelper(workspace)
            const overlay = path.join(
              workspace.home,
              `.omp/overlays/task-${profile}.yml`,
            )
            fs.mkdirSync(path.dirname(overlay), { recursive: true })
            fs.writeFileSync(overlay, 'modelRoles: {}')
            let prefix = ''
            let modeArgs = mode === 'no-skill' ? ['--no-skills'] : []
            if (mode === 'project') {
              const project = await createProjectSkillTree(workspace)
              prefix = `cd ${shellQuote(project.cwd)}; `
              modeArgs = project.fixedArgs
            }
            const result = await runShell(
              shell,
              workspace,
              `${prefix}agent-task ${host} ${profile} --mode ${mode} --show-command -- --model 'parent model' 'secret text' ''`,
              { AGENT_TASK_TEST_EXIT_CODE: '23' },
            )
            expect(result.exitCode).toBe(23)
            expect(result.stderr).not.toContain('secret text')
            expect(readLog(workspace)).toBe(
              formatFakeHostLog(host, host === 'pi' ? profile : '', [
                ...(host === 'omp' ? ['--config', overlay] : []),
                ...modeArgs,
                '--model',
                'parent model',
                'secret text',
                '',
              ]),
            )
          })
        }
        it(`${shellName} ${host} ${profile} dry-run 无写入、无宿主执行`, async () => {
          const workspace = createWorkspace()
          writeFakeHost(workspace, host)
          writeProfileHelper(workspace)
          const overlay = path.join(
            workspace.home,
            `.omp/overlays/task-${profile}.yml`,
          )
          fs.mkdirSync(path.dirname(overlay), { recursive: true })
          fs.writeFileSync(overlay, '')
          const result = await runShell(
            shell,
            workspace,
            `agent-task ${host} ${profile} --dry-run -- 'sensitive prompt'`,
          )
          expect(result.exitCode).toBe(0)
          expect(result.stderr).not.toContain('sensitive prompt')
          expect(readLog(workspace)).toBe('')
          expect(fs.existsSync(path.join(workspace.home, 'profile'))).toBe(
            false,
          )
        })
      }
    }
    it(`${shellName} Pi helper 失败或缺失时不启动，支持自定义 agentDir`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const agentDir = path.join(workspace.root, 'custom agent')
      const missing = await runShell(
        shell,
        workspace,
        'agent-task pi default',
        { PI_CODING_AGENT_DIR: agentDir },
      )
      expect(missing.exitCode).not.toBe(0)
      expect(readLog(workspace)).toBe('')
      writeProfileHelper(workspace, agentDir)
      const failed = await runShell(shell, workspace, 'agent-task pi sol', {
        PI_CODING_AGENT_DIR: agentDir,
        PROFILE_FAIL: '1',
      })
      expect(failed.exitCode).toBe(37)
      expect(readLog(workspace)).toBe('')
      const result = await runShell(shell, workspace, 'agent-task pi sol', {
        PI_CODING_AGENT_DIR: agentDir,
      })
      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(formatFakeHostLog('pi', 'sol', []))
    })
    it(`${shellName} 废弃档位和不兼容mode均在写配置前失败`, async () => {
      const workspace = createWorkspace()
      writeProfileHelper(workspace)
      for (const host of ['pi', 'omp']) {
        for (const profile of [
          'fast',
          'medium',
          'slow',
          'max',
          'ultra',
          'ultrafast',
          'worker_ultrafast',
          'unknown',
        ]) {
          const result = await runShell(
            shell,
            workspace,
            `agent-task ${host} ${profile}`,
          )
          expect(result.exitCode).toBe(64)
        }
      }
      for (const invocation of [
        'pi default --mode core',
        'pi sol --mode chat',
        'omp sol --mode project',
        'codex default',
        'codex max --mode no-skill',
        'pi default --mode',
      ]) {
        const result = await runShell(
          shell,
          workspace,
          `agent-task ${invocation}`,
        )
        expect(result.exitCode).toBe(64)
      }
      expect(readLog(workspace)).toBe('')
      expect(fs.existsSync(path.join(workspace.home, 'profile'))).toBe(false)
    })
    it(`${shellName} OMP overlay缺失时失败`, async () => {
      const workspace = createWorkspace()
      expect(
        (await runShell(shell, workspace, 'agent-task omp sol')).exitCode,
      ).toBe(66)
    })
    it(`${shellName} Codex 保留五档既有模型、参数与退出码`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'codex')
      for (const [profile, model, effort] of [
        ['fast', 'gpt-5.6-luna', 'high'],
        ['medium', 'gpt-5.6-luna', 'xhigh'],
        ['slow', 'gpt-5.6-luna', 'max'],
        ['max', 'gpt-6.1-sol', 'high'],
        ['ultra', 'gpt-6-astra', 'low'],
      ]) {
        fs.rmSync(workspace.log, { force: true })
        const result = await runShell(
          shell,
          workspace,
          `agent-task codex ${profile} -- --flag 'two words'`,
          { AGENT_TASK_TEST_EXIT_CODE: '19' },
        )
        expect(result.exitCode).toBe(19)
        expect(readLog(workspace)).toBe(
          formatFakeHostLog('codex', '', [
            '-c',
            `agents.default_subagent_model="${model}"`,
            '-c',
            `agents.default_subagent_reasoning_effort="${effort}"`,
            '--flag',
            'two words',
          ]),
        )
      }
    })
    it(`${shellName} help 明确持久化行为和dry-run无写入`, async () => {
      const workspace = createWorkspace()
      const result = await runShell(shell, workspace, 'agent-task --help')
      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('default|sol')
      expect(result.stdout).toContain('持久化切换 profile')
      expect(result.stdout).toContain('不写入 profile')
    })
    for (const mode of [
      'full',
      'no-skill',
      'core',
      'core-search',
      'read',
      'read-search',
      'chat',
      'chat-search',
    ] as const) {
      it(`${shellName} 为 pi-mode ${mode} 组装稳定参数`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')
        const webExtension = path.join(
          workspace.home,
          '.pi/agent/npm/node_modules/pi-web-access/index.ts',
        )
        if (mode.endsWith('-search')) {
          writeWebExtension(workspace)
        }
        const webTools =
          'web_search,source_check,fetch_content,get_search_content'
        const localChatPrompt =
          "You are a concise, helpful conversational assistant. Answer directly and reply in the user's language unless asked otherwise."
        const searchChatPrompt =
          "You are a concise, helpful conversational assistant with web search and page-fetching tools. Answer directly, use tools when current or source-backed information is needed, and reply in the user's language unless asked otherwise."
        const fixedArgsByMode: Record<string, string[]> = {
          full: [],
          'no-skill': ['--no-skills'],
          core: ['--no-skills', '--no-extensions'],
          'core-search': ['--no-skills', '--no-extensions', '-e', webExtension],
          read: [
            '--no-skills',
            '--no-extensions',
            '--tools',
            'read,grep,find,ls',
          ],
          'read-search': [
            '--no-skills',
            '--no-extensions',
            '-e',
            webExtension,
            '--tools',
            `read,grep,find,ls,${webTools}`,
          ],
          chat: [
            '--no-skills',
            '--no-extensions',
            '--no-context-files',
            '--no-tools',
            '--system-prompt',
            localChatPrompt,
          ],
          'chat-search': [
            '--no-skills',
            '--no-extensions',
            '-e',
            webExtension,
            '--no-context-files',
            '--no-builtin-tools',
            '--system-prompt',
            searchChatPrompt,
          ],
        }
        const userArgs = ['--', '--flag', 'two words', '']

        const result = await runShell(
          shell,
          workspace,
          `pi-mode ${mode} -- --flag ${shellQuote('two words')} ''`,
        )

        expect(result.exitCode).toBe(0)
        expect(readLog(workspace)).toBe(
          formatFakeHostLog('pi', '', [...fixedArgsByMode[mode], ...userArgs]),
        )
      })
    }

    it(`${shellName} pi-mode project 只恢复 cwd 到 Git 根的项目 Skill`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const project = await createProjectSkillTree(workspace)

      const result = await runShell(
        shell,
        workspace,
        `cd ${shellQuote(project.cwd)} && pi-mode project --flag`,
      )

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', '', [...project.fixedArgs, '--flag']),
      )
      expect(readLog(workspace)).not.toContain(
        path.join(workspace.root, '.agents/skills'),
      )
    })

    it(`${shellName} mode 函数帮助别名一致并拒绝未知及旧模式`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      writeFakeHost(workspace, 'omp')

      const piHelp = await runShell(shell, workspace, 'pi-mode')
      const piLongHelp = await runShell(shell, workspace, 'pi-mode --help')
      const piShortHelp = await runShell(shell, workspace, 'pi-mode -h')
      const ompHelp = await runShell(shell, workspace, 'omp-mode')
      const ompLongHelp = await runShell(shell, workspace, 'omp-mode --help')
      const ompShortHelp = await runShell(shell, workspace, 'omp-mode -h')
      const unknownPi = await runShell(shell, workspace, 'pi-mode unknown')
      const offlinePi = await runShell(shell, workspace, 'pi-mode offline')
      const unknownOmp = await runShell(shell, workspace, 'omp-mode full')

      expect(piHelp.exitCode).toBe(0)
      expect(piLongHelp.exitCode).toBe(0)
      expect(piShortHelp.exitCode).toBe(0)
      expect(piLongHelp.stdout).toBe(piHelp.stdout)
      expect(piShortHelp.stdout).toBe(piHelp.stdout)
      expect(piHelp.stdout).toContain(
        'pi-mode <full|project|no-skill|core|core-search|read|read-search|chat|chat-search>',
      )
      expect(piHelp.stdout).toContain('移除 global/package/settings Skills')
      expect(piHelp.stdout).toContain('不受自动 project trust gate 控制')
      expect(piHelp.stdout).toContain('*-search 模式显式加载 pi-web-access')
      expect(piHelp.stdout).toContain('不是模型或进程级断网沙箱')
      expect(piHelp.stdout).not.toContain('offline')
      expect(ompHelp.exitCode).toBe(0)
      expect(ompLongHelp.exitCode).toBe(0)
      expect(ompShortHelp.exitCode).toBe(0)
      expect(ompLongHelp.stdout).toBe(ompHelp.stdout)
      expect(ompShortHelp.stdout).toBe(ompHelp.stdout)
      expect(ompHelp.stdout).toContain('omp-mode no-skill')
      expect(unknownPi.exitCode).toBe(64)
      expect(unknownPi.stderr).toContain('未知 mode')
      expect(offlinePi.exitCode).toBe(64)
      expect(offlinePi.stderr).toContain('未知 mode')
      expect(unknownOmp.exitCode).toBe(64)
      expect(unknownOmp.stderr).toContain('未知 mode')
      expect(readLog(workspace)).toBe('')
    })

    for (const mode of ['core-search', 'read-search', 'chat-search'] as const) {
      it(`${shellName} pi-mode ${mode} 在 Web 扩展缺失时 fail closed`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')

        const result = await runShell(shell, workspace, `pi-mode ${mode}`)

        expect(result.exitCode).toBe(69)
        expect(result.stderr).toContain('pi-web-access 不存在或不可读')
        expect(readLog(workspace)).toBe('')
      })
    }

    it(`${shellName} Pi Web 环境覆盖只影响约定的搜索分支`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const agentDir = path.join(workspace.root, 'custom agent dir')
      const webExtension = writeWebExtension(workspace, agentDir)
      const env = {
        PI_CODING_AGENT_DIR: agentDir,
        PI_MODE_WEB_TOOLS: 'search_custom,fetch_custom',
      }
      const searchChatPrompt =
        "You are a concise, helpful conversational assistant with web search and page-fetching tools. Answer directly, use tools when current or source-backed information is needed, and reply in the user's language unless asked otherwise."

      const localRead = await runShell(
        shell,
        workspace,
        'pi-mode read --flag',
        env,
      )
      const coreSearch = await runShell(
        shell,
        workspace,
        'pi-mode core-search --flag',
        env,
      )
      const readSearch = await runShell(
        shell,
        workspace,
        'pi-mode read-search --flag',
        env,
      )
      const chatSearch = await runShell(
        shell,
        workspace,
        'pi-mode chat-search --flag',
        env,
      )

      for (const result of [localRead, coreSearch, readSearch, chatSearch]) {
        expect(result.exitCode).toBe(0)
      }
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', '', [
          '--no-skills',
          '--no-extensions',
          '--tools',
          'read,grep,find,ls',
          '--flag',
        ]) +
          formatFakeHostLog('pi', '', [
            '--no-skills',
            '--no-extensions',
            '-e',
            webExtension,
            '--flag',
          ]) +
          formatFakeHostLog('pi', '', [
            '--no-skills',
            '--no-extensions',
            '-e',
            webExtension,
            '--tools',
            'read,grep,find,ls,search_custom,fetch_custom',
            '--flag',
          ]) +
          formatFakeHostLog('pi', '', [
            '--no-skills',
            '--no-extensions',
            '-e',
            webExtension,
            '--no-context-files',
            '--no-builtin-tools',
            '--system-prompt',
            searchChatPrompt,
            '--flag',
          ]),
      )
    })

    it(`${shellName} PI_MODE_WEB_EXTENSION 优先于默认 Web 路径`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const webExtension = path.join(workspace.root, 'custom web extension.ts')
      fs.writeFileSync(webExtension, 'export default function () {}\n')

      const result = await runShell(shell, workspace, 'pi-mode core-search', {
        PI_MODE_WEB_EXTENSION: webExtension,
      })

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', '', [
          '--no-skills',
          '--no-extensions',
          '-e',
          webExtension,
        ]),
      )
    })

    it(`${shellName} omp-mode no-skill 保留原生参数边界`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'omp')

      const result = await runShell(
        shell,
        workspace,
        `omp-mode no-skill -- --flag ${shellQuote('two words')} ''`,
      )

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('omp', '', [
          '--no-skills',
          '--',
          '--flag',
          'two words',
          '',
        ]),
      )
    })

    it(`${shellName} mode 函数透传宿主非零退出码`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      writeFakeHost(workspace, 'omp')

      const piResult = await runShell(
        shell,
        workspace,
        'pi-mode no-skill --flag',
        { AGENT_TASK_TEST_EXIT_CODE: '23' },
      )
      const ompResult = await runShell(
        shell,
        workspace,
        'omp-mode no-skill --flag',
        { AGENT_TASK_TEST_EXIT_CODE: '29' },
      )

      expect(piResult.exitCode).toBe(23)
      expect(ompResult.exitCode).toBe(29)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', '', ['--no-skills', '--flag']) +
          formatFakeHostLog('omp', '', ['--no-skills', '--flag']),
      )
    })
  }
})
