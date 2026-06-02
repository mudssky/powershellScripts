import { mkdir, rm } from 'node:fs/promises'
import { build } from 'rolldown'

await rm('scripts', { force: true, recursive: true })
await mkdir('scripts', { recursive: true })

await build({
  input: 'src/database-query.ts',
  platform: 'node',
  external: ['@zilliz/milvus2-sdk-node'],
  output: {
    file: 'scripts/database-query.js',
    format: 'esm',
    minify: false,
    banner: '#!/usr/bin/env node',
  },
})
