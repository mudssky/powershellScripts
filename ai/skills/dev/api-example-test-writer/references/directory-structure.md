# 目录层级与配置策略

## 总原则

优先沿用项目已有 HTTP/API 测试结构。没有既有约定时，用项目规模、业务域数量、跨接口流程复杂度和 CI 粒度决定目录层级。

默认采用目录化 env/dotenv 配置，主要面向 httpYac CLI 和 httpYac VS Code 插件。REST Client 只作为兼容提示，不作为主目标。

## 小型项目

适合接口少、业务域少、CI 只跑一组冒烟或测试请求的项目。

```text
http/
  env/
    .env.example
    .env.test
    .env.local
  auth.http
  tasks.http
```

放置规则：

- `auth.http`：登录、刷新 token、当前用户、权限失败等认证相关请求。
- `tasks.http`：单个业务域或主流程请求。
- `env/.env.example`：可提交模板，只放变量名、非敏感默认值和占位说明。
- `env/.env.test`：可提交测试默认值，只放测试 URL、非敏感账号名、租户、超时和开关。
- `env/.env.local`：本机私有值，必须被 `.gitignore` 忽略。

## 中型项目

适合业务域变多、需要按模块维护请求的项目。

```text
http/
  env/
    .env.example
    .env.test
    .env.local
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
    .env.example
    .env.test
    .env.staging.example
    .env.local
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
    .env.example
    .env.test
    .env.local
```

`.env.example` 示例：

```dotenv
baseUrl=http://localhost:3000
username=api-test@example.com
tenantId=demo
requestTimeout=30000
```

`.env.test` 示例，可以提交但不能包含敏感值：

```dotenv
baseUrl=http://localhost:3000
username=api-test@example.com
tenantId=test
requestTimeout=30000
```

`.env.local` 示例，不提交：

```dotenv
password=<replace-me>
token=<replace-me>
```

推荐 `.gitignore`：

```gitignore
http/env/.env.local
http/env/.env.*.local
http/env/*.local.env
http/env/*.secret.env
.env.local
*.env.local
```

规则：

- `.env.example` 和 `.env.test` 可以提交，但只放非敏感默认值和变量名。
- 真实密码、token、client secret 放本机私有 env、系统环境变量或 CI secret。
- 变量名在 CLI、VS Code 和 `.http` 文件中保持一致，例如 `baseUrl`、`username`、`password`、`tenantId`。

## VS Code httpYac 插件

优先同时提供 httpYac 原生项目配置和 VS Code 工作区配置，不复制业务变量。这样 CLI、VS Code 插件、多根工作区能共享同一套 env 文件。

httpYac 解析 dotenv 的规则：

- `httpyac.envDirName` 是相对或绝对路径。
- 相对路径会从 `.http` 文件所在目录开始向上查找，每一层都尝试拼接 `envDirName`。
- 选择 `test` 环境时读取 `.env.test` 和 `test.env`；选择 `local` 环境时读取 `.env.local` 和 `local.env`。
- 未选择环境时只读取 `.env`，不会自动读取 `.env.test` 或 `.env.local`。

路径选择规则：

- 如果请求文件放在 `http/*.http`，env 放在 `http/env/.env.test`，`envDirName` 推荐写 `env`。
- 如果请求文件分散在仓库多个目录，但 env 固定在根目录 `http/env/`，可以写 `http/env`，并用 CLI 验证每个目录下的 `.http` 是否能读到变量。
- 若已有项目使用其他结构，优先按“从 `.http` 所在目录向上找”的规则推导，不盲目套用 `http/env`。

提供 VS Code 配置时按这个顺序落地：

1. 先确认 `.http` 文件和 `env/` 的相对位置，再决定 `envDirName`。
2. 新增或更新 `.httpyac.json`，让 CLI 和插件共享 httpYac 原生配置。
3. 新增或更新 `.vscode/settings.json`，只放适合 folder/resource 作用域的配置。
4. 如果仓库已有 `.code-workspace`，保留全部 `folders`，只合并 `settings`；不要重建或覆盖已有工作区结构。
5. 如果仓库没有 `.code-workspace`，只有在团队需要多根工作区或 window 级默认环境时才创建。

