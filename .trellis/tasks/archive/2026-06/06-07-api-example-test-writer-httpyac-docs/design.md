# 完善 api-example-test-writer httpyac 文档与示例 - Design

## Architecture and Boundaries

本任务保持 `api-example-test-writer` 为纯文档型 skill，不新增脚本、构建配置、测试依赖或自动生成能力。

文件边界：

- `SKILL.md`：保留短入口，更新默认 env 命名、认证复用原则和资源路由。
- `references/httpyac-patterns.md`：承载 httpyac env/dotenv、登录 token 复用、标签与 CLI 命令细节。
- `references/directory-structure.md`：承载小/中/大型目录树、VS Code 插件配置、长行处理和 `.gitignore` 策略。
- `examples/httpyac/*.http`：保持可复制请求示例，去掉与 env 约定冲突的硬编码变量，补充认证复用。
- `examples/httpyac/env/*`：新增可提交 env 模板示例，展示 `.env.example` 与 `.env.test` 的分工；不提交 `.env.local` 真实文件。
- `~/.agents/skills/api-example-test-writer`：实现完成并验证后同步安装态副本，保证当前 agent 后续使用到最新 skill。

## Env Contract

默认新项目使用目录化 dotenv，目录为 `http/env/`：

- `.env.example`：可提交模板，描述变量名、非敏感默认值和占位符。
- `.env.test`：可提交测试环境默认值，只放非敏感测试 URL、账号名、租户、超时、开关等；密码和 token 由 CI secret 或本机私有 env 注入。
- `.env.local`：本机私有值，必须忽略，不提交真实密码、token、client secret。

旧的 `dev.env.example`、`test.env.example`、`local.env` 不再作为新项目默认命名，只可作为既有项目兼容提示出现。

## Authentication Flow

推荐认证流程：

- 登录请求使用 `# @name login`，从 env 读取 `baseUrl`、`username`、`password`、`tenantId` 等变量。
- 登录响应只断言 token 存在，不把 token 格式或签名实现写死。
- 受保护请求使用 `# @ref login` 与 `Authorization: Bearer {{login.response.body.$.data.token}}` 复用登录结果。
- 跨文件复用时，优先把认证请求放入 `shared/auth.http` 或 `auth.http`，业务文件用 `# @import` 加 `# @ref login` 表达依赖。
- 固定 token 只用于无法登录、第三方 OAuth、机器账号或排查场景，并且必须来自私有 env 或 CI secret。

## CLI and VS Code Compatibility

命令行与编辑器共用变量命名，避免 `.vscode/settings.json` 和 env 文件各维护一套业务变量：

- CLI 使用 `httpyac send "http/**/*.http" --all --env test --tag test --bail` 选择环境。
- CI 可使用 `--var password="$API_TEST_PASSWORD"` 或对应 CI secret 注入敏感值。
- VS Code 插件使用 `httpyac.envDirName` 指向 `http/env`，配合 `httpyac.environmentSelectedOnStart`、`httpyac.environmentPickMany`、CodeLens 等行为配置。
- `http-client.env.json` 仅作为已有项目兼容方案，不作为新项目默认首选。

## Documentation Shape

保持 progressive disclosure：

- `SKILL.md` 只写核心流程、边界和 reference 路由。
- 具体 env 文件内容、认证案例、CLI 命令和 `.gitignore` 示例放到 reference 或 examples。
- 示例中的注释继续遵循 `references/interface-comments.md`：解释业务意图、前置条件和断言理由，不复述 HTTP 语法。

## Compatibility and Rollback

- 不修改 skill frontmatter `name`，不修改 `skills.config.json`。
- 不提交 `.env.local`，只提交模板和测试默认值示例。
- 回滚只需还原本任务涉及的 skill 文档、示例和安装态同步；无运行态数据迁移。

## Trade-offs

- 选择 `.env.example/.env.test/.env.local` 能更贴近常见 dotenv 约定，但会替换上一轮文档中的目录化命名，需要全局搜索确保不遗留旧默认。
- 把 `.env.test` 设为可提交要求团队避免把真实测试密码写进去；因此文档必须反复强调密码和 token 仍走 secret 或 `.env.local`。
- 不新增脚本能力能快速修正 skill 的使用质量，但自动从代码生成 `.http` 仍需后续单独规划。
