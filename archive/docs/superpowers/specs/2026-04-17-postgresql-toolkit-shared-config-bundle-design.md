# PostgreSQL Toolkit Shared Config Bundle Design

## Context

`scripts/pwsh/devops/Postgres-Toolkit.ps1` 目前是由 `scripts/pwsh/devops/postgresql/**` 多文件源码拼装出的单文件产物。现有实现已经支持：

- 通过 `build/Build-PostgresToolkit.ps1` 按固定顺序 bundle 为单文件脚本
- 通过 `--env-file` 显式读取 PostgreSQL `PG*` 连接变量
- 通过当前进程环境变量补齐 `PGHOST`、`PGPORT`、`PGUSER`、`PGPASSWORD`、`PGDATABASE`

但它还有两个明显短板：

1. PostgreSQL toolkit 仍然维护了一套独立的 dotenv 解析逻辑，没有复用仓库里已经沉淀出的配置解析能力。
2. bundle 过程只能手工列出源码片段，无法自动把共享 helper 的源码打进单文件产物，因此很难安全复用 `psutils` 中的新能力。

仓库当前已经具备一个可用但还不够“source-first”的配置解析器：

- [`psutils/modules/config.psm1`](/Users/mudssky/projects/powershellScripts/psutils/modules/config.psm1) 已支持默认解析 `.env` / `.env.local`
- [`psutils/tests/config.Tests.ps1`](/Users/mudssky/projects/powershellScripts/psutils/tests/config.Tests.ps1) 已覆盖多文件合并、显式文件输入和 trace 行为

与此同时，`Postgres-Toolkit` 的连接优先级和默认发现规则还没有覆盖新的 CLI 预期：

- 不传 `--env-file` 时，默认自动发现 `.env` / `.env.local`
- 自动发现优先查当前工作目录，必要时回退脚本目录
- 自动发现的文件值只能作为默认值，不能压过用户当前 shell 已导出的 `PG*`
- 显式 `--env-file` 仍然是强意图，优先级应高于当前进程环境变量

这次设计的目标，是在不破坏单文件分发体验的前提下，把共享配置能力真正接入 PostgreSQL toolkit，并为后续更多单文件脚本沉淀一套可复用的“源码抽取 + AST 自动补依赖 + bundle”机制。

## Goals

- 让 `scripts/pwsh/devops/postgresql/**` 复用共享配置解析能力，而不是长期维护独立 dotenv 解析器。
- 保持 `Postgres-Toolkit.ps1` 为自包含单文件产物，不要求目标机器预装 `psutils` 模块。
- 在 PostgreSQL toolkit 中新增默认 `.env` / `.env.local` 自动发现能力。
- 明确定义 `--env-file`、当前进程环境变量和自动发现文件之间的优先级。
- 引入一套仓库内的 AST 依赖抽取机制，让 bundle 可以自动补齐被调用的共享函数源码。
- 保证构建过程可失败、可解释、可测试，避免静默漏打包。

## Non-Goals

- 不把这次工作扩大为整个仓库的通用打包系统重写。
- 不在第一版支持任意动态调用的静态分析，例如 `& $FunctionName`、`Invoke-Expression`。
- 不在第一版引入新的外部闭源打包工具链。
- 不要求所有 `psutils` 模块立刻迁移到新结构，只覆盖这次需要复用的配置相关能力。
- 不改变 PostgreSQL toolkit 现有子命令形态、帮助结构和单文件产物位置。

## Constraints

- 真实实现入口在 `scripts/pwsh/devops/postgresql/**`，`scripts/pwsh/devops/Postgres-Toolkit.ps1` 只是构建产物。
- 单文件产物必须继续在无 `psutils` 模块依赖的环境中直接执行。
- dotenv 解析必须保持保守和安全，只接受简单 `KEY=VALUE` 语法，不执行 shell 表达式。
- 默认 env 文件发现逻辑必须稳定、可预测，不能跨目录“拼盘式”补缺。
- 默认发现与显式 `--env-file` 必须区分语义，避免把“自动默认值”做成“隐式强覆盖”。
- 任何无效 env 行都必须直接失败，不能静默跳过。

## Approach Options

### Option 1: 继续手工维护 PostgreSQL toolkit 自己的 dotenv 解析器

只在 `scripts/pwsh/devops/postgresql/core/*.ps1` 内部加默认 `.env` / `.env.local` 发现规则，不复用共享配置源码。

