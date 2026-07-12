# httpyac 接口活示例与测试速查

`httpyac` 是用于执行 `.http` / `.rest` 文件的命令行 HTTP 客户端，适合把接口调试请求沉淀成可执行示例、冒烟测试和 CI 回归检查。

## 推荐目录

小项目或个人项目优先用单目录：

```text
http/
  http-client.env.json
  auth.http
  task.http
```

中大型项目再拆开：

```text
requests/
  auth.http
tests/api/
  auth.test.http
```

如果请求本身稳定，优先让 `.http` 同时承担示例和测试。临时调试请求必须打 `manual` 标签，不要进入 CI。

## 环境与密钥方案

推荐三层配置：

1. `http/http-client.env.json`：可提交，只放 `baseUrl`、测试用户名等非敏感默认值。
2. 本机 `.env.local`、shell 环境变量或团队自定义私有 env 文件：本机私有密钥，不提交。
3. CI 环境变量或 `--var`：流水线注入真实 token、账号和密码。

可提交示例：

```json
{
  "$shared": {
    "apiVersion": "v1"
  },
  "$default": {
    "baseUrl": "http://localhost:3000",
    "username": "dev@example.com"
  },
  "staging": {
    "baseUrl": "https://staging-api.example.com",
    "username": "smoke@example.com"
  }
}
```

本机私有值可以放在 `.env.local` 或由 shell/CI 注入，不提交：

```dotenv
API_TEST_PASSWORD=<replace-me>
API_TOKEN=<replace-me>
```

`.gitignore` 建议：

```gitignore
http/*.local.env.json
.env.local
```

执行时选择环境：

```bash
httpyac send "http/**/*.http" --all --env staging --tag smoke --bail
```

CI 注入变量：

```bash
httpyac send "http/**/*.http" --all --env staging --tag test --bail --var password="$API_TEST_PASSWORD"
```

## Token 认证

优先通过登录接口动态获取 token，而不是把固定 token 写进文件。

```http
@baseUrl = http://localhost:3000

###
# @name login
# @tag test
# @tag smoke
POST {{baseUrl}}/api/auth/login
Content-Type: application/json

{
  "username": "{{username}}",
  "password": "{{password}}"
}

?? status == 200
?? body $.data.token exists

###
# @name me
# @tag test
# @tag smoke
# @ref login
GET {{baseUrl}}/api/me
Authorization: Bearer {{login.response.body.$.data.token}}

?? status == 200
?? body $.data.id exists
```

如果项目使用机器 token，可通过环境或 CLI 注入：

```http
GET {{baseUrl}}/api/me
Authorization: Bearer {{apiToken}}
```

```bash
httpyac send http/auth.http --name me --var apiToken="$API_TOKEN"
```

OAuth2 场景可以使用 httpyac 的内置认证：

```http
@oauth2_tokenEndpoint = https://auth.example.com/oauth/token
@oauth2_clientId = my-client
@oauth2_clientSecret = {{clientSecret}}

###
# @name protected
GET {{baseUrl}}/api/protected
Authorization: oauth2 client_credentials
```

## 标签约定

```text
test      自动化测试，可进 CI
smoke     冒烟测试，覆盖主流程
manual    手动调试，CI 不跑
negative  异常场景
async     异步任务或轮询流程
```

常用命令：

```bash
# 跑全部测试请求
httpyac send "http/**/*.http" --all --tag test --bail

# 只跑冒烟
httpyac send "http/**/*.http" --all --tag smoke --bail

# 输出 CI 友好 JSON
httpyac send "http/**/*.http" --all --tag test --json --bail

# 输出 JUnit XML
httpyac send "http/**/*.http" --all --tag test --junit --bail

# 只跑指定请求
httpyac send http/auth.http --name login
```

## 异步任务轮询

```http
@baseUrl = http://localhost:3000
@maxPoll = 20

###
{{
  exports.pollCount = 0;
  exports.finished = false;
}}

###
# @name submitTask
# @tag test
# @tag async
POST {{baseUrl}}/api/tasks
Content-Type: application/json

{
  "type": "report"
}

?? status == 200
?? body $.data.taskId exists

{{response
  const body = JSON.parse(response.body);
  exports.taskId = body.data.taskId;
}}

###
# @name pollTask
# @tag test
# @tag async
# @ref submitTask
# @loop while !finished && pollCount < maxPoll
# @sleep 2000
GET {{baseUrl}}/api/tasks/{{taskId}}/status

?? status == 200

{{response
  const body = JSON.parse(response.body);
  exports.pollCount = pollCount + 1;
  exports.finished = ['SUCCESS', 'FAILED'].includes(body.data.status);

  if (body.data.status === 'FAILED') {
    throw new Error('任务失败');
  }

  if (exports.pollCount >= maxPoll && !exports.finished) {
    throw new Error('轮询超时');
  }
}}

###
# @name taskResult
# @tag test
# @tag async
# @ref pollTask
GET {{baseUrl}}/api/tasks/{{taskId}}/result

?? status == 200
?? body $.data exists
```

## 写作规则

- `.http` 是默认接口活文档：请求、示例数据、断言放在一起。
- 代码是契约来源，先读路由、控制器、schema、DTO、校验逻辑，再写 `.http`。
- 不要把真实 token、密码、Cookie 写入仓库。
- 稳定请求加 `test`，临时请求加 `manual`。
- 复杂业务规则只在 `.http` 示例解释不清时，才补轻量 Markdown 或代码注释。
- 涉及副作用的接口要设计可重复执行的数据，或补清理请求。
