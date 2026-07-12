# Tailscale DERP Compose Template Design

## Summary

本设计把仓库内自建 Tailscale DERP 的默认入口，从共享 `config/dockerfiles/compose/docker-compose.yml`
里的极简 `derper` 服务，迁移为独立维护的
`config/network/tailscale/derp/compose.yaml` 模板。

新的默认方案聚焦三个目标：

- 用仓库内可维护的模板和镜像，替代当前依赖共享 compose 的临时 DERP 容器
- 默认启用 `--verify-clients`，避免任何知道公网 IP 的外部 tailnet 直接盗用 DERP
- 在“无域名”前提下，提供一套除公网 IP 之外基本都可预配置好的 IP-only 模板

目标落地后，用户应通过独立目录完成 DERP 的构建、启动与维护，而不是继续使用
`./scripts/pwsh/devops/start-container.ps1 -ServiceName derper`。

## Context

仓库当前已经存在两条与 DERP 相关的资产：

- 共享 compose 中的 `derper` 服务
- `scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1`，用于把自建节点写入 tailnet policy 的 `derpMap`

但共享 compose 里的 `derper` 只是最小容器封装，存在明显缺口：

- 默认 `DERP_VERIFY_CLIENTS=false`
- 没有同机 `tailscaled` 参与客户端校验
- 没有仓库内自维护镜像与版本对齐策略
- 没有独立目录承载证书、状态、环境变量与操作说明
- 继续把它挂在通用 `start-container.ps1` 下，会误导用户把 DERP 当作普通 Web 服务容器来启动

与此同时，仓库新的 `Set-TailscaleDerp.ps1` 已经转向当前官方路线：

- 自建 DERP 节点单独维护
- 再把节点地址写进 tailnet policy 的 `derpMap`

这意味着仓库内 DERP 的“运行入口”和“tailnet policy 写入入口”也应该保持一致的结构化方案。

## Goals

- 提供一套独立的 Tailscale DERP compose 模板，作为仓库默认入口
- 默认使用双容器结构：`tailscaled-auth` + `derper`
- 默认启用 `--verify-clients`，把访问范围限制在当前 tailnet
- 支持无域名、仅公网 IP 的部署方式
- 通过 `.env.example` 预置除公网 IP、auth key、证书路径外的大多数参数
- 删除共享 compose 中的旧 `derper` 入口，避免继续沿用不安全默认值
- 同步更新文档与测试，让迁移后的入口和预期行为一致

## Non-Goals

- 不在本设计中实现设备级或用户级的 DERP 白名单
- 不在本设计中引入多节点 DERP mesh
- 不在本设计中接入反向代理、全局负载均衡或自动证书签发
- 不在本设计中新增额外的 PowerShell 包装启动脚本
- 不在本设计中修改 `Set-TailscaleDerp.ps1` 的参数契约或 `derpMap` 写入流程

## Chosen Approach

采用“独立目录 + 双容器 + 仓库内自维护 `derper` 镜像 + IP-only 手动证书”的方案。

### Why This Approach

相比继续扩展共享 compose 中的单容器 `derper` 服务，这条路径更适合当前仓库：

- `--verify-clients` 需要同机 `tailscaled`，双容器结构最直观
- 独立目录更适合承载 DERP 特有的证书、state、socket 与说明
- 自维护 `Dockerfile.derper` 可以把 `derper` 与 `tailscaled` 的版本对齐责任显式化
- 不再依赖通用 `start-container.ps1`，可以减少“通用服务脚本”和“网络基础设施节点”之间的职责混淆

## Architecture

目标目录：

`config/network/tailscale/derp`

目标文件：

- `compose.yaml`
- `Dockerfile.derper`
- `.env.example`
- `README.md`

### Service Topology

`compose.yaml` 包含两个长期服务：

1. `tailscaled-auth`
   作用：运行 `tailscaled`，加入目标 tailnet，并暴露本地 `tailscaled.sock`
2. `derper`
   作用：编译并运行 `cmd/derper`，通过本地 socket 启用 `--verify-clients`

### Design Constraints

