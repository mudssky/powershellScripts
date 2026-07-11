import { spawnSync } from 'node:child_process'

const forwardedArgs = process.argv.slice(2)

// pnpm run <script> -- <args> 会把分隔符继续传给 PowerShell，
// 而 pwsh -File 会在脚本执行前将它误解为空参数名。
if (forwardedArgs[0] === '--') {
  forwardedArgs.shift()
}

const result = spawnSync(
  'pwsh',
  [
    '-NoProfile',
    '-File',
    './scripts/pwsh/devops/Invoke-Benchmark.ps1',
    ...forwardedArgs,
  ],
  { stdio: 'inherit' },
)

if (result.error) {
  console.error(`benchmark 启动失败: ${result.error.message}`)
  process.exit(1)
}

process.exit(result.status ?? 1)
