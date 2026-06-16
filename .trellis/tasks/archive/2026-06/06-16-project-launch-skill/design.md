# 通用项目启动 skill 技术设计

## Architecture

`project-launcher` 是 `ai/skills/dev/project-launcher/` 下的 TypeScript 脚本型 skill。开发态维护 `src/`、`tests/`、`package.json`、`tsconfig.json`、`build.mjs`；安装态入口是构建生成并提交的 `scripts/project-launcher.js`。

首版 CLI 使用 `cac` 组织子命令，构建方式对齐 `database-query`：`tsc --noEmit` 做类型检查，`rolldown` 打包为单文件 ESM，并加 `#!/usr/bin/env node` banner。

建议源码模块：

- `src/project-launcher.ts`：CLI 入口，只负责调用 `runCli(process.argv.slice(2))`。
- `src/cli.ts`：命令注册、参数解析、输出格式、退出码映射。
- `src/types.ts`：配置、服务、诊断、计划、tmux 元数据等共享类型。
- `src/config.ts`：配置查找、读取、合并、`${env:NAME}` 解析、local JSON 写回和备份。
- `src/discovery.ts`：零配置项目识别，发现 Maven/Gradle/Spring Boot 服务候选。
- `src/planner.ts`：根据配置、发现结果和 CLI 覆盖生成启动计划。
- `src/doctor.ts`：检测 tmux、Java、Maven/Gradle、端口、外部依赖命令。
- `src/tmux.ts`：生成和执行 tmux 命令，处理 session/pane/window 映射。
- `src/session.ts`：`.project-launcher/session.json` 读写、配置指纹、复用/冲突判断。
- `src/format.ts`：text/json 输出，不在业务逻辑里拼接展示文本。

## CLI Contract

主命令：

- `plan [--service <name>] [--all] [--config <path>] [--format text|json]`
- `doctor [--config <path>] [--format text|json]`
- `start --service <name> [--attach] [--format text|json]`
- `start --all [--attach] [--format text|json]`
- `start --name <name> --command <command> [--port <port>] [--save] [--overwrite]`
- `attach [--print]`
- `stop [--force]`
- `init --write-gitignore`

`start` 默认创建/复用 tmux session 后立即返回，不直接进入长期 TUI。`--attach` 才执行 attach。输出必须包含 session 名、attach 命令和服务映射。

`--format json` 面向 agent 自动化，至少包含：

```json
{
  "ok": true,
  "session": "pl-my-project",
  "attachCommand": "tmux attach -t pl-my-project",
  "services": [
    {
      "name": "api",
      "pane": "dev.0",
      "port": 8080,
      "command": "./mvnw spring-boot:run"
    }
  ],
  "diagnostics": []
}
```

## Configuration

配置文件首版使用 JSON，配置是增强能力，不是启动前提。

查找优先级：

1. 显式 `--config <path>`。
2. 项目级本机私有 `project-launch.local.json`。
3. 项目级可提交 `project-launch.config.json`。
4. 可选用户级 `$XDG_CONFIG_HOME/project-launcher/project-launch.local.json` 或 `~/.config/project-launcher/project-launch.local.json`，仅作为后续跨项目默认值来源；MVP 可先实现路径展示，不依赖它完成启动。

配置结构草案：

```json
{
  "defaults": {
    "profile": "dev",
    "reload": "auto",
    "sessionName": "pl-my-project",
    "allowParallelBuild": false
  },
  "services": [
    {
      "name": "api",
      "cwd": ".",
      "command": "./mvnw spring-boot:run -pl api",
      "port": 8080,
      "profile": "dev",
      "prepare": "./mvnw -pl api -am compile",
      "reloadCommand": "./mvnw spring-boot:run -pl api",
      "env": {
        "SPRING_PROFILES_ACTIVE": "dev"
      }
    }
  ],
  "dependencies": [
    {
      "name": "postgres",
      "checkCommand": "pg_isready -h localhost -p 5432",
      "startCommand": "docker compose up -d postgres"
    }
  ]
}
```

