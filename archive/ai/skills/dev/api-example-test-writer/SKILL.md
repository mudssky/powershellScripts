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
5. 抽取变量前先判断价值：只把密码、token、client secret、base URL、账号/租户等机器差异值，或跨多个请求复用的稳定值放进 env；一次性查询参数、普通筛选条件和只出现一次的业务值直接写在请求里。
6. 让命令行和 VS Code 共用变量命名；提供或修改 VS Code/httpYac 配置、处理变量未找到或多根工作区问题时，先读 `references/directory-structure.md` 的 VS Code 配置规则。
7. 使用私有环境文件、shell 环境变量或 CI secret 注入密码、token、client secret，不把真实凭据写入仓库。
8. 每个请求块都写面向人的接口注释；注释说明用途、前置条件、认证、关键业务含义和断言意图，不复述 HTTP 语法。
9. 优先通过登录请求动态获取 token，再用 `@ref` 和响应变量复用认证结果。
10. 稳定请求加 `# @tag test`；主流程加 `# @tag smoke`；临时调试请求只加 `# @tag manual`。
11. 断言默认保持轻量，优先让发送请求的人能看到原始响应内容；复杂业务校验只在关键自动化场景追加，避免把活示例变成只输出测试结果的黑盒。
12. 日期、日期时间和时间戳参数优先使用可读表达式；接口要求时间戳时，可以用 `Date.parse('2024-04-01T00:00:00+08:00')` 这类写法生成数值。
13. 给出执行命令，例如 `httpyac send "http/**/*.http" --all --tag test --bail`。

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
- 不为只出现一次的查询参数、分页值、排序字段、普通筛选条件或示例业务字段创建 env 变量；这些值留在 URL、query 或 JSON body 中更便于直接阅读。
- CI：用 secret 注入，并通过 `--var password="$API_TEST_PASSWORD"` 或对应环境配置传入。
- VS Code：httpYac 插件用 `httpyac.envDirName` 指向 env 目录；优先写项目级 httpYac 配置或工作区配置，`settings.json` 不复制业务变量。
- 兼容：已有项目使用 `http-client.env.json` 时沿用，不把它作为新项目默认首选。
- 优先登录取 token：用 `# @name login` + 响应脚本写入 `exports.authToken`，后续请求用 `# @ref login` + `Authorization: Bearer {{authToken}}`。
- 固定 token 只用于机器账号、第三方 OAuth 或无法登录的场景。
- 写入 `.gitignore` 时只忽略私有配置，不要忽略可提交模板。

## 请求参数与断言策略

- URL query 和 JSON body 优先保留业务语义：`type=expense&state=paid&start=0&count=10` 这类一次性示例参数直接写在请求中，除非它们会跨多个请求复用或代表环境差异。
- 日期字符串优先写成人可读形式，例如 `2024-04-01 00:00:00`、`2024-04-01T00:00:00+08:00`。如果接口只接受毫秒时间戳，使用预请求脚本或懒变量从可读字符串转换，不直接写裸数字。
- 自动断言优先覆盖 `status`、稳定业务 code 和最关键字段存在性。响应脚本中的深度校验应只用于关键自动化用例；手动排查请求应保留响应输出优先，不为了测试完整性牺牲可读性。
- 需要更具体的 httpyac 写法时，读取 `references/httpyac-patterns.md`。

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
- 需要目录层级、目录化 env、VS Code 插件配置、变量未找到排查和长行处理策略时，读取 `references/directory-structure.md`。
- 需要 httpyac 语法、认证复用、变量抽取边界、日期时间写法、响应可见性、标签和 CLI 命令时，读取 `references/httpyac-patterns.md`。
- 需要可复制请求示例时，查看 `examples/httpyac/auth-smoke.http` 和 `examples/httpyac/async-task.http`。
- 需要可复制 env 模板时，查看 `examples/httpyac/env/.env.example` 和 `examples/httpyac/env/.env.test`。

## 边界

- 不凭猜测写接口路径、字段或状态码；仓库能回答的，必须先读代码。
- 不写真实密钥、真实 Cookie、生产 token 或个人账号密码。
- 不让 `manual` 请求进入 CI 命令。
- 不把复杂端到端流程硬塞进 `.http`；需要数据库校验、复杂并发或 mock 外部服务时，建议用代码化测试补充。