优点是改动最小，但会继续制造两套相似逻辑，后续修 bug 或增强语法时容易分叉，因此不推荐。

### Option 2: 引入 source-first 共享源码与 AST 自动补依赖 bundle

把配置相关共享能力抽到可直接复用的源码目录中，`psutils` 模块继续做薄封装；PostgreSQL toolkit 的构建脚本通过 PowerShell AST 自动收集被调用到的共享函数，并把源码打进单文件产物。

这是推荐方案，因为它同时解决：

- 共享配置能力复用
- 单文件产物自包含
- bundle 手工维护成本过高

### Option 3: 直接依赖外部打包工具或运行时模块导入

例如让单文件脚本在运行时导入 `psutils`，或者尝试引入现成脚本打包器统一处理依赖。

这种方式对当前仓库并不理想。调研表明已有开源积木可借鉴，但没有发现一个能直接满足“PowerShell 函数级按调用图抽取并单文件打包”的成熟开源工具；运行时模块导入也会破坏当前单文件分发目标，因此本次不采用。

## External Tool Research

本次调研过几类可能的现成方案：

- `ModuleBuilder` 适合 PowerShell 模块构建，但更偏模块级拼装，不是函数级按需抽取。
- `PSScriptAnalyzer` 与 PowerShell 官方 AST API 适合自建函数索引和依赖收集。
- `tree-sitter-powershell` 提供语法树 grammar，但不直接解决 PowerShell 命令解析、作用域和 bundle 规则问题。
- `Merge-Script` / PowerShell Pro Tools 更接近脚本打包，但不适合作为本仓库这次需求的开源基础设施。

因此本设计选择“基于官方 PowerShell AST，自建仓库内 bundling helper”的路线，而不是引入新的外部核心依赖。

参考来源：

- <https://github.com/PoshCode/ModuleBuilder>
- <https://github.com/PowerShell/PSScriptAnalyzer>
- <https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.parser.parsefile>
- <https://learn.microsoft.com/en-us/dotnet/api/system.management.automation.language.functiondefinitionast>
- <https://github.com/airbus-cert/tree-sitter-powershell>
- <https://docs.poshtools.com/powershell-pro-tools-documentation/powershell-module/aboutmergescript>

## Chosen Approach

采用“source-first 共享源码 + `psutils` 模块薄封装 + PostgreSQL bundler AST 自动补依赖”的方案。

架构边界如下：

- `psutils` 中的配置能力改为源码优先组织，模块文件只负责装配与导出。
- PostgreSQL toolkit 继续在 `scripts/pwsh/devops/postgresql/**` 中维护业务语义，例如连接优先级、CLI 形态、帮助文本和命令构建。
- 构建脚本不再只依赖手工列出的 `$bundleParts`，而是允许从共享源码目录按需递归抽取函数定义并打进单文件产物。

这样可以同时保留：

- `psutils` 模块调用体验
- `Postgres-Toolkit.ps1` 自包含的单文件体验
- 共享 helper 的单点维护

## Design

### 1. Source-First Shared Config Layout

建议把配置相关共享实现从 `psutils/modules/config.psm1` 中抽出，改为 source-first 结构，例如：

```text
psutils/
├── modules/
│   └── config.psm1
└── src/
    └── config/
        ├── convert.ps1
        ├── discovery.ps1
        ├── env.ps1
        ├── reader.ps1
        └── resolver.ps1
```

设计要求如下：

- `psutils/modules/config.psm1` 变成薄封装，只负责 dot-source `psutils/src/config/*.ps1` 并 `Export-ModuleMember`
- 共享源码文件中保留清晰注释，避免把可复用逻辑重新埋回聚合模块文件
- PostgreSQL bundler 只从 source-first 目录抽源码，不从 `psm1` 聚合文件中反向拆函数

这样做的原因是：

- 聚合模块文件适合导出，不适合做稳定的 bundle 抽取输入
- source-first 结构更适合 AST 建索引、做函数级去重和递归依赖收集
- `psutils` 的模块边界仍然存在，对既有调用方兼容

### 2. AST-Based Bundle Dependency Resolver

建议新增一个仓库内 bundling helper，可放在：

- `scripts/pwsh/devops/postgresql/build/`
- 或更通用的 `scripts/pwsh/build/`

其职责分成三步：

