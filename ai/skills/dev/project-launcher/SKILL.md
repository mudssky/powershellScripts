---
name: project-launcher
description: 用 tmux 启动和管理本地项目服务。Use when 用户需要一键启动 Java/JVM 项目、多个服务、指定 profile、检查端口/依赖、进入 tmux 查看服务输出，或把一次性启动命令沉淀为本机配置。
---

# 项目启动器

## 使用时机

用于帮助 agent 在本地项目中识别启动方式、检查依赖与端口，并通过 tmux 启动一个或多个服务。首版优先支持 Java/JVM、Maven、Gradle、Spring Boot 项目；其他语言可通过显式 `--command` 接入。

tmux 是主要启动承载层。真实启动默认创建或复用一个 `pl-<project>` session，并返回 attach 命令；只有显式传 `--attach` 才直接进入 tmux。

## 工作流程

1. 先查看启动计划，不要直接猜命令：

   ```bash
   node scripts/project-launcher.js plan
   node scripts/project-launcher.js plan --format json
   ```

2. 检查 tmux、Java、Maven/Gradle、端口和依赖服务：

   ```bash
   node scripts/project-launcher.js doctor
   ```

3. 单服务项目可直接启动；多服务项目需要显式选择服务或传 `--all`：

   ```bash
   node scripts/project-launcher.js start --service api
   node scripts/project-launcher.js start --all
   ```

4. 启动后根据返回的命令进入 tmux，或使用内置 attach：

   ```bash
   node scripts/project-launcher.js attach
   tmux attach -t pl-my-project
   ```

5. 非标准项目可以传一次性命令。需要下次复用时，显式保存到本机私有配置：

   ```bash
   node scripts/project-launcher.js start --name api --command "./mvnw spring-boot:run" --port 8080 --save
   ```

   `--save` 只写入 `project-launch.local.json`，写前会创建 `.bak`。同名服务默认不覆盖，需要传 `--overwrite`。

## 配置

配置不是简单项目的前提。需要复杂编排时，优先使用项目级 JSON：

- `project-launch.local.json`：本机私有配置，不提交。
- `project-launch.config.json`：可提交默认配置，不写真实 secret。

`.project-launcher/session.json` 是运行态元数据，用于安全复用、attach 和 stop。若项目未忽略 `.project-launcher/`，CLI 默认只提示；需要写入 `.gitignore` 时显式执行：

```bash
node scripts/project-launcher.js init --write-gitignore
```

## 边界

- 不自动安装 JDK、Maven、Gradle、tmux、Docker、数据库或 MQ。
- 不默认启动 Docker Compose、数据库、Redis 或 MQ；只检测并提示。
- 不把真实密码、token、生产连接串写入可提交配置。
- 不默认并发执行多服务构建；并发构建必须显式允许。
- 不为了热重载自动改写业务项目源码或配置。
