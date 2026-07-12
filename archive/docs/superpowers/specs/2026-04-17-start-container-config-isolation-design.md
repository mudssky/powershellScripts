# Start-Container Config Isolation Design

## Context

`scripts/pwsh/devops/start-container.ps1` 目前通过全局环境变量驱动 `docker compose`，并在脚本运行过程中直接把 `.env`、`.env.local`、`-Env` 与解析后的默认值写入当前 PowerShell 进程环境。这个模型对大多数服务是方便的，但会带来两个问题：

1. 同一 PowerShell 会话内，不同服务之间会通过进程环境互相污染。例如先启动 `minio` 或 `rustfs` 后残留的 `DEFAULT_USER=root`，会影响后续 `postgre` 或 `paradedb` 的解析结果。
2. 脚本把“读取配置来源”和“应用环境变量”耦合在一起，导致后续脚本难以复用，也让排查最终值来源变得困难。

最近一次 `postgre` / `paradedb` 默认用户修复已经把服务级默认值收口到 `postgres`，但当前优先级仍允许通用 `DEFAULT_*` 被历史会话状态覆盖。这说明问题的根因不是默认值函数本身，而是配置来源与环境隔离模型。

## Goals

- 修复 `start-container.ps1` 的环境污染问题，避免同一会话内前一次调用影响后一次调用。
- 保留现有易用性：继续支持 `-DefaultUser`、`-DefaultPassword`、`-Env`、`.env`、`.env.local`。
- 为 `psutils` 沉淀一套可复用的“配置解析 + 作用域环境执行”基础能力。
- 让 `postgre` / `paradedb` 继续兼容 `DEFAULT_*` 用法，但只接受“本次调用明确提供的来源”。
- 提供足够的调试信息，能回答“某个键最终来自哪里”。

## Non-Goals

- 不重写 `start-container.ps1` 的整体 CLI 形态。
- 不要求所有服务立即改为专用变量。
- 不自动迁移已有 PostgreSQL/ParadeDB 数据目录中的用户、密码或默认库。
- 不在第一版支持复杂 JSON 映射、嵌套对象展开或变量插值。

## Approach Options

### Option 1: 仅在 `start-container.ps1` 中快照并恢复环境

进入脚本时记录相关环境变量，退出时统一恢复。

优点是改动最小，但环境隔离能力仍沉在单个脚本中，后续其他脚本容易重复实现，因此不推荐。

### Option 2: 在 `psutils` 中新增双层通用能力

新增一个通用配置解析器和一个通用作用域环境执行器，`start-container.ps1` 只负责声明来源、优先级和服务特例。

这是推荐方案，因为它既能修复当前问题，又能沉淀公共基础设施，兼顾复用性与兼容性。

### Option 3: 改为临时 env 文件驱动 `docker compose`

每次调用先渲染临时 env 文件，再用 `docker compose --env-file` 执行。

优点是来源非常显式，但实现更重，dry-run、文件清理和兼容性处理也更复杂，因此本次不采用。

## Design

### 1. `psutils` 配置解析器

在 `psutils` 中新增通用配置解析器，例如 `Resolve-ConfigSources`。该函数只负责读取和合并配置，不直接写入当前进程环境。

第一版支持以下来源类型：

- `Hashtable`
- `EnvFile`
- `JsonFile`
- `ProcessEnv`

调用方显式传入来源列表和优先级顺序。解析器返回一个结构化对象，至少包含：

- `Values`：最终合并后的键值对
- `Sources`：每个键最终命中的来源标识
- `Trace`：可选调试信息，记录候选值和覆盖顺序

为兼顾脚本内调用与命令行易用性，解析器提供两套入口：

- CLI 友好的简洁入口：`-ConfigFile`
- 脚本内高级入口：`-Sources`

其中：

- `-ConfigFile` 面向命令行与简单脚本场景，允许多次传入，解析器根据扩展名自动识别 `.env` / `.env.local` 与 `.json`
- `-Sources` 面向内部脚本与高级调用场景，允许显式声明来源类型、名称与数据

默认行为采用“自动发现 + 显式覆盖并存”的模式：

- 未显式传入 `-ConfigFile` 时，自动在当前工作目录或调用方指定基准目录查找 `.env` 与 `.env.local`
- 显式传入 `-ConfigFile` 时，仅解析用户指定的文件列表，不再额外自动发现默认文件
- `-Sources` 作为高级入口，不参与默认自动发现逻辑

这样可以保证：

- 命令行场景足够顺手，不需要手写 hashtable
- 脚本内仍保留完全可编排的来源声明能力
- 默认行为与仓库现有 `.env` / `.env.local` 习惯保持一致

