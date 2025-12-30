export interface InstallerOptions {
  cwd: string
  force?: boolean
  verbose?: boolean
}

export interface Installer {
  name: string
  install(options: InstallerOptions): Promise<void>
}
