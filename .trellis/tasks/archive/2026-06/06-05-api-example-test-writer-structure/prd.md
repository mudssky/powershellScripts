# 完善 API 示例测试编写 skill 结构

## Goal

完善 `ai/skills/dev/api-example-test-writer` 这个纯文档型 skill，让 agent 为 HTTP/API 编写 `.http` / httpyac 活示例时，不只生成可运行请求，还能沉淀清晰的接口注释，并按项目规模建立可维护的目录层级。

用户价值：

- `.http` 示例同时具备测试价值和活文档价值，读者能理解接口用途、前置条件、请求含义、响应断言和异常场景。
- agent 面对多模块 API 时能按业务域、认证、共享变量、场景流程、负例和私有配置建立目录结构，而不是把所有请求平铺到少数文件。
- skill 入口保持精炼，详细注释模板、目录层级规则和示例按需下沉到 `references/` 或 `examples/`。

## Confirmed Facts

- 用户指出 `ai/skills/dev/api-example-test-writer` 当前“没有接口注释，没有目录层级的概念”。
- 当前 skill 是纯文档型 skill，已有文件：
  - `SKILL.md`
  - `references/httpyac-patterns.md`
  - `examples/httpyac/auth-smoke.http`
  - `examples/httpyac/async-task.http`
  - `agents/openai.yaml`
- `.trellis/spec/infra/agent-skill-dev.md` 规定纯文档 skill 可以只有 `SKILL.md`、`references/`、`examples/`；`SKILL.md` 是必需文件，frontmatter `name` 必须与目录名一致。
- 当前 `SKILL.md` 已要求先读代码确认契约、沿用既有 HTTP 目录、默认创建 `http/`，并按业务域拆分 `.http` 文件。
- 当前 `SKILL.md` 已有“默认目录约定”，但只给出 `http/http-client.env.json`、`auth.http`、`task.http` 这种平铺示例，缺少小型/中型/大型项目的层级选择、共享文件、模块目录、场景目录、负例目录或 README/index 规则。
- 当前 `SKILL.md` 的“文档策略”只说明 `.http` 难以表达时才补最小 Markdown 或代码注释，没有明确要求 `.http` 请求块内写接口注释。
- 当前两个示例 `.http` 文件包含 `@name`、`@tag`、`@ref` 等执行元数据和断言，但缺少接口用途、前置条件、业务语义、断言意图、失败场景和维护提示。
- 当前 `references/httpyac-patterns.md` 主要覆盖环境文件、登录取 token、CLI 命令和标签，没有覆盖接口注释模板或目录层级策略。
- 仓库已有相近 skill 开发经验：文档型 skill 应保持 `SKILL.md` 精炼，把细节拆入 `references/` 和 `examples/`。
- 已通过 Context7 查询当前 httpYac 文档：
  - VS Code 插件文档包含 `httpyac.environmentSelectedOnStart`、`httpyac.environmentPickMany`、`httpyac.environmentVariables`、`httpyac.envDirName` 等配置。
  - VS Code 插件文档明确 `httpyac.envDirName` 是相对或绝对路径的 dotenv 文件目录；当前检索结果未显示插件支持任意指定 `http-client.env.json` 文件路径的通用配置项。
  - CLI 文档包含 `httpyac send`、`--env`、`--var`、`--tag`、`--json`、`--junit`、`--bail` 等执行参数，并说明变量可来自 `.env`、`http-client.env.json`、`.httpyac.js` 和 CLI inline variables。
- 已通过 Context7 查询 VS Code REST Client 文档：REST Client 支持 `rest-client.environmentVariables`，也支持 `$dotenv` 从与 `.http` 文件同目录的 `.env` 文件读取变量。
- 用户确认目录层级先不新增实际分层 `.http` 示例目录，优先补 reference 规则。
- 用户新增要求：需要把 VS Code 插件相关配置考虑进去，配置方式要同时适配命令行和 VS Code。
- 用户新增要求：需要说明参数太多、一行太长时的处理方式。
- 用户倾向使用 env/dotenv 方式作为主配置，减少同时维护 `http-client.env.json` 和 `.vscode/settings.json` 两套变量的麻烦，并考虑 REST Client 的兼容性。
- 用户确认 env 文件采用目录化方案；实际主要面向 httpYac CLI 和 httpYac VS Code 插件，不以 REST Client 为主要目标。

## Requirements

