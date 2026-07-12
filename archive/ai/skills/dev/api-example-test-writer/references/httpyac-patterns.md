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

### 变量抽取边界

只在这些场景抽成 env 变量：

- 密码、token、client secret、api key、Cookie 等敏感值。
- `baseUrl`、租户、环境名、测试账号等机器或环境差异值。
- 同一个文件或多个文件反复出现、且需要统一切换的稳定值。

不要把这些值默认抽成 env：

- 只出现一次的 query 参数，例如 `type=expense`、`state=paid`、`orderBy=updateTime`。
- 分页和排序示例值，例如 `start=0`、`count=10`、`orderByType=desc`。
- 用来说明接口能力的普通筛选条件或 JSON 字段。
- 临时排查时才会变化的业务值；这类值直接改请求更直观。

错误倾向：

```http
GET {{baseUrl}}/api/docs?type={{docType}}&state={{docState}}&start={{start}}&count={{count}}
```

更推荐：

```http
GET {{baseUrl}}/api/docs?type=expense&state=paid&start=0&count=10
```

理由：一次性参数留在 URL 中，维护者打开文件就能看懂请求语义；env 只承担环境差异和复用，不承担“把请求藏起来”的职责。

## 日期时间与时间戳

日期、日期时间和时间戳都优先保留人类可读来源。接口接受字符串时，直接写清楚：

```http
GET {{baseUrl}}/api/docs?startDate=2024-04-01%2000:00:00&endDate=2024-04-30%2023:59:59
```

接口要求毫秒时间戳时，用可读字符串转换，不直接写裸数字：

```http
@startDateMs := {{Date.parse('2024-04-01T00:00:00+08:00')}}
@endDateMs := {{Date.parse('2024-04-30T23:59:59+08:00')}}

###
# 说明：按更新时间查询 2024 年 4 月已支付费用单据，时间戳由可读日期生成。
# 断言：这里只确认接口可用和列表结构，具体业务失败信息优先从原始响应查看。
# @name paid-expense-docs
# @tag test
GET {{baseUrl}}/api/openapi/v1.1/docs/getApplyList?accessToken={{authToken}}&type=expense&state=paid&start=0&count=10&orderBy=updateTime&orderByType=desc&startDate={{startDateMs}}&endDate={{endDateMs}}

?? status == 200
?? body $.items exists
```

如果接口要求秒级时间戳，明确转换意图：

```http
@startDateSeconds := {{Math.floor(Date.parse('2024-04-01T00:00:00+08:00') / 1000)}}
```

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

## 响应可见性与断言取舍

`.http` 文件首先是活示例，其次才是自动化测试。默认让发送请求的人能直接看到原始响应 body；断言只覆盖最稳定、最能说明契约的部分。

优先使用轻量断言：

```http
###
# 说明：读取已支付费用单据列表，便于人工查看接口真实响应结构。
# 前置：authToken 来自登录请求或私有环境；查询参数是本示例的一次性业务条件。
# 断言：只检查 HTTP 成功和列表字段存在，业务错误详情直接看响应 body。
# @name paid-expense-docs
# @tag test
GET {{baseUrl}}/api/openapi/v1.1/docs/getApplyList?accessToken={{authToken}}&type=expense&state=paid&start=0&count=10&orderBy=updateTime&orderByType=desc&startDate=2024-04-01%2000:00:00&endDate=2024-04-30%2023:59:59

?? status == 200
?? body $.items exists
```

只有关键自动化用例才追加响应脚本，把业务失败转成测试失败：

```http
{{response
  const body = JSON.parse(response.body);

  if (body.errorCode) {
    throw new Error(`易快报单据列表业务失败: ${body.errorCode} ${body.errorMessage || ''}`.trim());
  }

  if (!Array.isArray(body.items)) {
    throw new Error('易快报单据列表响应缺少 items');
  }
}}
```

不要在手动排查请求上默认堆复杂 `{{response}}` 脚本；如果用户运行后只能看到测试结果、看不到响应内容，应先调整输出模式或移除深度脚本。CI 可以用 `--json --output exchange` 保留响应和测试结果，人工调试优先看正常响应输出。

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
