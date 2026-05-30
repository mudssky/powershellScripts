import { mkdtemp, rm, writeFile } from 'node:fs/promises'
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

  it('doctor 输出安装参考', async () => {
    const stdout: string[] = []
    const exitCode = await runCli(['doctor'], {
      stdout: (message) => stdout.push(message),
      stderr: () => undefined,
    })

    expect(exitCode).toBe(0)
    expect(stdout.join('\n')).toContain('database-query doctor')
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