第一版 JSON 只支持顶层 key-value 对象，例如：

```json
{
  "DEFAULT_USER": "postgres",
  "DEFAULT_PASSWORD": "12345678",
  "COMPOSE_PROJECT_NAME": "dev-paradedb"
}
```

不支持嵌套展开、数组映射或变量插值。

### 1.1 解析器命令形态示例

命令行推荐用法：

```powershell
Resolve-ConfigSources
```

上面等价于自动查找当前目录下的 `.env` 与 `.env.local`。

显式指定文件时：

```powershell
Resolve-ConfigSources -ConfigFile .env -ConfigFile .env.local
```

混合 JSON 配置时：

```powershell
Resolve-ConfigSources -ConfigFile .env -ConfigFile .env.local -ConfigFile ./config/start-container.json
```

脚本内高级调用时，可使用结构化来源：

```powershell
$config = Resolve-ConfigSources -Sources @(
    @{ Type = 'EnvFile'; Path = '.env' },
    @{ Type = 'EnvFile'; Path = '.env.local' },
    @{ Type = 'Hashtable'; Name = 'CliEnv'; Data = $Env },
    @{ Type = 'Hashtable'; Name = 'Defaults'; Data = @{
        DEFAULT_USER = 'postgres'
        DEFAULT_PASSWORD = '12345678'
    }}
) -IncludeTrace
```

其中：

- 命令行主推 `-ConfigFile` 与默认自动发现
- 脚本内部主推 `-Sources`
- `Trace` 仅在需要排查来源时启用

### 2. `psutils` 作用域环境执行器

在 `psutils` 中新增通用作用域环境执行器，例如 `Invoke-WithScopedEnvironment`。该函数接收一组环境变量覆盖值和一个 `ScriptBlock`，在执行前注入进程级环境变量，执行结束后无论成功或失败都恢复原值。

其职责与配置解析器严格分离：

- 不关心配置来自哪里
- 只负责临时应用与恢复
- 支持变量原本不存在时在退出后清理

该能力与现有 PostgreSQL 工具中的临时环境恢复模式保持一致，但上提为公共基础设施。

### 2.1 作用域环境执行器推荐接口

第一版推荐保持最小接口：

```powershell
Invoke-WithScopedEnvironment -Variables @{
    DEFAULT_USER = 'postgres'
    DEFAULT_PASSWORD = '12345678'
    COMPOSE_PROJECT_NAME = 'dev-paradedb'
} -ScriptBlock {
    docker compose -f $composePath -p $projectName --profile paradedb up -d
}
```

推荐行为如下：

- 仅修改 `Process` 级环境变量
- 使用 `try/finally` 保证恢复
- 原本不存在的变量在退出时删除
- 原本存在的变量在退出时恢复旧值
- `ScriptBlock` 抛错时不吞异常，只在恢复后继续抛出
- 支持嵌套调用

第一版不承担以下职责：

- 不直接解析 `.env`、`.json` 或 `-ConfigFile`
- 不直接封装 `docker compose`
- 不默认输出敏感值

### 2.2 在 `start-container.ps1` 中的典型使用方式

`start-container.ps1` 中推荐的接法为：

```powershell
$config = Resolve-ConfigSources -ConfigFile .env -ConfigFile .env.local

$composeEnv = @{
    DATA_PATH            = $config.Values.DATA_PATH
    DEFAULT_USER         = $config.Values.DEFAULT_USER
    DEFAULT_PASSWORD     = $config.Values.DEFAULT_PASSWORD
    COMPOSE_PROJECT_NAME = $config.Values.COMPOSE_PROJECT_NAME
}

Invoke-WithScopedEnvironment -Variables $composeEnv -ScriptBlock {
    Invoke-DockerCompose -File $composePath -Project $projectName -Profiles $targetProfiles -Action 'up -d'
}
```

如需调试，可在后续实现中支持 `-Verbose` 输出键名列表，但不输出敏感值本身。例如：

- `Applying scoped environment keys: DEFAULT_USER, DEFAULT_PASSWORD, COMPOSE_PROJECT_NAME`

不应输出：

- `DEFAULT_PASSWORD=12345678`

### 3. `start-container.ps1` 的接入方式

`start-container.ps1` 改为“解析本次调用配置，再局部执行 compose”的模式：

1. 收集本次调用显式来源
   - CLI 参数
   - `-Env`
   - 脚本目录下的 `.env`
   - 脚本目录下的 `.env.local`
   - 服务默认值
2. 调用 `Resolve-ConfigSources`
3. 根据服务类型构造本次调用的 compose 环境变量集合
4. 使用 `Invoke-WithScopedEnvironment` 包裹 `Invoke-DockerCompose`

