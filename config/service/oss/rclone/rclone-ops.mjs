#!/usr/bin/env node

import { spawn, spawnSync } from 'node:child_process'
import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from 'node:fs'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url))
const DEFAULT_SOURCE_PATH = join(SCRIPT_DIR, 'rclone.config.local.json')
const DEFAULT_CONFIG_PATH = join(SCRIPT_DIR, 'rclone.conf')
const DEFAULT_RUNTIME_DIR = join(SCRIPT_DIR, '.runtime')
const DEFAULT_LOG_DIR = join(DEFAULT_RUNTIME_DIR, 'logs')
const DEFAULT_RC_ADDR = '127.0.0.1:5572'
const DEFAULT_RC_USER = 'admin'

/**
 * 解析命令行参数，保留 `--` 之后需要原样传给 rclone 的参数。
 *
 * @param {string[]} argv 原始命令行参数，不包含 node 与脚本路径。
 * @returns {{command: string, positional: string[], flags: Map<string, string|boolean>, passthrough: string[]}} 规范化后的命令结构。
 */
export function parseArgs(argv) {
  const [command = 'help', ...rest] = argv
  const positional = []
  const flags = new Map()
  const passthroughIndex = rest.indexOf('--')
  const parsedPart =
    passthroughIndex >= 0 ? rest.slice(0, passthroughIndex) : rest
  const passthrough =
    passthroughIndex >= 0 ? rest.slice(passthroughIndex + 1) : []

  for (let index = 0; index < parsedPart.length; index += 1) {
    const item = parsedPart[index]
    if (!item.startsWith('--')) {
      positional.push(item)
      continue
    }

    const [rawKey, inlineValue] = item.slice(2).split('=', 2)
    if (inlineValue !== undefined) {
      flags.set(rawKey, inlineValue)
      continue
    }

    const next = parsedPart[index + 1]
    if (next && !next.startsWith('--')) {
      flags.set(rawKey, next)
      index += 1
      continue
    }

    flags.set(rawKey, true)
  }

  return { command, positional, flags, passthrough }
}

/**
 * 读取命令行 flag、环境变量或默认值。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag 集合。
 * @param {string} name flag 名称。
 * @param {string} envName 环境变量名称。
 * @param {string} fallback 默认值。
 * @returns {string} 解析后的字符串值。
 */
function resolveOption(flags, name, envName, fallback) {
  const value = flags.get(name)
  if (typeof value === 'string' && value.length > 0) {
    return value
  }
  if (process.env[envName]) {
    return process.env[envName]
  }
  return fallback
}

/**
 * 安全读取文本文件；文件不存在时抛出清晰错误。
 *
 * @param {string} path 文件路径。
 * @returns {string} 文件内容。
 */
function readTextFile(path) {
  if (!existsSync(path)) {
    throw new Error(`配置文件不存在：${path}`)
  }
  return readFileSync(path, 'utf8')
}

/**
 * 读取 JSON 主配置文件。
 *
 * @param {string} path 配置文件路径。
 * @returns {Record<string, unknown>} JSON 顶层配置对象。
 */
export function readConfigValues(path) {
  if (!/\.json$/i.test(path)) {
    throw new Error('rclone-ops 仅支持 JSON 主配置；.env 不再用于表达多 remote 配置。')
  }
  return JSON.parse(readTextFile(path))
}

/**
 * 替换 JSON 字符串中的环境变量占位符。
 *
 * @param {unknown} value 待替换的配置值。
 * @param {string} context 当前值所在配置路径，用于错误提示。
 * @returns {unknown} 替换后的配置值。
 */
export function resolveEnvPlaceholders(value, context = 'config') {
  if (typeof value !== 'string') {
    return value
  }
  return value.replace(/\$\{([A-Za-z_][A-Za-z0-9_]*)}/g, (_, envName) => {
    const envValue = process.env[envName]
    if (envValue === undefined) {
      throw new Error(`环境变量未设置: ${envName}（${context}）`)
    }
    return envValue
  })
}

/**
 * 安全读取可选 JSON 主配置文件。
 *
 * @param {string} path 配置文件路径。
 * @returns {Record<string, unknown>} 文件存在时返回 JSON 顶层配置，否则返回空对象。
 */
function readOptionalConfigValues(path) {
  if (!existsSync(path)) {
    return {}
  }
  return readConfigValues(path)
}

