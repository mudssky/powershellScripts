# 完善 API 示例测试编写 skill 结构 - Design

## Architecture and Boundaries

本任务保持 `api-example-test-writer` 为纯文档型 skill，不新增脚本、构建配置或测试依赖。

文件边界：

- `SKILL.md`：保留短入口，负责触发场景、核心工作流、安全边界和 reference 路由。
- `references/httpyac-patterns.md`：继续承载 httpyac 语法、环境配置、认证变量、标签和 CLI 命令。
- 新增或扩展 reference：承载接口注释规范和目录层级策略，避免把长模板塞进 `SKILL.md`。
- 新增或扩展 reference：承载 CLI + VS Code 插件兼容配置方式，以及长行/长参数格式策略。
- `examples/httpyac/*.http`：展示真实可复制风格，每个请求块都有面向人的注释。

## Documentation Contract

`.http` 请求块必须同时满足两类读者：

- 机器：请求、变量、引用、断言、标签能被 httpyac 执行。
- 人：注释能解释接口用途、前置条件、认证要求、业务语义、断言意图和风险边界。

注释规则：

- 所有请求块都写注释。
- 注释解释“为什么有这个请求、读者要注意什么”，不复述 HTTP 方法、URL、字段名等表面语法。
- 手动调试请求也写短注释，说明适用环境、不能进 CI 的原因或敏感风险。
- 初始化脚本块不是接口，但也应说明它在流程里的用途。

## Directory Strategy

目录层级采用渐进规则：

- 优先沿用项目已有 HTTP/API 测试约定。
- 无约定时，小项目使用 `http/` 下平铺文件。
- 中型项目按业务域或模块建子目录，保留共享环境文件在根层。
- 大型项目区分共享配置、认证、模块、跨模块流程、负例、手动请求和私有本机配置。

目录策略不强制某个固定树，而是给出选择信号和参考树。最终结构应根据 API 数量、团队习惯、CI 粒度和跨模块流程复杂度收敛。

## CLI and VS Code Configuration

配置策略需要同时服务两种使用方式：

- 命令行：`httpyac send` 支持 `--env`、`--var`、`--tag`、`--json`、`--junit`、`--bail` 等参数，适合本地自动化和 CI。
- VS Code 插件：工作区 `settings.json` 支持 `httpyac.environmentSelectedOnStart`、`httpyac.environmentPickMany`、`httpyac.environmentVariables`、`httpyac.envDirName` 等设置，适合编辑器内 CodeLens、环境选择和手动调试。
- VS Code REST Client：支持 `rest-client.environmentVariables`，也支持 `$dotenv` 从 `.env` 文件读取变量；env/dotenv 方案对跨插件迁移更友好。

推荐方向：

- 变量命名保持统一，例如 `baseUrl`、`username`、`password`、`token`、`tenantId`。
- env/dotenv 目录作为新项目默认主契约，减少同时维护 `http-client.env.json` 和 `.vscode/settings.json` 业务变量的成本。
- 推荐目录化 env，例如 `http/env/dev.env.example`、`http/env/test.env.example`、`http/env/local.env`；可提交 example 文件，本机真实 env 文件必须忽略。
- `.vscode/settings.json` 默认只配置插件行为：`httpyac.envDirName`、默认环境、是否多选环境、CodeLens 等；不复制 `baseUrl`、`token` 这类业务变量。
- 可提交 env 示例只放非敏感默认值和变量名说明，真实敏感值来自系统环境变量或被忽略的本机私有 env 文件。
- VS Code 插件可通过 `httpyac.envDirName` 指向 dotenv 文件目录；该路径可以是相对路径或绝对路径。
- 当前文档证据只确认插件可指定 dotenv 目录，未确认可指定任意 `http-client.env.json` 文件路径，因此 reference 应避免把“指定 JSON 配置文件路径”写成已确认能力。
- `http-client.env.json` 作为兼容既有项目的方案保留说明，但不作为新项目默认首选。
- reference 同时给 CLI 命令、dotenv 目录和 `.vscode/settings.json` 插件行为样例，让 agent 生成产物时能兼顾两端体验。

## Long Line Formatting

长行策略需要覆盖：

- URL query 参数多：优先把动态值提取成变量，必要时使用请求脚本或请求体表达复杂筛选。
- Header 多或 token 长：公共 header 放默认配置或变量，敏感值通过环境变量引用。
- JSON body 长：使用多行 JSON，字段按业务分组；复杂示例避免压成单行。
- CLI 命令长：用 shell 换行示例展示，并同时给 CI 可复制的一行版本或脚本建议。

`.http` 文件里的换行必须以 httpyac 可执行性为准；reference 应避免推荐未经验证或容易破坏解析的 URL 断行写法。

## Compatibility

- 保持 skill frontmatter `name: api-example-test-writer` 不变。
- 不修改 `ai/skills/skills.config.json`，现有安装入口继续有效。
- 示例中的 URL、账号和任务类型继续使用虚构占位，不引入真实项目配置。

## Trade-offs

- 所有请求块都要求注释会增加编写成本，但能最大化 `.http` 的活文档价值。
- 为避免注释膨胀，规范必须强调“解释业务意图，不复述语法”。
- env-first 对 CLI 和 httpYac VS Code 插件都更友好；REST Client 只保留兼容提示，不作为主设计目标。
- 同时覆盖 CLI 和 httpYac VS Code 会让配置章节更长，因此入口只保留原则，具体样例下沉到 reference。
- 只补文档和示例，不做生成器脚本；这样首版更轻，也避免把项目差异固化到工具里。

## Rollback

回滚时只需还原本任务涉及的 skill 文档和示例文件，不涉及生成产物、配置迁移或运行态数据。