脚本不再把解析后的 `DEFAULT_*`、`DATA_PATH`、`COMPOSE_PROJECT_NAME` 等值长期写回当前会话环境。

### 4. `postgre` / `paradedb` 的特例规则

本次不改变用户的使用习惯。数据库服务仍继续支持：

- `-DefaultUser`
- `-DefaultPassword`
- `-Env @{ DEFAULT_USER = ... }`
- `.env` / `.env.local` 中的 `DEFAULT_*`

但它们默认不再读取“历史会话残留的 `ProcessEnv`”。换句话说，数据库服务继续兼容 `DEFAULT_*`，但只接受“本次调用明确提供的来源”。

普通服务可继续维持当前行为，允许按既有方式消费通用 `DEFAULT_*`。

### 5. 旧数据目录保护性提示

针对 `postgre` 与 `paradedb`，在启动前检查对应数据目录中是否存在 `PG_VERSION`。若存在，输出明确提示：

- 当前用户名、密码、库名配置仅影响新初始化实例
- 已有数据目录不会自动迁移内部角色、密码或默认库
- 如需变更旧实例内部状态，需要手工迁移或重新初始化数据目录

该提示只负责澄清行为，不阻止启动。

### 6. 调试与可观测性

当用户需要排查来源时，脚本应能基于配置解析器返回的 `Sources` / `Trace` 输出信息，例如：

- `DEFAULT_USER` 最终来自 `-Env`
- `COMPOSE_PROJECT_NAME` 最终来自 `.env.local`
- `DEFAULT_PASSWORD` 最终来自服务默认值

第一版可先提供内部结构和测试，不强制在常规输出中展示所有 trace；后续需要时可扩展为 `-Verbose` 或专门调试输出。

## Priority Rules

配置优先级不在解析器内部写死，而由调用方传入。

对 `start-container.ps1` 的默认推荐顺序为：

1. CLI 显式参数与 `-Env`
2. `.env.local`
3. `.env`
4. 服务默认值
5. `ProcessEnv`（仅普通服务启用；数据库服务默认关闭）

其中数据库服务通过关闭 `ProcessEnv` 来源来避免历史会话污染，而不是彻底放弃 `DEFAULT_*` 兼容性。

## Testing Strategy

### `psutils` 配置解析器

- `.env` 与 `.env.local` 的优先级覆盖
- JSON 与 env 文件的覆盖顺序
- `ProcessEnv` 关闭时不参与解析
- `Trace` 正确记录最终命中来源
- 缺失文件的默认忽略行为

### `psutils` 作用域环境执行器

- 正常执行后恢复环境
- 异常执行后仍恢复环境
- 原本不存在的变量在退出后被移除

### `start-container.ps1`

- `postgre` / `paradedb` 不再读取历史会话残留 `DEFAULT_*`
- `postgre` / `paradedb` 继续接受 `.env`、`.env.local`、`-Env`、CLI 参数中的 `DEFAULT_*`
- 普通服务继续保留当前通用变量行为
- 检测到 `PG_VERSION` 时输出迁移提示
- 现有默认用户测试按新优先级更新

## Compatibility and Migration

此改动属于脚本行为收敛，不是数据迁移：

- 普通服务现有使用方式基本保持不变
- `postgre` / `paradedb` 的命令行和 `.env` 用法保持不变
- 唯一被刻意收紧的是数据库服务对“历史会话残留环境”的读取行为

因此：

- 依赖 shell 中长期保留 `DEFAULT_USER` 驱动数据库服务的用法会变化
- 通过本次调用的 `-Env`、`.env`、`.env.local`、CLI 参数显式提供值的用法不受影响

## Risks

- 如果配置解析器抽象过重，可能增加脚本理解成本。
- 如果数据库服务与普通服务的优先级差异没有写清楚，可能造成新的认知偏差。
- 如果测试只覆盖解析器，不覆盖 `start-container.ps1` 接入层，仍可能出现“解析正确、接入错误”的问题。

对应缓解方式：

- 第一版只支持 env/json/process hashtable 四类来源
- 明确把数据库服务特例写进文档与测试
- 在 `psutils` 与 `start-container.ps1` 两层同时加测试

## Recommended Outcome

本次推荐采用：

- `psutils` 新增通用配置解析器
- `psutils` 新增通用作用域环境执行器
- `start-container.ps1` 改为“解析本次调用配置，再局部注入环境执行 compose”
- `postgre` / `paradedb` 继续兼容 `DEFAULT_*`，但只接受本次调用显式来源
- 新增旧 `PGDATA` 检测提示与来源追踪测试

这样既能修掉当前 `start-container.ps1` 的环境污染问题，又不会把常用的通用变量模型整体推翻。