- 不新增第三个包装服务或 sidecar
- 不通过 Nginx、Traefik 等 HTTP 代理转发 DERP 流量
- 不使用全局负载均衡器
- 默认只开放 `TCP 443` 与 `UDP 3478`

## Runtime Model

### `tailscaled-auth`

`tailscaled-auth` 使用官方 `tailscale/tailscale` 镜像，负责：

- 通过 `TS_AUTHKEY` 登录 tailnet
- 持久化 Tailscale state
- 生成并维护供 `derper` 使用的 `tailscaled.sock`

为了减少宿主机依赖，第一版优先采用容器内 `tailscaled`，而不是要求宿主机先安装并运行
系统级 `tailscaled`。

### `derper`

`derper` 使用仓库内 `Dockerfile.derper` 构建镜像。容器启动后直接执行 `cmd/derper`，
并挂载：

- DERP TLS 证书与私钥
- `tailscaled.sock`
- 可选的证书目录或运行时缓存目录

默认命令需要明确声明安全相关参数，而不是依赖镜像黑盒环境变量。

## Security Model

### Primary Control: Tailnet-Level Admission

防止别人盗用 DERP 的主机制是：

`derper --verify-clients`

该机制要求同机存在一个可访问的 `tailscaled`，并通过本地 socket 验证发起连接的客户端是否属于
当前可见 tailnet 范围。第一版把这项能力作为默认值，而不是可选增强。

这意味着：

- 只知道公网 IP 的外部 tailnet 不能直接把该节点当作开放 DERP 使用
- 准入控制粒度为 tailnet 级，而不是设备级
- 如果调用方不在当前 tailnet ACL 可见范围内，即使扫到端口也不能完成有效 DERP 准入

### Secondary Controls

模板还会额外默认启用以下补强措施：

- `--accept-connection-limit`
- `--accept-connection-burst`
- 最小端口暴露：`443/tcp`、`3478/udp`

README 需要明确说明：

- 连接限速只用于控制滥用和突发连接压力
- 它不能替代 `--verify-clients`
- 不建议对 `UDP 3478` 的 STUN 流量做前置速率限制

## IP-Only Deployment Model

本设计默认按“没有域名”场景落地。

### Certificate Strategy

`derper` 使用：

- `--certmode=manual`
- `--hostname=<DERP_PUBLIC_IP>`

根据当前 `cmd/derper` 行为，在 `--certmode=manual` 下，`--hostname` 可以直接使用 IP，
从而避免对域名和 SNI 的依赖。

因此模板不把域名作为默认前提，而是把以下内容作为用户必填项：

- 公网 IP
- 与该 IP 匹配的证书文件路径
- 私钥文件路径

README 需要明确提醒：

- 这条路线技术上可行，但证书申请与轮换需要用户自行负责
- 若后续具备稳定域名，仍然可以平滑切到域名 + 自动证书方案，但这不属于第一版范围

## Compose Contract

### `compose.yaml`

`compose.yaml` 需要满足以下契约：

- 默认包含 `tailscaled-auth` 与 `derper` 两个服务
- 使用 `.env.local` 或用户自定义 `--env-file` 注入环境变量
- `derper` 通过显式命令行传参，而不是隐藏在难以审阅的 entrypoint 黑盒中
- 端口映射默认发布：
  - `${DERP_PORT}:443/tcp` 或与监听端口一致的 TCP 映射
  - `${DERP_STUN_PORT}:${DERP_STUN_PORT}/udp`
- `tailscaled.sock` 通过共享 volume 提供给 `derper`
- `tailscaled-auth` 的 state 使用独立 volume 持久化

### `Dockerfile.derper`

`Dockerfile.derper` 需要体现以下设计意图：

- 由仓库负责构建 `cmd/derper`
- 镜像版本可通过构建参数或环境变量固定到明确的 Tailscale 版本
- 文档中明确说明：如果启用 `--verify-clients`，`derper` 与 `tailscaled` 应来自同一 Tailscale 版本线

第一版不要求实现复杂的多阶段缓存优化，但需要保证构建逻辑清晰可维护。

### `.env.example`

`.env.example` 只把真正需要环境差异化的值暴露给用户。

