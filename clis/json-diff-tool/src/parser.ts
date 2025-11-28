/**
 * JSON文件解析模块
 * 支持JSON、JSONC、JSON5三种格式的统一解析
 *
 * @author mudssky
 */

import * as fs from 'node:fs/promises'
import * as path from 'node:path'
import JSON5 from 'json5'
import { type JsonObject, SupportedFormat } from './types'

/**
 * 文件解析器类
 * 提供统一的JSON格式文件解析接口
 */
export class FileParser {
  /**
   * 解析JSON文件
   * @param filePath 文件路径
   * @returns 解析后的JSON对象
   * @throws 当文件不存在、格式错误或解析失败时抛出错误
   */
  async parseFile(filePath: string): Promise<JsonObject> {
    try {
      // 检查文件是否存在
      await this.validateFileExists(filePath)

      // 读取文件内容
      const content = await this.readFileContent(filePath)

      // 使用JSON5统一解析所有格式
      const parsed = JSON5.parse(content)

      // 验证解析结果是否为对象
      if (
        typeof parsed !== 'object' ||
        parsed === null ||
        Array.isArray(parsed)
      ) {
        throw new Error(
          `File ${filePath} must contain a JSON object at root level`,
        )
      }

      return parsed as JsonObject
    } catch (error) {
      if (error instanceof SyntaxError) {
        throw new Error(
          `Invalid ${this.detectFormat(
            filePath,
          ).toUpperCase()} syntax in file ${filePath}: ${error.message}`,
        )
      }

      if (error instanceof Error) {
        throw error
      }

      throw new Error(
        `Unknown error parsing file ${filePath}: ${String(error)}`,
      )
    }
  }

  /**
   * 检测文件格式
   * @param filePath 文件路径
   * @returns 文件格式类型
   */
  detectFormat(filePath: string): SupportedFormat {
    const ext = path.extname(filePath).toLowerCase()

    switch (ext) {
      case '.json':
        return SupportedFormat.JSON
      case '.jsonc':
        return SupportedFormat.JSONC
      case '.json5':
        return SupportedFormat.JSON5
      default:
        // 默认按JSON格式处理
        return SupportedFormat.JSON
    }
  }

  /**
   * 读取文件内容
   * @param filePath 文件路径
   * @returns 文件内容字符串
   * @throws 当文件读取失败时抛出错误
   */
  async readFileContent(filePath: string): Promise<string> {
    try {
      return await fs.readFile(filePath, 'utf-8')
    } catch (error) {
      if (error instanceof Error && 'code' in error) {
        const nodeError = error as NodeJS.ErrnoException

        switch (nodeError.code) {
          case 'ENOENT':
            throw new Error(`File not found: ${filePath}`)
          case 'EACCES':
            throw new Error(`Permission denied: ${filePath}`)
          case 'EISDIR':
            throw new Error(`Path is a directory, not a file: ${filePath}`)
          default:
            throw new Error(
              `Failed to read file ${filePath}: ${nodeError.message}`,
            )
        }
      }

      throw new Error(`Failed to read file ${filePath}: ${String(error)}`)
    }
  }

  /**
   * 验证文件是否存在
   * @param filePath 文件路径
   * @throws 当文件不存在时抛出错误
   */
  private async validateFileExists(filePath: string): Promise<void> {
    try {
      const stats = await fs.stat(filePath)

      if (!stats.isFile()) {
        throw new Error(`Path is not a file: ${filePath}`)
      }
    } catch (error) {
      if (error instanceof Error && 'code' in error) {
        const nodeError = error as NodeJS.ErrnoException

        if (nodeError.code === 'ENOENT') {
          throw new Error(`File not found: ${filePath}`)
        }
      }

      throw error
    }
  }

  /**
   * 批量解析多个文件
   * @param filePaths 文件路径数组
   * @returns 解析结果数组，包含文件路径和解析后的对象
   */
  async parseFiles(
    filePaths: string[],
  ): Promise<
    Array<{ filePath: string; content: JsonObject; format: SupportedFormat }>
  > {
    const results: Array<{
      filePath: string
      content: JsonObject
      format: SupportedFormat
    }> = []

    for (const filePath of filePaths) {
      try {
        const content = await this.parseFile(filePath)
        const format = this.detectFormat(filePath)

        results.push({
          filePath,
          content,
          format,
        })
      } catch (error) {
        // 重新抛出错误，包含文件路径信息
        throw new Error(
          `Error parsing file ${filePath}: ${
            error instanceof Error ? error.message : String(error)
          }`,
        )
      }
    }

    return results
  }

  /**
   * 获取支持的文件扩展名列表
   * @returns 支持的扩展名数组
   */
  static getSupportedExtensions(): string[] {
    return ['.json', '.jsonc', '.json5']
  }

  /**
   * 检查文件是否为支持的格式
   * @param filePath 文件路径
   * @returns 是否支持该格式
   */
  static isSupportedFormat(filePath: string): boolean {
    const ext = path.extname(filePath).toLowerCase()
    return FileParser.getSupportedExtensions().includes(ext)
  }
}
