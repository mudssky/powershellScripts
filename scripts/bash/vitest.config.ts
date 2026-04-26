import path from 'node:path'
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    include: [path.join(__dirname, 'tests', '**/*.test.ts')],
    testTimeout: 30_000,
  },
})
