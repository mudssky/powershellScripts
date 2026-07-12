import { mkdir, mkdtemp, readFile, stat, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import { runCli } from '../src/cli'
import { loadConfig, saveServiceToLocalConfig } from '../src/config'
import {
  discoverProject,
  parseGradleIncludes,
  parseMavenModules,
} from '../src/discovery'
import { createLaunchPlan, selectServices } from '../src/planner'
import { createSessionMetadata, validateSessionMetadata } from '../src/session'
import { buildTmuxCommands, tmuxSessionExists } from '../src/tmux'
import type { CommandRunner } from '../src/types'

describe('配置读取与保存', () => {
  it('按显式配置、project local、project config 的顺序读取', async () => {
    const dir = await mkTempProject()
    await writeJson(join(dir, 'project-launch.config.json'), {
      services: [{ name: 'shared', command: 'echo shared' }],
    })
    await writeJson(join(dir, 'project-launch.local.json'), {
      services: [{ name: 'local', command: 'echo local' }],
    })
    const explicit = join(dir, 'custom.json')
    await writeJson(explicit, {
      services: [{ name: 'explicit', command: 'echo explicit' }],
    })

    expect((await loadConfig(dir)).config.services?.[0].name).toBe('local')
    expect(
      (await loadConfig(dir, { configPath: explicit })).config.services?.[0]
        .name,
    ).toBe('explicit')
  })

  it('保存一次性命令到 local JSON 并创建备份', async () => {
    const dir = await mkTempProject()
    await saveServiceToLocalConfig(dir, {
      name: 'api',
      command: './mvnw spring-boot:run',
    })
    await expect(
      saveServiceToLocalConfig(dir, {
        name: 'api',
        command: './mvnw spring-boot:run -DskipTests',
      }),
    ).rejects.toThrow(/已存在同名服务/)

    const result = await saveServiceToLocalConfig(
      dir,
      {
        name: 'api',
        command: './mvnw spring-boot:run -DskipTests',
      },
      { overwrite: true, now: new Date('2026-06-16T01:02:03') },
    )

    expect(result.backupPath).toContain('2026-06-16_01-02-03.bak')
    await expect(stat(result.backupPath ?? '')).resolves.toBeTruthy()
    const saved = JSON.parse(
      await readFile(join(dir, 'project-launch.local.json'), 'utf8'),
    )
    expect(saved.services[0].command).toContain('-DskipTests')
  })
})

describe('零配置发现', () => {
  it('解析 Maven 和 Gradle 模块声明', () => {
    expect(
      parseMavenModules(
        '<modules><module>api</module><module>common</module></modules>',
      ),
    ).toEqual(['api', 'common'])
    expect(parseGradleIncludes("include 'api', ':worker'\n")).toEqual([
      'api',
      'worker',
    ])
  })

  it('发现 Maven Spring Boot 服务并忽略 common 模块', async () => {
    const dir = await mkTempProject()
    await writeFile(
      join(dir, 'pom.xml'),
      '<project><packaging>pom</packaging><modules><module>api</module><module>common</module></modules></project>',
      'utf8',
    )
    await mkdir(join(dir, 'api', 'src', 'main', 'java', 'demo'), {
      recursive: true,
    })
    await mkdir(join(dir, 'common'), { recursive: true })
    await writeFile(
      join(dir, 'api', 'pom.xml'),
      '<project><build><plugins><plugin><artifactId>spring-boot-maven-plugin</artifactId></plugin></plugins></build></project>',
      'utf8',
    )
    await writeFile(
      join(dir, 'api', 'src', 'main', 'java', 'demo', 'App.java'),
      '@SpringBootApplication class App { public static void main(String[] args) {} }',
      'utf8',
    )
    await writeFile(
      join(dir, 'common', 'pom.xml'),
      '<project></project>',
      'utf8',
    )

    const result = await discoverProject(dir)

    expect(result.services.map((service) => service.name)).toEqual(['api'])
    expect(result.ignored.map((item) => item.name)).toContain('common')
  })
})

describe('计划与 tmux', () => {
  it('多个服务未显式选择时只提示选择', async () => {
    const selected = selectServices(
      [service('api', 'echo api'), service('worker', 'echo worker')],
      { action: 'start' },
    )

    expect(selected.services).toHaveLength(0)
    expect(selected.selectionRequired).toBe(true)
    expect(selected.diagnostics[0].code).toBe(
      'MULTI_SERVICE_SELECTION_REQUIRED',
    )
  })

  it('start 没有服务候选时阻止创建空会话', () => {
    const selected = selectServices([], { action: 'start' })

    expect(selected.services).toHaveLength(0)
    expect(selected.diagnostics[0].code).toBe('NO_SERVICE_CANDIDATE')
    expect(selected.diagnostics[0].level).toBe('error')
  })

  it('生成三服务 pane 平铺 tmux 命令', async () => {
    const dir = await mkTempProject()
    const plan = await createLaunchPlan({
      action: 'start',
      projectRoot: dir,
      all: true,
      loadedConfig: {
        source: 'project-local',
        config: {
          services: [
            { name: 'api', command: 'echo api' },
            { name: 'worker', command: 'echo worker' },
            { name: 'admin', command: 'echo admin' },
          ],
        },
      },
    })

    const commands = buildTmuxCommands(plan)

    expect(plan.session).toMatch(/^pl-/)
    expect(
      commands.filter((item) => item.args[0] === 'split-window'),
    ).toHaveLength(2)
    expect(commands.at(-1)?.display).toContain('select-layout')
  })

  it('session 元数据只复用匹配项目和服务列表', async () => {
    const dir = await mkTempProject()
    const plan = await createLaunchPlan({
      action: 'start',
      projectRoot: dir,
      all: true,
      loadedConfig: {
        source: 'project-local',
        config: { services: [{ name: 'api', command: 'echo api' }] },
      },
    })
    const metadata = createSessionMetadata(
      plan,
      new Date('2026-06-16T00:00:00Z'),
    )

    expect(validateSessionMetadata(metadata, plan).ok).toBe(true)
    expect(
      validateSessionMetadata({ ...metadata, services: ['worker'] }, plan).ok,
    ).toBe(false)
  })

  it('通过 has-session 判断 tmux session 是否存在', async () => {
    const runner = recordRunner({
      'tmux has-session -t pl-demo': { exitCode: 0, stdout: '', stderr: '' },
    })

    await expect(tmuxSessionExists('pl-demo', runner, '.')).resolves.toBe(true)
  })
})

describe('CLI 输出', () => {
  it('plan --format json 输出 agent 可解析字段', async () => {
    const dir = await mkTempProject()
    await writeJson(join(dir, 'project-launch.local.json'), {
      services: [{ name: 'api', command: 'echo api', port: 8080 }],
    })
    const stdout: string[] = []
    const stderr: string[] = []
    const exitCode = await runCli(['plan', '--format', 'json'], {
      cwd: dir,
      runner: okRunner(),
      io: {
        stdout: (message) => stdout.push(message),
        stderr: (message) => stderr.push(message),
      },
    })

    expect(exitCode).toBe(0)
    const parsed = JSON.parse(stdout.join('\n'))
    expect(parsed.session).toMatch(/^pl-/)
    expect(parsed.attachCommand).toContain('tmux attach')
    expect(parsed.services[0].name).toBe('api')
  })
})

/**
 * 创建临时项目目录。
 *
 * @returns 临时目录路径。
 */
async function mkTempProject(): Promise<string> {
  return mkdtemp(join(tmpdir(), 'project-launcher-'))
}

/**
 * 写入 JSON 文件。
 *
 * @param filePath 文件路径。
 * @param value JSON 值。
 * @returns 无返回值。
 */
async function writeJson(filePath: string, value: unknown): Promise<void> {
  await writeFile(filePath, `${JSON.stringify(value, null, 2)}\n`, 'utf8')
}

/**
 * 创建测试服务候选。
 *
 * @param name 服务名。
 * @param command 启动命令。
 * @returns 服务候选。
 */
function service(name: string, command: string) {
  return {
    name,
    cwd: '.',
    command,
    source: 'config' as const,
    ports: [],
    prepare: [],
    env: {},
    reload: 'auto' as const,
    allowParallelBuild: false,
    confidence: 'high' as const,
    reasons: [],
  }
}

/**
 * 创建永远成功的命令执行器。
 *
 * @returns 命令执行器。
 */
function okRunner(): CommandRunner {
  return {
    async run() {
      return { exitCode: 0, stdout: '', stderr: '' }
    },
  }
}

/**
 * 创建可按命令字符串返回结果的 runner。
 *
 * @param responses 命令响应表。
 * @returns 命令执行器。
 */
function recordRunner(
  responses: Record<
    string,
    { exitCode: number; stdout: string; stderr: string }
  >,
): CommandRunner {
  return {
    async run(command, args) {
      return (
        responses[[command, ...args].join(' ')] ?? {
          exitCode: 1,
          stdout: '',
          stderr: 'missing response',
        }
      )
    },
  }
}
