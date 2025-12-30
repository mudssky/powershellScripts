import fs from 'fs/promises'
import path from 'path'
import matter from 'gray-matter'
import type { TraeRule, AntigravityRuleMetadata } from '../types'

/**
 * Antigravity 规则转换器
 */
export class AntigravityConverter {
  /**
   * 转换所有规则
   *
   * @param rules - Trae 规则数组
   * @param outputDir - 输出目录
   */
  async convert(rules: TraeRule[], outputDir: string): Promise<void> {
    // 确保输出目录存在
    await fs.mkdir(outputDir, { recursive: true })

    for (const rule of rules) {
      try {
        const { metadata, content } = this.convertOne(rule)
        const fileName = `${rule.id}.md`
        const outputPath = path.join(outputDir, fileName)

        // 使用 gray-matter 生成带有 Frontmatter 的文件内容
        const fileContent = matter.stringify(content, metadata)

        await fs.writeFile(outputPath, fileContent, 'utf-8')
      } catch (error) {
        console.error(`转换规则失败: ${rule.id}`, error)
      }
    }
  }

  /**
   * 转换单个规则
   *
   * @param rule - Trae 规则
   * @returns 转换后的元数据和内容
   */
  private convertOne(rule: TraeRule): {
    metadata: AntigravityRuleMetadata
    content: string
  } {
    const { metadata } = rule
    let trigger: AntigravityRuleMetadata['trigger'] = 'manual'

    const hasGlobs = !!(metadata.globs || metadata.glob)
    // Trae 规则默认 alwaysApply 为 true
    const alwaysApply = metadata.alwaysApply !== false

    // 映射逻辑
    if (alwaysApply) {
      if (hasGlobs) {
        // 如果有 glob 且总是应用，映射为 glob 触发
        trigger = 'glob'
      } else {
        // 全局强制规则
        trigger = 'always_on'
      }
    } else {
      // 非强制规则，映射为手动触发
      trigger = 'manual'
    }

    // 构造 Antigravity 元数据
    const newMetadata: AntigravityRuleMetadata = {
      trigger,
      description: metadata.description,
      globs: metadata.globs || metadata.glob,
    }

    // 清理 undefined 字段
    if (!newMetadata.globs) delete newMetadata.globs
    if (!newMetadata.description) delete newMetadata.description

    return {
      metadata: newMetadata,
      content: rule.content,
    }
  }
}