/**
 * 读取嵌套 JSON 配置值。
 *
 * @param {Record<string, unknown>} values 顶层 JSON 配置对象。
 * @param {string} section section 名称。
 * @param {string} name section 内部键名。
 * @returns {unknown} 命中的配置值；未命中时返回 undefined。
 */
function getNestedConfigValue(values, section, name) {
  const sectionValue = values?.[section]
  if (!sectionValue || typeof sectionValue !== 'object' || Array.isArray(sectionValue)) {
    return undefined
  }
  return sectionValue[name]
}

/**
 * 按 flag、环境变量、JSON 配置、默认值的优先级解析选项。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag 集合。
 * @param {string} name flag 名称。
 * @param {string} envName 环境变量名称。
 * @param {Record<string, unknown>} configValues 顶层 JSON 配置对象。
 * @param {string} section JSON section 名称。
 * @param {string} configName JSON section 内部键名。
 * @param {string} fallback 默认值。
 * @returns {string} 解析后的字符串值。
 */
export function resolveOptionWithConfig(
  flags,
  name,
  envName,
  configValues,
  section,
  configName,
  fallback,
) {
  const flagValue = flags.get(name)
  if (typeof flagValue === 'string' && flagValue.length > 0) {
    return flagValue
  }
  if (process.env[envName]) {
    return process.env[envName]
  }
  const configValue = getNestedConfigValue(configValues, section, configName)
  if (configValue !== undefined && String(configValue).length > 0) {
    return String(resolveEnvPlaceholders(configValue, `${section}.${configName}`))
  }
  return fallback
}

/**
 * 根据 JSON remotes 数组生成 rclone remote 定义。
 *
 * @param {Record<string, unknown>|{values: Record<string, unknown>}} configValues JSON 顶层配置对象。
 * @returns {Array<Record<string, string>>} rclone remote 定义列表。
 */
export function buildRemoteDefinitions(configValues) {
  const values = configValues.values ?? configValues
  if (Object.hasOwn(values, 'RCLONE_REMOTE_NAMES')) {
    throw new Error('旧平铺格式已不支持；请改用 JSON remotes 数组。')
  }
  if (!Array.isArray(values.remotes)) {
    throw new Error('配置缺少 remotes 数组，无法生成 rclone remote。')
  }
  if (values.remotes.length === 0) {
    throw new Error('配置 remotes 数组不能为空。')
  }

  return values.remotes.map((remote, index) => {
    if (!remote || typeof remote !== 'object' || Array.isArray(remote)) {
      throw new Error(`remotes[${index}] 必须是对象。`)
    }

    const { name, ...rawSettings } = remote
    if (typeof name !== 'string' || name.trim().length === 0) {
      throw new Error(`remotes[${index}] 缺少 name。`)
    }

    const settings = Object.fromEntries(
      Object.entries(rawSettings).map(([key, value]) => [
        key,
        String(resolveEnvPlaceholders(value, `remotes[${index}].${key}`)),
      ]),
    )
    if (!settings.type) {
      throw new Error(`remote '${name}' 缺少 type。`)
    }
    return { name, ...settings }
  })
}

/**
 * 将 remote 定义渲染成 rclone.conf 文本。
 *
 * @param {Array<Record<string, string>>} remotes remote 定义列表。
 * @returns {string} rclone 配置文件内容。
 */
export function renderRcloneConfig(remotes) {
  return `${remotes
    .map((remote) => {
      const { name, ...settings } = remote
      const body = Object.entries(settings)
        .filter(([, value]) => value !== undefined && value !== '')
        .map(([key, value]) => `${key} = ${value}`)
        .join('\n')
      return `[${name}]\n${body}`
    })
    .join('\n\n')}\n`
}

/**
 * 读取 rclone.conf 中的 remote 名称。
 *
 * @param {string} content rclone.conf 文本。
 * @returns {string[]} remote 名称列表。
 */
export function listRemoteNames(content) {
  return [...content.matchAll(/^\[([^\]]+)]\s*$/gm)].map((match) => match[1])
}

/**
 * 创建目录，已存在时保持幂等。
 *
 * @param {string} path 目录路径。
 * @returns {void}
 */
function ensureDir(path) {
  mkdirSync(path, { recursive: true })
}

/**
 * 写入本地 rclone.conf，并限制权限避免其他用户读取密钥。
 *
 * @param {string} path 输出路径。
 * @param {string} content 配置内容。
 * @param {boolean} overwrite 是否覆盖已有文件。
 * @returns {void}
 */
