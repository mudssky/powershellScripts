import fs from 'node:fs/promises'
import path from 'node:path'
import inquirer from 'inquirer'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { ClaudeInstaller } from '../src/rule-loader/installers/claude'

// Mock dependencies
vi.mock('fs/promises')
vi.mock('inquirer')

describe('ClaudeInstaller', () => {
  let installer: ClaudeInstaller
  const cwd = '/test/cwd'
  const configPath = path.resolve(cwd, '.claude', 'settings.json')

  beforeEach(() => {
    installer = new ClaudeInstaller()
    vi.resetAllMocks()
    // Default mocks
    vi.mocked(fs.mkdir).mockResolvedValue(undefined)
    // Silence console.log during tests
    vi.spyOn(console, 'log').mockImplementation(() => {})
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  it('should be named claude', () => {
    expect(installer.name).toBe('claude')
  })

  describe('install', () => {
    it('should create new config if file does not exist', async () => {
      // Mock readFile to fail with ENOENT
      vi.mocked(fs.readFile).mockRejectedValue({ code: 'ENOENT' })
      // Mock inquirer to confirm
      vi.mocked(inquirer.prompt).mockResolvedValue({ confirm: true })
      // Mock writeFile
      vi.mocked(fs.writeFile).mockResolvedValue(undefined)

      await installer.install({ cwd })

      // Verify file was written
      expect(fs.writeFile).toHaveBeenCalledTimes(1)
      const callArgs = vi.mocked(fs.writeFile).mock.calls[0]
      expect(callArgs[0]).toBe(configPath)
      const writtenConfig = JSON.parse(callArgs[1] as string)

      expect(writtenConfig.hooks).toBeDefined()
      expect(writtenConfig.hooks.SessionStart).toHaveLength(3)
      expect(writtenConfig.hooks.UserCommand).toHaveLength(1)
    })

    it('should merge with existing config', async () => {
      const existingConfig = {
        hooks: {
          SessionStart: [{ matcher: 'existing', hooks: [] }],
        },
        other: 'value',
      }

      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(existingConfig))
      vi.mocked(inquirer.prompt).mockResolvedValue({ confirm: true })
      vi.mocked(fs.writeFile).mockResolvedValue(undefined)

      await installer.install({ cwd })

      const callArgs = vi.mocked(fs.writeFile).mock.calls[0]
      const writtenConfig = JSON.parse(callArgs[1] as string)

      expect(writtenConfig.other).toBe('value')
      expect(writtenConfig.hooks.SessionStart).toHaveLength(4) // 1 existing + 3 new
      expect(writtenConfig.hooks.UserCommand).toHaveLength(1) // 1 new
    })

    it('should not duplicate existing hooks', async () => {
      const existingConfig = {
        hooks: {
          SessionStart: [
            {
              matcher: 'startup',
              hooks: [
                {
                  type: 'command',
                  command: "echo '项目启动，加载 Trae 规则...' && rule-loader",
                },
              ],
            },
          ],
        },
      }

      vi.mocked(fs.readFile).mockResolvedValue(JSON.stringify(existingConfig))
      vi.mocked(inquirer.prompt).mockResolvedValue({ confirm: true })
      vi.mocked(fs.writeFile).mockResolvedValue(undefined)

      await installer.install({ cwd })

      const callArgs = vi.mocked(fs.writeFile).mock.calls[0]
      const writtenConfig = JSON.parse(callArgs[1] as string)

      expect(writtenConfig.hooks.SessionStart).toHaveLength(3)
    })

    it('should skip write if user declines', async () => {
      vi.mocked(fs.readFile).mockRejectedValue({ code: 'ENOENT' })
      vi.mocked(inquirer.prompt).mockResolvedValue({ confirm: false })

      await installer.install({ cwd })

      expect(fs.writeFile).not.toHaveBeenCalled()
    })

    it('should force write if force option is true', async () => {
      vi.mocked(fs.readFile).mockRejectedValue({ code: 'ENOENT' })

      await installer.install({ cwd, force: true })

      expect(inquirer.prompt).not.toHaveBeenCalled()
      expect(fs.writeFile).toHaveBeenCalled()
    })
  })
})