`--save` 只写入 `project-launch.local.json`。写入前必须在同目录创建时间戳 `.bak`；同名 service 默认报错，`--overwrite` 才替换。不得把真实 secret 写入可提交 `project-launch.config.json`。

## Discovery

零配置发现必须保守。

明显可运行的服务候选：

- Maven 模块存在 Spring Boot 插件、`spring-boot:run` 线索、`@SpringBootApplication` 或可运行 main class。
- Gradle 子项目存在 `bootRun`、`run`、application 插件、Spring Boot 插件或可运行 main class。
- 单模块项目存在 `pom.xml` / `build.gradle(.kts)` 且可推导出 `spring-boot:run`、`bootRun` 或 `run`。

不自动启动：

- parent/aggregator 模块。
- common、model、sdk、client、starter、bom 等普通 library 模块。
- 无 main class、无 run/bootRun 任务、无明显 Spring Boot 配置的模块。

发现到多个服务且用户未传 `--service` 或 `--all` 时只输出计划和候选，不启动任何服务。

## Planning And Execution

启动计划分两层：

1. 串行准备阶段：依赖检查、端口检查、`prepare` / 预编译 / 短生命周期构建。
2. tmux 长期运行阶段：一个 session、一个 `dev` window、多 pane 平铺，pane 内运行长期服务命令。

并发构建默认关闭。只有 `--allow-parallel-build` 或配置声明服务可并行时，才允许多个 `compile`、`build`、`package` 等短生命周期命令同时运行。

热重载通过 `--reload auto|off|command` 控制。默认 `auto` 只复用项目已有 dev/run/watch 能力或配置的 `reloadCommand`；检测不到能力时正常启动并提示，不改业务项目源码或配置。

## Tmux Contract

session 默认名：`pl-<project-slug>`。多 profile 或多配置可追加 `-<profile>` 或短 hash。

session 元数据写入 `.project-launcher/session.json`：

```json
{
  "managedBy": "project-launcher",
  "session": "pl-my-project",
  "projectRoot": "/abs/project",
  "configPath": "/abs/project/project-launch.local.json",
  "configHash": "abc123",
  "services": ["api", "worker"],
  "createdAt": "2026-06-16T10:00:00.000Z"
}
```

复用同名 session 时必须同时满足：

- tmux session 存在。
- 元数据存在且 `managedBy` 为 `project-launcher`。
- `projectRoot` 匹配当前项目。
- 配置路径/指纹和服务列表兼容。

不满足时默认报错，提示 `--attach`、`--replace` 或换 session 名。`stop` 只能默认停止元数据匹配的 session，`--force` 才允许处理不完整状态。

`.project-launcher/` 未被 `.gitignore` 忽略时，默认只提示。只有 `init --write-gitignore` 才修改项目 `.gitignore`。

## Diagnostics

`doctor` 和 `start` 前检查：

- `tmux` 是否可用；无 tmux 时真实启动失败，`plan` / `doctor` 仍可运行。
- `java` 是否可用。
- Maven/Gradle wrapper 优先，其次全局 `mvn` / `gradle`。
- 声明端口是否被占用；能识别 PID/进程名就输出，否则至少输出端口冲突。
- 外部依赖默认只检查和提示，不自动启动。只有显式配置且传 `--start-deps` 时才考虑执行 `startCommand`。

诊断输出不得泄露 secret、token、完整生产连接串。

## Compatibility And Rollback

首版只新增 `ai/skills/dev/project-launcher/` 和 Trellis 任务文档，不改现有 skill 行为。

构建产物可由 `pnpm -C ai/skills/dev/project-launcher build` 重新生成。若实现出问题，可删除新 skill 目录和任务文件回滚，不影响现有工具。

## Trade-offs

- JSON 配置牺牲注释友好性，换取 agent 生成、测试和无额外 YAML 依赖。
- `start` 默认不 attach 牺牲交互即时性，换取 agent 调用后能返回结构化结果。
- 零配置发现保守，可能需要 `--command --save` 补充非标准服务，但能减少误启动。
- tmux 是主启动路径，无 tmux 时不提供后台 spawn 替代，换取交互终端一致性。