建议分成三类：

1. 必填：
   - `DERP_PUBLIC_IP`
   - `TS_AUTHKEY`
   - `DERP_CERT_FILE`
   - `DERP_KEY_FILE`
2. 常见可调：
   - `DERP_PORT`
   - `DERP_STUN_PORT`
   - `DERP_ACCEPT_CONNECTION_LIMIT`
   - `DERP_ACCEPT_CONNECTION_BURST`
3. 一般保持默认：
   - state 目录
   - socket 路径
   - compose project 名
   - Tailscale 镜像版本
   - `derper` 构建版本

### `README.md`

README 需要覆盖：

- 目录内各文件职责
- 环境变量说明
- 启动命令
- 停止、查看日志、重新构建命令
- 如何生成并挂载证书
- 如何使用 `Set-TailscaleDerp.ps1` 把同一个公网 IP 写入 tailnet policy
- 常见验证命令：
  - `docker compose ... config`
  - `tailscale netcheck`
  - `tailscale ping`
  - `tailscale debug derp`

## Migration Plan

### Remove Old Shared Entry

需要从共享入口移除以下内容：

- `config/dockerfiles/compose/docker-compose.yml` 中的 `derper` 服务块
- `scripts/pwsh/devops/start-container.ps1` 中与 `derper` 相关的：
  - `ValidateSet`
  - 服务说明
  - 示例命令

### Update Tests

需要同步调整现有测试：

- 原先断言“共享 compose 中存在 `derper`”的测试，改为断言其不再存在
- 原先带有 `derper` 场景名称但实际只验证 UDP localhost 绑定重写能力的测试，改成更通用的测试命名

### Update Docs

Tailscale 文档需要从“共享 compose / 通用容器入口”迁移为：

1. 进入 `config/network/tailscale/derp`
2. 复制 `.env.example` 为 `.env.local`
3. 填写公网 IP、auth key、证书路径
4. 运行 `docker compose --env-file .env.local -f compose.yaml up -d --build`
5. 再执行 `Set-TailscaleDerp.ps1` 生成或写入 `derpMap`

## Compatibility With Existing Policy Script

第一版不修改 `Set-TailscaleDerp.ps1` 的参数契约，但新模板必须和它当前的输出模型兼容：

- `HostName` 继续可写入公网 IP
- 默认端口与 README 示例保持一致
- 文档要清楚说明 `compose.yaml` 中的监听端口、证书主机名与 policy 里写入的公网 IP 必须保持一致

这能保证用户把运行模板和 policy 更新视作同一条链路，而不是两个互不相关的功能点。

## Testing Strategy

实现阶段至少需要覆盖以下验证：

1. `docker compose -f config/network/tailscale/derp/compose.yaml config`
   目的：确认模板结构、变量插值与挂载写法有效
2. Pester
   目的：确认共享 compose 中已移除 `derper`，并更新相关脚本/测试预期
3. `pnpm qa`
   目的：满足仓库对代码改动的统一质量检查要求
4. `pnpm test:pwsh:all`
   目的：本次会修改 `scripts/pwsh/**` 与 `tests/**/*.ps1`，需要满足仓库额外约定

如果实现中显式触达 coverage 规范，再额外执行 `pnpm test:pwsh:coverage`。

## Risks And Trade-Offs

- 无域名 + 手动证书路线可行，但证书维护成本高于常规域名方案
- 把 DERP 从通用 `start-container.ps1` 中移除，会改变已有使用习惯，但能换来更清晰的安全边界
- 双容器结构比单容器稍复杂，但能把 `tailscaled` 校验职责和 `derper` 数据面职责明确分开
- 第一版只做 tailnet 级准入，不能满足更细粒度的“同 tailnet 内部分设备禁止使用”需求

## Open Questions

- 第一版是否要把 `Set-TailscaleDerp.ps1` 中固定的 `InsecureForTests=true` 一并改成可配置
- README 中是否要顺手补一份“自签 / 私有 CA / 公网可信证书”的最小证书准备示例
- 后续是否需要补一个专门用于 DERP 的健康检查或探测脚本，而不是完全依赖手动命令
