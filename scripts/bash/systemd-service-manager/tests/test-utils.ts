import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'

const repoRoot = path.resolve(__dirname, '../../../..')
const managerRoot = path.join(
  repoRoot,
  'scripts',
  'bash',
  'systemd-service-manager',
)

export type Workspace = {
  root: string
  managerHome: string
  sourceEntry: string
  buildScript: string
  builtBin: string
  builtLocal: string
  fakeSystemDir: string
  fakeUserDir: string
  mockBin: string
  home: string
}

export type RunResult = {
  stdout: string
  stderr: string
  exitCode: number
}

export function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ssm-'))
  const managerHome = path.join(root, 'scripts', 'bash', 'systemd-service-manager')
  const fakeSystemDir = path.join(root, 'etc', 'systemd', 'system')
  const fakeUserDir = path.join(root, 'home', 'tester', '.config', 'systemd', 'user')
  const mockBin = path.join(root, 'mock-bin')
  const home = path.join(root, 'home', 'tester')

  fs.mkdirSync(path.dirname(managerHome), { recursive: true })
  fs.mkdirSync(fakeSystemDir, { recursive: true })
  fs.mkdirSync(fakeUserDir, { recursive: true })
  fs.mkdirSync(mockBin, { recursive: true })
  fs.mkdirSync(home, { recursive: true })

  if (fs.existsSync(managerRoot)) {
    fs.cpSync(managerRoot, managerHome, { recursive: true })
  }

  return {
    root,
    managerHome,
    sourceEntry: path.join(managerHome, 'main.sh'),
    buildScript: path.join(managerHome, 'build.sh'),
    builtBin: path.join(root, 'bin', 'systemd-service-manager'),
    builtLocal: path.join(
      root,
      'scripts',
      'bash',
      'systemd-service-manager',
      'systemd-service-manager.local.sh',
    ),
    fakeSystemDir,
    fakeUserDir,
    mockBin,
    home,
  }
}

export function cleanupWorkspace(workspace: Workspace): void {
  fs.rmSync(workspace.root, { recursive: true, force: true })
}

export async function runCommand(
  command: string,
  args: string[],
  workspace: Workspace,
  extraEnv: NodeJS.ProcessEnv = {},
): Promise<RunResult> {
  const result = await execa(command, args, {
    cwd: workspace.root,
    env: {
      ...process.env,
      HOME: workspace.home,
      SSM_SYSTEM_UNIT_DIR: workspace.fakeSystemDir,
      SSM_USER_UNIT_DIR: workspace.fakeUserDir,
      PATH: `${workspace.mockBin}:${process.env.PATH ?? ''}`,
      ...extraEnv,
    },
    reject: false,
  })

  return {
    stdout: result.stdout,
    stderr: result.stderr,
    exitCode: result.exitCode,
  }
}

export function runSource(
  workspace: Workspace,
  args: string[],
  extraEnv: NodeJS.ProcessEnv = {},
): Promise<RunResult> {
  return runCommand('bash', [workspace.sourceEntry, ...args], workspace, extraEnv)
}

export function runBuilt(
  workspace: Workspace,
  target: 'bin' | 'local',
  args: string[],
  extraEnv: NodeJS.ProcessEnv = {},
): Promise<RunResult> {
  const scriptPath = target === 'bin' ? workspace.builtBin : workspace.builtLocal
  return runCommand('bash', [scriptPath, ...args], workspace, extraEnv)
}

export function runBuild(
  workspace: Workspace,
  extraEnv: NodeJS.ProcessEnv = {},
): Promise<RunResult> {
  return runCommand('bash', [workspace.buildScript], workspace, extraEnv)
}

export function readText(filePath: string): string {
  return fs.readFileSync(filePath, 'utf8')
}

export function writeText(filePath: string, content: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content, 'utf8')
}

export function installMockCommand(
  workspace: Workspace,
  name: string,
  body: string,
): void {
  const scriptPath = path.join(workspace.mockBin, name)
  writeText(scriptPath, body)
  fs.chmodSync(scriptPath, 0o755)
}
