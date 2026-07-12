import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  stat,
  writeFile,
} from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'

import {
  applyDatabaseFilters,
  filterSystemDatabases,
  formatResult,
  mergeDiscoveredDatabasesIntoConfig,
  parseDatabaseListOutput,
  probeTool,
  runCli,
} from '../src/cli'
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

  it('SQLite 执行场景允许仅配置 path 而不要求 database', () => {
    const target = resolveTarget(
      {
        instances: [
          {
            id: 'sqlite',
            type: 'sqlite',
            path: '/tmp/app.db',
          },
        ],
      },
      { requireDatabase: true },
    )

    expect(target.instance.id).toBe('sqlite')
    expect(target.database).toBeUndefined()
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
  it('context 默认输出 text 格式', async () => {
    const { configPath, cleanup } = await createTempConfig()
    const stdout: string[] = []

    try {
      const exitCode = await runCli(['context', '--config', configPath], {
        stdout: (message) => stdout.push(message),
        stderr: () => undefined,
      })
      const output = stdout.join('\n')

      expect(exitCode).toBe(0)
      expect(output).toContain('config:')
      expect(output).toContain('defaults:')
      expect(() => JSON.parse(output)).toThrow()
    } finally {
      await cleanup()
    }
  })

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
      expect(stdout.join('\n')).toMatch(/command: psql(\.exe)?/)
      expect(stdout.join('\n')).toContain('PGPASSWORD=<redacted>')
      expect(stdout.join('\n')).not.toContain('secret-value')
    } finally {
      await cleanup()
    }
  })

  it('exec --print-command 在原生命令缺失时使用 windows exe 客户端', async () => {
    const { configPath, cleanup } = await createTempConfig()
    const binDir = await mkdtemp(join(tmpdir(), 'database-query-bin-'))
    const previousPath = process.env.PATH
    const stdout: string[] = []

    try {
      const fakePsql = join(binDir, 'psql.exe')
      await writeFile(fakePsql, '#!/bin/sh\necho "psql fake"\n')
      await chmod(fakePsql, 0o755)
      process.env.PATH = binDir

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
          stderr: () => undefined,
        },
      )

      expect(exitCode).toBe(0)
      expect(stdout.join('\n')).toContain('command: psql.exe')
    } finally {
      restoreEnv('PATH', previousPath)
      await cleanup()
      await rm(binDir, { recursive: true, force: true })
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

  it('config paths 输出默认查找顺序与全局路径', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'database-query-paths-'))
    const previousXdgConfigHome = process.env.XDG_CONFIG_HOME
    const stdout: string[] = []
    process.env.XDG_CONFIG_HOME = dir

    try {
      const exitCode = await runCli(['config', 'paths', '--format', 'json'], {
        stdout: (message) => stdout.push(message),
        stderr: () => undefined,
      })
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(parsed.globalDirectory).toBe(join(dir, 'database-query'))
      expect(parsed.globalLocalConfigPath).toBe(
        join(dir, 'database-query', 'database-query.local.json'),
      )
      expect(parsed.filenames).toContain('database-query.local.json')
      expect(parsed.projectCandidates[0]).toContain('database-query.local.mjs')
    } finally {
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      await rm(dir, { recursive: true, force: true })
    }
  })

  it('config current 输出当前默认命中的配置路径', async () => {
    const fixture = await createConfigSearchFixture()
    const previousCwd = process.cwd()
    const stdout: string[] = []

    try {
      process.chdir(fixture.projectDir)
      const exitCode = await runCli(['config', 'current', '--format', 'json'], {
        stdout: (message) => stdout.push(message),
        stderr: () => undefined,
      })
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(parsed.mode).toBe('default')
      expect(parsed.path).toBe(fixture.projectConfigPath)
    } finally {
      process.chdir(previousCwd)
      await fixture.cleanup()
    }
  })

  it('config current 无配置时返回提示', async () => {
    const dir = await mkdtemp(join(tmpdir(), 'database-query-empty-'))
    const previousCwd = process.cwd()
    const previousXdgConfigHome = process.env.XDG_CONFIG_HOME
    const stdout: string[] = []
    const stderr: string[] = []
    process.env.XDG_CONFIG_HOME = join(dir, 'xdg')

    try {
      process.chdir(dir)
      const exitCode = await runCli(['config', 'current'], {
        stdout: (message) => stdout.push(message),
        stderr: (message) => stderr.push(message),
      })
      const output = stdout.join('\n')

      expect(exitCode).toBe(1)
      expect(output).toContain('path: <not-found>')
      expect(output).toContain('hint:')
      expect(stderr.join('\n')).toContain('未找到配置文件')
    } finally {
      process.chdir(previousCwd)
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      await rm(dir, { recursive: true, force: true })
    }
  })

  it('解析和过滤发现到的数据库名称', () => {
    const parsed = parseDatabaseListOutput(
      'template1\npostgres\napp\napp\nreporting\n',
    )

    expect(parsed).toEqual(['app', 'postgres', 'reporting', 'template1'])
    expect(filterSystemDatabases('postgres', parsed)).toEqual([
      'app',
      'postgres',
      'reporting',
    ])
    expect(
      filterSystemDatabases('mysql', [
        'information_schema',
        'mysql',
        'app',
        'sys',
        'tenant_bak',
      ]),
    ).toEqual(['app', 'tenant_bak'])
    expect(
      applyDatabaseFilters(['app', 'app_test', 'tenant_bak'], {
        include: 'app*',
        exclude: '*_test',
      }),
    ).toEqual(['app'])
  })

  it('合并发现库时保留已有条目并按需补默认库', () => {
    const merged = mergeDiscoveredDatabasesIntoConfig(
      {
        instances: [
          {
            id: 'pg',
            type: 'postgres',
            databases: [{ name: 'app', schemas: ['public'] }],
          },
        ],
      },
      {
        instanceId: 'pg',
        databases: ['postgres', 'app', 'reporting'],
        connectionDatabase: 'postgres',
      },
    )

    expect(merged.instances[0]?.defaultDatabase).toBe('postgres')
    expect(merged.instances[0]?.databases).toEqual([
      { name: 'app', schemas: ['public'] },
      { name: 'postgres' },
      { name: 'reporting' },
    ])
  })

  it('合并发现库时不覆盖已有 defaultDatabase', () => {
    const merged = mergeDiscoveredDatabasesIntoConfig(
      {
        instances: [
          {
            id: 'pg',
            type: 'postgres',
            defaultDatabase: 'app',
            databases: [{ name: 'app' }],
          },
        ],
      },
      {
        instanceId: 'pg',
        databases: ['postgres', 'reporting'],
        connectionDatabase: 'postgres',
      },
    )

    expect(merged.instances[0]?.defaultDatabase).toBe('app')
  })

  it('config discover-databases 默认只预览且不修改配置', async () => {
    const fixture = await createDiscoverFixture('postgres')
    const stdout: string[] = []

    try {
      const before = await readFile(fixture.configPath, 'utf8')
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--config',
          fixture.configPath,
          '--instance',
          'pg',
          '--include',
          'app*,postgres',
          '--exclude',
          '*_old',
          '--format',
          'json',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )
      const after = await readFile(fixture.configPath, 'utf8')
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(after).toBe(before)
      expect(parsed.write).toBe(false)
      expect(parsed.connectionDatabase).toBe('postgres')
      expect(parsed.discovered).toEqual(['app', 'app_old', 'postgres'])
      expect(parsed.selected).toEqual(['app', 'postgres'])
    } finally {
      await fixture.cleanup()
    }
  })

  it('config discover-databases 允许使用未预登记的 PostgreSQL 连接库', async () => {
    const fixture = await createDiscoverFixture('postgres')
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--config',
          fixture.configPath,
          '--instance',
          'pg',
          '--database',
          'maintenance',
          '--format',
          'json',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(parsed.connectionDatabase).toBe('maintenance')
    } finally {
      await fixture.cleanup()
    }
  })

  it('config discover-databases --write 写回 local JSON 并创建备份', async () => {
    const fixture = await createDiscoverFixture('mysql')
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--config',
          fixture.configPath,
          '--instance',
          'mysql',
          '--write',
          '--format',
          'json',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )
      const parsed = JSON.parse(stdout.join('\n'))
      const updated = JSON.parse(await readFile(fixture.configPath, 'utf8'))
      const backup = await stat(parsed.backupPath)

      expect(exitCode).toBe(0)
      expect(parsed.selected).toEqual(['app', 'reporting'])
      expect(parsed.updatedPath).toBe(fixture.configPath)
      expect(backup.isFile()).toBe(true)
      expect(updated.instances[0].databases).toEqual([
        { name: 'app', schemas: ['public'] },
        { name: 'reporting' },
      ])
      expect(JSON.stringify(updated)).toContain(
        '$' + '{env:DB_QUERY_TEST_PASSWORD}',
      )
    } finally {
      await fixture.cleanup()
    }
  })

  it('config discover-databases --global 写入 XDG 全局 local JSON', async () => {
    const fixture = await createGlobalDiscoverFixture()
    const stdout: string[] = []

    try {
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--global',
          '--instance',
          'mysql',
          '--write',
          '--format',
          'json',
        ],
        {
          stdout: (message) => stdout.push(message),
          stderr: () => undefined,
        },
      )
      const parsed = JSON.parse(stdout.join('\n'))

      expect(exitCode).toBe(0)
      expect(parsed.configPath).toBe(fixture.globalConfigPath)
      expect(parsed.updatedPath).toBe(fixture.globalConfigPath)
    } finally {
      await fixture.cleanup()
    }
  })

  it('config discover-databases 拒绝写回非 local JSON 配置', async () => {
    const fixture = await createDiscoverFixture('mysql', {
      fileName: 'database-query.config.json',
    })
    const stderr: string[] = []

    try {
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--config',
          fixture.configPath,
          '--instance',
          'mysql',
          '--write',
        ],
        {
          stdout: () => undefined,
          stderr: (message) => stderr.push(message),
        },
      )

      expect(exitCode).toBe(1)
      expect(stderr.join('\n')).toContain('*.local.json')
    } finally {
      await fixture.cleanup()
    }
  })

  it('config discover-databases 对不支持类型返回清晰错误', async () => {
    const fixture = await createUnsupportedDiscoverFixture()
    const stderr: string[] = []

    try {
      const exitCode = await runCli(
        [
          'config',
          'discover-databases',
          '--config',
          fixture.configPath,
          '--instance',
          'sqlite',
        ],
        {
          stdout: () => undefined,
          stderr: (message) => stderr.push(message),
        },
      )

      expect(exitCode).toBe(1)
      expect(stderr.join('\n')).toContain('暂不支持 sqlite')
    } finally {
      await fixture.cleanup()
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

  it('doctor 工具探测支持 windows .exe 兜底', () => {
    const result = probeTool('psql', (command) => {
      if (command === 'psql.exe') {
        return { ok: true, output: 'psql (PostgreSQL) 16.13\n' }
      }

      return { ok: false }
    })

    expect(result).toEqual({
      name: 'psql',
      command: 'psql.exe',
      origin: 'windows-exe',
      version: 'psql (PostgreSQL) 16.13',
    })
  })

  it('doctor 工具探测在命令完全缺失时返回 missing 状态', () => {
    const result = probeTool('mysql', () => ({ ok: false }))

    expect(result).toEqual({ name: 'mysql' })
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
 * 创建数据库发现 CLI 测试用配置与假客户端。
 *
 * @param type 数据库类型。
 * @param options 可选文件名覆盖。
 * @returns 配置、环境清理函数。
 */
async function createDiscoverFixture(
  type: 'postgres' | 'mysql',
  options: { fileName?: string } = {},
) {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-discover-'))
  const binDir = join(dir, 'bin')
  const configPath = join(dir, options.fileName ?? 'database-query.local.json')
  const previousPath = process.env.PATH

  await mkdir(binDir, { recursive: true })
  await writeFile(
    join(binDir, type === 'postgres' ? 'psql' : 'mysql'),
    type === 'postgres'
      ? '#!/bin/sh\nprintf "template1\\npostgres\\napp\\napp_old\\n"\n'
      : '#!/bin/sh\nprintf "information_schema\\nmysql\\nperformance_schema\\nsys\\napp\\nreporting\\n"\n',
  )
  await chmod(join(binDir, type === 'postgres' ? 'psql' : 'mysql'), 0o755)
  process.env.PATH = binDir

  await writeFile(
    configPath,
    JSON.stringify(
      {
        defaults: {
          defaultInstance: type === 'postgres' ? 'pg' : 'mysql',
        },
        instances: [
          type === 'postgres'
            ? {
                id: 'pg',
                type: 'postgres',
                host: 'localhost',
                username: 'app',
                password: '$' + '{env:DB_QUERY_TEST_PASSWORD}',
              }
            : {
                id: 'mysql',
                type: 'mysql',
                host: 'localhost',
                username: 'app',
                password: '$' + '{env:DB_QUERY_TEST_PASSWORD}',
                defaultDatabase: 'app',
                databases: [{ name: 'app', schemas: ['public'] }],
              },
        ],
      },
      null,
      2,
    ),
  )
  process.env.DB_QUERY_TEST_PASSWORD = 'secret-value'

  return {
    configPath,
    cleanup: async () => {
      restoreEnv('PATH', previousPath)
      delete process.env.DB_QUERY_TEST_PASSWORD
      await rm(dir, { recursive: true, force: true })
    },
  }
}

/**
 * 创建 XDG 全局发现写回测试夹具。
 *
 * @returns 全局配置路径与清理函数。
 */
async function createGlobalDiscoverFixture() {
  const dir = await mkdtemp(join(tmpdir(), 'database-query-global-discover-'))
  const xdgDir = join(dir, 'xdg')
  const globalDir = join(xdgDir, 'database-query')
  const globalConfigPath = join(globalDir, 'database-query.local.json')
  const fixture = await createDiscoverFixture('mysql')
  const previousXdgConfigHome = process.env.XDG_CONFIG_HOME

  await mkdir(globalDir, { recursive: true })
  await writeFile(globalConfigPath, await readFile(fixture.configPath, 'utf8'))
  process.env.XDG_CONFIG_HOME = xdgDir

  return {
    globalConfigPath,
    cleanup: async () => {
      restoreEnv('XDG_CONFIG_HOME', previousXdgConfigHome)
      await fixture.cleanup()
      await rm(dir, { recursive: true, force: true })
    },
  }
}

/**
 * 创建不支持类型的发现测试配置。
 *
 * @returns 配置路径与清理函数。
 */
async function createUnsupportedDiscoverFixture() {
  const dir = await mkdtemp(
    join(tmpdir(), 'database-query-discover-unsupported-'),
  )
  const configPath = join(dir, 'database-query.local.json')

  await writeFile(
    configPath,
    JSON.stringify({
      instances: [
        {
          id: 'sqlite',
          type: 'sqlite',
          path: '/tmp/app.db',
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
