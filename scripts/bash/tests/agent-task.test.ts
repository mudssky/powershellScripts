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
function writeFakeHost(workspace: Workspace, name: 'pi' | 'omp' | 'codex'): string {
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
  const args = shellName === 'zsh'
    ? ['-f', '-c', `source ${shellQuote(sourceScript)}\n${body}`]
    : ['--noprofile', '--norc', '-c', `source ${shellQuote(sourceScript)}\n${body}`]

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
  return fs.existsSync(workspace.log) ? fs.readFileSync(workspace.log, 'utf8') : ''
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
      const args = shellName === 'zsh' ? ['-f', '-n', sourceScript] : ['--noprofile', '--norc', '-n', sourceScript]
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
      expect(result.stderr).toBe([
        'agent-task: host=pi profile=fast source-agent=worker_fast (+2 user args)',
        'agent-task command: PI_PROFILED_TASK_PROFILE=fast pi (+2 user args)',
      ].join('\n'))
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
      expect(result.stderr).toBe([
        'agent-task: host=pi profile=max source-agent=worker_max (+2 user args)',
        'agent-task command: PI_PROFILED_TASK_PROFILE=max pi (+2 user args)',
      ].join('\n'))
      expect(result.stderr).not.toContain('--message')
      expect(result.stderr).not.toContain('private task text')
      expect(readLog(workspace)).toBe([
        'command=pi',
        'profile=max',
        'argc=2',
        'arg[0]=<--message>',
        'arg[1]=<private task text>',
        '',
      ].join('\n'))
    })

    for (const profile of ['fast', 'slow', 'max'] as const) {
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
      expect(readLog(workspace)).toBe([
        'command=pi',
        'profile=slow',
        'argc=3',
        'arg[0]=<--dry-run>',
        'arg[1]=<two words>',
        'arg[2]=<>',
        '',
      ].join('\n'))
    })

    for (const profile of ['fast', 'slow', 'max'] as const) {
      it(`${shellName} pi-task${profile} 精确路由 ${profile} profile`, async () => {
        const workspace = createWorkspace()
        writeFakeHost(workspace, 'pi')

        const result = await runShell(
          shell,
          workspace,
          `pi-task${profile} -- --profile-argument ${shellQuote('kept together')}`,
        )

        expect(result.exitCode).toBe(0)
        expect(readLog(workspace)).toBe([
          'command=pi',
          `profile=${profile}`,
          'argc=2',
          'arg[0]=<--profile-argument>',
          'arg[1]=<kept together>',
          '',
        ].join('\n'))
      })
    }

    it(`${shellName} 保持 OMP 参数形态和转发语义`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'omp')

      const result = await runShell(
        shell,
        workspace,
        `agent-task omp fast -- --flag ${shellQuote('two words')}`,
      )

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe([
        'command=omp',
        'profile=',
        'argc=4',
        'arg[0]=<--config>',
        `arg[1]=<${path.join(workspace.home, '.omp/overlays/task-fast.yml')}>`,
        'arg[2]=<--flag>',
        'arg[3]=<two words>',
        '',
      ].join('\n'))
    })

    it(`${shellName} 保持 Codex 覆盖参数和转发语义`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'codex')

      const result = await runShell(
        shell,
        workspace,
        `agent-task codex max -- --flag ${shellQuote('two words')}`,
      )

      expect(result.exitCode).toBe(0)
      expect(readLog(workspace)).toBe([
        'command=codex',
        'profile=',
        'argc=6',
        'arg[0]=<-c>',
        'arg[1]=<agents.default_subagent_model="gpt-5.6-sol">',
        'arg[2]=<-c>',
        'arg[3]=<agents.default_subagent_reasoning_effort="medium">',
        'arg[4]=<--flag>',
        'arg[5]=<two words>',
        '',
      ].join('\n'))
    })

    it(`${shellName} 对未知 host、未知 profile 和 Claude 保持启动前失败`, async () => {
      const workspace = createWorkspace()
      writeFakeHost(workspace, 'pi')

      const missingArguments = await runShell(shell, workspace, 'agent-task')
      const unknownHost = await runShell(shell, workspace, 'agent-task other fast')
      const unknownProfile = await runShell(shell, workspace, 'agent-task pi turbo')
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

    it(`${shellName} help 展示 Pi 支持和快捷命令`, async () => {
      const workspace = createWorkspace()

      const result = await runShell(shell, workspace, 'agent-task --help')

      expect(result.exitCode).toBe(0)
      expect(result.stdout).toContain('pi    fast|slow|max')
      expect(result.stdout).toContain('pi-taskfast / pi-taskslow / pi-taskmax')
      expect(result.stdout).toContain('claude              仅支持持久化 worker-fast')
    })
  }
})
