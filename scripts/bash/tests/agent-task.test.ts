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
      '  printf "profile=%s\\n" "${PI_PROFILED_TASK_PROFILE-}"',
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
 * @param profile Pi 进程级 profile；其它宿主传空字符串。
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

describe('shell/shared.d/ai.sh agent-task', () => {
  for (const shell of getAvailableShells()) {
    const shellName = path.basename(shell)

    it(`${shellName} 可解析共享脚本语法`, async () => {
      const workspace = createWorkspace()
      const args =
        shellName === 'zsh'
          ? ['-f', '-n', sourceScript]
          : ['--noprofile', '--norc', '-n', sourceScript]
      const result = await execa(shell, args, {
        cwd: workspace.root,
        env: {
          HOME: workspace.home,
          PATH: `${workspace.bin}:/usr/bin:/bin`,
        },
        extendEnv: false,
        reject: false,
      })

      expect(result.exitCode).toBe(0)
      expect(result.stderr).toBe('')
    })

    it(`${shellName} dry-run 不执行 Pi 且不泄漏参数值`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const result = await runShell(
        shell,
        workspace,
        `agent-task pi fast --dry-run -- --token ${shellQuote('secret prompt value')}`,
      )

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe('')
      expect(result.stderr).toBe(
        [
          'agent-task: host=pi profile=fast source-agent=worker_fast (+2 user args)',
          'agent-task command: PI_PROFILED_TASK_PROFILE=fast pi (+2 user args)',
        ].join('\n'),
      )
      expect(result.stderr).not.toContain('--token')
      expect(result.stderr).not.toContain('secret prompt value')
    })

    it(`${shellName} show-command 只显示固定命令形态并继续执行 Pi`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const result = await runShell(
        shell,
        workspace,
        `agent-task pi max --show-command -- --message ${shellQuote('private task text')}`,
      )

      expect(result.exitCode).toBe(0)
      expect(result.stderr).toBe(
        [
          'agent-task: host=pi profile=max source-agent=worker_max (+2 user args)',
          'agent-task command: PI_PROFILED_TASK_PROFILE=max pi (+2 user args)',
        ].join('\n'),
      )
      expect(result.stderr).not.toContain('--message')
      expect(result.stderr).not.toContain('private task text')
      expect(readLog(workspace)).toBe(
        [
          'command=pi',
          'profile=max',
          'argc=2',
          'arg[0]=<--message>',
          'arg[1]=<private task text>',
          '',
        ].join('\n'),
      )
    })

    for (const profile of ['fast', 'medium', 'slow', 'max'] as const) {
      it(`${shellName} 为 Pi ${profile} 设置进程级 profile`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')

        const result = await runShell(
          shell,
          workspace,
          `agent-task pi ${profile}; printf 'parent-profile=%s\\n' "\${PI_PROFILED_TASK_PROFILE-unset}"`,
        )

        expect(result.exitCode).toBe(0)
        expect(result.stdout).toBe('parent-profile=unset')
        expect(readLog(workspace)).toContain(`profile=${profile}\n`)
        expect(result.stderr).toContain(`source-agent=worker_${profile}`)
      })
    }

    it(`${shellName} 保留空白参数、-- 后参数和 Pi 非零退出码`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const result = await runShell(
        shell,
        workspace,
        `agent-task pi slow -- --dry-run ${shellQuote('two words')} ''`,
        { AGENT_TASK_TEST_EXIT_CODE: '23' },
      )

      expect(result.exitCode).toBe(23)
      expect(readLog(workspace)).toBe(
        [
          'command=pi',
          'profile=slow',
          'argc=3',
          'arg[0]=<--dry-run>',
          'arg[1]=<two words>',
          'arg[2]=<>',
          '',
        ].join('\n'),
      )
    })

    for (const profile of ['fast', 'medium', 'slow', 'max'] as const) {
      it(`${shellName} 保持 OMP ${profile} 参数形态和转发语义`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'omp')
        const overlays = path.join(workspace.home, '.omp/overlays')
        fs.mkdirSync(overlays, { recursive: true })
        fs.writeFileSync(
          path.join(overlays, `task-${profile}.yml`),
          `modelRoles:\n  task: "@worker_${profile}"\n`,
        )

        const result = await runShell(
          shell,
          workspace,
          `agent-task omp ${profile} -- --flag ${shellQuote('two words')}`,
        )

        expect(result.exitCode).toBe(0)
        expect(readLog(workspace)).toBe(
          [
            'command=omp',
            'profile=',
            'argc=4',
            'arg[0]=<--config>',
            `arg[1]=<${path.join(workspace.home, `.omp/overlays/task-${profile}.yml`)}>`,
            'arg[2]=<--flag>',
            'arg[3]=<two words>',
            '',
          ].join('\n'),
        )
      })
    }

    it(`${shellName} 在 OMP overlay 缺失时不启动宿主`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'omp')

      const result = await runShell(shell, workspace, 'agent-task omp medium')

      expect(result.exitCode).toBe(66)
      expect(result.stderr).toContain('OMP overlay 不存在或不可读')
      expect(result.stderr).toContain('task-medium.yml')
      expect(readLog(workspace)).toBe('')
    })

    for (const [profile, model, effort] of [
      ['fast', 'gpt-5.6-luna', 'high'],
      ['medium', 'gpt-5.6-luna', 'xhigh'],
      ['slow', 'gpt-5.6-luna', 'max'],
      ['max', 'gpt-5.6-sol', 'medium'],
    ] as const) {
      it(`${shellName} 保持 Codex ${profile} 覆盖参数和转发语义`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'codex')

        const result = await runShell(
          shell,
          workspace,
          `agent-task codex ${profile} -- --flag ${shellQuote('two words')}`,
        )

        expect(result.exitCode).toBe(0)
        expect(readLog(workspace)).toBe(
          [
            'command=codex',
            'profile=',
            'argc=6',
            'arg[0]=<-c>',
            `arg[1]=<agents.default_subagent_model="${model}">`,
            'arg[2]=<-c>',
            `arg[3]=<agents.default_subagent_reasoning_effort="${effort}">`,
            'arg[4]=<--flag>',
            'arg[5]=<two words>',
            '',
          ].join('\n'),
        )
      })
    }

    it(`${shellName} 对未知 host、未知 profile 和 Claude 保持启动前失败`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const missingArguments = await runShell(shell, workspace, 'agent-task')
      const unknownHost = await runShell(
        shell,
        workspace,
        'agent-task other fast',
      )
      const unknownProfile = await runShell(
        shell,
        workspace,
        'agent-task pi turbo',
      )
      const claude = await runShell(shell, workspace, 'agent-task claude fast')

      expect(missingArguments.exitCode).toBe(64)
      expect(missingArguments.stderr).toContain('需要 host 和 profile')
      expect(unknownHost.exitCode).toBe(64)
      expect(unknownHost.stderr).toContain('未知 host')
      expect(unknownProfile.exitCode).toBe(64)
      expect(unknownProfile.stderr).toContain('未知 profile')
      expect(claude.exitCode).toBe(64)
      expect(claude.stderr).toContain('claude 仅支持持久化 Agent')
      expect(readLog(workspace)).toBe('')
    })

    it(`${shellName} help 展示四档唯一入口`, async () => {
      const workspace = createWorkspace()

      const result = await runShell(shell, workspace, 'agent-task --help')

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('pi    fast|medium|slow|max')
      expect(result.stdout).not.toContain('快捷命令')
      expect(result.stdout).toContain(
        'claude                     仅支持持久化 worker-fast',
      )
    })

    it(`${shellName} 显式 full mode 保持三个宿主的旧参数与日志`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      writeFakeHost(workspace, 'omp')
      writeFakeHost(workspace, 'codex')
      const overlay = path.join(workspace.home, '.omp/overlays/task-fast.yml')
      fs.mkdirSync(path.dirname(overlay), { recursive: true })
      fs.writeFileSync(overlay, 'modelRoles:\n  task: "@worker_fast"\n')

      const piResult = await runShell(
        shell,
        workspace,
        'agent-task pi fast --mode full -- --flag',
      )
      const ompResult = await runShell(
        shell,
        workspace,
        'agent-task omp fast --mode full -- --flag',
      )
      const codexResult = await runShell(
        shell,
        workspace,
        'agent-task codex fast --mode full -- --flag',
      )

      for (const result of [piResult, ompResult, codexResult]) {
        expect(result.exitCode).toBe(0)
        expect(result.stderr).not.toContain('mode=full')
      }
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', 'fast', ['--flag']) +
          formatFakeHostLog('omp', '', ['--config', overlay, '--flag']) +
          formatFakeHostLog('codex', '', [
            '-c',
            'agents.default_subagent_model="gpt-5.6-luna"',
            '-c',
            'agents.default_subagent_reasoning_effort="high"',
            '--flag',
          ]),
      )
    })

    for (const mode of [
      'full',
      'no-skill',
      'core',
      'read',
      'chat',
      'offline',
    ] as const) {
      it(`${shellName} 为 pi-mode ${mode} 组装稳定参数`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')
        const webExtension = writeWebExtension(workspace)
        const webTools =
          'web_search,source_check,fetch_content,get_search_content'
        const chatPrompt =
          "You are a concise, helpful conversational assistant with web search and page-fetching tools. Answer directly, use tools when current or source-backed information is needed, and reply in the user's language unless asked otherwise."
        const offlinePrompt =
          "You are a concise, helpful conversational assistant. Answer directly and reply in the user's language unless asked otherwise."
        const fixedArgsByMode: Record<string, string[]> = {
          full: [],
          'no-skill': ['--no-skills'],
          core: ['--no-skills', '--no-extensions', '-e', webExtension],
          read: [
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
            '-e',
            webExtension,
            '--no-context-files',
            '--no-builtin-tools',
            '--system-prompt',
            chatPrompt,
          ],
          offline: [
            '--no-skills',
            '--no-extensions',
            '--no-context-files',
            '--no-tools',
            '--system-prompt',
            offlinePrompt,
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

    it(`${shellName} mode 函数帮助别名一致并拒绝未知模式`, async () => {
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
      const unknownOmp = await runShell(shell, workspace, 'omp-mode full')

      expect(piHelp.exitCode).toBe(0)
      expect(piLongHelp.exitCode).toBe(0)
      expect(piShortHelp.exitCode).toBe(0)
      expect(piLongHelp.stdout).toBe(piHelp.stdout)
      expect(piShortHelp.stdout).toBe(piHelp.stdout)
      expect(piHelp.stdout).toContain(
        'pi-mode <full|project|no-skill|core|read|chat|offline>',
      )
      expect(piHelp.stdout).toContain('移除 global/package/settings Skills')
      expect(piHelp.stdout).toContain('不受自动 project trust gate 控制')
      expect(piHelp.stdout).toContain('从 full 到 chat 默认保留 Web')
      expect(piHelp.stdout).toContain('不保证模型或进程级断网')
      expect(ompHelp.exitCode).toBe(0)
      expect(ompLongHelp.exitCode).toBe(0)
      expect(ompShortHelp.exitCode).toBe(0)
      expect(ompLongHelp.stdout).toBe(ompHelp.stdout)
      expect(ompShortHelp.stdout).toBe(ompHelp.stdout)
      expect(ompHelp.stdout).toContain('omp-mode no-skill')
      expect(unknownPi.exitCode).toBe(64)
      expect(unknownPi.stderr).toContain('未知 mode')
      expect(unknownOmp.exitCode).toBe(64)
      expect(unknownOmp.stderr).toContain('未知 mode')
      expect(readLog(workspace)).toBe('')
    })

    for (const mode of ['core', 'read', 'chat'] as const) {
      it(`${shellName} pi-mode ${mode} 在 Web 扩展缺失时 fail closed`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')

        const result = await runShell(shell, workspace, `pi-mode ${mode}`)

        expect(result.exitCode).toBe(69)
        expect(result.stderr).toContain('pi-web-access 不存在或不可读')
        expect(readLog(workspace)).toBe('')
      })
    }

    it(`${shellName} 支持 Pi agentDir 与 Web 工具名称覆盖`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const agentDir = path.join(workspace.root, 'custom agent dir')
      const webExtension = writeWebExtension(workspace, agentDir)

      const result = await runShell(shell, workspace, 'pi-mode read --flag', {
        PI_CODING_AGENT_DIR: agentDir,
        PI_MODE_WEB_TOOLS: 'search_custom,fetch_custom',
      })

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', '', [
          '--no-skills',
          '--no-extensions',
          '-e',
          webExtension,
          '--tools',
          'read,grep,find,ls,search_custom,fetch_custom',
          '--flag',
        ]),
      )
    })

    it(`${shellName} PI_MODE_WEB_EXTENSION 优先于默认 Web 路径`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      const webExtension = path.join(workspace.root, 'custom web extension.ts')
      fs.writeFileSync(webExtension, 'export default function () {}\n')

      const result = await runShell(shell, workspace, 'pi-mode core', {
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

    for (const profile of ['fast', 'medium', 'slow', 'max'] as const) {
      for (const mode of ['project', 'no-skill'] as const) {
        it(`${shellName} 组合 Pi ${profile} profile 与 ${mode} mode`, async () => {
          const workspace = createWorkspace()
          writeFakeHost(workspace, 'pi')
          const project = await createProjectSkillTree(workspace)
          const cwdPrefix =
            mode === 'project' ? `cd ${shellQuote(project.cwd)} && ` : ''
          const fixedArgs =
            mode === 'project' ? project.fixedArgs : ['--no-skills']

          const result = await runShell(
            shell,
            workspace,
            `${cwdPrefix}agent-task pi ${profile} --mode ${mode} -- --flag ${shellQuote('two words')}`,
          )

          expect(result.exitCode).toBe(0)
          expect(result.stderr).toContain(`mode=${mode}`)
          expect(readLog(workspace)).toBe(
            formatFakeHostLog('pi', profile, [
              ...fixedArgs,
              '--flag',
              'two words',
            ]),
          )
        })
      }
    }

    for (const profile of ['fast', 'medium', 'slow', 'max'] as const) {
      it(`${shellName} 组合 OMP ${profile} profile 与 no-skill mode`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'omp')
        const overlay = path.join(
          workspace.home,
          `.omp/overlays/task-${profile}.yml`,
        )
        fs.mkdirSync(path.dirname(overlay), { recursive: true })
        fs.writeFileSync(overlay, `modelRoles:\n  task: "@worker_${profile}"\n`)

        const result = await runShell(
          shell,
          workspace,
          `agent-task omp ${profile} --mode no-skill -- --flag`,
        )

        expect(result.exitCode).toBe(0)
        expect(result.stderr).toContain('mode=no-skill')
        expect(readLog(workspace)).toBe(
          formatFakeHostLog('omp', '', [
            '--config',
            overlay,
            '--no-skills',
            '--flag',
          ]),
        )
      })
    }

    it(`${shellName} agent-task 拒绝无效 mode 组合与缺值`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')
      writeFakeHost(workspace, 'omp')
      writeFakeHost(workspace, 'codex')
      const overlay = path.join(workspace.home, '.omp/overlays/task-fast.yml')
      fs.mkdirSync(path.dirname(overlay), { recursive: true })
      fs.writeFileSync(overlay, 'modelRoles:\n  task: "@worker_fast"\n')

      const piCore = await runShell(
        shell,
        workspace,
        'agent-task pi fast --mode core',
      )
      const ompProject = await runShell(
        shell,
        workspace,
        'agent-task omp fast --mode project',
      )
      const codexNoSkill = await runShell(
        shell,
        workspace,
        'agent-task codex fast --mode no-skill',
      )
      const missingMode = await runShell(
        shell,
        workspace,
        'agent-task pi fast --mode',
      )

      for (const result of [piCore, ompProject, codexNoSkill, missingMode]) {
        expect(result.exitCode).toBe(64)
      }
      expect(piCore.stderr).toContain('不支持 mode')
      expect(ompProject.stderr).toContain('不支持 mode')
      expect(codexNoSkill.stderr).toContain('只支持 full mode')
      expect(missingMode.stderr).toContain('--mode 需要值')
      expect(readLog(workspace)).toBe('')
    })

    it(`${shellName} agent-task mode 最后值生效且 delimiter 后不再解析`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const repeated = await runShell(
        shell,
        workspace,
        'agent-task pi fast --mode project --mode no-skill -- --flag',
      )
      const delimited = await runShell(
        shell,
        workspace,
        'agent-task pi slow -- --mode no-skill',
      )

      expect(repeated.exitCode).toBe(0)
      expect(delimited.exitCode).toBe(0)
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', 'fast', ['--no-skills', '--flag']) +
          formatFakeHostLog('pi', 'slow', ['--mode', 'no-skill']),
      )
    })

    it(`${shellName} 非 full dry-run 不执行宿主且不泄漏参数`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const result = await runShell(
        shell,
        workspace,
        `agent-task pi fast --mode no-skill --dry-run -- --token ${shellQuote('secret value')}`,
      )

      expect(result.exitCode).toBe(0)
      expect(result.stderr).toContain('mode=no-skill')
      expect(result.stderr).toContain('(+2 user args)')
      expect(result.stderr).not.toContain('--token')
      expect(result.stderr).not.toContain('secret value')
      expect(readLog(workspace)).toBe('')
    })

    it(`${shellName} 非 full show-command 保持父环境并透传退出码`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const result = await runShell(
        shell,
        workspace,
        `agent-task pi slow --mode no-skill --show-command -- --message ${shellQuote('private mode text')}; host_status=$?; printf 'parent-profile=%s\\n' "\${PI_PROFILED_TASK_PROFILE-unset}"; exit "$host_status"`,
        { AGENT_TASK_TEST_EXIT_CODE: '31' },
      )

      expect(result.exitCode).toBe(31)
      expect(result.stdout).toBe('parent-profile=unset')
      expect(result.stderr).toContain('mode=no-skill')
      expect(result.stderr).toContain('(+2 user args)')
      expect(result.stderr).not.toContain('--message')
      expect(result.stderr).not.toContain('private mode text')
      expect(readLog(workspace)).toBe(
        formatFakeHostLog('pi', 'slow', [
          '--no-skills',
          '--message',
          'private mode text',
        ]),
      )
    })

    it(`${shellName} agent-task help 展示 profile 与 mode 支持矩阵`, async () => {
      const workspace = createWorkspace()

      const result = await runShell(shell, workspace, 'agent-task --help')

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('[--mode <mode>]')
      expect(result.stdout).toContain('pi    full|project|no-skill')
      expect(result.stdout).toContain('omp   full|no-skill')
      expect(result.stdout).toContain('codex full')
    })
  }
})
