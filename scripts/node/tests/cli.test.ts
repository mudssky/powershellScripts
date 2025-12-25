import { execa } from 'execa'
import fs from 'fs'
import path from 'path'
import { describe, expect, it } from 'vitest'

// Helper to run the built script
const runScript = async (scriptName: string, args: string[] = []) => {
  const binPath = path.resolve(
    __dirname,
    '../../../bin',
    process.platform === 'win32' ? `${scriptName}.cmd` : scriptName,
  )

  // Ensure build exists
  if (!fs.existsSync(binPath)) {
    throw new Error(`Script not found at ${binPath}. Did you run 'pnpm build'?`)
  }

  return execa(binPath, args)
}

describe('CLI Integration Tests', () => {
  it('should run hello script successfully', async () => {
    const { stdout } = await runScript('hello', ['integration-test'])

    expect(stdout).toContain('Hello from Rspack bundled script!')
    expect(stdout).toContain('You said: integration-test')
  })

  it('should handle no arguments', async () => {
    const { stdout } = await runScript('hello')

    expect(stdout).toContain('No arguments provided')
  })
})
