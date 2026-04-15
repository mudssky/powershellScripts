# LiteLLM Compose Design

## Summary

本设计将 `ai/gateway/litellm` 的启动方式从脚本内硬编码 `docker run` 参数，调整为以 `compose.yaml` 为中心的 `docker compose` 工作流。

调整后的目录仍保留 `start.ps1` 作为用户入口，但它的职责将从“手工拼装容器启动参数”收敛为“统一封装 LiteLLM 常用 compose 操作”，覆盖 `up`、`down`、`restart`、`logs`、`ps`、`pull` 等日常动作，同时保留“直接运行脚本即可启动”的低门槛体验。

第一版只处理 LiteLLM 单服务的 compose 化，不扩展到额外数据库服务或更大的 AI 网关编排。

## Context

当前 `ai/gateway/litellm/start.ps1` 直接构造 `docker run` 参数数组，内含以下运行时细节：

- 容器名固定为 `litellm`
- 宿主机端口 `34000` 映射到容器端口 `4000`
- `PORT` 通过环境变量注入到 LiteLLM 官方镜像
- `DATABASE_URL` 在脚本中写死默认值
- `newapi.yaml` 被挂载到容器内 `/app/config.yaml`
- `ai/gateway/.env.local` 通过 `--env-file` 注入
- 容器重启策略为 `unless-stopped`

这套方式虽然能工作，但存在几个明显问题：

- 运行配置分散在 PowerShell 脚本里，后续维护端口、挂载、环境变量时不够直观。
- 日常操作只有“启动”这条路径，其它 `logs`、`down`、`pull` 等动作没有统一入口。
- 从其他目录执行脚本时，路径解析和参数复用的可读性一般。
- 仓库内已经存在 compose 风格配置示例，但 LiteLLM 目录仍停留在单条 `docker run` 方式，风格不一致。

## Goals

- 为 `ai/gateway/litellm` 增加可直接使用的 `compose.yaml` 模板。
- 把 LiteLLM 的运行时配置从 `start.ps1` 迁移到 compose 文件中。
- 保留 `start.ps1` 作为统一入口，并内置常用 compose 操作。
- 保持当前默认端口、镜像、配置挂载和环境变量来源不变，避免无关行为漂移。
- 让脚本在任意工作目录执行时都能稳定定位 `compose.yaml` 与 `../.env.local`。

## Non-Goals

- 不在本次改动中引入 PostgreSQL、Redis 或其它依赖服务。
- 不调整 LiteLLM 的模型配置格式，不改写 `newapi.yaml` 语义。
- 不在第一版增加复杂 profile、多环境矩阵或多 compose 文件叠加方案。
- 不改变 LiteLLM 默认镜像版本、宿主机端口或现有 `.env.local` 配置结构。

## Constraints

- 目录入口仍应保留在 `ai/gateway/litellm/start.ps1`，避免破坏现有使用习惯。
- `compose.yaml` 必须能从脚本所在目录稳定解析，不依赖用户当前工作目录。
- 敏感环境变量继续放在 `ai/gateway/.env.local`，不回写到 `compose.yaml` 或 `newapi.yaml`。
- 脚本需要提供清晰注释，尤其是公共入口、路径解析和非直观命令映射逻辑。
- 需要兼容 Windows 上以 PowerShell 调用 `docker compose` 的场景。

## Chosen Approach

采用“单服务 compose 模板 + PowerShell 包装入口”方案。

实现后职责分层如下：

- `compose.yaml` 负责声明 LiteLLM 服务的静态运行配置。
- `start.ps1` 负责参数解析、路径定位、依赖检查和常用 compose 子命令转发。
- `newapi.yaml` 继续只承担 LiteLLM 代理配置。
- `ai/gateway/.env.local` 继续承担本地敏感环境变量注入。

相比继续扩展 `docker run` 脚本，这个方案的优势是：

- 配置边界更清晰，容器配置集中在 compose 文件中查看和维护。
- 常用运维动作可以通过统一入口复用，减少手工记忆完整 compose 命令。
- 后续若需要补充 `healthcheck`、额外挂载或镜像参数，也更容易在 compose 文件中增量维护。

## File Layout

调整后的相关文件角色如下：

```text
ai/gateway/
├── .env.example
├── .env.local
└── litellm/
    ├── compose.yaml
    ├── newapi.yaml
    ├── start.ps1
    └── litellm.md
```

职责说明：

- `compose.yaml`：LiteLLM compose 模板，承载镜像、端口、挂载、env file、重启策略等配置。
- `start.ps1`：统一入口，封装常用 `docker compose` 子命令。
- `newapi.yaml`：LiteLLM 代理配置文件，挂载到容器内 `/app/config.yaml`。
- `.env.local`：本地私有环境变量来源。
- `.env.example`：用户可复制参考的环境变量样板。

## Compose Design

`compose.yaml` 第一版只定义一个 `litellm` 服务，并维持当前运行语义：

