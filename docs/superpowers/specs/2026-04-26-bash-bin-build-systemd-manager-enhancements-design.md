# Bash Bin Build 与 systemd-service-manager 增强设计

## Summary

本设计补齐 Bash 工具的统一构建入口，并增强 `systemd-service-manager` 的可观察性与失败恢复能力。

核心方向是保持职责边界清晰：`Manage-BinScripts.ps1` 继续只负责 `.ps1` / `.py` 的 `bin` shim 同步；Bash 工具通过新增的 `scripts/bash/build.sh` 统一构建；根目录 `install.ps1` 在安装流程中调用这个 Bash 构建入口。`systemd-service-manager` 本身继续保留自己的模块化源码和局部 `build.sh`，由统一入口调度。

## Context

当前仓库已经存在三类 `bin` 产物来源：

- `Manage-BinScripts.ps1` 扫描 `.ps1` / `.py`，生成 PowerShell shim。
- `scripts/node` 通过 Node 构建流程生成 `bin/rule-loader` 等包装器。
- `scripts/bash/systemd-service-manager/build.sh` 独立构建 `bin/systemd-service-manager`。

这种结构能工作，但 Bash 构建没有统一入口，根安装流程也没有显式刷新 Bash 工具。用户还指出 `systemd-service-manager list` 目前只显示名称，不方便判断服务实际运行命令；同时希望补充重试能力。

## Goals

- 新增 `scripts/bash/build.sh`，作为 Bash 工具的统一构建入口。
- 让 `install.ps1` 调用 `scripts/bash/build.sh`，安装时自动刷新 Bash `bin` 产物。
- Bash 构建支持并行执行，并可限制并发数，默认根据 CPU 核心数推导。
- `systemd-service-manager list` 输出更多配置摘要，包括命令、目标、调度、scope 与重启策略。
- `systemd-service-manager list --json` 输出结构化数据，便于脚本消费与测试断言。
- `systemd-service-manager` 增加明确的 retry 配置模型，避免服务重启和 timer task 重试语义混乱。
- 更新相关 README 与模板，让用户知道新字段和构建入口。

## Non-Goals

- 不把 Bash 构建逻辑塞进 `Manage-BinScripts.ps1`。
- 不在本轮统一重构 PowerShell、Node、Bash 三类构建为同一个跨语言构建器。
- 不实现全局插件注册表或动态扫描所有目录下的任意 `build.sh`。
- 不改变已有 `systemd-service-manager install/start/status/logs` 的命令语义。
- 不默认启用 timer task retry，避免改变现有定时任务失败行为。

## Chosen Approach

采用“Bash 独立统一构建入口 + systemd 管理器小步增强”的方案。

`scripts/bash/build.sh` 维护一个显式构建清单。第一版只纳入 `scripts/bash/systemd-service-manager/build.sh`，后续 Bash 工具可以按需加入。显式清单比目录全量扫描更可控，能避免误执行示例、临时目录或未完成工具里的 `build.sh`。

`install.ps1` 在同步 PowerShell/Python shim 之后调用 Bash 构建入口，再继续 Node 构建和 PATH 配置。这样安装流程从用户视角仍是一条命令，但内部职责没有混在一起。

## Bash Build Entry

新增文件：

```text
scripts/bash/build.sh
```

第一版构建清单：

```text
scripts/bash/systemd-service-manager/build.sh
```

命令形态：

```bash
scripts/bash/build.sh
scripts/bash/build.sh --jobs 2
scripts/bash/build.sh --list
scripts/bash/build.sh --only systemd-service-manager
```

参数含义：

- `--jobs <n>`：限制并发构建数，必须是大于 0 的整数。
- `--list`：只列出可构建工具，不执行构建。
- `--only <name>`：只构建指定工具，便于本地调试。

环境变量：

- `BASH_BUILD_JOBS`：未传 `--jobs` 时作为并发数覆盖值。

默认并发数：

```text
jobs = max(1, min(cpu_count, task_count))
```

CPU 核心数探测顺序：

1. Linux 优先使用 `nproc`。
2. macOS / BSD 优先使用 `getconf _NPROCESSORS_ONLN`。
3. 失败时回退到 `1`。

并行执行策略：

- 每个构建任务后台执行。
- 每个任务输出写入独立临时日志。
- 调度器最多同时运行 `jobs` 个任务。
- 所有任务结束后统一打印成功/失败摘要。
- 任一任务失败时，`scripts/bash/build.sh` 返回非零退出码。

## Install Integration

`install.ps1` 新增 `Install-BashScripts` 函数，负责调用：

```powershell
bash ./scripts/bash/build.sh
```

如果当前环境没有 `bash`：

- Windows 原生环境打印 warning，不中断安装。
- Linux/macOS 环境打印 error，并将 Bash 构建视为失败。

安装顺序调整为：

