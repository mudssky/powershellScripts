import { mkdir, rm } from 'node:fs/promises'
import { build } from 'rolldown'

await rm('scripts', { force: true, recursive: true })
await mkdir('scripts', { recursive: true })

await build({
  input: 'src/project-launcher.ts',
  platform: 'node',
  output: {
    file: 'scripts/project-launcher.js',
    format: 'esm',
    minify: false,
    banner: '#!/usr/bin/env node',
  },
})
