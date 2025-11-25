## 优化目标
- 提升健壮性与可维护性：完善错误处理、路径与参数验证、Docker/Compose 兼容。
- 改善使用体验：增加列出服务、干运行、停止/销毁等常用操作与清晰输出。
- 强化跨平台与 Windows 细节：统一路径规范、优雅处理环境变量与 .env 文件。
- 清理未使用代码：移除或接入现有但未生效的参数数组。

## 技术改动点
### 健壮性与安全
- 启用 `Set-StrictMode -Version Latest` 与 `CmdletBinding(SupportsShouldProcess = $true)`。
- 增加 `Test-DockerAvailable`：检测 `docker` CLI 与 `compose` 子命令是否可用，决定使用 `docker compose` 或回退 `docker-compose`。
- 在所有外部调用处加入 `try/catch`，失败时输出 `Write-Error` 并返回非 0 退出码。

### 参数与路径
- 增加参数：`[switch]$List`、`[switch]$DryRun`、`[switch]$Down`、`[switch]$Pull`、`[switch]$Build`、`[string]$ProjectName`、`[string]$NetworkName`、`[hashtable]$Env`。
- `DataPath` 标准化：使用 `Resolve-Path` 与 `Join-Path`，在 Windows 下统一成 `C:\docker_data` 风格；启动前自动创建目录（`Ensure-DataPath`）。
- 通过 `.env` 文件或 `--env-file` 管理环境变量，避免依赖进程级环境（保留现有方式作为兼容）。

### Compose 互操作
- 封装 `Invoke-DockerCompose`：统一 `-f`、`-p`、`--profile`、服务名/动作（`up -d`、`down`、`pull`、`build`），并实现 `docker compose` ↔ `docker-compose` 透明回退。
- 保留 `Get-ComposeServiceNames` 并在 `-List` 模式输出可用服务与可用 profiles；如 `ServiceName` 不在集合内，给出近似匹配建议。

### 运行后验证
- 增加健康探测：对常见服务（如 `postgre`、`mongodb`、`redis`）轮询 `docker inspect` 的 `Health.Status`，直到 `healthy` 或超时（可配置）。
- 统一输出：使用 `Write-Host`（带颜色）/`Write-Verbose` 告知启动进度、健康状态与端口映射提示。

### 清理与对齐
- `$commonParams`、`$pgHealthCheck`：若改为 `docker run` 场景则接入；否则删除以免混淆。
- 说明 `RestartPolicy` 仅在 `docker run` 有效；如需在 Compose 生效，约定在 Compose 模板里读取该变量。

### 文档与帮助
- 完善帮助注释：补充 `.OUTPUTS`、更多 `.EXAMPLE`（`-List`、`-DryRun`、`-Down`、`-Pull`、`-Build`、`-ProjectName`）。

## 实施步骤
1. 引入严格模式与 `SupportsShouldProcess`，统一入口参数定义与验证（含默认值处理）。
2. 编写 `Test-DockerAvailable` 与 `Invoke-DockerCompose` 两个辅助函数，替换脚本中直接调用的 `docker compose`。
3. 实现 `Ensure-DataPath` 与 `.env` 写入逻辑；给出是否使用 `.env` 或进程环境的切换（优先 `.env`）。
4. 接入新参数流：
   - `-List`：列出 `Get-ComposeServiceNames` 解析出的服务与 profiles。
   - `-DryRun`：打印将要执行的 compose 命令，不实际执行。
   - `-Down/-Pull/-Build`：对应动作分支，支持组合（如 `-Pull -Build`）。
   - `-ProjectName`、`-NetworkName`：透传到 compose 调用，网络不存在时自动创建。
   - `-Env`：附加用户自定义的环境变量键值对。
5. 启动后健康检查模块：按服务名选择性探测，带超时与重试提示。
6. 移除或接入未使用数组与注释，保证代码一致性与可读性。
7. 增强输出与错误处理：统一前缀、颜色与详细模式，关键失败路径返回非 0。
8. 完善帮助注释与示例；验证在 Windows 11 + PowerShell 7 环境下的实际行为。

## 验证方案
- 功能验证：在 `-List`、`-DryRun`、`up`、`down`、`pull`、`build`、`mongodb-replica` 分支分别执行并检查输出与行为。
- 健康探测：以 `redis`、`postgre`、`mongodb` 进行验证，模拟失败与成功路径。
- 兼容性验证：在同一脚本中切换 `docker compose` 与 `docker-compose`，确保回退逻辑正确。

## 交付范围
- 仅修改 `c:\home\env\powershellScripts\start-container.ps1`；不新增文件，除非按 `.env` 模式在 compose 目录生成 `.env`（可配置）。
- 保持现有默认行为不变；新增功能均为可选参数触发。

请确认以上计划，确认后我将按步骤落地到代码并完成验证。