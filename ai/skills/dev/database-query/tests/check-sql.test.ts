import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

import { formatResult, runCli } from '../src/cli'
import { createContextSnapshot, loadConfig, resolveTarget } from '../src/config'
import {
  checkSql,
  extractLimit,
  hasResultLimit,
  splitSqlStatements,
  stripSqlNoise,
} from '../src/core'

describe('SQL guard 静态分析', () => {
  it('忽略注释和字符串中的危险关键词', () => {
    const normalized = stripSqlNoise(
      "select 'drop table users' as note -- delete\nfrom audit limit 5",
    )

    expect(normalized).not.toMatch(/drop table users/i)
    expect(normalized).not.toMatch(/delete/i)
  })

  it('按真实语句分号拆分 SQL', () => {
    const statements = splitSqlStatements(
      "select ';' as semi limit 1; select 2 limit 1;",
    )

    expect(statements).toHaveLength(2)
  })

  it('允许 readonly 下带 LIMIT 的查询', () => {
    const result = checkSql('select id, name from users limit 10', {
      dialect: 'postgres',
      level: 'readonly',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(true)
    expect(result.findings).toHaveLength(0)
  })

  it('阻断 readonly 下缺少 LIMIT 的查询', () => {
    const result = checkSql('select * from users', {
      dialect: 'postgres',
      level: 'readonly',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(false)
    expect(result.findings).toContainEqual(
      expect.objectContaining({ code: 'MISSING_LIMIT', severity: 'block' }),
    )
  })

  it('阻断 readonly 下过大的 LIMIT', () => {
    const result = checkSql('select * from users limit 5000', {
      dialect: 'mysql',
      level: 'readonly',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(false)
    expect(result.findings).toContainEqual(
      expect.objectContaining({ code: 'LIMIT_TOO_LARGE', severity: 'block' }),
    )
  })

  it('阻断多语句', () => {
    const result = checkSql('select * from users limit 1; drop table users;', {
      dialect: 'postgres',
      level: 'readonly',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(false)
    expect(result.findings).toContainEqual(
      expect.objectContaining({ code: 'MULTI_STATEMENT', severity: 'block' }),
    )
  })

  it('阻断 DML 和 DDL', () => {
    const updateResult = checkSql(
      "update users set role = 'admin' where id = 1",
      {
        dialect: 'postgres',
        level: 'readonly',
        maxLimit: 1000,
      },
    )
    const dropResult = checkSql('drop table users', {
      dialect: 'sqlite',
      level: 'readonly',
      maxLimit: 1000,
    })

    expect(updateResult.kind).toBe('write')
    expect(dropResult.kind).toBe('ddl')
    expect(updateResult.ok).toBe(false)
    expect(dropResult.ok).toBe(false)
  })

  it('maintenance 允许维护类语句但阻断写入', () => {
    const explainResult = checkSql('explain select * from users limit 1', {
      dialect: 'postgres',
      level: 'maintenance',
      maxLimit: 1000,
    })
    const deleteResult = checkSql('delete from users where id = 1', {
      dialect: 'postgres',
      level: 'maintenance',
      maxLimit: 1000,
    })

    expect(explainResult.ok).toBe(true)
    expect(deleteResult.ok).toBe(false)
    expect(deleteResult.findings).toContainEqual(
      expect.objectContaining({ code: 'MAINTENANCE_FORBIDDEN' }),
    )
  })

  it('admin 对导出仍保持阻断', () => {
    const result = checkSql("copy users to '/tmp/users.csv'", {
      dialect: 'postgres',
      level: 'admin',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(false)
    expect(result.findings).toContainEqual(
      expect.objectContaining({
        code: 'ADMIN_EXPORT_REVIEW',
        severity: 'block',
      }),
    )
  })

  it('yolo 将静态阻断降级为警告', () => {
    const result = checkSql('drop table users', {
      dialect: 'postgres',
      level: 'yolo',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(true)
    expect(result.findings).toContainEqual(
      expect.objectContaining({ severity: 'warn' }),
    )
  })

  it('空 SQL 即使在 yolo 下也阻断', () => {
    const result = checkSql('', {
      dialect: 'postgres',
      level: 'yolo',
      maxLimit: 1000,
    })

    expect(result.ok).toBe(false)
    expect(result.findings).toContainEqual(
      expect.objectContaining({ code: 'EMPTY_SQL', severity: 'block' }),
    )
  })

  it('识别 LIMIT', () => {
    expect(hasResultLimit('select * from users limit 20')).toBe(true)
    expect(extractLimit('select * from users limit 20')).toBe(20)
  })
})

describe('SQL guard CLI', () => {
  it('输出中文帮助', async () => {
    const stdout: string[] = []
    const exitCode = await runCli(['check-sql', '--help'], {
      stdout: (message) => stdout.push(message),
      stderr: () => undefined,
    })

    expect(exitCode).toBe(0)
    expect(stdout.join('\n')).toContain('Usage')
    expect(stdout.join('\n')).toContain('--dialect <dialect>')
  })

  it('输出阻断报告和非零退出码', async () => {
    const stdout: string[] = []
    const stderr: string[] = []
    const exitCode = await runCli(['check-sql', '--sql', 'drop table users'], {
      stdout: (message) => stdout.push(message),
      stderr: (message) => stderr.push(message),
    })

    expect(exitCode).toBe(2)
    expect(stderr.join('\n')).toContain('SQL guard 阻断执行')
    expect(stdout.join('\n')).toContain('SQL guard: BLOCK')
  })

  it('格式化 yolo 风险提示', () => {
    const report = formatResult(
      checkSql('drop table users', {
        dialect: 'postgres',
        level: 'yolo',
        maxLimit: 1000,
      }),
    )

    expect(report).toContain('yolo 层级只跳过静态阻断')
    expect(report).toContain('[warn]')
  })
})

describe('database-query 配置与上下文', () => {
  it('解析 JSON env 占位符并输出脱敏上下文', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'database-query-'))
    const configPath = join(dir, 'database-query.config.json')
    process.env.DB_QUERY_TEST_PASSWORD = 'secret-value'

    await writeFile(
      configPath,
      JSON.stringify({
        defaults: { defaultInstance: 'pg', limit: 25 },
        instances: [
          {
            id: 'pg',
            type: 'postgres',
            host: 'localhost',
            username: 'app',
            password: '$' + '{env:DB_QUERY_TEST_PASSWORD}',
            defaultDatabase: 'app',
            databases: [{ name: 'app', schemas: ['public'] }],
          },
        ],
      }),
    )

    try {
      const loaded = await loadConfig(configPath)
      const snapshot = createContextSnapshot(loaded)

      expect(loaded.config.instances[0]?.password).toBe('secret-value')
      expect(snapshot.instances[0]?.secretStatus.password).toBe('present')
      expect(JSON.stringify(snapshot)).not.toContain('secret-value')
    } finally {
      delete process.env.DB_QUERY_TEST_PASSWORD
      await rm(dir, { recursive: true, force: true })
    }
  })

  it('显式 --config 路径优先于默认查找', async () => {
    const fixture = await createConfigSearchFixture()

    try {
      const loaded = await loadConfig(fixture.explicitConfigPath)

      expect(loaded.path).toBe(fixture.explicitConfigPath)
      expect(loaded.config.defaults?.defaultInstance).toBe('explicit')
    } finally {
      await fixture.cleanup()
    }
  })

  it('当前目录配置优先于 XDG 全局配置', async () => {
    const fixture = await createConfigSearchFixture()
    const previousCwd = process.cwd()

    try {
      process.chdir(fixture.projectDir)
      const loaded = await loadConfig()

      expect(loaded.path).toBe(fixture.projectConfigPath)
      expect(loaded.config.defaults?.defaultInstance).toBe('project')
    } finally {
      process.chdir(previousCwd)
      await fixture.cleanup()
    }
  })

  it('当前目录无配置时读取 XDG 全局配置', async () => {
    const fixture = await createConfigSearchFixture()
    const previousCwd = process.cwd()

    try {
      process.chdir(fixture.emptyProjectDir)
      const loaded = await loadConfig()

      expect(loaded.path).toBe(fixture.globalConfigPath)
      expect(loaded.config.defaults?.defaultInstance).toBe('global')
    } finally {
      process.chdir(previousCwd)
      await fixture.cleanup()
    }
  })

  it('未设置 XDG_CONFIG_HOME 时回退到 HOME 下的 .config', async () => {
    const fixture = await createHomeFallbackFixture()
    const previousCwd = process.cwd()

    try {
      process.chdir(fixture.emptyProjectDir)
      const loaded = await loadConfig()

      expect(loaded.path).toBe(fixture.globalConfigPath)
      expect(loaded.config.defaults?.defaultInstance).toBe('home-global')
    } finally {
      process.chdir(previousCwd)
      await fixture.cleanup()
    }
  })

  it('按默认实例与单候选解析目标', () => {
    const target = resolveTarget(
      {
        defaults: { defaultInstance: 'pg' },
        instances: [
          {
            id: 'pg',
            type: 'postgres',
            defaultDatabase: 'app',
            databases: [{ name: 'app', schemas: ['public'] }],
          },
          {
            id: 'mysql',
            type: 'mysql',
            databases: [{ name: 'reporting' }],
          },
        ],
      },
      { requireDatabase: true },
    )

    expect(target.instance.id).toBe('pg')
    expect(target.database?.name).toBe('app')
    expect(target.schema).toBe('public')
  })

  it('defaultDatabase 存在时允许省略 databases 候选', () => {
    const target = resolveTarget(
      {
        defaults: { defaultInstance: 'pg' },
        instances: [
          {
            id: 'pg',
            type: 'postgres',
            defaultDatabase: 'app',
          },
        ],
      },
      { requireDatabase: true },
    )

    expect(target.database?.name).toBe('app')
  })

  it('显式 database 存在时允许省略 databases 候选', () => {
    const target = resolveTarget(
      {
        instances: [
          {
            id: 'mysql',
            type: 'mysql',
          },
        ],
      },
      { instance: 'mysql', database: 'reporting', requireDatabase: true },
    )

    expect(target.database?.name).toBe('reporting')
  })

  it('需要数据库但没有 defaultDatabase 或显式 database 时报错', () => {
    expect(() =>
      resolveTarget(
        {
          instances: [
            {
              id: 'pg',
              type: 'postgres',
            },
          ],
        },
        { requireDatabase: true },
      ),
    ).toThrow(/需要 database/)
  })

  it('多实例无默认值时要求显式指定', () => {
    expect(() =>
      resolveTarget(
        {
          instances: [
            { id: 'pg', type: 'postgres' },
            { id: 'mysql', type: 'mysql' },
          ],
        },
        {},
      ),
    ).toThrow(/无法唯一确定 instance/)
  })
})

describe('database-query 统一 CLI', () => {
  it('context --format json 输出 agent 可解析上下文', async () => {
    const { configPath, cleanup } = await createTempConfig()
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        ['context', '--config', configPath, '--format', 'json'],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(parsed.instances[0].id).toBe('pg')
      expect(parsed.instances[0].secretStatus.password).toBe('present')
      expect(stdout.join('\n')).not.toContain('secret-value')
    } finally {
      await cleanup()
    }
  })

  it('exec --print-command 自动运行 guard 并打印脱敏计划', async () => {
    const { configPath, cleanup } = await createTempConfig()
    const stdout: string[] = []
    const stderr: string[] = []

    try {
      const exitCode = await runCli(
        [
          'exec',
          '--config',
          configPath,
          '--sql',
          'select id from users limit 10',
          '--print-command',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: (message) => stderr.push(message),
        },
      )

      expect(exitCode).toBe(0)
      expect(stderr).toHaveLength(0)
      expect(stdout.join('\n')).toContain('SQL guard: PASS')
      expect(stdout.join('\n')).toContain('command: psql')
      expect(stdout.join('\n')).toContain('PGPASSWORD=<redacted>')
      expect(stdout.join('\n')).not.toContain('secret-value')
    } finally {
      await cleanup()
    }
  })

  it('client --print-command 透传参数并脱敏凭据', async () => {
    const { configPath, cleanup } = await createTempConfig()
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'client',
          '--config',
          configPath,
          '--print-command',
          '--',
          '--set',
          'ON_ERROR_STOP=1',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )

      expect(exitCode).toBe(0)
      expect(stdout.join('\n')).toContain('--set ON_ERROR_STOP=1')
      expect(stdout.join('\n')).toContain('PGPASSWORD=<redacted>')
      expect(stdout.join('\n')).not.toContain('secret-value')
    } finally {
      await cleanup()
    }
  })

  it('client --print-command 支持只配置 defaultDatabase', async () => {
    const { configPath, cleanup } = await createTempConfigWithoutDatabases()
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'client',
          '--config',
          configPath,
          '--print-command',
          '--',
          '--set',
          'ON_ERROR_STOP=1',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )

      expect(exitCode).toBe(0)
      expect(stdout.join('\n')).toContain('PostgreSQL pg/app')
      expect(stdout.join('\n')).toContain('-d app')
    } finally {
      await cleanup()
    }
  })

  it('client --print-command 支持显式 database 且省略 databases', async () => {
    const { configPath, cleanup } = await createTempConfigWithoutDatabases({
      defaultDatabase: undefined,
    })
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'client',
          '--config',
          configPath,
          '--database',
          'reporting',
          '--print-command',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )

      expect(exitCode).toBe(0)
      expect(stdout.join('\n')).toContain('PostgreSQL pg/reporting')
      expect(stdout.join('\n')).toContain('-d reporting')
    } finally {
      await cleanup()
    }
  })

  it('init-config --print 输出最小模板且不包含真实密钥', async () => {
    const stdout: string[] = []
    const exitCode = await runCli(['init-config', '--global', '--print'], {
      stdout: (message) => stdout.push(message),
      stderr: () => undefined,
    })
    const parsed = JSON.parse(stdout.join('\n'))

    expect(exitCode).toBe(0)
    expect(parsed.defaults.defaultInstance).toBe('local-postgres')
    expect(parsed.instances[0].defaultDatabase).toBe('app')
    expect(parsed.instances[0].databases).toBeUndefined()
    expect(stdout.join('\n')).toContain(
      '$' + '{env:DB_LOCAL_POSTGRES_PASSWORD}',
    )
  })

  it('init-config --global 写入 XDG 全局配置且默认不覆盖', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'database-query-init-'))
    const previousXdgConfigHome = process.env.XDG_CONFIG_HOME
    const stdout: string[] = []
    const stderr: string[] = []
    process.env.XDG_CONFIG_HOME = dir

    try {
      const firstExitCode = await runCli(['init-config', '--global'], {
        stdout: (message) => stdout.push(message),
        stderr: (message) => stderr.push(message),
      })
      const secondExitCode = await runCli(['init-config', '--global'], {
        stdout: (message) => stdout.push(message),
        stderr: (message) => stderr.push(message),
      })

      expect(firstExitCode).toBe(0)
      expect(secondExitCode).toBe(1)
      expect(stdout.join('\n')).toContain(
        join(dir, 'database-query', 'database-query.local.json'),
      )
      expect(stderr.join('\n')).toContain('配置文件已存在')
    } finally {
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      await rm(dir, { recursive: true, force: true })
    }
  })

  it('doctor 输出安装参考', async () => {
    const stdout: string[] = []
    const exitCode = await runCli(['doctor'], {
      stdout: (message) => stdout.push(message),
      stderr: () => undefined,
    })

    expect(exitCode).toBe(0)
    expect(stdout.join('\n')).toContain('database-query doctor')
    expect(stdout.join('\n')).toContain('不自动安装底层客户端')
    expect(stdout.join('\n')).toContain('references/client-installation.md')
  })
})

