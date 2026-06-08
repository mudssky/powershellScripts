---
name: api-example-test-writer
description: 在项目中为 HTTP/API 接口编写可执行 .http 活示例和 httpyac 测试。Use when 用户要求补接口示例、接口测试、接口冒烟、httpyac 文件、baseUrl/token 认证配置、把接口文档改成可执行示例，或同步代码接口契约与 .http 请求。
---

# API 示例测试编写

## 使用时机

用于把接口契约沉淀为可运行的 `.http` 文件。默认产物是可执行示例和测试，不默认创建长篇接口文档。

## 工作流程

1. 先读项目代码确认契约：路由、控制器、handler、schema、DTO、验证逻辑、认证中间件、错误处理和现有测试。
2. 查找项目已有 HTTP 目录、API 文档、OpenAPI、Postman、Bruno、REST Client 或 httpyac 文件，沿用现有结构。
3. 若没有既有约定，优先创建 `http/`，并按项目规模选择平铺、业务域目录或流程目录。
4. 默认采用目录化 env/dotenv 配置，例如 `http/env/.env.example`、`http/env/.env.test`、`http/env/.env.local`。
5. 让命令行和 VS Code 共用变量命名；`.vscode/settings.json` 默认只放 `httpyac.envDirName`、默认环境、CodeLens 等插件行为配置。
6. 使用私有环境文件、shell 环境变量或 CI secret 注入密码、token、client secret，不把真实凭据写入仓库。
7. 每个请求块都写面向人的接口注释；注释说明用途、前置条件、认证、关键业务含义和断言意图，不复述 HTTP 语法。
8. 优先通过登录请求动态获取 token，再用 `@ref` 和响应变量复用认证结果。
9. 稳定请求加 `# @tag test`；主流程加 `# @tag smoke`；临时调试请求只加 `# @tag manual`。
10. 为关键响应写断言：状态码、业务 code、关键字段、权限失败、边界错误和异步任务最终状态。
11. 给出执行命令，例如 `httpyac send "http/**/*.http" --all --tag test --bail`。

## 默认目录约定

```text
http/
  env/
    .env.example
    .env.test
    .env.local
  auth.http
  tasks.http
```

中大型项目按业务域、流程或测试类型分层。已有测试体系可以沿用：

```text
requests/
tests/api/
```

## 配置与认证规则

- 默认可提交：`.env.example` 和不含敏感值的 `.env.test`，只放 `baseUrl`、非敏感账号名、公共租户、超时和开关。
- 默认不提交：`.env.local`、`*.local.env`、`*.secret.env` 或团队约定的私有 env 文件，放密码、token、client secret。
- CI：用 secret 注入，并通过 `--var password="$API_TEST_PASSWORD"` 或对应环境配置传入。
- VS Code：httpYac 插件用 `httpyac.envDirName` 指向 env 目录；`settings.json` 默认不复制业务变量。
- 兼容：已有项目使用 `http-client.env.json` 时沿用，不把它作为新项目默认首选。
- 优先登录取 token：用 `# @name login` + 响应脚本写入 `exports.authToken`，后续请求用 `# @ref login` + `Authorization: Bearer {{authToken}}`。
- 固定 token 只用于机器账号、第三方 OAuth 或无法登录的场景。
- 写入 `.gitignore` 时只忽略私有配置，不要忽略可提交模板。

## 文档策略

默认不要新建长篇 `docs/api/*.md`。优先让 `.http` 成为活文档：请求、示例、断言和命令都能运行。

所有请求块都要有接口注释。注释写给维护者看，解释业务意图、前置条件、断言理由和风险边界；不要把方法、URL、字段名翻译一遍。

只有遇到这些 `.http` 难以表达的内容时，才补最小 Markdown 或代码注释：

- 权限模型
- 错误码规范
- 分页、筛选、排序统一约定
- 幂等性与重试规则
- 异步任务状态流转
- Webhook 签名验证
- 文件上传限制
- 兼容性和迁移说明
- 复杂字段业务含义

## 资源

- 需要接口注释模板和好/坏示例时，读取 `references/interface-comments.md`。
- 需要目录层级、目录化 env、VS Code 插件配置和长行处理策略时，读取 `references/directory-structure.md`。
- 需要 httpyac 语法、认证复用、标签和 CLI 命令时，读取 `references/httpyac-patterns.md`。
- 需要可复制请求示例时，查看 `examples/httpyac/auth-smoke.http` 和 `examples/httpyac/async-task.http`。
- 需要可复制 env 模板时，查看 `examples/httpyac/env/.env.example` 和 `examples/httpyac/env/.env.test`。

## 边界

- 不凭猜测写接口路径、字段或状态码；仓库能回答的，必须先读代码。
- 不写真实密钥、真实 Cookie、生产 token 或个人账号密码。
- 不让 `manual` 请求进入 CI 命令。
- 不把复杂端到端流程硬塞进 `.http`；需要数据库校验、复杂并发或 mock 外部服务时，建议用代码化测试补充。
