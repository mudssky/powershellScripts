import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import { createRequire } from 'node:module'
import os from 'node:os'
import path from 'node:path'
import { describe, expect, it } from 'vitest'

const require = createRequire(import.meta.url)

type RunOptions = {
  cwd?: string
  env?: NodeJS.ProcessEnv
}

const runCommand = (
  command: string,
  args: string[],
  options: RunOptions = {},
) => {
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'node-script-cli-'))
  const stdoutPath = path.join(tempDir, 'stdout.log')
  const stderrPath = path.join(tempDir, 'stderr.log')
  const stdoutFd = fs.openSync(stdoutPath, 'w')
  const stderrFd = fs.openSync(stderrPath, 'w')

  try {
    const result = spawnSync(command, args, {
      cwd: options.cwd,
      env: {
        ...process.env,
        ...options.env,
      },
      stdio: ['ignore', stdoutFd, stderrFd],
    })

    const stdout = fs.readFileSync(stdoutPath, 'utf8')
    const stderr = fs.readFileSync(stderrPath, 'utf8')
    const exitCode = result.status ?? 1

    if (exitCode !== 0) {
      const details = [stderr.trim(), stdout.trim()].filter(Boolean).join('\n')
      throw new Error(
        `Command failed with exit code ${exitCode}: ${command} ${args.join(' ')}${details ? `\n${details}` : ''}`,
      )
    }

    return {
      stdout,
      stderr,
    }
  } finally {
    fs.closeSync(stdoutFd)
    fs.closeSync(stderrFd)
    fs.rmSync(tempDir, { recursive: true, force: true })
  }
}

// Helper to run the script (preferring source, falling back to built bin)
const runScript = async (
  scriptName: string,
  args: string[] = [],
  options: RunOptions = {},
) => {
  // 1. Try running from source first (faster feedback, no build needed)
  const sourcePath = path.resolve(__dirname, `../src/${scriptName}/index.ts`)

  if (fs.existsSync(sourcePath)) {
    try {
      const tsxLoaderPath = require.resolve('tsx')
      return runCommand(
        process.execPath,
        ['--import', tsxLoaderPath, sourcePath, ...args],
        options,
      )
    } catch {
      try {
        const tsxPath = require.resolve('tsx/cli')
        return runCommand(
          process.execPath,
          [tsxPath, sourcePath, ...args],
          options,
        )
      } catch {
        return runCommand('tsx', [sourcePath, ...args], options)
      }
    }
  }

  // 2. Fallback to built binary
  const binPath = path.resolve(
    __dirname,
    '../../../bin',
    process.platform === 'win32' ? `${scriptName}.cmd` : scriptName,
  )

  // Ensure build exists
  if (!fs.existsSync(binPath)) {
    throw new Error(`Script not found at ${binPath}. Did you run 'pnpm build'?`)
  }

  return runCommand(binPath, args, options)
}

describe('CLI Integration Tests', () => {
  it('should run rule-loader --version', async () => {
    const { stdout } = await runScript('rule-loader', ['--version'])

    expect(stdout).toContain('1.0.0')
  })

  it('should run rule-loader --help', async () => {
    const { stdout } = await runScript('rule-loader', ['--help'])

    expect(stdout).toContain('Usage: rule-loader')
    expect(stdout).toContain('AI 编码规则加载器')
  })

  it('should show --full option in load command help', async () => {
    const { stdout } = await runScript('rule-loader', ['load', '--help'])
    expect(stdout).toContain('--full')
  })

  it('should run rule-loader --full', async () => {
    // 运行全量模式，并通过 cwd 选项指向测试目录（因为 loader 默认找 .trae/rules）
    // 但 CLI 没有直接暴露 rulesDir 选项，它是通过 options.rulesDir 传递给 loadRules 的
    // 不过，rule-loader 默认在 cwd 下找 .trae/rules
    // 所以我们需要构造一个临时的 .trae/rules 结构或者让 loader 支持指定目录

    // 查看 cli.ts 发现 run 函数没有暴露 rulesDir 参数，它只接受 format, filterApply 等
    // 但 loader.ts 的 loadRules 函数接受 rulesDir。
    // cli.ts 的 createCli 并没有暴露 --rules-dir 选项。
    // 让我们先通过 SearchCodebase 确认 cli.ts 是否支持指定目录，或者我们是否需要添加它。

    // 假设 cli.ts 没有支持指定目录，我们可能需要 mock process.cwd 或者修改 cli.ts 支持 --dir
    // 或者我们在测试中临时创建一个 .trae/rules 目录。

    // 为了简单起见，我们在 cli.ts 中添加一个隐藏的 --rules-dir 选项用于测试，或者
    // 我们在测试运行时切换 cwd。

    // 让我们先尝试切换 cwd。
    // runScript 使用 execa，可以指定 cwd。

    // 我们需要一个包含 .trae/rules 的目录。
    // fixtures/rule-loader 里面直接是 md 文件。
    // 我们创建一个临时目录结构。

    const tempRoot = path.resolve(__dirname, './temp_test_root')
    const rulesDir = path.join(tempRoot, '.trae/rules')

    await fs.promises.mkdir(rulesDir, { recursive: true })

    // 复制一些测试文件
    await fs.promises.writeFile(
      path.join(rulesDir, '00_global.md'),
      '---\nalwaysApply: true\n---\n# Global Rule',
    )
    await fs.promises.writeFile(
      path.join(rulesDir, '10_conditional.md'),
      '---\nglobs: *.js\n---\n# Conditional Rule',
    )

    try {
      const { stdout } = await runScript('rule-loader', ['load', '--full'], {
        cwd: tempRoot,
      })

      expect(stdout).toContain('Global Rule')
      expect(stdout).toContain('Conditional Rule')
      expect(stdout).not.toContain('CONDITIONAL RULES INDEX')
    } finally {
      // 清理
      await fs.promises.rm(tempRoot, { recursive: true, force: true })
    }
  })
})