/**
 * 创建临时 database-query 配置。
 *
 * @returns 配置路径与清理函数。
 */
async function createTempConfig() {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-'))
  const configPath = join(dir, 'database-query.config.json')

  await writeFile(
    configPath,
    JSON.stringify({
      defaults: {
        defaultInstance: 'pg',
        limit: 25,
        maxLimit: 1000,
        permissionLevel: 'readonly',
      },
      instances: [
        {
          id: 'pg',
          type: 'postgres',
          host: 'localhost',
          port: 5432,
          username: 'app',
          password: 'secret-value',
          defaultDatabase: 'app',
          databases: [{ name: 'app', schemas: ['public'] }],
        },
      ],
    }),
  )

  return {
    configPath,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  }
}

/**
 * 创建省略 databases[] 的临时配置。
 *
 * @param options 可选默认库覆盖。
 * @returns 配置路径与清理函数。
 */
async function createTempConfigWithoutDatabases(
  options: { defaultDatabase?: string } = { defaultDatabase: 'app' },
) {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-no-databases-'))
  const configPath = join(dir, 'database-query.config.json')

  await writeFile(
    configPath,
    JSON.stringify({
      defaults: {
        defaultInstance: 'pg',
      },
      instances: [
        {
          id: 'pg',
          type: 'postgres',
          host: 'localhost',
          port: 5432,
          username: 'app',
          password: 'secret-value',
          defaultDatabase: options.defaultDatabase,
        },
      ],
    }),
  )

  return {
    configPath,
    cleanup: () => rm(dir, { recursive: true, force: true }),
  }
}

