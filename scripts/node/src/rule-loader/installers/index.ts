import { ClaudeInstaller } from './claude'
import type { Installer } from './types'

export const installers: Record<string, Installer> = {
  claude: new ClaudeInstaller(),
}

export type { Installer, InstallerOptions } from './types'
