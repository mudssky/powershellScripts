/**
 * 判断某个 QA 分支是否只应在 Linux 上执行。
 *
 * `fnos` 这类依赖 Bash / Linux 文件系统语义的测试在非 Linux 平台上
 * 没有稳定意义，因此这里统一提供平台判定 helper，避免在多个 QA 入口里散落条件。
 *
 * @param {string} [platform=process.platform] Node 运行时平台标识。
 * @returns {boolean} 仅当平台为 `linux` 时返回 `true`。
 */
export function shouldRunLinuxOnlyQa(platform = process.platform) {
  return platform === 'linux'
}
