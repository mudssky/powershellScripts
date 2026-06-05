# 目录层级与配置策略

## 总原则

优先沿用项目已有 HTTP/API 测试结构。没有既有约定时，用项目规模、业务域数量、跨接口流程复杂度和 CI 粒度决定目录层级。

默认采用目录化 env/dotenv 配置，主要面向 httpYac CLI 和 httpYac VS Code 插件。REST Client 只作为兼容提示，不作为主目标。

## 小型项目

适合接口少、业务域少、CI 只跑一组冒烟或测试请求的项目。

```text
http/
  env/
    dev.env.example
    local.env
  auth.http
  tasks.http
```

放置规则：

- `auth.http`：登录、刷新 token、当前用户、权限失败等认证相关请求。
- `tasks.http`：单个业务域或主流程请求。
- `env/*.env.example`：可提交模板，只放非敏感默认值和变量名说明。
- `env/local.env`：本机私有值，必须被 `.gitignore` 忽略。

## 中型项目

适合业务域变多、需要按模块维护请求的项目。

```text
http/
  env/
    dev.env.example
    test.env.example
    local.env
  auth/
    login.http
    permissions.http
  tasks/
    task-crud.http
    task-async.http
  negative/
    auth-negative.http
    task-negative.http
```

放置规则：

- 按业务域建目录，目录内再按主流程或接口族拆文件。
- `negative/` 放自动化异常场景，必须使用 `# @tag negative`。
- 跨模块但属于主流程的请求，可以先放在主业务域；跨多个域且复用频繁时再拆 `flows/`。

## 大型项目

适合模块多、跨模块流程多、手动调试与 CI 请求需要隔离的项目。

```text
http/
  env/
    dev.env.example
    test.env.example
    staging.env.example
    local.env
  shared/
    auth.http
    health.http
  modules/
    users/
      user-crud.http
      user-negative.http
    tasks/
      task-crud.http
      task-async.http
  flows/
    onboarding-smoke.http
    billing-smoke.http
  manual/
    debug-login.http
```

放置规则：

- `shared/` 放认证、健康检查、租户切换、公共准备请求。
- `modules/` 放模块内接口。
- `flows/` 放跨模块主流程，通常加 `# @tag smoke`。
- `manual/` 放手动调试请求，只加 `# @tag manual`，CI 命令不要包含它。

## env/dotenv 配置

推荐目录化 env：

```text
http/
  env/
    dev.env.example
    test.env.example
    local.env
```

`dev.env.example` 示例：

```dotenv
baseUrl=http://localhost:3000
username=dev@example.com
tenantId=demo
```

`local.env` 示例，不提交：

```dotenv
password=<replace-me>
token=<replace-me>
```

推荐 `.gitignore`：

```gitignore
http/env/local.env
http/env/*.local.env
http/env/*.secret.env
.env.local
```

规则：

- example 文件可以提交，但只放非敏感默认值和变量名。
- 真实密码、token、client secret 放本机私有 env、系统环境变量或 CI secret。
- 变量名在 CLI、VS Code 和 `.http` 文件中保持一致，例如 `baseUrl`、`username`、`password`、`tenantId`。

## VS Code httpYac 插件

`.vscode/settings.json` 只放插件行为配置，不复制业务变量：

```json
{
  "httpyac.environmentSelectedOnStart": ["dev"],
  "httpyac.environmentPickMany": true,
  "httpyac.envDirName": "http/env",
  "httpyac.codelens": {
    "send": true,
    "sendAll": true,
    "pickEnvironment": true,
    "testResult": true
  }
}
```

说明：

- `httpyac.envDirName` 是相对或绝对路径的 dotenv 文件目录。
- `httpyac.environmentVariables` 只在项目已有此约定时使用；新项目默认不复制业务变量，避免和 env 文件漂移。
- 当前文档证据只确认插件可指定 dotenv 目录，不把“指定任意 `http-client.env.json` 文件路径”写成通用能力。

## CLI 命令

本地测试：

```bash
httpyac send "http/**/*.http" --all --tag test --bail
```

CI 输出 JSON：

```bash
httpyac send "http/**/*.http" --all --tag test --json --bail
```

长命令在文档中可以换行：

```bash
httpyac send "http/**/*.http" \
  --all \
  --tag test \
  --env test \
  --json \
  --bail \
  --var password="$API_TEST_PASSWORD"
```

在 CI YAML 或 package script 中，如果换行不方便，可以保留一行版本，或封装成项目脚本。

## REST Client 兼容提示

REST Client 支持 `$dotenv` 从 `.http` 同目录的 `.env` 文件读取变量。若团队实际主要使用 REST Client，可以在请求目录放 `.env` 或按它的工作区设置维护变量。

本 skill 的默认目标是 httpYac CLI 和 httpYac VS Code 插件，因此只要求变量名可迁移，不强制为 REST Client 调整目录结构。

## 长行处理

### URL query 参数过长

- 优先把重复或环境相关值提取到 env 变量。
- 对复杂筛选条件，优先使用 POST JSON body 或后端支持的 filter 对象。
- 不推荐随意把 URL 在 `?` 或 `&` 后硬换行；除非已经确认当前工具能正确解析。

### Header 过长

- 公共 header 放请求默认配置或变量。
- token、api key 等敏感值只通过 env、系统环境变量或响应变量注入。
- 不把长 token 直接写在 `.http` 文件里。

### JSON body 过长

- 使用多行 JSON，并按业务含义分组。
- 大型请求体可以把稳定示例拆成多个请求块或最小必需字段。
- 不把复杂 JSON 压成单行。

### CLI 参数过长

- 文档里给 shell 换行版本。
- CI 或 `package.json` 里需要一行时，优先封装脚本或减少 inline `--var`，把变量放 env 文件或 CI secret。
