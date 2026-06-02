# Dev Container 模板调研记录

## 调研目标

为 `config/vscode` 下的 Dev Container 标准配置模板确定基础写法、可复用边界和 AI Agent 配置复用策略。

## 官方配置要点

* `devcontainer.json` 支持 `image` 或 `build` 两种入口；模板库更适合保留可复制的 `devcontainer.json`，复杂环境再配套 `Dockerfile`。
* `features` 可组合安装通用工具、Java、Node.js 等能力，适合做标准模板的默认构建块。
* `customizations.vscode` 可内置 VS Code 扩展与 settings，适合把 Remote - Containers、Java 开发插件、终端偏好沉淀在模板里。
* `mounts` 可挂载宿主目录或 Docker volume，适合复用宿主侧的 agent 配置目录，避免把 token 和登录态写进模板。
* `remoteEnv` 可追加 PATH 或声明容器内可见环境变量，适合给 CLI shim 或工具目录预留入口。
* Java Feature 支持 `version: "8"`，并可安装 Maven/Gradle；Java 8 模板可以基于该 Feature，而不是手写安装脚本。
* Node Feature 可安装 Node.js 与 pnpm/yarn；如果希望容器内运行 Node 生态 CLI，模板可以把它作为 agent 运行依赖。

## 本仓库约束

* 目标是模板库与最佳实践文档，不是只给单个项目生成 `.devcontainer`。
* 用户明确要求文档中不要出现具体项目名称和本机项目路径，只把示例描述为 Java 8 项目。
* 用户希望 Dev Container 能使用本机已有 Codex 或 Claude Code 工作流；模板应优先复用宿主配置和登录态，避免把 secrets 写入模板。
* 本机 `codex` 当前是 Node 入口脚本，`claude` 当前是本机二进制；因此“直接挂载宿主 CLI 可执行文件”跨容器不稳定，推荐在容器内安装/准备 CLI，再挂载宿主配置目录。

## 推荐方向

* 在 `config/vscode/devcontainers/` 下维护模板目录，例如 `base/`、`java8/`、`with-ai-agents/` 或组合型示例。
* Java 8 示例模板使用 Dev Container Java Feature 安装 Java 8，并安装 Maven；Gradle 先按可选项或注释说明处理。
* AI Agent 复用采用“容器内安装 CLI + 只读/按需挂载宿主配置目录”的模式：
  * Codex: 挂载 `~/.codex` 到容器用户 home 下的 `.codex`。
  * Claude Code: 挂载 `~/.claude` 到容器用户 home 下的 `.claude`。
  * CLI 安装方式放在模板文档中说明，避免模板假定宿主二进制可在容器里运行。

## 风险与边界

* 挂载宿主配置目录会把登录态带入容器；文档需要提醒只用于可信项目和可信容器镜像。
* 若用户使用自定义代理、router 或私有 CA，模板不应硬编码这些值；应通过本机配置或 `.env` 注入。
* Java 8 生态可能涉及旧 Maven 仓库、TLS 或私服证书问题；首版模板只提供标准 JDK/Maven 基础，不处理公司私服和证书。