/**
 * 创建用于默认配置查找优先级测试的临时目录。
 *
 * @returns 配置路径集合与清理函数。
 */
async function createConfigSearchFixture() {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-search-'))
  const projectDir = join(dir, 'project')
  const emptyProjectDir = join(dir, 'empty-project')
  const explicitDir = join(dir, 'explicit')
  const xdgDir = join(dir, 'xdg')
  const globalDir = join(xdgDir, 'database-query')
  const previousXdgConfigHome = process.env.XDG_CONFIG_HOME

  await mkdir(projectDir, { recursive: true })
  await mkdir(emptyProjectDir, { recursive: true })
  await mkdir(explicitDir, { recursive: true })
  await mkdir(globalDir, { recursive: true })

  const projectConfigPath = join(projectDir, 'database-query.local.json')
  const explicitConfigPath = join(explicitDir, 'database-query.local.json')
  const globalConfigPath = join(globalDir, 'database-query.local.json')

  await writeMinimalConfig(projectConfigPath, 'project')
  await writeMinimalConfig(explicitConfigPath, 'explicit')
  await writeMinimalConfig(globalConfigPath, 'global')
  process.env.XDG_CONFIG_HOME = xdgDir

  return {
    projectDir,
    emptyProjectDir,
    projectConfigPath,
    explicitConfigPath,
    globalConfigPath,
    cleanup: async () => {
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      await rm(dir, { recursive: true, force: true })
    },
  }
}

