export type Dialect = 'postgres' | 'mysql' | 'sqlite'
export type PermissionLevel = 'readonly' | 'maintenance' | 'admin' | 'yolo'
export type DatabaseType = Dialect | 'mongodb' | 'redis' | 'milvus'
export type OutputFormat = 'text' | 'json'
export type Severity = 'block' | 'warn'
export type StatementKind =
  | 'readonly'
  | 'maintenance'
  | 'write'
  | 'ddl'
  | 'export'
  | 'transaction'
  | 'unknown'

export interface Finding {
  code: string
  message: string
  severity: Severity
}

export interface CheckOptions {
  dialect: Dialect
  level: PermissionLevel
  maxLimit: number
}

export interface CheckResult {
  ok: boolean
  level: PermissionLevel
  dialect: Dialect
  statementCount: number
  kind: StatementKind
  findings: Finding[]
}

export type SecretStatus = 'present' | 'missing' | 'notRequired'

export interface ConfigDefaults {
  defaultInstance?: string
  limit?: number
  maxLimit?: number
  permissionLevel?: PermissionLevel
  outputFormat?: OutputFormat
  redactFields?: string[]
  allowedActions?: Partial<Record<DatabaseType, string[]>>
}

export interface DatabaseEntry {
  name: string
  schemas?: string[]
  collections?: string[]
  defaultSchema?: string
  defaultCollection?: string
}

export interface DatabaseInstance {
  id: string
  type: DatabaseType
  environment?: string
  readonly?: boolean
  host?: string
  port?: number
  username?: string
  password?: string
  uri?: string
  url?: string
  address?: string
  token?: string
  path?: string
  defaultDatabase?: string
  databases?: DatabaseEntry[]
  allowedActions?: string[]
}

export interface DatabaseQueryConfig {
  defaults?: ConfigDefaults
  instances: DatabaseInstance[]
}

export interface LoadedConfig {
  path?: string
  config: DatabaseQueryConfig
}

export interface ResolvedTarget {
  instance: DatabaseInstance
  database?: DatabaseEntry
  schema?: string
  collection?: string
}

export interface ContextInstance {
  id: string
  type: DatabaseType
  environment?: string
  readonly?: boolean
  defaultDatabase?: string
  databases: DatabaseEntry[]
  allowedActions: string[]
  secretStatus: Record<string, SecretStatus>
}

export interface ContextSnapshot {
  configPath?: string
  defaults: Required<
    Pick<
      ConfigDefaults,
      'limit' | 'maxLimit' | 'permissionLevel' | 'outputFormat'
    >
  > &
    Pick<ConfigDefaults, 'defaultInstance' | 'redactFields' | 'allowedActions'>
  instances: ContextInstance[]
}

export interface ExecutionPlan {
  tool: string
  args: string[]
  displayArgs: string[]
  env: Record<string, string>
  displayEnv: Record<string, string>
  summary: string
  sdk?: SdkExecutionPlan
}

export interface SdkExecutionPlan {
  provider: 'milvus'
  action: string
  address: string
  token?: string
  collection?: string
  query?: string
  vector?: string
  limit: number
}