function writeSecretConfig(path, content, overwrite) {
  if (existsSync(path) && !overwrite) {
    throw new Error(`配置已存在：${path}。如需覆盖请追加 --overwrite。`)
  }
  ensureDir(dirname(path))
  writeFileSync(path, content, { mode: 0o600 })
  chmodSync(path, 0o600)
}

/**
 * 检查 rclone 命令是否可用。
 *
 * @param {string} binary rclone 可执行文件路径或命令名。
 * @returns {{ok: boolean, stdout: string, stderr: string}} 检查结果。
 */
function checkRclone(binary) {
  const result = spawnSync(binary, ['version'], { encoding: 'utf8' })
  return {
    ok: result.status === 0,
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? result.error?.message ?? '',
  }
}

/**
 * 运行 rclone 并继承当前终端输入输出。
 *
 * @param {string} binary rclone 命令。
 * @param {string[]} args rclone 参数。
 * @param {{background?: boolean, pidFile?: string}} options 运行选项。
 * @returns {Promise<number>} 退出码；后台模式成功时返回 0。
 */
function runRclone(binary, args, options = {}) {
  if (options.background) {
    ensureDir(
      dirname(options.pidFile ?? join(DEFAULT_RUNTIME_DIR, 'rclone.pid')),
    )
    const child = spawn(binary, args, {
      detached: true,
      stdio: 'ignore',
    })
    child.unref()
    if (options.pidFile) {
      writeFileSync(options.pidFile, `${child.pid}\n`)
    }
    console.log(`已后台启动 rclone，PID=${child.pid}`)
    return Promise.resolve(0)
  }

  return new Promise((resolveExit) => {
    const child = spawn(binary, args, { stdio: 'inherit' })
    child.on('exit', (code) => resolveExit(code ?? 0))
  })
}

/**
 * 生成 rclone.conf。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @returns {void}
 */
function commandInitConfig(flags) {
  const sourcePath = resolveOption(
    flags,
    'source',
    'RCLONE_SOURCE_CONFIG_PATH',
    DEFAULT_SOURCE_PATH,
  )
  const configPath = resolveOption(
    flags,
    'config',
    'RCLONE_CONFIG_PATH',
    DEFAULT_CONFIG_PATH,
  )
  const remotes = buildRemoteDefinitions(readConfigValues(sourcePath))
  if (remotes.length === 0) {
    throw new Error(
      `未从 ${sourcePath} 解析到可用 remote，请参考 rclone.config.example.json 补齐配置。`,
    )
  }
  writeSecretConfig(
    configPath,
    renderRcloneConfig(remotes),
    flags.has('overwrite'),
  )
  console.log(
    `已生成 ${configPath}，remote: ${remotes.map((remote) => remote.name).join(', ')}`,
  )
}

/**
 * 输出环境与配置健康检查结果。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @returns {void}
 */
function commandDoctor(flags) {
  const binary = resolveOption(flags, 'rclone', 'RCLONE_BIN', 'rclone')
  const configPath = resolveOption(
    flags,
    'config',
    'RCLONE_CONFIG_PATH',
    DEFAULT_CONFIG_PATH,
  )
  const rclone = checkRclone(binary)
  console.log(`rclone: ${rclone.ok ? 'OK' : 'MISSING'} (${binary})`)
  if (!rclone.ok && rclone.stderr) {
    console.log(rclone.stderr.trim())
  }
  console.log(
    `config: ${existsSync(configPath) ? 'OK' : 'MISSING'} (${configPath})`,
  )
  if (existsSync(configPath)) {
    console.log(
      `remotes: ${listRemoteNames(readFileSync(configPath, 'utf8')).join(', ') || '<empty>'}`,
    )
  }
}

/**
 * 构造通用 rclone 参数。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @returns {{binary: string, configPath: string}} rclone 可执行文件与配置路径。
 */
function resolveRcloneRuntime(flags) {
  return {
    binary: resolveOption(flags, 'rclone', 'RCLONE_BIN', 'rclone'),
    configPath: resolveOption(
      flags,
      'config',
      'RCLONE_CONFIG_PATH',
      DEFAULT_CONFIG_PATH,
    ),
  }
}

/**
 * 启动 rclone RC/WebUI。
 *
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @param {string[]} passthrough 透传给 rclone 的额外参数。
 * @returns {Promise<number>} rclone 退出码。
 */