1. 配置项目根目录 PATH。
2. 执行 `Manage-BinScripts.ps1 -Action sync -Force`。
3. 执行 `scripts/bash/build.sh`。
4. 构建 `scripts/node` 工具。
5. 配置 `bin` PATH。
6. 执行 nbstripout、AutoHotkey、Shell 配置等后续步骤。

## systemd-service-manager List

`list` 默认输出从“仅名称”升级为可扫描摘要。

建议文本输出：

```text
Services
- api | scope=system | restart=always/3s | command=/usr/bin/env bash -lc 'node server.js'

Timers
- cleanup | scope=system | schedule=0 3 * * * | target=task | command=/usr/bin/find /tmp/myapp -type f -mtime +7 -delete
- restart-api | scope=system | schedule=@daily | target=service:api | action=restart
```

`list --json` 输出数组结构：

```json
[
  {
    "type": "service",
    "name": "api",
    "scope": "system",
    "command": "/usr/bin/env bash -lc 'node server.js'",
    "restart": "always",
    "restartSec": "3s"
  }
]
```

设计取舍：

- 默认文本输出面向人读，保持紧凑。
- JSON 输出面向脚本，字段稳定；缺失值统一保留字段并置为 `null`，方便消费者处理。
- `SSM_DEBUG_DUMP_CONFIG=1` 的测试辅助路径保留，不和正式 `--json` 混用。

## Retry Model

Service 重试继续使用 systemd 原生字段：

- `RESTART`
- `RESTART_SEC`

Timer task 新增可选字段：

- `RETRY_ATTEMPTS`
- `RETRY_DELAY_SEC`

行为规则：

- 默认不启用 timer task retry。
- 当 `TARGET_TYPE=task` 且 `RETRY_ATTEMPTS` 大于 `1` 时，渲染出的 task service 使用轻量 Bash wrapper 执行 `COMMAND`。
- wrapper 在命令失败时等待 `RETRY_DELAY_SEC` 秒后重试。
- 所有尝试失败后返回最后一次命令的退出码。
- `TARGET_TYPE=service` 的 timer 不支持 `RETRY_ATTEMPTS`，因为它只是触发 `systemctl restart/start/stop`，失败恢复应交给目标 service 的 `Restart=` 或人工处理。

默认值：

- `RETRY_ATTEMPTS` 未设置时视为 `1`。
- `RETRY_DELAY_SEC` 未设置时视为 `5`。

## Error Handling

Bash 构建入口：

- 构建脚本不存在时报错并返回非零。
- `--jobs` 或 `BASH_BUILD_JOBS` 非法时报错并返回非零。
- 任一子构建失败时打印失败工具名、退出码与日志路径。
- 构建全部成功时打印产物摘要。

`install.ps1`：

- 调用 Bash 构建失败时输出清晰错误。
- Windows 无 `bash` 时只 warning，因为不是所有 Windows 安装都需要 Bash 工具。
- Linux/macOS 无 `bash` 或 Bash 构建失败时返回失败状态，避免用户以为 `bin/systemd-service-manager` 已刷新。

`systemd-service-manager`：

- `list` 遇到单个无效配置时整体失败，避免展示半可信列表。
- retry 字段非法时在解析阶段失败。
- timer service target 上配置 retry 时失败并提示该字段只适用于 `TARGET_TYPE=task`。

## Testing

需要覆盖以下测试：

- `scripts/bash/build.sh --list` 能列出 `systemd-service-manager`。
- `scripts/bash/build.sh --jobs 1` 能构建 `bin/systemd-service-manager`。
- 多个 fake build 任务时，并发数不超过 `--jobs`。
- 子构建失败时统一入口返回非零，并打印失败摘要。
- `install.ps1` 能调用 Bash 构建入口；缺少 `bash` 的平台分支用 mock 或最小断言覆盖。
- `systemd-service-manager list` 输出包含 service command、timer command / target 与 schedule。
- `systemd-service-manager list --json` 输出可解析 JSON。
- service retry 字段仍渲染为 `Restart=` / `RestartSec=`。
- timer task retry 字段生成 wrapper，并在字段非法时失败。

按仓库规则，本次实现涉及 `scripts/bash/**`、`install.ps1`、`tests/**/*.ps1` 与 systemd-manager Vitest，因此完成后需要执行：

```bash
pnpm run qa:systemd-service-manager
pnpm qa
```

如果改动触及 PowerShell 测试或 `install.ps1` 行为测试，还需要执行：

```bash
pnpm test:pwsh:all
```

## Rollout

第一阶段：

- 新增 `scripts/bash/build.sh`。
- 接入 `install.ps1`。
- 补充 Bash 构建入口测试与文档。

第二阶段：

- 增强 `systemd-service-manager list` 与 `list --json`。
- 增加 retry 配置解析与渲染。
- 更新模板与 README。

这两个阶段可以在同一个实现计划中完成，但代码提交时应尽量按职责拆分，便于回滚与 review。
