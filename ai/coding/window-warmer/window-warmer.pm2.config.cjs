const path = require('node:path')

const scriptDir = __dirname

module.exports = {
  apps: [
    {
      name: 'coding-window-warmer',
      cwd: scriptDir,
      script: 'uv',
      interpreter: 'none',
      args: [
        'run',
        '--script',
        path.join(scriptDir, 'window_warmer.py'),
        '--config',
        path.join(scriptDir, 'window-warmer.toml'),
      ],
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      watch: false,
      time: true,
      restart_delay: 5000,
      max_restarts: 10,
    },
  ],
}
