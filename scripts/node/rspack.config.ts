import path from 'path'
import fs from 'fs'
import { defineConfig } from '@rspack/cli'
import { rspack } from '@rspack/core'

// Get all .ts files in src
const srcDir = path.resolve(__dirname, 'src')
const entries: Record<string, string> = {}

if (fs.existsSync(srcDir)) {
  const files = fs.readdirSync(srcDir)
  files.forEach((file) => {
    if (file.endsWith('.ts')) {
      const name = file.replace('.ts', '')
      entries[name] = path.join(srcDir, file)
    }
  })
}

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
    extensions: ['.ts', '.js'],
    modules: ['node_modules', path.resolve(__dirname, 'node_modules')],
  },
})
