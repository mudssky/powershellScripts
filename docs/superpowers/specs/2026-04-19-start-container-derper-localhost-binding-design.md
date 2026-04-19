# Start-Container Derper And Localhost Binding Design

## Summary

本设计为通用容器入口 `scripts/pwsh/devops/start-container.ps1` 补充两项能力：

- 把 `derper` 作为新的通用 compose 服务接入 `config/dockerfiles/compose/docker-compose.yml`
- 为所有使用 `ports:` 暴露端口的服务增加统一的 localhost 绑定能力，既支持命令行临时开启，也支持通过 `config/dockerfiles/compose/.env.local` 持久化配置

默认行为保持不变。只有显式开启 localhost 绑定时，脚本才会把宿主机端口限制到 `127.0.0.1`。

## Context

当前 `start-container.ps1` 已经具备以下基础能力：

- 自动定位项目根目录与 `config/dockerfiles/compose/docker-compose.yml`
- 按“服务默认值 -> 进程环境 -> .env -> .env.local -> CLI 环境变量”的优先级合并 compose 配置
- 通过 `docker compose` 或 `docker-compose` 启动目标 profile
- 在启动后输出服务访问信息

当前通用 compose 模板的端口暴露方式也比较统一：

- 大部分服务使用 `ports: ["5432:5432"]` 这类字符串写法
- 少数服务使用多行列表写法，例如 RustDesk
- 仓库中已经存在 `network_mode: host` 的服务块，例如 `beszel-agent`

这意味着我们有两个明确约束：

- localhost 绑定应围绕 `ports:` 服务设计，而不是试图统一改写 host 网络服务
- 方案应尽量复用现有配置解析链路，而不是再引入一套独立配置系统

## Goals

- 在通用 compose 模板中新增 `derper` 服务，并让它能通过 `-ServiceName derper` 启动
- 为 `start-container.ps1` 增加 `-BindLocalhost` 参数
- 支持通过 `config/dockerfiles/compose/.env.local` 中的 `BIND_LOCALHOST=true|false` 持久化控制 localhost 绑定
- 明确定义 CLI、`.env.local` 与默认值之间的优先级
- 让 `Show-ServiceAccessInfo` 与实际绑定行为保持一致
- 在测试中覆盖端口改写、配置优先级、非法配置与 host 网络拒绝逻辑

## Non-Goals

- 不把所有服务改为 `network_mode: host`
- 不修改现有服务默认是否对外开放的行为
- 不让原生命令 `docker compose -f config/dockerfiles/compose/docker-compose.yml ...` 自动继承 localhost 绑定能力
- 不在本次改动中扩展更复杂的网络策略，例如按单个端口选择绑定地址、绑定到特定内网 IP 或 Tailscale IP
- 不为 `network_mode: host` 服务实现半自动兼容逻辑

## Chosen Approach

采用“基础 compose 保持声明式配置 + `start-container.ps1` 在需要时生成临时 localhost override”的方案。

理由如下：

- 默认行为可以保持完全不变，不会让未开启 localhost 模式的用户受到影响
- `-BindLocalhost` 与 `.env.local` 可以沿用现有配置解析优先级，入口一致
- 不需要把整个基础 compose 模板重构为依赖 `host_ip` 插值的形式
- 当目标服务不是 `ports:` 暴露而是 `network_mode: host` 时，可以明确拒绝执行，边界清晰

相比维护一份额外的 `docker-compose.localhost.yml`，临时 override 不会引入长期双份配置的同步成本。

## Configuration Contract

### CLI Parameter

`start-container.ps1` 新增 `-BindLocalhost` 开关，用于显式要求把目标服务的宿主机端口绑定到 `127.0.0.1`。

该参数需要支持三种状态：

- 未传入：表示不覆盖配置文件，继续走配置解析结果
- 显式为 `true`：强制开启 localhost 绑定
- 显式为 `false`：例如 `-BindLocalhost:$false`，即使 `.env.local` 中写了 `BIND_LOCALHOST=true`，也要临时关闭 localhost 绑定

这意味着实现层不能只把它当作普通的“有没有传开关”来处理，而需要保留“显式传 false”这一覆盖语义。

### Persistent Env Setting

`config/dockerfiles/compose/.env.local` 增加：

```dotenv
BIND_LOCALHOST=true
```

该变量只影响 `start-container.ps1` 的启动路径，不承诺对用户直接运行原生命令时仍然生效。

### Precedence

最终优先级定义为：

