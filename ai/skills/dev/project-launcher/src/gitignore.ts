import { appendFile, readFile } from 'node:fs/promises'
import { join } from 'node:path'

import { exists } from './config.js'

const IGNORE_ENTRY = '.project-launcher/'

/**
 * 检查项目 .gitignore 是否忽略运行态目录。
 *
 * @param projectRoot 项目根目录。
 * @returns 已忽略时为 true。
 */
export async function isRuntimeDirectoryIgnored(
  projectRoot: string,
): Promise<boolean> {
  const gitignorePath = join(projectRoot, '.gitignore')
  if (!(await exists(gitignorePath))) {
    return false
  }
  const content = await readFile(gitignorePath, 'utf8')
  return content
    .split(/\r?\n/)
    .map((line) => line.trim())
    .some((line) => line === IGNORE_ENTRY || line === '.project-launcher')
}

/**
 * 写入 .project-launcher/ 忽略规则。
 *
 * @param projectRoot 项目根目录。
 * @returns 是否实际写入。
 */
export async function writeRuntimeGitignore(
  projectRoot: string,
): Promise<boolean> {
  if (await isRuntimeDirectoryIgnored(projectRoot)) {
    return false
  }

  const gitignorePath = join(projectRoot, '.gitignore')
  const prefix = (await exists(gitignorePath)) ? '\n' : ''
  await appendFile(gitignorePath, `${prefix}${IGNORE_ENTRY}\n`, 'utf8')
  return true
}