- skill 必须明确要求为所有请求块补充面向人的接口注释，说明接口用途、适用场景、认证要求、关键参数、预期响应和断言意图。
- 注释应服务可维护性，不复述 HTTP 方法、URL 或 JSON 字段这种一眼可见的信息。
- 对手动调试请求也要有注释，但可以更短，重点说明为什么保留、适用环境和风险边界。
- `.http` 示例应展示推荐注释风格，覆盖登录冒烟和异步任务两类代表性流程。
- skill 必须建立目录层级决策规则：优先沿用项目已有结构；无既有约定时，根据 API 数量、业务域数量、共享配置复杂度和 CI 场景选择平铺或分层结构。
- 目录层级规则应覆盖至少三种规模：
  - 小型项目：少量 `.http` 文件平铺在 `http/`。
  - 中型项目：按业务域或模块拆分目录。
  - 大型项目：区分共享环境、认证、模块、跨模块流程、负例、手动请求和私有配置。
- skill 必须说明共享环境文件、私有本机配置、认证流程、可复用变量、跨接口场景和负例测试分别放在哪里。
- skill 必须说明 httpYac CLI 与 VS Code 插件的兼容配置方式，推荐 env/dotenv-first 的变量契约同时服务命令行执行和编辑器交互。
- 配置规则必须覆盖：
  - `.env` / env 目录作为默认变量来源，优先统一 CLI、httpYac VS Code 插件和 REST Client 的变量名。
  - 默认推荐目录化 env，例如 `http/env/dev.env.example`、`http/env/test.env.example`、`http/env/local.env`，并通过 `httpyac.envDirName` 指向该目录。
  - `.vscode/settings.json` 中只放 httpYac 插件工作区体验设置，例如默认环境、是否多选环境、`httpyac.envDirName`、CodeLens 等；默认不复制业务变量。
  - `httpyac.envDirName` 指向的 dotenv 文件目录，用于 VS Code 插件读取环境变量文件。
  - `http-client.env.json` 作为兼容或既有项目方案，不作为新项目默认首选，除非仓库已有此约定。
  - 系统环境变量或私有本机文件承载敏感值。
  - CLI 的 `--env`、`--var`、`--tag`、`--bail`、`--json` 等 CI/本地执行参数。
  - VS Code 中环境选择、CodeLens、默认环境、多环境选择等交互需求。
- skill 必须说明长行处理策略，覆盖长 query 参数、长 header、长 JSON body、长 CLI 命令和复杂变量注入。
- skill 应继续默认把 `.http` 作为活文档，不默认创建长篇 `docs/api/*.md`。
- skill 入口应保持短，详细注释模板、目录层级样例和 httpyac 模式放入 `references/` 或 `examples/`。
- 不新增脚本；本次仍按纯文档型 skill 处理。

## Acceptance Criteria

- [x] `SKILL.md` 明确提到接口注释要求，并能路由到详细参考文档或示例。
- [x] `SKILL.md` 明确提到目录层级选择规则，不只给平铺目录示例。
- [x] `references/` 中存在接口注释模板或规范，能指导 agent 写出有价值且不过度冗长的 `.http` 注释。
- [x] `references/` 中存在目录层级策略，覆盖小型、中型、大型项目以及既有约定优先的规则。
- [x] `references/` 中存在 CLI + VS Code 插件兼容配置策略，说明可提交配置、私有配置、系统环境变量和 CI 参数的分工。
- [x] 配置策略采用 env/dotenv-first：避免默认同时维护 `http-client.env.json` 和 `.vscode/settings.json` 两套业务变量。
- [x] env 配置策略采用目录化方案，并说明 `.gitignore`、示例 env 文件和本机私有 env 文件的边界。
- [x] `references/` 中存在长行处理策略，说明请求参数、请求体、header 和 CLI 命令过长时的推荐拆分方式。
- [x] `examples/httpyac/auth-smoke.http` 展示带接口注释的认证冒烟流程。
- [x] `examples/httpyac/async-task.http` 展示带接口注释的异步任务流程，并说明轮询状态和超时断言意图。
- [x] 两个示例中的每个请求块都有面向人的注释；脚本初始化块也说明用途，避免出现无语义空块。
- [x] 文档不包含真实密钥、生产 token、个人账号密码或项目私有配置。
- [x] 文档型改动不强制执行根目录 `pnpm qa`；如最终只修改 Markdown 和 `.http` 示例，说明未执行 `qa` 的原因。

## Out of Scope

- 不实现自动扫描接口并生成 `.http` 的脚本。
- 不引入新的测试框架或依赖。
- 不强制所有项目使用同一套目录树；已有项目约定优先。
- 不把 `.http` 难以承载的完整接口手册搬进 skill 入口。

## Open Questions

- 无。

## Notes

- 初步判断为中等复杂度文档型 skill：不新增脚本，但会更新入口、reference 和示例。进入实现前补 `design.md` 和 `implement.md`，明确文件拆分和验证命令。
- 本次最终只修改 Markdown、Trellis 任务文档和 `.http` 示例，未执行根目录 `pnpm qa`。
