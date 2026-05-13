# brainstorm: rathole 配置示例与维护脚本

## Goal

在 `config/network/tailscale` 下补充 rathole 配置示例文档与维护脚本，让实际使用者可以复制示例生成本地 `.local` 配置，并以裸二进制 + PM2 的方式完成启动、停止、查看配置、日志等维护操作，同时避免真实私有配置被提交到 Git。

## What I already know

* 用户希望增加一些 rathole 配置示例文档，位置倾向于 `config/network/tailscale`。
* 用户希望提供维护脚本，示例命名为 `start.ps1`。
* 实际使用预计采用 `.local` 结尾的配置文件，避免提交到 Git。
* 仓库已有 `config/network/tailscale/derp` 模块，包含 `README.md`、`compose.yaml`、`.env.example`、`.env.local`、`start.ps1`、`.gitignore` 等维护模式。
* 根目录 `.gitignore` 已忽略 `*.local.json`、`.env.local`、`*.env.local`。
* DERP 的 `start.ps1` 已有 Pester 测试 `tests/TailscaleDerpStart.Tests.ps1`，配置模板也有 `tests/TailscaleDerpComposeTemplate.Tests.ps1` 覆盖。
* rathole 官方配置使用 TOML，常见拆分为 server/client 两个配置文件；真实 token 应留在 `.local.toml`。
* 用户担心容器比裸二进制占用更多资源，因此倾向裸二进制运行；PM2 可以作为进程管理器。
* PM2 官方文档支持直接管理可执行二进制，ecosystem 配置可声明 `script`、`args`、日志和重启策略。
* 仓库已有 `ai/coding/window-warmer/window-warmer.pm2.config.cjs` 作为 PM2 管理示例。
* 用户选择 PM2 配置拆成 server/client 两份，避免一份配置里同时声明两端造成误启动。
* 用户希望覆盖“公网白名单转发”场景：目标服务只允许某台公网服务器 IP 访问时，可在该公网服务器运行 rathole client，通过 rathole server 暴露的端口把流量转发到白名单目标服务，相当于四层反向代理/出口代理。

## Assumptions (temporary)

* rathole 示例会作为一个新的目录加入，例如 `config/network/rathole`。
* 共享文件应使用 `.example.*` 或 README 形式入库，真实配置使用 `.local.*` 并通过目录级 `.gitignore` 防误提交。
* 维护脚本优先沿用现有 PowerShell `start.ps1` 风格，底层调用 PM2 管理 rathole 裸二进制。

## Open Questions

* 无。

## Requirements (evolving)

* 在 `config/network/tailscale` 下新增 rathole 配置示例与说明。
* 提供 `.local` 私有配置约定，并确保真实配置默认不会提交。
* 提供维护脚本，降低启动、停止、日志、配置检查等操作成本。
* 共享示例优先使用 `server.example.toml` 与 `client.example.toml`，真实配置优先使用 `server.local.toml` 与 `client.local.toml`。
* 公网白名单转发示例单独提供 `whitelist-proxy.example.toml`，避免基础 client 示例过载。
* MVP 以裸二进制 + PM2 为主线，README 可简要说明 Docker Compose 只是备选方式。
* 提供拆分的 PM2 ecosystem 示例，分别维护 rathole server 与 client 进程、配置路径、日志路径与基础重启策略。
* `start.ps1` MVP 优先封装 PM2 常用动作，例如 `start`、`stop`、`restart`、`logs`、`status`、`delete`、`save`、`config`、`help`。
* README 和配置示例需要覆盖公网白名单转发场景，并说明 rathole 是 TCP/UDP 四层转发，不提供 HTTP Host、路径、TLS 终止等七层反向代理能力。

## Acceptance Criteria (evolving)

* [x] 仓库包含可复制的 rathole server/client 示例配置，且示例不包含真实密钥。
* [x] README 说明 `.local` 配置文件的复制与维护流程。
* [x] README 说明裸二进制 + PM2 是推荐日常运行方式，并交代 Docker Compose 作为备选的取舍。
* [x] 维护脚本支持常用 PM2 维护动作，并能通过 dry-run 或测试验证关键命令生成逻辑。
* [x] PM2 ecosystem 示例引用 `.local.toml` 配置路径，并避免写入真实 token。
* [x] PM2 ecosystem 示例拆分 server/client 两份，使用者可以按机器角色选择启动。
* [x] 示例文档包含公网白名单转发用法，并明确它是端口级四层转发。
* [x] 仓库包含可复制的 `whitelist-proxy.example.toml`，用于公网 IP 白名单转发场景。
* [x] Git 忽略规则覆盖真实 `.local` 配置文件。

