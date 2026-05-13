# rathole template spec

> 本规范记录 `config/network/rathole` 的 rathole 裸二进制、PM2 管理、`.local.toml` 配置和公网白名单转发约定。修改 rathole 模板、PM2 配置、维护脚本或相关文档时必须先阅读。

---

## Scenario: rathole Binary + PM2 Tunnel Maintenance

### 1. Scope / Trigger

- Trigger: 修改 `config/network/rathole/**`、rathole 文档、rathole PM2 ecosystem 配置或 rathole 维护脚本。
- Scope: 仓库提供 rathole server/client TOML 示例、白名单转发示例、拆分 PM2 配置和 `start.ps1` 包装脚本。
- Design intent: rathole 主线使用裸二进制降低常驻资源开销；PM2 只负责进程管理、日志、重启和开机恢复。Docker Compose 只能作为备选说明，不作为当前模板主线。

### 2. Signatures

- 文件路径：
  - `config/network/rathole/server.example.toml`
  - `config/network/rathole/client.example.toml`
  - `config/network/rathole/whitelist-proxy.example.toml`
  - `config/network/rathole/rathole-server.pm2.config.cjs`
  - `config/network/rathole/rathole-client.pm2.config.cjs`
  - `config/network/rathole/start.ps1`
  - `config/network/rathole/README.md`
- 维护脚本：
  - `./config/network/rathole/start.ps1`
  - `./config/network/rathole/start.ps1 start -Role client`
  - `./config/network/rathole/start.ps1 start -Role server`
  - `./config/network/rathole/start.ps1 logs -Role client --lines 100`
  - `./config/network/rathole/start.ps1 config -Role server`
  - `./config/network/rathole/start.ps1 -DryRun`
- PM2：
  - `pm2 start config/network/rathole/rathole-client.pm2.config.cjs`
  - `pm2 start config/network/rathole/rathole-server.pm2.config.cjs`
  - PM2 app names: `rathole-client`, `rathole-server`

### 3. Contracts

- Local config contract:
  - 真实 server 配置命名为 `server.local.toml`，从 `server.example.toml` 复制。
  - 真实 client 配置命名为 `client.local.toml`，从 `client.example.toml` 或 `whitelist-proxy.example.toml` 复制。
  - `*.local.toml` 必须被 `config/network/rathole/.gitignore` 忽略。
- PM2 contract:
  - client/server 必须拆成两个 ecosystem 文件，避免同一机器误启动不需要的一端。
  - `script` 使用 `process.env.RATHOLE_BIN || 'rathole'`，允许用户覆盖二进制路径。
  - `interpreter` 必须是 `'none'`，避免 PM2 把 rathole 当 Node 脚本处理。
  - `args` 指向对应 `.local.toml`。当配置文件只包含 `[server]` 或 `[client]` 时，rathole 会自动识别运行模式，不需要额外加 `--server` / `--client`。
  - 日志输出到 `config/network/rathole/logs/`，目录用 `.gitkeep` 保留，真实日志不入库。
- Forwarding contract:
  - rathole 是 TCP/UDP 四层转发，不负责 HTTP Host、路径、Header 路由或 TLS 终止。
  - 公网白名单转发示例必须单独放在 `whitelist-proxy.example.toml`，不塞进基础 `client.example.toml`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| `start.ps1 -DryRun` | 只输出 PM2 预览命令，不要求本机安装 PM2 |
| `start.ps1 start -Role client` 且 `client.local.toml` 不存在 | 输出 warning，提示从 `client.example.toml` 复制；仍交给 PM2 启动以保留显式用户意图 |
| `start.ps1 start -Role server` 且 PM2 不存在 | 抛出缺少 `pm2` 的错误 |
| `start.ps1 config -Role server` | 输出 server 的 app、ecosystem、example/local 路径和复制命令 |
| PM2 config 首次启动且 `logs/` 不存在 | ecosystem 配置通过 `fs.mkdirSync(logDir, { recursive: true })` 创建目录 |
| `*.local.toml` 出现在模板目录 | Git 必须忽略，避免 token 和私有目标地址泄露 |

### 5. Good/Base/Bad Cases

- Good: `client.local.toml` 只包含 `[client]`，PM2 `args` 直接传配置路径，让 rathole 自动识别 client 模式。
- Good: 把白名单公网服务器作为 rathole client 所在机器，`local_addr` 指向只允许该公网 IP 访问的第三方服务。
- Good: 使用 `RATHOLE_BIN=/opt/rathole/rathole pm2 start ...` 覆盖二进制路径。
- Base: 默认 `./start.ps1` 管理 client，避免普通机器误启动 server 监听端口。
- Bad: 把真实 token、内网地址或白名单目标写进 `.example.toml`。
- Bad: 把 server/client 放进同一个 PM2 ecosystem 默认一起启动。
- Bad: 把 rathole 描述成 HTTP 七层反向代理，误导用户用它做路径/Host 路由。

### 6. Tests Required

- Template tests:
  - 断言三份 TOML 示例存在：server、client、whitelist proxy。
  - 断言 `.gitignore` 忽略 `*.local.toml` 和真实日志。
  - 断言 PM2 configs 拆分、使用 `interpreter: 'none'`、引用对应 `.local.toml`。
  - 断言 README 提到裸二进制 + PM2、`.local.toml`、白名单转发和四层边界。
- Script tests:
  - `Show-Usage` 覆盖动作列表和 `-Role`。
  - `Get-RatholeRoleConfig` 区分 client/server 路径。
  - `Get-Pm2InvocationPlan` 生成 start/restart/save 等 PM2 参数。
  - `Invoke-Pm2Command -DryRun` 返回可复制预览命令。
  - `Show-RatholeConfig` 返回复制命令与启动提示。
- Smoke checks:
  - `node -c config/network/rathole/rathole-client.pm2.config.cjs`
  - `node -c config/network/rathole/rathole-server.pm2.config.cjs`
  - rathole 相关 Pester 测试必须在 host 和 Linux Pester 中通过。

### 7. Wrong vs Correct

#### Wrong

```javascript
module.exports = {
  apps: [
    { name: 'rathole', script: 'rathole', args: ['server.local.toml'] },
    { name: 'rathole', script: 'rathole', args: ['client.local.toml'] },
  ],
}
```

问题：两个 app 同名，且 server/client 默认一起启动，容易在普通客户端机器误开公网监听端口。

#### Correct

```javascript
module.exports = {
  apps: [
    {
      name: 'rathole-client',
      script: process.env.RATHOLE_BIN || 'rathole',
      interpreter: 'none',
      args: [path.join(__dirname, 'client.local.toml')],
    },
  ],
}
```

理由：每台机器按角色选择独立 PM2 配置，二进制路径可覆盖，PM2 不会误按 Node 解释 rathole。
