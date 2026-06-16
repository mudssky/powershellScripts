export type OutputFormat = 'text' | 'json'
export type ReloadMode = 'auto' | 'off' | 'command'
export type DiagnosticLevel = 'info' | 'warn' | 'error'
export type DiagnosticCode =
  | 'CONFIG_NOT_FOUND'
  | 'CONFIG_PARSE_ERROR'
  | 'DEPENDENCY_MISSING'
  | 'PORT_IN_USE'
  | 'PORT_CHECK_FAILED'
  | 'TMUX_MISSING'
  | 'JAVA_MISSING'
  | 'BUILD_TOOL_MISSING'
  | 'MULTI_SERVICE_SELECTION_REQUIRED'
  | 'PARALLEL_BUILD_RISK'
  | 'SESSION_CONFLICT'
  | 'GITIGNORE_MISSING'
  | 'RELOAD_UNAVAILABLE'
  | 'UNKNOWN_SERVICE'
  | 'NO_SERVICE_CANDIDATE'
  | 'PREPARE_FAILED'

export interface ProjectLauncherDefaults {
  profile?: string
  reload?: ReloadMode
  reloadCommand?: string
  sessionName?: string
  allowParallelBuild?: boolean
}

export interface ProjectServiceConfig {
  name: string
  cwd?: string
  command: string
  port?: number
  ports?: number[]
  profile?: string
  prepare?: string | string[]
  reload?: ReloadMode
  reloadCommand?: string
  allowParallelBuild?: boolean
  env?: Record<string, string>
}

export interface ProjectDependencyConfig {
  name: string
  checkCommand?: string
  startCommand?: string
}

export interface ProjectLauncherConfig {
  defaults?: ProjectLauncherDefaults
  services?: ProjectServiceConfig[]
  dependencies?: ProjectDependencyConfig[]
}

export interface LoadedConfig {
  path?: string
  config: ProjectLauncherConfig
  source:
    | 'explicit'
    | 'project-local'
    | 'project-config'
    | 'global-local'
    | 'none'
}

export type DiscoverySource =
  | 'config'
  | 'maven'
  | 'gradle'
  | 'command'
  | 'unknown'

export interface ServiceCandidate {
  name: string
  cwd: string
  command: string
  source: DiscoverySource
  modulePath?: string
  port?: number
  ports: number[]
  prepare: string[]
  env: Record<string, string>
  reload: ReloadMode
  reloadCommand?: string
  allowParallelBuild: boolean
  confidence: 'high' | 'medium' | 'low'
  reasons: string[]
}

export interface IgnoredModule {
  name: string
  path: string
  reason: string
}

export interface DiscoveryResult {
  projectRoot: string
  buildTool?: 'maven' | 'gradle'
  services: ServiceCandidate[]
  ignored: IgnoredModule[]
}

export interface Diagnostic {
  code: DiagnosticCode
  level: DiagnosticLevel
  message: string
  target?: string
  detail?: string
}

export interface PlannedService {
  name: string
  cwd: string
  command: string
  displayCommand: string
  port?: number
  ports: number[]
  prepare: string[]
  env: Record<string, string>
  displayEnv: Record<string, string>
  pane?: string
  source: DiscoverySource
}

export interface LaunchPlan {
  ok: boolean
  action: 'plan' | 'doctor' | 'start' | 'attach' | 'stop' | 'init'
  projectRoot: string
  session: string
  attachCommand: string
  services: PlannedService[]
  ignored: IgnoredModule[]
  diagnostics: Diagnostic[]
  metadataPath: string
  configPath?: string
  selectionRequired: boolean
}

export interface SessionMetadata {
  managedBy: 'project-launcher'
  session: string
  projectRoot: string
  configPath?: string
  configHash: string
  services: string[]
  createdAt: string
}

export interface CommandRunnerResult {
  exitCode: number
  stdout: string
  stderr: string
}

export interface CommandRunner {
  /**
   * 运行外部命令。
   *
   * @param command 要执行的命令。
   * @param args 命令参数。
   * @param options 执行目录和环境变量。
   * @returns 命令退出码、标准输出和标准错误。
   */
  run(
    command: string,
    args: string[],
    options?: { cwd?: string; env?: NodeJS.ProcessEnv; input?: string },
  ): Promise<CommandRunnerResult>
}

export interface CliIo {
  stdout: (message: string) => void
  stderr: (message: string) => void
}

export class CliError extends Error {
  code: DiagnosticCode
  exitCode: number

  /**
   * 创建可映射到 CLI 退出码的错误。
   *
   * @param code 诊断代码。
   * @param message 面向用户的错误消息。
   * @param exitCode CLI 退出码。
   */
  constructor(code: DiagnosticCode, message: string, exitCode = 1) {
    super(message)
    this.name = 'CliError'
    this.code = code
    this.exitCode = exitCode
  }
}
