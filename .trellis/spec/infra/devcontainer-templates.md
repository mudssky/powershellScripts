# Dev Container Template Guidelines

> 适用于 `config/vscode/devcontainers/` 下的 Dev Container 标准模板、片段和配套文档。

## Scenario: Standard Dev Container Templates

### 1. Scope / Trigger

* Trigger: 新增或修改可复制到业务项目的 Dev Container 模板。
* Scope: `config/vscode/devcontainers/**`、Dev Container 相关 cheatsheet、模板内初始化脚本。
* Goal: 模板必须可复用、无项目专属路径、无真实 secrets，并明确宿主配置复用的安全边界。

### 2. Signatures

* 模板入口：`config/vscode/devcontainers/<template-name>/devcontainer.json`
* 可组合片段：`config/vscode/devcontainers/<capability>/devcontainer.fragment.jsonc`
* 配套脚本：`.devcontainer/scripts/*.sh`
* 文档入口：`config/vscode/devcontainers/README.md`

### 3. Contracts

* `devcontainer.json` 必须是可解析 JSON；不要在正式模板 JSON 中使用注释。
* 片段文件可使用 `.jsonc`，但必须在文档中说明需要人工合并。
* 宿主配置默认采用“配置只读 + 缓存读写”：
  * 配置类文件和目录使用只读 bind mount。
  * 缓存类目录可使用读写 bind mount 或 Docker volume。
  * 容器运行态日志、session、临时文件优先保留在容器用户目录。
* AI Agent CLI 默认在容器内安装，不直接挂载宿主可执行文件。
* 模板不得写入真实 token、API key、个人项目路径、私有代理或项目专属服务地址。

### 4. Validation & Error Matrix

| Condition | Expected handling |
|-----------|-------------------|
| 宿主配置目录不存在 | `initializeCommand` 预创建空目录，避免 bind mount 失败 |
| 宿主单文件配置不存在 | 预创建空文件或把文件挂载改为可选脚本逻辑，避免 Docker 把文件路径误建成目录 |
| 容器内需要写日志或 session | 写入容器 home 下的运行态目录，不回写只读宿主配置 |
| 需要在容器内重新登录 agent | 文档说明临时改读写挂载，完成后恢复只读 |
| 模板需要私服或代理 | 通过本机配置、环境变量或项目私有配置注入，不写进标准模板 |

### 5. Good/Base/Bad Cases

* Good: Java 8 模板使用 Dev Container Feature 安装 JDK/Maven，Maven settings 只读链接，Maven repository 读写挂载。
* Base: 仅提供 `base/devcontainer.json`，不包含语言工具链和宿主敏感配置挂载。
* Bad: 在模板中硬编码某个本机项目路径、API key、私有 Maven 仓库认证，或直接挂载宿主 `codex` / `claude` 二进制。

### 6. Tests Required

* JSON 模板：运行 JSON parse 检查。
* Shell 脚本：运行 `bash -n`。
* 文档/模板：搜索确认不含项目专属路径、真实 secret、一次性调试内容。
* 仓库质量门禁：配置/文档变更完成后运行根目录 `pnpm qa`。

### 7. Wrong vs Correct

#### Wrong

```json
{
  "mounts": [
    "source=/home/user/company/project,target=/workspace,type=bind",
    "source=${localEnv:HOME}/.local/bin/claude,target=/usr/local/bin/claude,type=bind"
  ]
}
```

#### Correct

```json
{
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/mnt/host-configs/claude,type=bind,readonly"
  ],
  "postCreateCommand": "npm install -g @anthropic-ai/claude-code"
}
```
