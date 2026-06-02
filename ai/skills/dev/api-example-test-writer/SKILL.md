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
3. 若没有既有约定，优先创建 `http/`，并按业务域拆分 `.http` 文件，例如 `http/auth.http`、`http/task.http`。
4. 使用 `http-client.env.json` 保存可提交的非敏感默认值，例如 `baseUrl`、测试用户名、租户 ID。
5. 使用私有环境文件、shell 环境变量或 CI secret 注入密码、token、client secret，不把真实凭据写入仓库。
6. 优先通过登录请求动态获取 token，再用 `@ref` 和响应变量复用认证结果。
7. 稳定请求加 `# @tag test`；主流程加 `# @tag smoke`；临时调试请求只加 `# @tag manual`。
8. 为关键响应写断言：状态码、业务 code、关键字段、权限失败、边界错误和异步任务最终状态。
9. 给出执行命令，例如 `httpyac send "http/**/*.http" --all --tag test --bail`。

## 默认目录约定

```text
http/
  http-client.env.json
  auth.http
  task.http
```

中大型项目或已有测试体系可以沿用：

```text
requests/
tests/api/
```

## 配置与认证规则

- 可提交：`http-client.env.json`，只放 `baseUrl`、非敏感账号名、公共租户、超时和开关。
- 不提交：`*.local.env.json`、`.env.local` 或团队约定的私有 env 文件，放密码、token、client secret。
- CI：用 secret 注入，并通过 `--var password="$API_TEST_PASSWORD"` 或对应环境配置传入。
- 优先登录取 token：用 `# @name login` + `# @ref login` + `Authorization: Bearer {{login.response.body.$.data.token}}`。
- 固定 token 只用于机器账号、第三方 OAuth 或无法登录的场景。
- 写入 `.gitignore` 时只忽略私有配置，不要忽略可提交模板。

## 文档策略

默认不要新建长篇 `docs/api/*.md`。优先让 `.http` 成为活文档：请求、示例、断言和命令都能运行。

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

- 需要 httpyac 语法和配置模板时，读取 `references/httpyac-patterns.md`。
- 需要可复制示例时，查看 `examples/httpyac/auth-smoke.http` 和 `examples/httpyac/async-task.http`。

## 边界

- 不凭猜测写接口路径、字段或状态码；仓库能回答的，必须先读代码。
- 不写真实密钥、真实 Cookie、生产 token 或个人账号密码。
- 不让 `manual` 请求进入 CI 命令。
- 不把复杂端到端流程硬塞进 `.http`；需要数据库校验、复杂并发或 mock 外部服务时，建议用代码化测试补充。
