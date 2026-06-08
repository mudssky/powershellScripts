# 完善 api-example-test-writer httpyac 文档与示例

## Goal

完善 `ai/skills/dev/api-example-test-writer` 中 httpyac 相关文档和示例，使 agent 在生成可执行 `.http` 活示例时，默认采用 `.env.example`、`.env.test`、`.env.local` 这类更常见的 dotenv 命名，并提供“登录接口获取 token 后给其他接口复用”的完整案例。

用户价值：

- 新项目可以直接复制 env 模板、认证流程和执行命令，不需要再猜 `.env.test`、`.env.local`、`.gitignore`、CI secret 的边界。
- agent 生成 `.http` 时能优先写登录取 token 的稳定流程，而不是把固定 token 写死到接口请求里。
- skill 入口继续保持精简，细节下沉到 `references/` 和 `examples/`，便于按需加载。

## Confirmed Facts

- 用户指出 `references/httpyac-patterns.md` 当前 env 命名应改为 `.env.test` 和 `.env.local`，并缺少 `.env.example` 示例。
- 用户指出当前还缺少“调用登录接口获取 token 并固化给其他接口使用”的常见案例，同时希望顺手审视 `ai/skills/dev/api-example-test-writer` 还有哪些优化点。
- 用户确认本次“优化点”限制在文档、示例、env 模板和必要的安装态同步，不新增脚本能力。
- 当前目标 skill 是纯文档型 skill，已有文件：
  - `SKILL.md`
  - `references/directory-structure.md`
  - `references/httpyac-patterns.md`
  - `references/interface-comments.md`
  - `examples/httpyac/auth-smoke.http`
  - `examples/httpyac/async-task.http`
  - `agents/openai.yaml`
- 当前 `SKILL.md` 与两个 reference 仍把默认目录化 env 写成 `http/env/dev.env.example`、`http/env/test.env.example`、`http/env/local.env`。
- 当前示例 `.http` 文件在文件头仍直接写 `@baseUrl = http://localhost:3000`，没有展示从 `.env.example` / `.env.test` / `.env.local` 读取变量的完整组合。
- 当前 `examples/httpyac/auth-smoke.http` 已展示 `# @name login`、`# @ref login` 与 `Authorization: Bearer {{login.response.body.$.data.token}}`，但它还不是一个配套 env 模板、私有密码、CI secret、后续接口复用边界都完整说明的案例。
- 当前 `examples/httpyac/async-task.http` 没有复用登录流程，异步任务示例默认无认证；如果真实项目的异步任务通常受保护，这个示例可以更好地展示 `@ref login` 或 `@import` 的认证复用方式。
- 当前 `references/directory-structure.md` 已覆盖小型/中型/大型项目目录层级、VS Code `httpyac.envDirName`、CLI 命令和长行处理，但命名体系仍是旧的 `dev.env.example/test.env.example/local.env`。
- 当前 `references/interface-comments.md` 已覆盖接口注释风格，不是本次主要问题。
- 已通过 Context7 查询当前 httpYac CLI 文档：
  - `httpyac send` 支持 `--env`、`--var`、`--tag`、`--json`、`--junit`、`--bail`、`--name`、`--line`、`--parallel` 等参数。
  - 官方示例仍包含 `http-client.env.json`，但 CLI 也支持命令行环境选择与变量注入，当前 skill 已把 JSON 作为兼容方案而非新项目默认方案。
- 已通过 Context7 查询当前 VS Code httpYac 插件文档：
  - 插件支持 `httpyac.environmentSelectedOnStart`、`httpyac.environmentPickMany`、`httpyac.environmentVariables`、`httpyac.envDirName`。
  - `httpyac.envDirName` 是相对或绝对 dotenv 文件目录，适合让编辑器读取与 CLI 相同的 env 文件目录。
- 仓库规范 `.trellis/spec/infra/agent-skill-dev.md` 确认：纯文档 skill 可以只有 `SKILL.md`、`references/`、`examples/`；`SKILL.md` 是必需文件，frontmatter `name` 必须与目录名一致。
- `ai/skills/skills.config.json` 已将 `api-example-test-writer` 配置为 global 安装的本地 skill 来源；当前 `~/.agents/skills/api-example-test-writer` 也存在已安装副本。

