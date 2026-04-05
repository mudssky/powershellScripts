import { spawnSync } from 'node:child_process'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const currentDir = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(currentDir, '../../../..')
const managerRoot = path.join(repoRoot, 'linux', 'fnos', 'fnos-mount-manager')
const fixturesRoot = path.join(managerRoot, 'tests', 'fixtures', 'basic')

export type Workspace = {
  root: string
  managerHome: string
  sourceEntry: string
  buildScript: string
  builtBin: string
  builtLocal: string
  exampleFstab: string
  localFstab: string
  localConfig: string
  targetFstab: string
  deviceRoot: string
  mockBin: string
  home: string
}

export type RunResult = {
  stdout: string
  stderr: string
  exitCode: number
}

export function createWorkspace(): Workspace {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'fnos-mount-manager-'))
  const managerParent = path.join(root, 'linux', 'fnos')
  const managerHome = path.join(managerParent, 'fnos-mount-manager')
  const home = path.join(root, 'home')
  const deviceRoot = path.join(root, 'fake-dev', 'disk')
  const mockBin = path.join(root, 'mock-bin')

  fs.mkdirSync(managerParent, { recursive: true })
  fs.mkdirSync(home, { recursive: true })
  fs.mkdirSync(path.join(deviceRoot, 'by-label'), { recursive: true })
  fs.mkdirSync(path.join(deviceRoot, 'by-uuid'), { recursive: true })
  fs.mkdirSync(mockBin, { recursive: true })

  fs.cpSync(managerRoot, managerHome, { recursive: true })
  fs.copyFileSync(
    path.join(fixturesRoot, 'disks.example.conf'),
    path.join(managerHome, 'disks.example.conf'),
  )
  fs.copyFileSync(
    path.join(fixturesRoot, 'disks.local.conf'),
    path.join(managerHome, 'disks.local.conf'),
  )
  fs.copyFileSync(
    path.join(fixturesRoot, 'system.fstab'),
    path.join(root, 'system.fstab'),
  )

  return {
    root,
    managerHome,
    sourceEntry: path.join(managerHome, 'main.sh'),
    buildScript: path.join(managerHome, 'build.sh'),
    builtBin: path.join(root, 'bin', 'fnos-mount-manager'),
    builtLocal: path.join(managerHome, 'fnos-mount-manager.sh'),
    exampleFstab: path.join(managerHome, 'fstab.example'),
    localFstab: path.join(managerHome, 'fstab'),
    localConfig: path.join(managerHome, 'disks.local.conf'),
    targetFstab: path.join(root, 'system.fstab'),
    deviceRoot,
    mockBin,
    home,
  }
}

export function cleanupWorkspace(workspace: Workspace): void {
  fs.rmSync(workspace.root, { recursive: true, force: true })
}

function baseEnv(workspace: Workspace): NodeJS.ProcessEnv {
  return {
    ...process.env,
    HOME: workspace.home,
    FNOS_MANAGER_TEST_NO_SUDO: '1',
    FNOS_MANAGER_DEVICE_ROOT: workspace.deviceRoot,
    PATH: `${workspace.mockBin}:${process.env.PATH ?? ''}`,
  }
}

export function runSource(
  workspace: Workspace,
  args: string[],
  env: NodeJS.ProcessEnv = {},
): RunResult {
  return runCommand('bash', [workspace.sourceEntry, ...args], workspace, env)
}

export function runBuilt(
  workspace: Workspace,
  target: 'bin' | 'local',
  args: string[],
  env: NodeJS.ProcessEnv = {},
): RunResult {
  const scriptPath =
    target === 'bin' ? workspace.builtBin : workspace.builtLocal
  return runCommand('bash', [scriptPath, ...args], workspace, env)
}

export function runBuild(
  workspace: Workspace,
  env: NodeJS.ProcessEnv = {},
): RunResult {
  return runCommand('bash', [workspace.buildScript], workspace, env)
}

export function runCommand(
  command: string,
  args: string[],
  workspace: Workspace,
  env: NodeJS.ProcessEnv = {},
): RunResult {
  const result = spawnSync(command, args, {
    cwd: workspace.root,
    env: {
      ...baseEnv(workspace),
      ...env,
    },
    encoding: 'utf8',
  })

  return {
    stdout: result.stdout ?? '',
    stderr: result.stderr ?? '',
    exitCode: result.status ?? 1,
  }
}

export function readText(filePath: string): string {
  return fs.readFileSync(filePath, 'utf8')
}

export function writeText(filePath: string, content: string): void {
  fs.mkdirSync(path.dirname(filePath), { recursive: true })
  fs.writeFileSync(filePath, content, 'utf8')
}

export function ensureFakeDevice(workspace: Workspace, source: string): string {
  const [kind, value] = source.split(':', 2)
  const directory =
    kind === 'LABEL'
      ? path.join(workspace.deviceRoot, 'by-label')
      : path.join(workspace.deviceRoot, 'by-uuid')
  const filePath = path.join(directory, value)
  writeText(filePath, '')
  return filePath
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

export function writeHomeFile(
  workspace: Workspace,
  relativePath: string,
  content: string,
): void {
  writeText(path.join(workspace.home, relativePath), content)
}