/**
 * 创建 HOME 回退路径测试的临时目录。
 *
 * @returns 配置路径集合与清理函数。
 */
async function createHomeFallbackFixture() {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-home-'))
  const emptyProjectDir = join(dir, 'empty-project')
  const homeDir = join(dir, 'home')
  const globalDir = join(homeDir, '.config', 'database-query')
  const previousXdgConfigHome = process.env.XDG_CONFIG_HOME
  const previousHome = process.env.HOME

  await mkdir(emptyProjectDir, { recursive: true })
  await mkdir(globalDir, { recursive: true })

  const globalConfigPath = join(globalDir, 'database-query.local.json')
  await writeMinimalConfig(globalConfigPath, 'home-global')
  delete process.env.XDG_CONFIG_HOME
  process.env.HOME = homeDir

  return {
    emptyProjectDir,
    globalConfigPath,
    cleanup: async () => {
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      restoreEnv('HOME', previousHome)
      await rm(dir, { recursive: true, force: true })
    },
  }
}

/**
 * 写入最小 database-query 配置。
 *
 * @param configPath 配置文件路径。
 * @param instanceId 默认实例与实例 ID。
 * @returns 无返回值。
 */
async function writeMinimalConfig(
  configPath: string,
  instanceId: string,
): Promise<void> {
  await writeFile(
    configPath,
    JSON.stringify({
      defaults: { defaultInstance: instanceId },
      instances: [{ id: instanceId, type: 'postgres' }],
    }),
  )
}

/**
 * 恢复被测试临时覆盖的环境变量。
 *
 * @param name 环境变量名称。
 * @param value 原始环境变量值。
 * @returns 无返回值。
 */
function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name]
    return
  }

  process.env[name] = value
}
