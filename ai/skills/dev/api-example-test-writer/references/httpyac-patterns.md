# httpyac 模式参考

## 环境文件

可提交的 `http/http-client.env.json`：

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

私有值示例，不提交：

```dotenv
API_TEST_PASSWORD=<replace-me>
API_TOKEN=<replace-me>
```

建议 `.gitignore`：

```gitignore
http/*.local.env.json
.env.local
```

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
httpyac send "http/**/*.http" --all --env staging --tag test --bail --var password="$API_TEST_PASSWORD"
```

## 标签

- `test`：自动化测试。
- `smoke`：主流程冒烟。
- `manual`：手动调试，CI 不跑。
- `negative`：异常场景。
- `async`：异步任务或轮询流程。