## Test Scope Note

配置示例、PM2 ecosystem 和 README 属于配置/文档类产物，不编写专门 Pester 内容断言，也不要求为文档和配置文件保留单独测试；测试聚焦 `start.ps1` 的命令生成与维护逻辑。

## Definition of Done (team quality bar)

* Tests added/updated (unit/integration where appropriate)
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* 暂不变更现有 DERP 配置与脚本行为。
* 暂不提交任何真实 rathole token、域名、端口或私有路径。
* 暂不实现完整 Docker Compose 生命周期脚本。
* 暂不实现 systemd 或 Windows Service 安装器。

## Technical Notes

* 已检查 `config/network/tailscale/derp` 现有结构，可作为 rathole 目录结构和脚本风格参考。
* 已检查根目录 `.gitignore`，全局已有部分 `.local` 忽略规则，但 rathole 目录仍建议提供局部 `.gitignore` 以表达意图。
* 相关测试线索：`tests/TailscaleDerpStart.Tests.ps1`、`tests/TailscaleDerpComposeTemplate.Tests.ps1`。
* 已检查仓库 PM2 示例与文档，相关路径包括 `ai/coding/window-warmer/README.md`、`ai/coding/window-warmer/window-warmer.pm2.config.cjs`、`docs/cheatsheet/node/pm2.md`。

## Research References

* [`research/rathole-config-and-maintenance.md`](research/rathole-config-and-maintenance.md) — rathole 使用 TOML server/client 配置，推荐裸二进制 + PM2 作为主线，Compose 仅作为备选说明。

## Research Notes

### Feasible approaches here

**Approach A: Docker Compose 优先**

* How it works: 新增 `compose.yaml`，挂载 `server.local.toml` / `client.local.toml`，`start.ps1` 封装 compose 操作。
* Pros: 与现有 DERP 目录模式一致，测试简单，维护动作稳定。
* Cons: 用户担心容器比裸二进制占用更多资源，不符合当前偏好。

**Approach B: 裸二进制 + PM2 优先（当前推荐）**

* How it works: 提供 TOML 示例、PM2 ecosystem 示例与 `start.ps1`，由 PM2 管理 rathole 二进制进程。
* Pros: 贴近 rathole 本体，资源占用更低；PM2 提供日志、重启和开机恢复能力。
* Cons: 需要运行环境已安装 rathole 与 PM2。

**Approach C: systemd 优先**

* How it works: 提供 systemd unit 示例，用系统服务管理 rathole。
* Pros: Linux 服务器最原生，开机自启和权限边界清晰。
* Cons: 跨平台性弱，脚本复杂度高于 PM2 MVP。

## Decision (ADR-lite)

**Context**: rathole 可通过容器或裸二进制运行；用户倾向降低常驻资源占用，并接受使用 PM2 做进程管理。

**Decision**: MVP 采用裸二进制 + PM2 主线。文档说明 Compose 只是备选方式，维护脚本优先封装 PM2 动作。

**Consequences**: 第一版需要用户自行安装 rathole 与 PM2，但避免容器层开销；脚本测试聚焦 PM2 命令生成与维护逻辑，`.local.toml` 保护和 README 可操作性通过文档约定维护。后续如要更贴近 Linux 生产部署，可扩展 systemd 示例或安装器。

**Decision**: 公网白名单转发示例单独放入 `whitelist-proxy.example.toml`。

**Consequences**: 基础 client 示例保持简单，白名单转发场景具备独立可复制模板；README 需要解释它与基础 client 示例的关系。

## Use Cases

### 公网白名单转发

目标服务只允许某台公网服务器 IP 访问时，可以把这台公网服务器作为 rathole client 所在机器，由它主动访问白名单目标服务；另一台入口机器运行 rathole server 并暴露访问端口。访问入口机器端口的 TCP/UDP 流量会经 rathole 隧道转到公网白名单服务器，再由该服务器访问目标服务。

注意：该模式是端口级四层转发，适合数据库、SSH、HTTP API 的固定端口透传；如果需要按域名、路径、Header、证书终止做路由，应继续使用 Nginx/Caddy/Traefik 等七层反向代理。
