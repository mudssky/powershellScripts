# Systemd Service Manager Design

## Summary

本设计定义一个基于 Bash 的轻量 systemd 服务管理工具，目标是用项目目录中的 `.conf` / `.env` 配置生成并管理 systemd `service` 与 `timer`，覆盖“像 pm2 一样做基础服务管理，但实际部署由 systemd 承担”的场景。

工具默认面向 **system service**，因为正式部署通常要求服务在 SSH 断开、用户退出、无人登录时仍持续运行；同时保留 **user service** 支持，覆盖开发者个人常驻工具与用户级定时任务场景。

实现方式采用“多文件源码 + `build.sh` 产出单文件脚本”的仓库既有模式，重点追求可维护、可阅读、可分发，而不是把第一版做成完整编排平台。

## Context

当前仓库已经有两条与本设计高度相关的先例：

- [`scripts/bash/aliyun-oss-put.sh`](/home/administrator/projects/env/powershellScripts/scripts/bash/aliyun-oss-put.sh) 体现了 Bash 单文件脚本的注释、边界与少依赖风格。
- [`linux/fnos/fnos-mount-manager/README.md`](/home/administrator/projects/env/powershellScripts/linux/fnos/fnos-mount-manager/README.md) 体现了“多文件源码 + `build.sh` 打包单文件产物 + 测试对照源码入口与构建产物”的结构化实践。

仓库中现有的 [`docs/cheatsheet/linux/services/systemd.md`](/home/administrator/projects/env/powershellScripts/docs/cheatsheet/linux/services/systemd.md) 提供了 systemd 基础知识，但缺少一个贴近“项目目录管理 service/timer”的工具层实现。

用户目标可以收敛为以下几点：

- 在 `scripts/bash` 下开发一个用于 systemd 部署服务的 Bash 工具。
- 工具源码要分模块，便于维护与阅读。
- 通过 `build.sh` 打包成单文件脚本，便于复制到目标机器执行。
- 除了服务管理，也支持简单定时任务管理。
- 配置采用 `.conf` / `.env`，并明确 `.env.local > .env` 的覆盖规则。
- 第一版以项目目录为管理单元，并提供 `init` 生成模板。
- 测试使用 `vitest`，并允许引入 `execa` 简化命令执行代码。

## Goals

- 提供面向项目目录的 `service` / `timer` 管理能力。
- 默认支持 system scope，并可切换 user scope。
- 使用简单的 `KEY=VALUE` 配置格式，避免引入更重的解析依赖。
- 让工具源码模块化，同时能通过 `build.sh` 输出单文件产物。
- 为新项目提供 `init` 模板，自动生成目录、示例配置和 README。
- 为定时任务同时支持友好别名与受限的 cron 表达式。
- 在不直接依赖 `/etc/systemd/system` 的前提下完成自动化测试。

## Non-Goals

- 不实现跨项目全局注册表或常驻守护进程。
- 不实现 Web UI、TUI 或交互式面板。
- 不扩展到 socket/path/mount 等更多 unit 类型。
- 不支持高级 cron 扩展，如 `?`、`L`、`W`、`#`、秒字段、年份字段。
- 不生成日志轮转配置，日志先统一交给 journald。
- 不在第一版实现 `add service` / `add timer` 之类的增量脚手架命令。
- 不尝试抽象复杂依赖编排图或多环境 profile 体系。

## Constraints

- 源码需放在 `scripts/bash/` 下，风格与现有 Bash 脚本保持一致。
- 必须使用清晰规范的注释，尤其是公共接口与非直观逻辑。
- 构建产物需要是单文件脚本，便于分发。
- 默认部署模型应优先解决“SSH 断开后服务仍持续运行”的场景，因此默认 scope 为 `system`。
- 测试不能依赖真实写入 `/etc/systemd/system` 或真实污染用户 systemd 配置。
- `dotenv` 解析必须保守，不执行 shell 代码。

## Chosen Approach

采用“模块化项目管理器”方案。

工具以“项目目录中的 systemd 配置集”为核心工作单元，负责：

1. 读取项目级与服务级 / 定时任务级配置。
2. 合并 `.env` / `.env.local` 环境变量。
3. 渲染出对应的 `.service` / `.timer` unit。
4. 安装到 `system` 或 `user` 的 systemd unit 目录。
5. 统一包装 `systemctl` 与 `journalctl` 的常见管理动作。

该方案比单一大脚本更易维护，也比全局注册表模式更贴合第一版的复杂度边界。

## Source Layout

工具源码建议放在 [`scripts/bash/systemd-service-manager/`](/home/administrator/projects/env/powershellScripts/scripts/bash) 下，结构如下：

