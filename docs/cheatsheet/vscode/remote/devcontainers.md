# Dev Container 模板最佳实践

## 什么时候用

当项目需要稳定的 Linux 开发环境、统一 JDK/Node/CLI 版本，或者希望减少本机环境污染时，优先使用 Dev Container。

本仓库的标准模板放在 `config/vscode/devcontainers/`：

* `base/`：最小 Ubuntu 基础模板。
* `java8/`：Java 8 + Maven + Codex / Claude Code 配置复用模板。
* `ai-agents/`：可合并到其他语言模板的 Agent 配置片段。

## 推荐复制方式

以 Java 8 项目为例，在项目根目录执行：

```bash
mkdir -p .devcontainer
cp -R /path/to/this-repo/config/vscode/devcontainers/java8/* .devcontainer/
```

复制后检查 `.devcontainer/devcontainer.json` 中的挂载项是否符合你的宿主系统路径，然后用 VS Code 执行 `Dev Containers: Reopen in Container`。

## Maven 配置复用

Java 8 模板默认复用宿主 Maven 配置：

* `~/.m2/settings.xml`、`settings-security.xml`、`toolchains.xml` 以只读符号链接进入容器。
* `~/.m2/repository` 读写挂载到容器，避免每个容器重复下载依赖。

如果项目需要私服、镜像或认证，优先放在宿主 Maven settings 中，不要写进模板。

## Codex / Claude Code 配置复用

模板默认在容器内安装 CLI：

* `@openai/codex`
* `@anthropic-ai/claude-code`

宿主配置通过只读挂载复用：

* `~/.codex` -> `/mnt/host-configs/codex`
* `~/.claude` -> `/mnt/host-configs/claude`
* `~/.claude.json` -> `/mnt/host-configs/claude.json`

`bootstrap-host-configs.sh` 会把配置类文件链接到容器用户目录，同时把日志、会话、临时文件保留在容器内。

## 安全建议

只读挂载不等于不可读取。容器内进程仍然可以读取宿主 Codex / Claude Code 登录态，因此只应在可信项目和可信镜像中启用这些挂载。

不要把下面内容提交到模板：

* API key / token
* 私有代理地址
* 公司私服认证信息
* 个人项目路径
* 项目专属数据库或中间件配置

## 常见调整

如果要在容器内重新登录 Codex 或 Claude Code，临时把对应挂载去掉 `readonly` 或改为读写，登录完成后再恢复只读。

如果宿主没有 Maven 本地仓库，可以先执行：

```bash
mkdir -p ~/.m2/repository
```

如果宿主没有 Codex 或 Claude Code 配置目录，可以先执行：

```bash
mkdir -p ~/.codex ~/.claude
```