function commandWebui(flags, passthrough) {
  const { binary, configPath } = resolveRcloneRuntime(flags)
  const sourcePath = resolveOption(
    flags,
    'source',
    'RCLONE_SOURCE_CONFIG_PATH',
    DEFAULT_SOURCE_PATH,
  )
  const sourceValues = readOptionalConfigValues(sourcePath)
  const rcAddr = resolveOptionWithConfig(
    flags,
    'addr',
    'RCLONE_RC_ADDR',
    sourceValues,
    'webui',
    'addr',
    DEFAULT_RC_ADDR,
  )
  const rcPass = resolveOptionWithConfig(
    flags,
    'pass',
    'RCLONE_RC_PASS',
    sourceValues,
    'webui',
    'pass',
    '',
  )
  const rcUser = rcPass
    ? resolveOptionWithConfig(
        flags,
        'user',
        'RCLONE_RC_USER',
        sourceValues,
        'webui',
        'user',
        DEFAULT_RC_USER,
      )
    : ''
  const isBackground = flags.has('background')
  const logFile = resolveOption(
    flags,
    'log-file',
    'RCLONE_LOG_FILE',
    join(DEFAULT_LOG_DIR, 'webui.log'),
  )
  if (isBackground) {
    ensureDir(dirname(logFile))
  }
  const rcloneCheck = checkRclone(binary)
  if (!rcloneCheck.ok) {
    throw new Error(
      `未找到 rclone 命令：${binary}。请先安装 rclone，或通过 --rclone / RCLONE_BIN 指定路径。`,
    )
  }

  // WebUI 会暴露 RC API；默认绑定 localhost，并鼓励设置密码，避免误暴露到局域网。
  const args = [
    'rcd',
    '--rc-web-gui',
    `--rc-addr=${rcAddr}`,
    `--config=${configPath}`,
    ...passthrough,
  ]
  if (isBackground) {
    args.push(`--log-file=${logFile}`)
  }
  if (rcPass) {
    args.push(`--rc-user=${rcUser}`, `--rc-pass=${rcPass}`)
  }
  if (flags.has('no-open-browser')) {
    args.push('--rc-web-gui-no-open-browser')
  }

  console.log('准备启动 rclone WebUI/RC：')
  console.log(`  地址: http://${rcAddr}`)
  console.log(`  配置: ${configPath}`)
  console.log(`  日志: ${isBackground ? logFile : '当前终端（rclone stdout/stderr）'}`)
  if (!rcPass) {
    console.log(
      '  认证: 未设置 RCLONE_RC_PASS，rclone 会生成临时认证信息；建议日常运维显式设置强密码。',
    )
  }
  if (isBackground) {
    console.log('  模式: 后台启动，可用 stop-webui 停止。')
  } else {
    console.log('  模式: 前台运行，rclone 日志会直接显示在当前终端，按 Ctrl+C 停止。')
    console.log('  提示: 如需命令立即返回，请使用 --background --no-open-browser。')
  }

  return runRclone(binary, args, {
    background: isBackground,
    pidFile: join(DEFAULT_RUNTIME_DIR, 'webui.pid'),
  })
}

/**
 * 执行 rclone 常用传输命令。
 *
 * @param {string} action rclone 子命令。
 * @param {string[]} positional 位置参数。
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @param {string[]} passthrough 透传参数。
 * @returns {Promise<number>} rclone 退出码。
 */
function commandTransfer(action, positional, flags, passthrough) {
  const { binary, configPath } = resolveRcloneRuntime(flags)
  if (positional.length < 2) {
    throw new Error(`${action} 需要 <source> <dest> 两个参数。`)
  }
  const safetyArgs = action === 'sync' && !flags.has('run') ? ['--dry-run'] : []
  if (action === 'sync' && !flags.has('run')) {
    console.log(
      '安全默认：sync 当前为 dry-run；确认无误后追加 --run 才会真实执行。',
    )
  }
  return runRclone(binary, [
    action,
    positional[0],
    positional[1],
    `--config=${configPath}`,
    ...safetyArgs,
    ...passthrough,
  ])
}

/**
 * 执行 rclone list/check/mount 等单次命令。
 *
 * @param {string} action rclone 子命令。
 * @param {string[]} positional 位置参数。
 * @param {Map<string, string|boolean>} flags 命令行 flag。
 * @param {string[]} passthrough 透传参数。
 * @returns {Promise<number>} rclone 退出码。
 */
