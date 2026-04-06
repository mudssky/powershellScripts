#!/usr/bin/env node

import lintStaged from 'lint-staged'

/**
 * 解析包装脚本支持的 lint-staged 参数。
 * 这里只保留仓库当前会用到的常见选项，并把 Windows 下的参数分块逻辑固定关闭，
 * 以便 whole-repo 型任务（如 `rumdl check --fix .`）始终只启动一次。
 *
 * @param {string[]} argv 原始命令行参数
 * @returns {import('lint-staged').Options}
 */
function parseLintStagedOptions(argv) {
  /** @type {import('lint-staged').Options} */
  const options = {
    maxArgLength: null,
  }

  /**
   * 读取当前参数的值，支持 `--name=value` 与 `--name value` 两种形式。
   *
   * @param {string} current 当前参数
   * @param {string} name 参数名
   * @param {number} index 当前索引
   * @returns {[string, number]}
   */
  function readValue(current, name, index) {
    const inlinePrefix = `--${name}=`
    if (current.startsWith(inlinePrefix)) {
      return [current.slice(inlinePrefix.length), index]
    }

    const next = argv[index + 1]
    if (typeof next !== 'string') {
      throw new Error(`missing value for --${name}`)
    }

    return [next, index + 1]
  }

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index]

    switch (true) {
      case arg === '--allow-empty':
        options.allowEmpty = true
        break
      case arg === '--continue-on-error':
        options.continueOnError = true
        break
      case arg === '--debug':
        options.debug = true
        break
      case arg === '--fail-on-changes':
        options.failOnChanges = true
        break
      case arg === '--hide-unstaged':
        options.hideUnstaged = true
        break
      case arg === '--no-hide-partially-staged':
        options.hidePartiallyStaged = false
        break
      case arg === '--no-revert':
        options.revert = false
        break
      case arg === '--no-stash':
        options.stash = false
        break
      case arg === '--quiet':
        options.quiet = true
        break
      case arg === '--relative':
        options.relative = true
        break
      case arg === '--verbose':
        options.verbose = true
        break
      case arg === '--config' || arg.startsWith('--config='): {
        const [value, nextIndex] = readValue(arg, 'config', index)
        options.configPath = value
        index = nextIndex
        break
      }
      case arg === '--concurrent' || arg.startsWith('--concurrent='): {
        const [value, nextIndex] = readValue(arg, 'concurrent', index)
        if (value === 'true') {
          options.concurrent = true
        } else if (value === 'false') {
          options.concurrent = false
        } else {
          const parsed = Number(value)
          if (!Number.isFinite(parsed)) {
            throw new Error(`invalid value for --concurrent: ${value}`)
          }
          options.concurrent = parsed
        }
        index = nextIndex
        break
      }
      case arg === '--cwd' || arg.startsWith('--cwd='): {
        const [value, nextIndex] = readValue(arg, 'cwd', index)
        options.cwd = value
        index = nextIndex
        break
      }
      case arg === '--diff' || arg.startsWith('--diff='): {
        const [value, nextIndex] = readValue(arg, 'diff', index)
        options.diff = value
        index = nextIndex
        break
      }
      case arg === '--diff-filter' || arg.startsWith('--diff-filter='): {
        const [value, nextIndex] = readValue(arg, 'diff-filter', index)
        options.diffFilter = value
        index = nextIndex
        break
      }
      default:
        throw new Error(`unsupported argument: ${arg}`)
    }
  }

  return options
}

try {
  const success = await lintStaged(parseLintStagedOptions(process.argv.slice(2)))
  process.exit(success ? 0 : 1)
} catch (error) {
  const message = error instanceof Error ? error.message : String(error)
  console.error(`[lint-staged-wrapper] ${message}`)
  process.exit(1)
}
