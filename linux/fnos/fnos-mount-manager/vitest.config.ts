import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'

const configDir = path.dirname(fileURLToPath(import.meta.url))

export default defineConfig({
  root: configDir,
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
    testTimeout: 15_000,
  },
})
