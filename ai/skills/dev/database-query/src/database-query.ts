import { fileURLToPath } from 'node:url'

import { runCli } from './cli.js'

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  process.exitCode = await runCli(process.argv.slice(2))
}
