# Dev Container 标准模板

这个目录保存可复制到业务项目的 Dev Container 模板。模板以“先能直接用，再方便组合”为原则：完整模板放在语言目录下，通用片段放在能力目录下。

## 目录结构

```text
config/vscode/devcontainers/
├── base/
│   └── devcontainer.json
├── java8/
│   ├── devcontainer.json
│   └── scripts/
│       └── bootstrap-host-configs.sh
└── ai-agents/
    ├── README.md
    └── devcontainer.fragment.jsonc
```

## 快速使用 Java 8 模板

在目标 Java 8 项目根目录执行：

```bash
mkdir -p .devcontainer
cp -R /path/to/this-repo/config/vscode/devcontainers/java8/* .devcontainer/
```

然后用 VS Code 执行 `Dev Containers: Reopen in Container`。

## Java 8 模板包含什么

* Java 8 JDK，默认使用 Dev Containers Java Feature 安装。
* Maven，默认安装最新版 Maven。
* Node.js LTS，用于在容器内安装 Codex 和 Claude Code CLI。
* Maven 本地仓库缓存读写挂载：容器复用宿主 `~/.m2/repository`。
* Maven 配置只读挂载：容器读取宿主 `~/.m2/settings.xml`、`settings-security.xml`、`toolchains.xml`。
* Codex 配置只读挂载：容器读取宿主 `~/.codex` 中的配置、登录态、规则和技能。
* Claude Code 配置只读挂载：容器读取宿主 `~/.claude` 和 `~/.claude.json` 中的配置、技能、命令和插件。

## 配置挂载策略

默认策略是“配置只读 + 缓存读写”：

* 只读配置：Maven settings、Codex 配置、Claude Code 配置。
* 读写缓存：Maven 本地仓库。
* 容器运行态：Codex/Claude 的日志、会话、临时文件保留在容器用户目录，不回写宿主。

这样可以减少容器误改宿主登录态、密钥配置和个人偏好的风险。只有在你明确需要在容器内重新登录或修改全局配置时，才建议临时把对应挂载改成读写。

## Agent CLI 策略

模板不直接挂载宿主 `codex` 或 `claude` 可执行文件。原因是宿主 CLI 可能依赖宿主 Node、动态库或二进制格式，直接挂进 Linux 容器后不一定可执行。

推荐做法是：

1. 容器内安装 CLI：`@openai/codex` 与 `@anthropic-ai/claude-code`。
2. 通过只读挂载复用宿主配置和登录态。
3. 把运行时写入保留在容器自己的 home 目录。

## 安全边界

只在可信项目和可信镜像中挂载宿主 Codex / Claude Code 配置。即使是只读挂载，容器内进程仍然可以读取登录态和配置文件。

不要把真实 token、API key、私有代理、公司私服地址或项目专属路径写入模板。需要这些内容时，优先放在本机配置、环境变量或项目自己的未提交配置文件中。

## 组合其他模板

`ai-agents/devcontainer.fragment.jsonc` 提供 Codex / Claude Code 复用片段。给其他语言模板添加 Agent 能力时，复制 fragment 中的 `features`、`mounts` 和 `postCreateCommand` 片段，再复制 `java8/scripts/bootstrap-host-configs.sh` 到目标项目的 `.devcontainer/scripts/`。
