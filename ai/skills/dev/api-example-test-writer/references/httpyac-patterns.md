# httpyac 模式参考

## 环境文件

默认使用目录化 env/dotenv，便于命令行和 VS Code httpYac 插件共用变量名：

```text
http/
  env/
    .env.example
    .env.test
    .env.local
```

可提交的 `http/env/.env.example`：

```dotenv
baseUrl=http://localhost:3000
username=api-test@example.com
tenantId=demo
requestTimeout=30000
```

可提交的 `http/env/.env.test`，只放非敏感测试默认值：

```dotenv
baseUrl=http://localhost:3000
username=api-test@example.com
tenantId=test
requestTimeout=30000
```

私有值示例 `http/env/.env.local`，不提交：

```dotenv
password=<replace-me>
token=<replace-me>
```

建议 `.gitignore`：

```gitignore
http/env/.env.local
http/env/.env.*.local
http/env/*.local.env
http/env/*.secret.env
.env.local
*.env.local
```

已有项目使用 `http-client.env.json` 时可以沿用；新项目默认优先使用 env/dotenv 目录，避免同时维护 JSON 和 VS Code settings 两套业务变量。

`.env.test` 可以提交，但不得写真实密码、真实 token、client secret 或个人账号。CI 中的敏感值用 secret 注入，例如 `--var password="$API_TEST_PASSWORD"`；本机调试时放在被忽略的 `.env.local`。

## 登录取 token

```http
###
# 说明：验证测试账号能登录，并把访问令牌固化到 authToken 供后续请求复用。
# 前置：baseUrl/username/tenantId 来自 .env.test，password 来自 CI secret 或 .env.local。
# 断言：只检查 token 存在，避免把 token 格式或签名实现绑定进示例。
# @name login
# @tag test
POST {{baseUrl}}/api/auth/login
Content-Type: application/json

{
  "username": "{{username}}",
  "password": "{{password}}",
  "tenantId": "{{tenantId}}"
}

?? status == 200
?? body $.data.token exists

{{response
  const body = JSON.parse(response.body);
  exports.authToken = body.data.token;
}}

###
# 说明：读取当前用户信息，证明 login 固化的 authToken 能访问受保护接口。
# 前置：依赖 login 请求成功；失败时先排查测试账号、认证中间件和 token 提取路径。
# 断言：只检查稳定身份字段，避免把展示型字段写成测试硬约束。
# @name me
# @tag test
# @ref login
GET {{baseUrl}}/api/me
Authorization: Bearer {{authToken}}

?? status == 200
?? body $.data.id exists
```

跨文件复用时，把认证请求放在 `http/shared/auth.http` 或 `http/auth.http`，业务文件显式引入：

```http
###
# 说明：创建任务前先引入共享登录请求，复用 login 写入的 authToken。
# 前置：auth.http 中存在 # @name login，且当前环境变量能登录测试账号。
# @import ../shared/auth.http
# @ref login
POST {{baseUrl}}/api/tasks
Authorization: Bearer {{authToken}}
Content-Type: application/json

{
  "type": "report"
}

?? status == 200
```

只有机器账号、第三方 OAuth、无法自动登录或一次性排查时，才从私有 env 或 CI secret 读取固定 token，例如 `Authorization: Bearer {{token}}`。不要把 token 直接写进 `.http` 或可提交 env 文件。

## CLI 命令

```bash
httpyac send "http/**/*.http" --all --env test --tag test --bail
httpyac send "http/**/*.http" --all --env test --tag smoke --bail
httpyac send "http/**/*.http" --all --env test --tag test --json --bail
httpyac send "http/**/*.http" --all --env test --tag test --junit --bail
httpyac send "http/**/*.http" --all --env test --tag test --bail --var password="$API_TEST_PASSWORD"
```

参数较多时，在文档里使用 shell 换行：

```bash
httpyac send "http/**/*.http" \
  --all \
  --env test \
  --tag test \
  --json \
  --bail \
  --var password="$API_TEST_PASSWORD"
```

## 标签

- `test`：自动化测试。
- `smoke`：主流程冒烟。
- `manual`：手动调试，CI 不跑。
- `negative`：异常场景。
- `async`：异步任务或轮询流程。
