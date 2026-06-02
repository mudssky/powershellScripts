# rathole 配置与维护脚本调研

## 背景

用户希望在 `config/network/tailscale` 下增加 rathole 配置示例文档，并提供维护脚本。真实配置预计使用 `.local` 后缀，避免提交到 Git。

## 资料来源

* Context7 查询 `rathole` 未命中 rathole 本体，结果偏到无关库，因此没有采用。
* rathole 官方仓库 README：`https://github.com/rathole-org/rathole`
* rathole 官方 examples：`https://github.com/rathole-org/rathole/tree/main/examples`

## rathole 配置约定

* rathole 使用 TOML 配置，常见形态为 `server.toml` 与 `client.toml`。
* 当配置文件只包含 `[server]` 或 `[client]` 其中之一时，rathole 会自动判断运行模式；只有把 server/client 合并到同一个文件时才需要 `--server` 或 `--client`。
* 服务端常见字段：
  * `[server]`
  * `bind_addr`
  * `[server.services.<name>]`
  * `token`
  * `bind_addr`
* 客户端常见字段：
  * `[client]`
  * `remote_addr`
  * `[client.services.<name>]`
  * `token`
  * `local_addr`
* token 属于敏感配置，示例应使用占位值，真实 token 放入 `.local.toml`。

## 公网白名单转发场景

* rathole 的 server 负责在入口侧监听公开端口，client 负责连接 server 并把流量转发到 `local_addr`。
* 当某个第三方服务只允许固定公网 IP 访问时，可以把 rathole client 部署在这台被白名单允许的公网服务器上，并把 `local_addr` 指向第三方服务地址。
* 外部使用者访问 rathole server 暴露的端口后，流量会通过隧道进入白名单公网服务器，再由该服务器访问第三方服务；第三方服务看到的来源 IP 是白名单公网服务器。
* 该模式是 TCP/UDP 四层端口转发，不是 HTTP 七层反向代理；不负责 Host、路径、Header 路由或 TLS 终止。
* 用户选择单独提供 `whitelist-proxy.example.toml`，避免基础 client 示例包含过多场景分支。

## PM2 维护调研

* Context7 命中 PM2 官方库 `/unitech/pm2`。
* PM2 支持直接启动可执行二进制：`pm2 start ./binary-app`。
* PM2 ecosystem 配置支持 `script`、`args`、`cwd`、日志文件、`autorestart`、`max_restarts`、`restart_delay` 等字段，适合管理 rathole 这种长驻单二进制进程。
* 仓库已有 `ai/coding/window-warmer/window-warmer.pm2.config.cjs` 与 README 的 PM2 管理示例，可复用“配置文件 + start/logs/restart/stop/save/startup 文档”的表达方式。

## 维护方式选项

### 方案 A：Docker Compose 优先

* 目录提供 `compose.yaml`，挂载 `server.local.toml` 与 `client.local.toml`。
* `start.ps1` 参考 DERP 模板封装 `docker compose`：
  * `up`
  * `down`
  * `restart`
  * `logs`
  * `ps`
  * `pull`
  * `config`
* 优点：和现有 `config/network/tailscale/derp/start.ps1` 一致；测试可以复用 dry-run 与 compose 参数生成思路。
* 缺点：相比裸二进制多一层容器隔离，用户明确更倾向低开销运行方式。

### 方案 B：裸二进制 + PM2 优先（推荐）

* 提供 `server.example.toml`、`client.example.toml`、拆分的 PM2 ecosystem 示例和 `start.ps1` 包装。
* `start.ps1` 优先封装 PM2 常用动作：
  * `start`
  * `stop`
  * `restart`
  * `logs`
  * `status`
  * `delete`
  * `save`
  * `config`
* 优点：贴近 rathole 本体，避免容器额外开销；PM2 负责后台运行、日志和重启策略，仓库已有 PM2 管理文档可参考。
* 缺点：运行机器需要安装 rathole 与 PM2；Linux production 场景下 systemd 可能更原生，但不作为本次 MVP。

### 方案 C：文档覆盖两者，脚本只覆盖 PM2

* README 简要说明 Docker Compose 也可以运行，但本仓库脚本与示例主线转向裸二进制 + PM2。
* 优点：满足用户低资源偏好，同时保留容器化备选说明。
* 缺点：第一版不提供 Compose 生命周期脚本。

## 映射到当前仓库

* 当前 `config/network/tailscale/derp` 已提供 compose + `.env.local` + `start.ps1` 模式，可参考 `start.ps1` 的函数注释、dry-run 和测试方式，但 rathole 不直接沿用 Compose 主线。
* 仓库已有 PM2 示例：`ai/coding/window-warmer/window-warmer.pm2.config.cjs`。
* 根目录 `.gitignore` 已忽略 `*.local.json`、`.env.local`、`*.env.local`，但尚未覆盖 `*.local.toml`。
* rathole 真实配置建议命名为：
  * `server.local.toml`
  * `client.local.toml`
* 共享示例建议命名为：
  * `server.example.toml`
  * `client.example.toml`
  * `whitelist-proxy.example.toml`

## 推荐

采用方案 C：文档主线为裸二进制 + PM2，脚本 MVP 只覆盖 PM2 常用维护动作；PM2 配置拆成 server/client 两份；README 简要保留 Compose 备选说明。这样满足用户对资源占用的偏好，同时借 PM2 获得后台运行、日志和重启管理能力，并避免同一机器误启动不需要的一端。
