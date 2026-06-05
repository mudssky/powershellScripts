# httpyac 模式参考

## 环境文件

默认使用目录化 env/dotenv，便于命令行和 VS Code httpYac 插件共用变量名：

```text
http/
  env/
    dev.env.example
    test.env.example
    local.env
```

可提交的 `http/env/dev.env.example`：

```dotenv
baseUrl=http://localhost:3000
username=dev@example.com
tenantId=demo
```

私有值示例 `http/env/local.env`，不提交：

```dotenv
password=<replace-me>
token=<replace-me>
```

建议 `.gitignore`：

```gitignore
http/env/local.env
http/env/*.local.env
http/env/*.secret.env
.env.local
```

已有项目使用 `http-client.env.json` 时可以沿用；新项目默认优先使用 env/dotenv 目录，避免同时维护 JSON 和 VS Code settings 两套业务变量。

## 登录取 token

```http
###
# @name login
# @tag test
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
# @ref login
GET {{baseUrl}}/api/me
Authorization: Bearer {{login.response.body.$.data.token}}

?? status == 200
```

## CLI 命令

```bash
httpyac send "http/**/*.http" --all --tag test --bail
httpyac send "http/**/*.http" --all --tag smoke --bail
httpyac send "http/**/*.http" --all --tag test --json --bail
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