```text
scripts/bash/systemd-service-manager/
├── build.sh
├── main.sh
├── common.sh
├── commands/
│   ├── init.sh
│   ├── list.sh
│   ├── install.sh
│   ├── uninstall.sh
│   ├── start.sh
│   ├── stop.sh
│   ├── restart.sh
│   ├── status.sh
│   ├── logs.sh
│   ├── enable.sh
│   └── disable.sh
├── lib/
│   ├── cli.sh
│   ├── project.sh
│   ├── env.sh
│   ├── parser-service.sh
│   ├── parser-timer.sh
│   ├── cron.sh
│   ├── render-service.sh
│   ├── render-timer.sh
│   ├── systemd.sh
│   └── validate.sh
└── templates/
    ├── project.conf.example
    ├── project.env.example
    ├── service.conf.example
    ├── service.env.example
    ├── timer-service.conf.example
    ├── timer-task.conf.example
    └── README.md
```

模块边界如下：

- `commands/` 只负责命令分发与用户交互，不直接拼接 unit 内容。
- `lib/parser-*` 负责解析 `.conf` 为内部字段。
- `lib/env.sh` 负责安全读取 `.env` / `.env.local` 并按优先级合并。
- `lib/render-*` 负责把内部字段渲染成 `.service` / `.timer` 内容。
- `lib/systemd.sh` 负责 `systemctl` / `journalctl` / `systemd-analyze` 的调用包装。
- `build.sh` 只负责拼接模块并输出单文件产物，不承载业务逻辑。

## Build Outputs

`build.sh` 生成两个产物：

- `bin/systemd-service-manager`
- `scripts/bash/systemd-service-manager.sh`

前者用于仓库内统一调用，后者作为源码目录附近的便携副本，便于复制和调试。

## Managed Project Layout

被管理项目使用固定目录结构：

```text
your-project/
└── deploy/systemd/
    ├── README.md
    ├── project.conf
    ├── project.conf.example
    ├── project.env
    ├── project.env.example
    ├── project.env.local
    ├── services/
    │   ├── api.conf
    │   ├── api.conf.example
    │   ├── api.env
    │   ├── api.env.example
    │   ├── api.env.local
    │   └── worker.conf
    └── timers/
        ├── restart-api.conf
        ├── restart-api.conf.example
        ├── cleanup.conf
        ├── cleanup.conf.example
        ├── cleanup.env
        ├── cleanup.env.example
        └── cleanup.env.local
```

职责分层如下：

- `project.conf`：项目级默认值，如项目名、默认 scope、默认工作目录、默认运行用户。
- `project.env` / `project.env.local`：项目级环境变量默认值。
- `services/*.conf`：每个常驻服务的声明式配置。
- `services/*.env` / `.env.local`：每个服务的环境变量。
- `timers/*.conf`：每个定时任务的声明式配置。
- `timers/*.env` / `.env.local`：定时任务专用环境变量，仅在 `TARGET_TYPE=task` 时生效。
- `*.example`：可提交模板与参考配置。
- `README.md`：项目内使用说明，解释目录结构、优先级、scope 与常用命令。

## Configuration Model

### Project Defaults

`project.conf` 仅保存项目级默认值，采用简单 `KEY=VALUE` 结构，例如：

```dotenv
PROJECT_NAME=myapp
UNIT_PREFIX=myapp
DEFAULT_SCOPE=system
DEFAULT_WORKDIR=/opt/myapp
DEFAULT_USER=myapp
DEFAULT_GROUP=myapp
DEFAULT_RESTART=on-failure
DEFAULT_RESTART_SEC=5s
DEFAULT_STDOUT=journal
DEFAULT_STDERR=journal
```

设计约束：

- `DEFAULT_SCOPE` 默认值为 `system`。
- `UNIT_PREFIX` 用于稳定生成 unit 名，不直接依赖目录名。
- 项目级默认值可被服务级与 timer 级配置覆盖。

### Service Config

每个服务使用 `services/<name>.conf` 声明，名称默认来自文件名。

示例：

```dotenv
DESCRIPTION=My API Service
COMMAND=/usr/bin/node server.js
WORKDIR=/opt/myapp
SCOPE=system
USER=myapp
GROUP=myapp
RESTART=always
RESTART_SEC=3s
WANTED_BY=multi-user.target
AFTER=network.target
WANTS=network.target
```

关键规则：

- `COMMAND` 必填。
- `WORKDIR`、`SCOPE`、`USER`、`GROUP` 可继承 `project.conf`。
- 同名 `.env` / `.env.local` 默认按约定自动发现，不要求每个 `.conf` 再写 `ENV_FILE`。
- 第一版只开放常见字段，不全面暴露 `ExecStartPre` 等低层 systemd 指令。