function commandGeneric(action, positional, flags, passthrough) {
  const { binary, configPath } = resolveRcloneRuntime(flags)
  return runRclone(
    binary,
    [action, ...positional, `--config=${configPath}`, ...passthrough],
    {
      background: flags.has('background'),
      pidFile: join(DEFAULT_RUNTIME_DIR, `${action}.pid`),
    },
  )
}

/**
 * 卸载本地挂载点，按当前平台选择常见卸载命令。
 *
 * @param {string[]} positional 位置参数，第一项为挂载点。
 * @returns {Promise<number>} 卸载命令退出码。
 */
function commandUnmount(positional) {
  const mountPoint = positional[0]
  if (!mountPoint) {
    throw new Error('unmount 需要 <mount-point> 参数。')
  }
  if (process.platform === 'darwin') {
    return runRclone('diskutil', ['unmount', mountPoint])
  }
  if (process.platform === 'linux') {
    return runRclone('fusermount', ['-u', mountPoint])
  }
  return runRclone('umount', [mountPoint])
}

/**
 * 停止通过后台模式启动的 WebUI。
 *
 * @returns {void}
 */
function commandStopWebui() {
  const pidFile = join(DEFAULT_RUNTIME_DIR, 'webui.pid')
  if (!existsSync(pidFile)) {
    console.log('未找到 WebUI PID 文件。')
    return
  }
  const pid = Number.parseInt(readFileSync(pidFile, 'utf8'), 10)
  if (!Number.isFinite(pid)) {
    throw new Error(`PID 文件内容无效：${pidFile}`)
  }
  process.kill(pid, 'SIGTERM')
  console.log(`已发送 SIGTERM 到 WebUI 进程：${pid}`)
}

/**
 * 输出帮助信息。
 *
 * @returns {void}
 */
function printHelp() {
  console.log(`rclone 通用运维脚本

用法：
  node rclone-ops.mjs init-config [--overwrite] [--source rclone.config.local.json] [--config rclone.conf]
  node rclone-ops.mjs doctor [--config rclone.conf]
  node rclone-ops.mjs webui [--background] [--addr 127.0.0.1:5572] [--user admin] [--pass ***] [--no-open-browser]
  node rclone-ops.mjs stop-webui
  node rclone-ops.mjs lsd <remote:>
  node rclone-ops.mjs ls <remote:path>
  node rclone-ops.mjs mount <remote:path> <mount-point> [--background] -- [额外 rclone 参数]
  node rclone-ops.mjs unmount <mount-point>
  node rclone-ops.mjs copy <source> <dest> -- [额外 rclone 参数]
  node rclone-ops.mjs sync <source> <dest> [--run] -- [额外 rclone 参数]
  node rclone-ops.mjs check <source> <dest> -- [额外 rclone 参数]

安全默认：
  - sync 默认追加 --dry-run，只有显式传入 --run 才真实执行。
  - WebUI 默认监听 ${DEFAULT_RC_ADDR}；未设置 RCLONE_RC_PASS 时由 rclone WebUI 自动生成临时认证信息。
  - rclone.conf 由 init-config 本地生成，默认不应提交到 Git。
`)
}

/**
 * CLI 主入口。
 *
 * @param {string[]} argv 命令行参数。
 * @returns {Promise<number>} 进程退出码。
 */
export async function main(argv) {
  const { command, positional, flags, passthrough } = parseArgs(argv)
  switch (command) {
    case 'help':
    case '--help':
    case '-h':
      printHelp()
      return 0
    case 'init-config':
      commandInitConfig(flags)
      return 0
    case 'doctor':
      commandDoctor(flags)
      return 0
    case 'webui':
      return commandWebui(flags, passthrough)
    case 'stop-webui':
      commandStopWebui()
      return 0
    case 'copy':
    case 'sync':
    case 'check':
      return commandTransfer(command, positional, flags, passthrough)
    case 'ls':
    case 'lsd':
    case 'mount':
    case 'serve':
      return commandGeneric(command, positional, flags, passthrough)
    case 'unmount':
      return commandUnmount(positional)
    default:
      throw new Error(
        `未知命令：${command}。执行 node rclone-ops.mjs help 查看用法。`,
      )
  }
}

const isCliEntry =
  process.argv[1] &&
  pathToFileURL(resolve(process.argv[1])).href === import.meta.url

if (isCliEntry) {
  main(process.argv.slice(2))
    .then((exitCode) => {
      process.exitCode = exitCode
    })
    .catch((error) => {
      console.error(error instanceof Error ? error.message : String(error))
      process.exitCode = 1
    })
}
