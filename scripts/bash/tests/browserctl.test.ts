import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { afterEach, describe, expect, it } from 'vitest'

const repoRoot = path.resolve(__dirname, '../../..')
const script = path.join(repoRoot, 'scripts/bash/browserctl.sh')
const roots: string[] = []
function fixture(exitCode = 0) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'browserctl-'))
  roots.push(root)
  const bin = path.join(root, 'bin')
  const log = path.join(root, 'argv.log')
  fs.mkdirSync(bin)
  fs.writeFileSync(
    path.join(bin, 'powershell.exe'),
    [
      '#!/bin/sh',
      'printf "%s\\n" "$@" > "$BROWSERCTL_TEST_LOG"',
      'printf \'{"schemaVersion":1,"state":"running"}\\n\'',
      `exit ${exitCode}`,
      '',
    ].join('\n'),
    { mode: 0o755 },
  )
  const host = path.join(root, 'browser-host.ps1')
  fs.writeFileSync(host, '# fixture')
  return { root, bin, log, host }
}
async function run(shell: string, args: string[], exitCode = 0) {
  const work = fixture(exitCode)
  const result = await execa(shell, [script, ...args], {
    cwd: work.root,
    env: {
      PATH: `${work.bin}:/usr/bin:/bin`,
      BROWSER_HOST_CONTROL_PATH: work.host,
      BROWSERCTL_TEST_LOG: work.log,
    },
    extendEnv: false,
    reject: false,
  })
  return { work, result }
}
afterEach(() => {
  for (const root of roots.splice(0))
    fs.rmSync(root, { recursive: true, force: true })
})
describe('browserctl Bash/Zsh wrapper', () => {
  for (const shell of [
    '/bin/bash',
    ...(fs.existsSync('/bin/zsh') ? ['/bin/zsh'] : []),
  ]) {
    it(`forwards argv and JSON/exit code from ${path.basename(shell)}`, async () => {
      const { work, result } = await run(shell, ['attach', 'agent-browser'], 7)
      expect(result.exitCode).toBe(7)
      expect(result.stdout).toContain('"state":"running"')
      expect(fs.readFileSync(work.log, 'utf8')).toContain(
        'attach\n-Client\nagent-browser',
      )
    })
    it(`routes setup through PowerShell and forwards path options from ${path.basename(shell)}`, async () => {
      const { work, result } = await run(shell, [
        'setup',
        'windows',
        '--source-root',
        'C:\\src\\self-hosted-compose',
        '--runtime-root',
        'D:\\browser-runtime',
        '--profile-root',
        'D:\\browser-runtime\\profile',
      ])
      expect(result.exitCode).toBe(0)
      const argv = fs.readFileSync(work.log, 'utf8')
      expect(argv).toContain('main.ps1\nsetup\nwindows')
      expect(argv).toContain('-SourceRoot\nC:\\src\\self-hosted-compose')
      expect(argv).toContain('-RuntimeRoot\nD:\\browser-runtime')
      expect(argv).toContain('-ProfileRoot\nD:\\browser-runtime\\profile')
      expect(argv).not.toContain(work.host)
    })
  }
  it('ordinary stop contains no destructive or recovery arguments', async () => {
    const { work, result } = await run('/bin/bash', ['stop'])
    expect(result.exitCode).toBe(0)
    expect(fs.readFileSync(work.log, 'utf8')).not.toMatch(
      /shutdown|kill|lock|recover/i,
    )
  })
  it('returns 127 with setup guidance when start has no installed host control', async () => {
    const work = fixture()
    fs.rmSync(work.host)
    const result = await execa('/bin/bash', [script, 'start', 'windows'], {
      cwd: work.root,
      env: {
        PATH: `${work.bin}:/usr/bin:/bin`,
        BROWSER_HOST_CONTROL_PATH: work.host,
        BROWSERCTL_TEST_LOG: work.log,
      },
      extendEnv: false,
      reject: false,
    })
    expect(result.exitCode).toBe(127)
    expect(result.stderr).toContain('browserctl setup windows')
    expect(fs.existsSync(work.log)).toBe(false)
  })
  it('fails closed for recovery without confirmation and invalid targets', async () => {
    expect((await run('/bin/bash', ['recover-owner'])).result.exitCode).toBe(2)
    expect((await run('/bin/bash', ['start', 'linux'])).result.exitCode).toBe(2)
  })
})