### Timer Config

定时任务支持两种模式：

1. 绑定已有服务。
2. 定义独立一次性任务。

绑定服务示例：

```dotenv
DESCRIPTION=Restart API Every Night
TARGET_TYPE=service
TARGET_NAME=api
ACTION=restart
SCHEDULE=@daily
PERSISTENT=true
RANDOMIZED_DELAY=5m
```

独立任务示例：

```dotenv
DESCRIPTION=Clean Temp Files
TARGET_TYPE=task
COMMAND=/usr/bin/find /tmp/myapp -type f -mtime +7 -delete
WORKDIR=/opt/myapp
USER=myapp
GROUP=myapp
SCHEDULE=0 3 * * *
PERSISTENT=true
```

规则如下：

- `TARGET_TYPE=service` 时，管理器会额外生成一个 `oneshot` service，用于执行 `systemctl start|restart <unit>`。
- `TARGET_TYPE=task` 时，管理器直接生成一个独立的 `oneshot` service，再由 timer 触发。
- `SCHEDULE` 同时支持别名与受限 cron。

## Environment Precedence

环境变量优先级定义为：

1. CLI 显式传入参数或环境变量
2. `service` / `timer` 同名 `.env.local`
3. `service` / `timer` 同名 `.env`
4. `project.env.local`
5. `project.env`

该顺序满足“局部覆盖高于项目默认值”的直觉，同时符合用户要求的 `.env.local > .env`。

## Unit Naming

生成的 unit 名保持稳定、可预测：

- 服务 unit：`<unit-prefix>-<service-name>.service`
- 定时任务触发用的 oneshot service：`<unit-prefix>-task-<timer-name>.service`
- timer unit：`<unit-prefix>-<timer-name>.timer`

例如：

- `myapp-api.service`
- `myapp-worker.service`
- `myapp-task-clean-temp.service`
- `myapp-restart-api.timer`

当 timer 绑定已有服务时，仍保持“调度动作 unit”和“业务服务 unit”分离，方便日志与职责排查。

## CLI Design

CLI 默认以当前项目目录为上下文，同时支持 `--project <path>` 指向其他项目目录。

第一版命令面如下：

- `init`
- `list`
- `install`
- `uninstall`
- `start`
- `stop`
- `restart`
- `status`
- `logs`
- `enable`
- `disable`

建议命令形态：

```bash
systemd-service-manager init
systemd-service-manager list
systemd-service-manager install all
systemd-service-manager install service api
systemd-service-manager install timer backup
systemd-service-manager start service api
systemd-service-manager restart service api
systemd-service-manager status service api
systemd-service-manager logs service api --follow
systemd-service-manager enable timer backup
systemd-service-manager disable service worker
systemd-service-manager uninstall all
```

其中：

- `service <name>`、`timer <name>`、`all` 用作统一选择器。
- `logs` 封装 `journalctl`，user scope 自动切换到 `journalctl --user`。
- `status` 输出配置名、unit 名、scope、installed/enabled/active 状态。

## Init Behavior

`init` 负责生成项目骨架、示例文件与项目内说明文档，不要求用户手工记忆目录结构。

建议行为：

- 创建 `deploy/systemd/` 目录结构。
- 写入 `README.md`。
- 写入 `project.conf.example`、`project.env.example`。
- 写入最小可运行的 `project.conf`、`project.env`。
- 生成至少一个 `service` 示例与两个 `timer` 示例：
  - 一个绑定已有服务
  - 一个独立一次性任务

这样既保留 `example` 模板，又让 `init` 后项目立即有可以修改和试跑的实际文件。

## Install and Uninstall Flow

`install` 的职责是“把配置转换成 unit 并写入对应 systemd 目录”，默认不隐式执行 `enable` 或 `start`。

建议流程：

1. 定位项目目录与目标配置。
2. 解析并合并 `project.conf`、目标 `.conf`、相关 `.env`。
3. 校验必填字段、命名合法性、scope 与 schedule。
4. 渲染到临时目录。
5. 调用 `systemd-analyze verify` 校验生成结果。
6. 写入目标 unit 目录：
   - system scope：`/etc/systemd/system`
   - user scope：`~/.config/systemd/user`
7. 调用相应的 `daemon-reload`。

所有生成的 unit 文件都添加统一头注释，例如：

```ini
# Managed by systemd-service-manager
# Source: /path/to/project/deploy/systemd/services/api.conf
```

`uninstall` 只删除该工具管理的 unit 文件，不删除项目内配置源文件。

## Schedule Support

### Calendar-Based Scheduling

支持以下两类输入并统一转换到 `OnCalendar=`：