- `image: docker.litellm.ai/berriai/litellm:main-latest`
- `container_name: litellm`
- `ports: ["34000:4000"]`
- `environment` 中固定 `PORT=4000`
- `env_file` 指向 `../.env.local`
- `volumes` 将 `./newapi.yaml` 只读挂载到 `/app/config.yaml`
- `restart: unless-stopped`

对于数据库连接，compose 层采用“允许本地覆写，保留当前默认值”的策略：

- `DATABASE_URL` 优先读取 `ai/gateway/.env.local`
- 若未显式提供，则回落到 `postgresql://postgres:12345678@host.docker.internal:5432/litellm`

为了让 Linux Docker Engine 场景也更稳妥，compose 中增加：

```yaml
extra_hosts:
  - "host.docker.internal:host-gateway"
```

这样即使运行环境不自带 `host.docker.internal` 解析，也能尽量保持与当前默认数据库连接写法兼容。

## CLI Design

`start.ps1` 设计为 LiteLLM 的统一运维入口，默认行为等价于 `up -d`。

建议支持以下命令：

- 无参数：执行 `up -d`
- `up`：启动或重建服务
- `down`：停止并移除当前 compose 管理资源
- `restart`：重启服务
- `logs`：跟随查看 LiteLLM 服务日志
- `ps`：查看服务状态
- `pull`：拉取最新镜像，不自动重启

脚本内部会固定使用：

- `-f <litellm-dir>/compose.yaml`
- `--project-directory <litellm-dir>`

必要时可显式指定服务名 `litellm`，从而避免用户必须手动切换到配置目录再执行命令。

## Script Responsibilities

`start.ps1` 只负责以下几类逻辑：

1. 解析用户输入的高频动作，并提供默认值。
2. 解析并固定 `compose.yaml` 与 `../.env.local` 的绝对路径。
3. 检查 `docker` 与 `docker compose` 是否可用。
4. 在命令执行前做少量前置校验，例如 `compose.yaml` 是否存在。
5. 将动作映射为具体 `docker compose` 调用，并把输出透传给用户。

以下事情不应由脚本承担：

- 不重新实现 compose 的复杂参数系统。
- 不在脚本内重新维护镜像、端口、挂载等容器细节。
- 不增加与当前需求无关的业务逻辑，例如自动初始化数据库或批量管理多个网关。

## Error Handling

第一版采用“显式前置检查 + 底层错误透传”的策略。

脚本应主动处理的错误包括：

- `docker` 命令不存在
- `docker compose` 子命令不可用
- `compose.yaml` 文件不存在
- 用户输入未知动作

其中：

- `docker` / `docker compose` 缺失时，直接输出明确错误和下一步建议
- `compose.yaml` 缺失时立即失败，避免执行空命令
- `.env.local` 缺失时不强制失败，但输出警告，提示当前环境变量可能未生效
- 未知动作时输出简短帮助，列出支持的动作和默认行为

## Documentation Changes

`ai/gateway/litellm/litellm.md` 需要同步改写为 compose 用法，重点说明：

- 当前目录包含 `compose.yaml`
- 如何通过 `start.ps1` 执行常用操作
- 如需直接调用原生命令，应使用 `docker compose -f ai/gateway/litellm/compose.yaml ...`
- `.env.local` 中哪些变量是必须或推荐配置的

`ai/gateway/.env.example` 也应补充 `DATABASE_URL` 示例，确保 compose 方案下环境变量来源清晰。

## Validation Strategy

实现时优先做两层验证：

### Compose Validation

通过 `docker compose -f ai/gateway/litellm/compose.yaml config` 检查：

- compose 语法可解析
- `env_file`、挂载路径和环境变量展开结果符合预期
- `DATABASE_URL` 默认值不会造成模板解析错误

### Repository Validation

遵循仓库约束，在完成代码改动后于仓库根目录执行：

```powershell
pnpm qa
```

本次改动不涉及 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1` 等 pwsh 测试要求路径，因此不额外要求执行 `pnpm test:pwsh:all`。

## Verification Plan

实现完成后至少验证以下路径：

1. `.\ai\gateway\litellm\start.ps1` 在无参数时能够映射为 `docker compose up -d`。
2. `.\ai\gateway\litellm\start.ps1 logs` 能正确进入 LiteLLM 服务日志跟随模式。
3. `.\ai\gateway\litellm\start.ps1 ps` 能输出当前服务状态。
4. `docker compose -f ai/gateway/litellm/compose.yaml config` 能成功展开配置。
5. 文档中的启动方式已经全部从旧的 `docker run` 切换为 `docker compose`。

## Deferred Work

如后续需要，可在独立变更中继续考虑：

- 为 LiteLLM 增加 `healthcheck`
- 增加 `stop`、`config` 或透传原生 compose 参数的高级入口
- 引入同目录数据库或观测组件的多服务编排
- 将端口、容器名等参数进一步抽象为可配置模板

这些内容不属于本次设计范围。
