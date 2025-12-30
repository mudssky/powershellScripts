import fs from 'node:fs'
import path from 'node:path'
import { defineConfig } from '@rspack/cli'
import { rspack } from '@rspack/core'

// Get all .ts files in src
// 注意：对于包含 index.ts 的子目录（如 rule-loader），只将 index.ts 作为入口
const srcDir = path.resolve(__dirname, 'src')
const entries: Record<string, string> = {}

function scanDir(dir: string, basePrefix = '') {
  if (!fs.existsSync(dir)) {
    return
  }

  const files = fs.readdirSync(dir)
  files.forEach((file) => {
    const fullPath = path.join(dir, file)
    const stat = fs.statSync(fullPath)

    if (stat.isDirectory()) {
      // 检查是否有 index.ts
      const indexPath = path.join(fullPath, 'index.ts')
      if (fs.existsSync(indexPath)) {
        // 如果有 index.ts，只将 index.ts 作为入口
        const newPrefix = basePrefix ? `${basePrefix}/${file}` : file
        const entryName = newPrefix.split(path.sep).join('/')
        entries[entryName] = indexPath
      } else {
        // 否则递归扫描子目录
        const newPrefix = basePrefix ? `${basePrefix}/${file}` : file
        scanDir(fullPath, newPrefix)
      }
    } else if (file.endsWith('.ts') && file !== 'index.ts') {
      // 对于非 index.ts 的文件，直接作为入口（如 load-trae-rules.ts）
      if (!basePrefix) {
        const nameWithoutExt = file.replace('.ts', '')
        entries[nameWithoutExt] = fullPath
      }
    }
  })
}

scanDir(srcDir)

export default defineConfig({
  mode: 'production',
  target: 'node',
  entry: entries,
  optimization: {
    minimize: process.env.MINIFY !== 'false',
  },
  output: {
    path: path.resolve(__dirname, 'dist'),
    filename: '[name].cjs',
    clean: true,
  },
  module: {
    rules: [
      {
        test: /\.ts$/,
        exclude: [/node_modules/],
        loader: 'builtin:swc-loader',
        options: {
          jsc: {
            parser: {
              syntax: 'typescript',
            },
          },
        },
      },
    ],
  },
  plugins: [
    new rspack.BannerPlugin({
      banner: '#!/usr/bin/env node',
      raw: true,
      entryOnly: true,
    }),
  ],
  resolve: {
    extensions: ['.ts', '.js', '.json'],
    modules: ['node_modules', path.resolve(__dirname, 'node_modules')],
    // 添加完全解析配置，确保相对路径正确解析
    fullySpecified: false,
    // 添加 mainFields 和 mainFiles 配置
    mainFields: ['main', 'module'],
    mainFiles: ['index', 'index.ts', 'index.js'],
  },
})