#### 2.1 建立函数索引

扫描白名单源码目录，例如：

- `scripts/pwsh/devops/postgresql/**`
- `psutils/src/config/**`

使用 PowerShell AST 收集：

- 函数名
- 函数定义源码文本
- 所在文件
- 函数体内静态可识别的命令调用名

#### 2.2 求依赖闭包

从 PostgreSQL toolkit 已知入口源码出发递归收集依赖。入口范围包括：

- `core/*.ps1`
- `platforms/*.ps1`
- `commands/*.ps1`
- `main.ps1`

当入口或其依赖函数调用到共享 helper，例如 `Resolve-ConfigSources`，构建器就从共享源码索引中找到函数定义，并继续递归收集它依赖的其他共享函数，直到闭包完整。

#### 2.3 输出 bundle

最终产物的组织原则为：

1. 产物头部与入口参数块保持现状
2. 先输出已解析出的共享依赖函数
3. 再输出 PostgreSQL toolkit 自己的核心源码和命令源码
4. 最后输出主分发函数与入口执行代码

这样既能保证依赖定义先于调用出现，又能尽量保持当前 bundle 可读性。

### 3. Bundle Resolver Rules

为避免“自动扫描”变成不可解释的黑箱，第一版 bundler 必须显式限制分析边界：

- 只扫描白名单目录，不扫整个仓库
- 只自动补齐静态可识别的函数调用
- 不支持 `& $name`、`Invoke-Expression` 等动态调用自动补依赖
- 如果调用了白名单目录内的函数名，但找不到定义，构建阶段直接失败
- 如果白名单目录内出现重名函数，构建阶段直接失败
- 若函数调用到 PowerShell 内置命令、外部命令或未纳入白名单的模块命令，则按“外部依赖”处理，不做源码抽取

这样做的目标不是“分析一切”，而是让构建行为足够稳定、可预期，并且在规则外场景下尽早失败。

### 4. Shared Config Capability Shape

PostgreSQL toolkit 这次主要需要复用的是“严格 dotenv 解析 + 多文件合并 + 默认文件发现”能力，因此建议把共享配置能力拆成更清晰的小函数，而不是只暴露一个大而全的入口。

推荐保留或新增以下职责边界：

- `Read-ConfigEnvFile`
  负责严格解析单个 env 文件
- `Resolve-ConfigSources`
  负责多来源合并
- `Resolve-DefaultEnvFiles`
  负责按照给定基准目录发现 `.env` / `.env.local`

其中 `Resolve-DefaultEnvFiles` 可以是 `psutils` 中新增的共享 helper，也可以是 PostgreSQL toolkit 专用 wrapper 调共享底层函数。关键是逻辑不能再散落在业务层多个函数里。

### 5. PostgreSQL Toolkit Default Env Discovery

`scripts/pwsh/devops/postgresql/core/context.ps1` 需要新增默认 env 自动发现能力，但必须与显式 `--env-file` 清晰区分。

规则如下：

#### 5.1 显式 `--env-file`

- 只读取用户显式传入的文件
- 不再做默认 `.env` / `.env.local` 自动发现
- 该文件中的 `PG*` 变量优先级高于当前进程环境变量

#### 5.2 未传 `--env-file`

默认发现按以下顺序进行：

1. 先在当前工作目录查找 `.env`、`.env.local`
2. 只要当前工作目录命中任意一个默认文件，就只读取当前工作目录中的默认文件集合
3. 如果当前工作目录一个默认文件都没命中，再回退到脚本目录查找
4. 不允许“当前目录命中部分文件，再去脚本目录补另一部分”的混合模式

在单个基准目录中，文件合并顺序固定为：

1. `.env`
2. `.env.local`

后者覆盖前者。

### 6. PostgreSQL Connection Precedence

结合本次目标，连接优先级调整为：

1. 显式参数  
   `--host` / `--port` / `--user` / `--password` / `--database`
2. `--connection-string`
3. 显式 `--env-file`
4. 当前进程环境变量  
   `PGHOST` / `PGPORT` / `PGUSER` / `PGPASSWORD` / `PGDATABASE`
5. 自动发现的默认 env 文件
6. `Port` 的最终缺省值 `5432`

这条规则的语义是：

- 显式传参永远最强
- 显式 `--env-file` 是强意图，应当压过当前 shell 环境
- 自动发现只是默认值来源，不应该悄悄覆盖用户当前会话里已经导出的 `PG*`