1. CLI 显式 `-BindLocalhost`
2. `config/dockerfiles/compose/.env.local` 中的 `BIND_LOCALHOST`
3. 默认值 `false`

这保证了：

- 默认保持当前对外暴露行为
- 用户可以通过 `.env.local` 为本机长期启用 localhost 模式
- 用户仍然可以临时通过 CLI 覆盖 `.env.local`

### Boolean Parsing

布尔值解析采用严格模式，只接受常见明确值：

- 真值：`true`、`1`、`yes`、`on`
- 假值：`false`、`0`、`no`、`off`

如果 `BIND_LOCALHOST` 出现其它值，脚本直接失败并给出明确错误，避免因为拼写错误导致端口意外暴露或意外关闭。

## Compose Override Design

### Base Principle

基础文件 `config/dockerfiles/compose/docker-compose.yml` 继续作为唯一长期维护的 compose 模板，不直接写入 localhost 绑定逻辑。

当最终配置判定需要启用 localhost 绑定时，`start-container.ps1` 额外生成一个临时 override compose 文件，并在执行时叠加：

```text
docker compose -f docker-compose.yml -f /tmp/start-container.localhost.override.12345.yml ...
```

### Override Scope

临时 override 只覆盖本次目标服务对应的 `ports:` 定义，不修改镜像、环境变量、volume 或 profile。

例如：

- `postgre` 只覆盖 `postgre.ports`
- `rustdesk` 组合服务会同时覆盖 `rustdesk-hbbs` 与 `rustdesk-hbbr`
- `derper` 会同时覆盖 `8443/tcp` 与 `3478/udp`

### Port Rewrite Rules

端口改写规则统一为：

- `5432:5432` -> `127.0.0.1:5432:5432`
- `21116:21116/udp` -> `127.0.0.1:21116:21116/udp`
- 已经带协议后缀的端口必须保留协议

解析器只支持当前仓库实际使用的两类 `ports:` 写法：

- 行内数组写法，例如 `ports: ["6379:6379"]`
- 多行字符串列表写法，例如

```yaml
ports:
  - "21117:21117"
  - "21119:21119"
```

如果未来基础 compose 中出现更复杂的 `ports` map 语法，脚本应直接失败并提示当前 override 生成器不支持该格式，而不是静默跳过。

### Host Network Guard

当本次目标服务或其关联服务块声明了 `network_mode: host`，并且最终配置要求启用 localhost 绑定时，脚本直接报错。

原因是：

- host 网络模式下 `ports:` 映射不存在统一改写入口
- “应用自身监听地址”与“Docker 发布端口地址”是两层不同语义
- 模糊兼容会让用户误以为已经只绑定本机，实际却可能仍暴露在宿主机所有网卡上

错误信息应明确指出：

- 哪个服务使用了 `network_mode: host`
- `-BindLocalhost` 只支持 `ports:` 服务

## Derper Service Design

`derper` 以普通 `ports:` 服务形式接入，而不是 `network_mode: host`。

建议的 compose 角色如下：

- 镜像：`fredliang/derper`
- 重启策略：沿用 `${RESTART_POLICY:-unless-stopped}`
- 环境变量：
  - `DERP_ADDR=:8443`
  - `DERP_STUN_PORT=3478`
  - `DERP_VERIFY_CLIENTS=false`
- 端口：
  - `8443:8443`
  - `3478:3478/udp`
- `profiles: ["derper"]`

之所以不采用 host 网络模式，是因为：

- 这样能无缝兼容本次新增的 localhost 绑定能力
- 行为与仓库里大多数通用容器服务更一致
- 对用户而言，是否对外开放由统一入口控制，而不是由单个服务另起一套网络模型

## Script Responsibilities

`start-container.ps1` 在本设计下新增以下职责：

1. 解析最终的 localhost 绑定偏好
2. 在需要时生成并清理临时 override compose 文件
3. 把 override 文件追加到所有相关 `docker compose` 调用中
4. 在目标服务不支持 localhost 绑定时明确失败
5. 让帮助信息、服务列表说明与实际能力保持一致

以下事情仍不应由脚本承担：

- 不去动态修改基础 compose 模板本身
- 不让 `docker compose` 的原生命令与脚本自动共享额外能力
- 不对 host 网络服务推断其内部监听地址

## Service Access Output

`Show-ServiceAccessInfo` 的显示需要与绑定行为一致。

调整原则如下：

- `127.0.0.1` 与 `::1` 都统一展示为 `localhost`
- 当端口实际只绑定到 localhost 时，不再打印 `LAN` 地址
- 只有在端口发布到 `0.0.0.0` / `::` 时，才继续打印局域网访问地址

