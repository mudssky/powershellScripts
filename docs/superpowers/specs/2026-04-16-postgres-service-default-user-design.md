# Postgres Service Default User Design

## Context

当前 `start-container.ps1` 通过全局 `DefaultUser` 参数为多个容器服务提供统一默认用户名，默认值为 `root`。这对 `minio`、`rustfs` 等服务是合理的，但对 `postgre` 与 `paradedb` 这类基于 PostgreSQL 的服务并不符合常见使用习惯，也会导致初始化用户、探活命令和实际连接方式之间出现认知偏差。

现有问题主要体现在两点：

1. `paradedb` 会直接继承全局 `DEFAULT_USER`，因此在未显式传参时会初始化为 `root` 用户，而使用者通常会按 `postgres` 登录。
2. `postgre` 的健康检查已经写死为 `pg_isready -U postgres`，但容器初始化默认用户仍可能来自全局 `root`，形成配置语义不一致。

本次设计目标是仅修正 PostgreSQL 系服务的默认用户名，不改变其他依赖 `root` 语义的服务行为。

## Goals

- 让 `postgre` 和 `paradedb` 在未显式传入 `-DefaultUser` 时默认使用 `postgres`
- 保留 `-DefaultUser` 的覆写能力，便于高级用法或与既有环境对齐
- 保证健康检查、容器初始化用户和脚本输出语义一致
- 不影响 `minio`、`rustfs`、`qdrant` 等其他服务当前的默认用户行为

## Non-Goals

- 不修改 PostgreSQL 数据卷挂载结构
- 不自动迁移或修复已经初始化完成的数据目录中的角色信息
- 不重构 `start-container.ps1` 的整体参数模型
- 不调整非 PostgreSQL 服务的默认用户名策略

## Approach Options

### Option 1: 直接修改全局 `DefaultUser`

将 `start-container.ps1` 中的全局 `DefaultUser` 默认值从 `root` 改为 `postgres`。

优点是实现最简单，但会改变所有依赖全局默认值的服务行为，容易误伤对象存储或通用服务，因此不采用。

### Option 2: 在 Compose 中写死 PostgreSQL 用户

在 `postgre` 与 `paradedb` 的 compose 配置中直接写死 `POSTGRES_USER=postgres`，不再依赖脚本注入。

优点是行为直观，但会削弱 `-DefaultUser` 的统一覆写能力，也会让脚本层和 compose 层的职责边界更模糊，因此不采用。

### Option 3: 为 PostgreSQL 系服务引入专用默认用户

保留全局 `DefaultUser=root`，但在脚本内部对 `postgre` 与 `paradedb` 做服务级默认值分流：未显式传入 `-DefaultUser`、环境变量中也未设置 `DEFAULT_USER` 时，这两个服务回落到 `postgres`；其他服务继续回落到 `root`。

这是推荐方案，因为它最符合用户预期，也能保持兼容面最小。

## Design

### Configuration Resolution

脚本继续维持当前的优先级顺序：

1. 显式命令行参数 `-DefaultUser`
2. 已存在的环境变量 `DEFAULT_USER`（包括 shell、`.env`、`.env.local` 注入）
3. 服务级默认值

其中服务级默认值规则调整为：

- `postgre` -> `postgres`
- `paradedb` -> `postgres`
- 其他服务 -> `root`

这样可以保证：

- 默认体验符合 PostgreSQL 常见约定
- 已有用户如果在 `.env.local` 中自定义过 `DEFAULT_USER`，行为不会被本次变更覆盖
- 命令行显式传入仍然拥有最高优先级

### Compose Integration

`docker-compose.yml` 中的 `postgre` 与 `paradedb` 继续通过 `${DEFAULT_USER:-postgres}` 形式消费用户名，但脚本会在运行前根据服务类型注入更合理的默认值。

`postgre` 需要显式补齐 `POSTGRES_USER: ${DEFAULT_USER:-postgres}`，让初始化用户与健康检查保持一致。

`paradedb` 保持现有的 `POSTGRES_USER` 写法，但其运行时 `DEFAULT_USER` 默认来源将改为服务级 `postgres`。

### Script Changes

脚本中新增一个小型解析函数，用于根据 `ServiceName` 计算服务级默认用户名。该函数职责单一：

- 输入服务名
- 输出该服务的默认用户名

主流程中不再直接把参数默认值 `root` 作为所有服务的最终回落值，而是改为：

- 显式参数存在时使用显式参数
- 否则为当前服务解析服务级默认用户名

这样可以减少后续新增数据库类服务时的重复判断，也让默认行为更集中、可测试。

### Testing Strategy

本次改动需要先新增失败测试，再做实现。测试重点包括：

1. `postgre` 未显式传入 `-DefaultUser` 时，应解析为 `postgres`
2. `paradedb` 未显式传入 `-DefaultUser` 时，应解析为 `postgres`
3. 非 PostgreSQL 服务（例如 `minio`）未显式传入时，仍保持 `root`
4. 当显式传入 `-DefaultUser custom` 时，`postgre` / `paradedb` 应使用 `custom`
5. `postgre` compose 配置中应包含 `POSTGRES_USER`

测试以最小范围覆盖行为变化，避免为了这一点默认值调整引入过度耦合的集成测试。

## Error Handling

本次变更不新增运行时异常分支。若用户提供了不存在或不兼容的用户名，容器初始化仍遵循 PostgreSQL 官方镜像行为。

需要在文档或最终说明中明确一条迁移提醒：

- 该默认值变更仅影响“首次初始化”的数据库目录
- 已经初始化过的数据卷不会因为重新执行脚本而自动新增 `postgres` 用户或替换现有超级用户
- 若已有数据目录使用 `root` 初始化，用户需要手工创建角色、显式传入 `-DefaultUser root`，或清空数据卷后重新初始化

## Compatibility and Migration

兼容性策略如下：

- 对 `postgre` / `paradedb` 的新实例：默认用户名改为 `postgres`
- 对显式配置了 `DEFAULT_USER` 的现有用户：行为保持原样
- 对已初始化的数据目录：数据库内部角色不发生自动变更

因此本次属于“改进默认值而非数据迁移”的兼容性修正，风险可控，但必须在交付说明中写清楚旧数据目录的影响。

## Risks

- 用户可能误以为修改脚本后，已有 `root` 初始化的数据卷会自动变成 `postgres`
- 如果测试只覆盖脚本层而不校验 compose 中 `postgre` 的 `POSTGRES_USER`，仍可能留下初始化与探活不一致的问题

对应缓解方式：

- 在测试中同时覆盖脚本解析与 compose 配置
- 在最终说明中单独强调“仅影响新初始化数据目录”

## Implementation Notes

- 优先提取一个服务级默认用户名解析函数，避免把特殊分支散落在主流程里
- `postgre` compose 配置补齐 `POSTGRES_USER`
- 不修改 `DefaultUser` 参数本身对外文档的通用语义，但要补充说明 PostgreSQL 系服务存在服务级默认值