### 7. PostgreSQL Context Refactor

为让 `Resolve-PgContext` 保持清晰，建议把当前连接上下文逻辑拆成三个小职责：

- `Resolve-PgDefaultEnvSource`
  负责“当前工作目录优先，否则脚本目录”的默认文件发现，并返回选中的基准目录与文件列表
- `Import-PgEnvFiles`
  负责严格解析一个或多个 env 文件并按顺序合并
- `Resolve-PgContext`
  负责把显式参数、连接串、显式 `--env-file`、当前进程环境变量和自动发现结果按既定优先级合成最终连接上下文

这样业务语义和文件发现细节就能分层测试，不需要再把所有条件堆在一个函数里。

### 8. Error Handling

无论是显式 `--env-file` 还是默认自动发现到的文件，只要出现非空、非注释且不符合 `KEY=VALUE` 的行，都必须直接失败。

推荐错误行为：

- 报错信息中包含文件路径
- 报错信息中尽量包含具体无效行内容，方便定位
- 不因为是自动发现文件就放宽规则

这比“宽松跳过无效行”更适合数据库连接配置场景，因为静默忽略更容易掩盖拼写错误和半配置状态。

## Validation Strategy

验证应拆成四层：

### 1. Shared Config Source Tests

放在 `psutils` 相关测试中，覆盖：

- 严格 dotenv 解析
- 多文件按顺序合并
- 默认发现 helper 的基准目录与命中规则
- 无效行直接失败

### 2. PostgreSQL Context Tests

扩展 [`tests/PostgresToolkit.Core.Tests.ps1`](/Users/mudssky/projects/powershellScripts/tests/PostgresToolkit.Core.Tests.ps1)，至少覆盖：

- 未传 `--env-file` 时当前工作目录优先
- 当前工作目录无默认文件时回退脚本目录
- 当前目录命中任意默认文件后不再去脚本目录补缺
- 显式 `--env-file` 禁用默认发现
- 当前进程环境变量优先于自动发现文件
- 显式 `--env-file` 优先于当前进程环境变量
- 无效 env 行严格失败

### 3. Bundle Resolver Tests

新增 builder 级测试，覆盖：

- 当 PostgreSQL toolkit 调用共享函数时，构建产物中确实包含该函数定义
- 共享函数的递归依赖也会被自动带入
- 缺失定义会导致构建失败
- 同名函数冲突会导致构建失败

### 4. Artifact Regression Tests

构建真实单文件产物后，至少验证：

- `help` 可直接执行
- 至少一个 `--dry-run` 场景可执行
- 产物在不导入 `psutils` 模块的前提下也能工作

## Rollout Plan

建议按以下顺序渐进落地：

1. 把 `psutils` 的 config 相关实现抽到 source-first 目录
2. 让 `psutils/modules/config.psm1` 改为薄封装，并保持既有模块行为不变
3. 在 PostgreSQL toolkit 中接入默认 env 自动发现和新的连接优先级
4. 再把 bundle 过程升级为“手工入口 + AST 自动补共享依赖”

这样即使第 4 步中途遇到 AST 边界问题，前 3 步也已经能单独交付用户价值，不会把功能绑定到 bundler 改造是否一步到位。

## Risks And Trade-Offs

- AST 自动依赖收集的边界需要刻意收紧，否则容易出现“看起来智能、实际不可预测”的构建行为。
- `psutils` 从聚合模块转向 source-first 后，短期内会增加一点目录层次和构建复杂度，但这是为了换取长期可复用性和 bundle 可靠性。
- PostgreSQL toolkit 新增默认 env 自动发现后，部分用户可能第一次注意到当前工作目录下历史遗留的 `.env` / `.env.local` 对连接有影响，因此帮助文档和错误信息需要说清楚优先级。
- 严格失败策略会让错误更早暴露，短期内可能让之前“侥幸可用”的坏配置直接失败，但这是可接受且更安全的取舍。

## Open Questions

当前设计不保留阻塞性 open question。若后续希望把 AST 自动 bundle 扩展到更多脚本，再单独评估：

- 共享源码目录是否需要统一到 `scripts/pwsh/shared/**`
- bundling helper 是否值得抽成仓库级公共工具
- 是否需要为 bundle 规则引入显式元数据，例如“允许被抽取的函数白名单”
