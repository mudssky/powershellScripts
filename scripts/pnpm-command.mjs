/**
 * 解析当前环境下最稳妥的 pnpm 启动方式。
 * npm_execpath 既可能指向 pnpm 的 JS 入口，也可能指向 Windows 的可执行包装器；
 * 这里统一返回可直接交给 spawnSync 的命令与前置参数，避免调用方重复判断平台细节。
 *
 * @returns {{ command: string, argsPrefix: string[] }}
 */
export function resolvePnpmRunner() {
  const pnpmExecPath =
    typeof process.env.npm_execpath === 'string' ? process.env.npm_execpath : null
  const pnpmExecPathLower = pnpmExecPath?.toLowerCase() ?? ''
  const pnpmExecPathLooksLikePnpm = pnpmExecPathLower.includes('pnpm')
  const pnpmExecPathUsesNodeRuntime = /\.(?:cjs|mjs|js)$/i.test(
    pnpmExecPath ?? '',
  )
  const pnpmExecPathIsDirectlyExecutable = /\.(?:exe|cmd|bat)$/i.test(
    pnpmExecPath ?? '',
  )

  if (pnpmExecPathLooksLikePnpm && pnpmExecPathUsesNodeRuntime) {
    return {
      command: process.execPath,
      argsPrefix: [pnpmExecPath],
    }
  }

  if (pnpmExecPathLooksLikePnpm && pnpmExecPathIsDirectlyExecutable) {
    return {
      command: pnpmExecPath,
      argsPrefix: [],
    }
  }

  return {
    command: process.platform === 'win32' ? 'pnpm.cmd' : 'pnpm',
    argsPrefix: [],
  }
}

/**
 * 构造一条可直接传给 spawnSync 的 pnpm 命令。
 * 调用方只需要关注业务参数，平台相关的执行细节由共享工具统一吸收。
 *
 * @param {string[]} pnpmArgs pnpm 原始参数
 * @returns {{ command: string, args: string[] }}
 */
export function buildPnpmCommand(pnpmArgs) {
  const runner = resolvePnpmRunner()

  return {
    command: runner.command,
    args: [...runner.argsPrefix, ...pnpmArgs],
  }
}
