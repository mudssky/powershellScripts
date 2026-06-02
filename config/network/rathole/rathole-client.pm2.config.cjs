const fs = require('node:fs')
const path = require('node:path')

const scriptDir = __dirname
const logDir = path.join(scriptDir, 'logs')

// PM2 启动前确保日志目录存在，避免首次部署时因为目录缺失而启动失败。
fs.mkdirSync(logDir, { recursive: true })

module.exports = {
  apps: [
    {
      name: 'rathole-client',
      cwd: scriptDir,
      script: process.env.RATHOLE_BIN || 'rathole',
      interpreter: 'none',
      args: [path.join(scriptDir, 'client.local.toml')],
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      watch: false,
      time: true,
      restart_delay: 5000,
      max_restarts: 10,
      out_file: path.join(logDir, 'rathole-client.out.log'),
      error_file: path.join(logDir, 'rathole-client.err.log'),
      pid_file: path.join(logDir, 'rathole-client.pid'),
      env: {
        RUST_LOG: process.env.RUST_LOG || 'info',
      },
    },
  ],
}