## Requirements

- 默认 env 命名改为：
  - 可提交模板：`http/env/.env.example`
  - 可提交测试环境变量：`http/env/.env.test`，仅放非敏感测试默认值或 CI 可覆盖变量名
  - 本机私有变量：`http/env/.env.local`，必须被 `.gitignore` 忽略
- `SKILL.md`、`references/httpyac-patterns.md`、`references/directory-structure.md` 的 env 命名必须一致，避免入口和详细参考互相打架。
- reference 必须给出 `.env.example`、`.env.test`、`.env.local` 的示例内容，并明确哪些可以提交、哪些禁止提交真实值。
- `.gitignore` 示例必须覆盖 `http/env/.env.local`、私有 local/secret 变体，并避免忽略可提交模板。
- httpyac 模式参考必须包含一个常见认证流程：
  - 登录请求读取 `username/password/tenantId/baseUrl` 等变量。
  - 登录响应提取 token。
  - 受保护接口通过 `@ref login` 复用 token。
  - 如果需要跨文件复用，说明使用 `@import` 引入认证请求或把认证请求放到 `shared/auth.http`。
- 示例文件应避免在文件头硬编码 `@baseUrl`，改为从 env 文件读取，或明确只作为覆盖默认值的临时写法。
- CLI 命令示例应覆盖本地、CI、标签过滤、JSON/JUnit 输出和 secret 注入，例如 `--env test` 与 `--var password="$API_TEST_PASSWORD"`。
- VS Code 配置示例应继续只放插件行为配置，例如 `httpyac.envDirName`、默认环境、多环境选择和 CodeLens，不复制业务变量。
- “除此之外的优化点”应先按最小可交付范围处理：修正命名一致性、补 env 模板、补认证复用案例、修正示例与入口导航；不默认新增生成器脚本或自动扫描能力。
- 不引入真实密钥、真实 Cookie、生产 token 或个人账号密码。
- 不改动 skill frontmatter `name`。
- 本次完成后需要同步安装态 skill，使 `~/.agents/skills/api-example-test-writer` 与仓库开发态保持一致；若安装工具不可用，应至少说明未同步原因和手工同步命令。

## Acceptance Criteria

- [x] `SKILL.md` 中默认 env 目录和配置规则已改为 `.env.example`、`.env.test`、`.env.local` 体系。
- [x] `references/httpyac-patterns.md` 使用 `.env.example`、`.env.test`、`.env.local` 作为主要示例，并包含 `.gitignore` 建议。
- [x] `references/directory-structure.md` 的小/中/大型目录树、env/dotenv 配置、VS Code 配置和 CLI 命令均与新命名一致。
- [x] `examples/httpyac/` 下存在可复制的 env 模板示例，至少覆盖 `.env.example` 与 `.env.test` 的可提交内容。
- [x] 示例或 reference 展示登录接口获取 token 后复用给受保护接口的完整流程，并说明固定 token 只用于无法登录或第三方 OAuth 等特殊场景。
- [x] `auth-smoke.http` 与 `async-task.http` 的变量来源、认证复用和注释不与新 env 约定冲突。
- [x] 文档继续保持 skill progressive disclosure：入口短，细节在 `references/` / `examples/`。
- [x] 文档不包含真实凭据或生产配置。
- [x] 如最终只修改 Markdown 和 `.http` / `.env.example` 示例，按项目规则说明未执行根目录 `pnpm qa` 的原因。

## Notes

- 本任务是中等复杂度文档型 skill 调整。进入实现前应补 `design.md` 和 `implement.md`，明确文件边界、验证命令和是否同步安装态 skill。
- 当前仍处于 planning；用户同意创建 Trellis task 不等于同意开始实现。
- 已同步安装态 skill 到 `~/.agents/skills/api-example-test-writer`。
- 本次最终只修改 Markdown、`.http` 和可提交 env 示例；未执行根目录 `pnpm qa`。

## Out of Scope

- 不新增自动扫描接口并生成 `.http` 的脚本。
- 不引入新测试框架或依赖。
- 不把 `http-client.env.json` 重新设为新项目默认首选；已有项目使用时仍保留兼容提示。
- 不把完整接口手册搬进 `SKILL.md`。

## Open Questions

- 无。
