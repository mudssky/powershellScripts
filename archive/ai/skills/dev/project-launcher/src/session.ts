import { createHash } from 'node:crypto'
import { mkdir, readFile, writeFile } from 'node:fs/promises'
import { dirname } from 'node:path'

import { exists } from './config.js'
import type { LaunchPlan, SessionMetadata } from './types.js'

/**
 * 创建 session 元数据。
 *
 * @param plan 启动计划。
 * @param now 当前时间。
 * @returns session 元数据。
 */
export function createSessionMetadata(
  plan: LaunchPlan,
  now = new Date(),
): SessionMetadata {
  return {
    managedBy: 'project-launcher',
    session: plan.session,
    projectRoot: plan.projectRoot,
    configPath: plan.configPath,
    configHash: createPlanHash(plan),
    services: plan.services.map((service) => service.name),
    createdAt: now.toISOString(),
  }
}

/**
 * 写入 session 元数据。
 *
 * @param metadataPath 元数据路径。
 * @param metadata 元数据。
 * @returns 无返回值。
 */
export async function writeSessionMetadata(
  metadataPath: string,
  metadata: SessionMetadata,
): Promise<void> {
  await mkdir(dirname(metadataPath), { recursive: true })
  await writeFile(
    metadataPath,
    `${JSON.stringify(metadata, null, 2)}\n`,
    'utf8',
  )
}

/**
 * 读取 session 元数据。
 *
 * @param metadataPath 元数据路径。
 * @returns 元数据或 undefined。
 */
export async function readSessionMetadata(
  metadataPath: string,
): Promise<SessionMetadata | undefined> {
  if (!(await exists(metadataPath))) {
    return undefined
  }
  return JSON.parse(await readFile(metadataPath, 'utf8')) as SessionMetadata
}

/**
 * 判断元数据是否匹配当前计划。
 *
 * @param metadata 已保存元数据。
 * @param plan 当前启动计划。
 * @returns 匹配结果和原因。
 */
export function validateSessionMetadata(
  metadata: SessionMetadata | undefined,
  plan: LaunchPlan,
): { ok: boolean; reason?: string } {
  if (!metadata) {
    return { ok: false, reason: '缺少 .project-launcher/session.json' }
  }
  if (metadata.managedBy !== 'project-launcher') {
    return { ok: false, reason: 'session 不是 project-launcher 管理' }
  }
  if (metadata.session !== plan.session) {
    return { ok: false, reason: 'session 名不匹配' }
  }
  if (metadata.projectRoot !== plan.projectRoot) {
    return { ok: false, reason: '项目根目录不匹配' }
  }
  const currentServices = plan.services.map((service) => service.name).sort()
  const metadataServices = [...metadata.services].sort()
  if (currentServices.join(',') !== metadataServices.join(',')) {
    return { ok: false, reason: '服务列表不匹配' }
  }
  return { ok: true }
}

/**
 * 生成计划指纹。
 *
 * @param plan 启动计划。
 * @returns 短 hash。
 */
export function createPlanHash(plan: LaunchPlan): string {
  const payload = {
    configPath: plan.configPath,
    services: plan.services.map((service) => ({
      name: service.name,
      cwd: service.cwd,
      command: service.command,
      ports: service.ports,
    })),
  }
  return createHash('sha256')
    .update(JSON.stringify(payload))
    .digest('hex')
    .slice(0, 12)
}