推荐项目级配置 `.httpyac.json`：

```json
{
  "envDirName": "env"
}
```

`.vscode/settings.json` 只放 resource 级配置，适合单根文件夹打开：

```json
{
  "httpyac.envDirName": "env"
}
```

`.code-workspace` 放 window 级默认环境和 CodeLens，适合多根工作区：

```json
{
  "folders": [
    {
      "name": "root",
      "path": "."
    }
  ],
  "settings": {
    "httpyac.envDirName": "env",
    "httpyac.environmentSelectedOnStart": ["test", "local"],
    "httpyac.environmentPickMany": true,
    "httpyac.codelens": {
      "send": true,
      "sendAll": true,
      "pickEnvironment": true,
      "testResult": true
    }
  }
}
```

更新既有 `.code-workspace` 时只合并 `settings`，不要删除已有子项目：

```json
{
  "folders": [
    {
      "name": "root",
      "path": "."
    },
    {
      "name": "frontend",
      "path": "frontend"
    },
    {
      "name": "backend",
      "path": "backend"
    }
  ],
  "settings": {
    "httpyac.envDirName": "env",
    "httpyac.environmentSelectedOnStart": ["test", "local"],
    "httpyac.environmentPickMany": true,
    "httpyac.codelens": {
      "send": true,
      "sendAll": true,
      "pickEnvironment": true,
      "testResult": true
    }
  }
}
```

如果团队不用 `.code-workspace`，也可以把这些 window 级配置留在 `.vscode/settings.json`，但要提醒使用者修改后可能需要 `Developer: Reload Window`，并手动执行 `httpyac: toggle environment` 选择环境。

可选：若希望 `.http` 文件有一键显示变量和验证变量，也可以打开：

```json
{
  "httpyac.codelens": {
    "send": true,
    "pickEnvironment": true,
    "showVariables": true,
    "validateVariables": true
  }
}
```

说明：

- `httpyac.envDirName` 在 VS Code 配置里使用 `httpyac.` 前缀，在 `.httpyac.json` 里使用 `envDirName`。
- `httpyac.environmentSelectedOnStart`、`httpyac.environmentPickMany`、`httpyac.codelens` 是 window 级设置；多根工作区优先放 `.code-workspace`。
- `.vscode/settings.json` 中如果只有 `httpyac.envDirName` 有补全或高亮，通常是 VS Code 对设置作用域的提示，不代表其他设置一定无效；仍建议按作用域拆分。
- `httpyac.environmentVariables` 只在项目已有此约定时使用；新项目默认不复制业务变量，避免和 env 文件漂移。
- 当前文档证据只确认插件可指定 dotenv 目录，不把“指定任意 `http-client.env.json` 文件路径”写成通用能力。

### VS Code 变量未找到排查

当插件诊断提示 `baseUrl is not found` 或类似变量缺失时，按顺序检查：

1. 确认 `.http` 文件实际位置，并按上面的规则推导 `envDirName`。例如 `http/foo.http` + `http/env/.env.test` 应写 `env`。
2. 确认当前 VS Code 打开的是仓库根目录或 `.code-workspace`，不是只打开了子目录。
3. 执行 `httpyac: toggle environment`，选中需要的环境，例如 `test` 和 `local`。
4. 修改配置后执行 `Developer: Reload Window`，让 `environmentSelectedOnStart` 重新生效。
5. 用 CLI 做最小变量展开验证，必要时覆盖 URL 到本地拒绝端口，避免误打真实接口：

```bash
httpyac send http/example.http \
  --name login \
  --env test \
  --env local \
  --output none \
  --timeout 1000 \
  --var baseUrl=http://127.0.0.1:9
```

如果输出里的 URL 或 body 已展开为实际值，只剩 `ECONNREFUSED 127.0.0.1:9`，说明 env 已加载；接下来再排查真实服务、凭据或网络。

## CLI 命令

本地测试：

```bash
httpyac send "http/**/*.http" --all --env test --tag test --bail
```

CI 输出 JSON：

```bash
httpyac send "http/**/*.http" --all --env test --tag test --json --bail
```

长命令在文档中可以换行：

```bash
httpyac send "http/**/*.http" \
  --all \
  --env test \
  --tag test \
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