这样用户看到的“Local / LAN”信息才能准确反映安全边界，而不会在 localhost 模式下误导性地暗示局域网可达。

## Error Handling

新增能力需要主动处理以下错误：

- `BIND_LOCALHOST` 不是合法布尔值
- 目标服务不存在 `ports:`，但用户要求 localhost 绑定
- 目标服务命中 `network_mode: host`
- 目标服务的 `ports:` 使用了当前 override 生成器不支持的格式
- 临时 override 文件生成失败

这些错误都应在执行 `docker compose` 前抛出，避免用户误以为容器已按预期启动。

## Testing Strategy

本次改动涉及 `scripts/pwsh/devops/start-container.ps1` 与 `tests/**/*.ps1`，因此实现阶段需要执行：

```powershell
pnpm qa
pnpm test:pwsh:all
```

测试覆盖至少包含以下几类：

### Compose Static Tests

在 `tests/StartContainer.Tests.ps1` 中新增断言：

- `derper` 服务块存在
- `derper` 端口同时包含 `8443:8443` 与 `3478:3478/udp`

### Configuration Resolution Tests

在 `tests/StartContainer.ConfigIsolation.Tests.ps1` 中新增断言：

- `.env.local` 中的 `BIND_LOCALHOST=true` 会被正确识别
- CLI 显式关闭可以覆盖 `.env.local` 的开启状态
- 非法布尔值会立即报错

### Localhost Override Tests

新增或扩展测试覆盖：

- 行内数组形式的 `ports` 会被改写为 `127.0.0.1:...`
- 多行列表形式的 `ports` 会被改写为 `127.0.0.1:...`
- UDP 端口后缀不会丢失
- 关闭 localhost 绑定时不会生成 override
- 命中 `network_mode: host` 时会明确拒绝执行

### Access Info Tests

如果对输出辅助函数增加可测试封装，应验证：

- localhost 绑定场景下仅显示 `Local: localhost:...`
- 对外发布场景下仍显示 `LAN: ...`

## Risks And Trade-offs

### Text-Based Port Parsing

由于当前脚本与仓库没有现成的 YAML 结构化解析依赖，override 生成器大概率需要基于当前 compose 模板的受控文本格式工作。

这带来的权衡是：

- 优点：无需引入额外模块，能快速复用当前模板风格
- 缺点：未来若 compose 写法变复杂，需要同步扩展解析器

因此设计上必须要求“不支持就失败”，而不是做静默兼容。

### Script-Only Capability

localhost 绑定能力只在 `start-container.ps1` 入口里生效，意味着：

- 优点：默认行为稳定，改动范围集中
- 缺点：用户如果绕过脚本直接运行原生命令，不会自动获得该能力

这是一个有意保留的边界，因为本次目标是增强仓库统一入口，而不是重写所有原生命令使用方式。

## Documentation Changes

实现时需要同步更新以下文档或帮助内容：

- `scripts/pwsh/devops/start-container.ps1` 顶部帮助注释
- 服务列表说明，补充 `derper`
- `-BindLocalhost` 参数说明与示例
- `config/dockerfiles/compose/.env.local` 中 `BIND_LOCALHOST` 的用法说明

如需补仓库文档，优先在现有 Docker localhost 速查或容器启动相关说明中补一段简短示例，而不是新增长篇独立教程。

## Validation Plan

实现完成后至少验证以下路径：

1. `./scripts/pwsh/devops/start-container.ps1 -ServiceName derper -DryRun` 能输出包含 `derper` profile 的 compose 命令
2. `./scripts/pwsh/devops/start-container.ps1 -ServiceName postgre -BindLocalhost -DryRun` 会叠加临时 override，并体现 localhost 绑定语义
3. `config/dockerfiles/compose/.env.local` 中写 `BIND_LOCALHOST=true` 后，不传 CLI 参数也会默认启用 localhost 绑定
4. UDP 端口服务在 localhost 模式下仍保留正确协议
5. 命中 `network_mode: host` 的目标服务在 localhost 模式下会被拒绝

## Deferred Work

如后续有需要，可在独立变更中继续考虑：

- 为 localhost 绑定补 `-BindAddress` 之类的更通用能力，支持指定内网 IP、Tailscale IP 等
- 为原生命令提供辅助脚本，降低“脚本入口”和“直接 compose”之间的体验差异
- 在不引入过重依赖的前提下，把受控文本解析升级为更稳健的 YAML 结构化处理
