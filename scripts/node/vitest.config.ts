import { defineConfig } from 'vitest/config'

process.env.FORCE_COLOR ??= '1'
delete process.env.NO_COLOR

export default defineConfig({
  test: {
    include: ['tests/**/*.test.ts'],
    environment: 'node',
    testTimeout: 10000,
  },
})