- systemd 风格别名：`@hourly`、`@daily`、`@weekly`、`@monthly`
- 标准 5 段 cron：如 `0 3 * * *`

cron 支持边界：

- 支持 `*`、`,`、`-`、`/`
- 不支持 `?`、`L`、`W`、`#`
- 不支持秒字段与年份字段

### Interval-Based Scheduling

支持 `@every-5m`、`@every-15m`、`@every-1h` 这类间隔别名。

这类配置不走 `OnCalendar=`，而是转换为：

- `OnBootSec=...`
- `OnUnitActiveSec=...`

这样可以明确表达“相对间隔执行”，避免和固定日历时间语义混淆。

## Error Handling

第一版采用“关键错误立即失败”的策略。

直接失败的情况包括：

- 配置文件缺失
- 必填字段为空
- 字段名非法或值不在允许范围内
- cron 转换失败
- `systemd-analyze verify` 失败
- 写入 unit 或 `daemon-reload` 失败

非致命场景：

- `list` / `status` 遇到未安装 unit 时，不中断整个命令，但清晰标记为 `not-installed`

统一输出前缀：

```text
[systemd-service-manager][error] ...
[systemd-service-manager][warn] ...
[systemd-service-manager][info] ...
```

## Validation Strategy

校验集中在安装前完成，避免所有命令都承担复杂解析成本。

核心校验项：

- `.conf` 中出现的 key 是否在允许列表内
- `COMMAND`、`TARGET_TYPE`、`SCHEDULE` 等关键字段是否存在
- `SCOPE` 是否为 `system` 或 `user`
- `UNIT_PREFIX`、服务名、timer 名是否只包含安全字符
- cron 是否在受支持范围内
- `TARGET_TYPE=service` 时，`TARGET_NAME` 是否能解析到当前项目中的服务
- `system` 模式下 `USER` / `GROUP` 字段格式是否合法
- `.env` 解析是否符合保守模式

同时提供：

```bash
systemd-service-manager install ... --dry-run
```

`--dry-run` 输出：

- 目标 unit 名
- 目标安装目录
- 将要生成的文件列表
- 渲染预览或预览文件路径

## Documentation Strategy

文档分三层：

1. 工具源码目录下的 `README.md`
   说明模块结构、构建方式、命令总览与支持字段。
2. `init` 生成的 `deploy/systemd/README.md`
   说明项目目录怎么用、scope 如何选择、env 优先级、常用命令与模板使用方式。
3. `*.example`
   提供最小可运行配置样板，便于团队共享与复制。

## Testing Strategy

测试框架使用 `vitest`，并允许引入 `execa` 统一执行 Bash 子进程、构建命令与 CLI 命令，减少测试辅助代码的样板。

测试分三层：

### Parser Tests

- 验证 `project.conf` / `service.conf` / `timer.conf` 解析结果
- 验证 `.env.local > .env` 及项目级 / 局部级优先级合并
- 验证非法 key、缺失字段、非法 scope 的报错

### Renderer Tests

- 验证 `.service` / `.timer` / timer 对应 oneshot service 的渲染结果
- 验证 unit 名生成规则稳定
- 验证 cron / 别名调度转换结果稳定

### CLI and Build Tests

- 验证 `init` 生成目录、README、example 文件与实际配置文件
- 验证 `install --dry-run` 不会写入真实 systemd 目录
- 验证 `timer service` 与 `timer task` 两条线都能正确生成 unit
- 验证 `build.sh` 产物与源码入口行为一致

测试过程中通过环境变量覆写目标 unit 目录到临时目录，避免污染真实 `/etc/systemd/system` 或用户 systemd 配置。

## Verification Plan

实现完成后至少验证以下路径：

1. 在临时项目目录执行 `init`，确认 `deploy/systemd/`、`README.md`、`*.example` 与实际配置文件都已生成。
2. 为一个常驻服务执行 `install service <name> --dry-run`，确认输出 unit 名、安装目录与渲染结果。
3. 为一个 `TARGET_TYPE=service` 的 timer 执行安装，确认同时生成 `.timer` 与对应的 oneshot `.service`。
4. 为一个 `TARGET_TYPE=task` 的 timer 执行安装，确认生成的 oneshot `.service` 使用任务命令本身。
5. 在覆写后的临时 unit 目录中检查生成文件，并验证 `build.sh` 产物与源码入口输出一致。

## Deferred Work

如果后续需求增长，可在独立变更中考虑：

- `add service` / `add timer` 增量脚手架
- 更丰富的 service 字段映射
- 更细粒度的 `validate` / `doctor` 命令
- 多环境 profile 支持
- 更完整的 systemd unit 类型支持

这些内容不属于第一版范围。
