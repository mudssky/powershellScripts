## 问题诊断
- 逻辑集中在单脚本，下载流程、资源评估、输出混杂在一起，后续扩展成本高（ai/downloadModels.ps1:21–24, 131–151, 169–222）。
- 配置读取与校验较弱，缺少字段合法性与默认值策略（ai/downloadModels.ps1:52–68）。
- 控制台输出路径耦合（`Write-Host` 与 `ListOnly` 分支交织），不易统一控制日志级别（ai/downloadModels.ps1:28–39, 193–216, 225–240）。
- 魔法常量较多：例如 CPU 模式 8GB 上限、内存系数 1.5 等（ai/downloadModels.ps1:113–120, 151），建议集中常量与策略。
- 测试缺失：未覆盖 macOS 统一内存、AMD 显存估算、skip 规则、`ListOnly` 计划列表等（psutils/modules/hardware.psm1:96–137, 178–323；ai/downloadModels.ps1:173–233）。

## 优化目标
- 解耦职责：读取配置、资源评估、筛选模型、下载执行、日志输出各自独立。
- 强化参数化：路径、阈值、策略、下载提供者可配置；支持标准 `-WhatIf`/`-Confirm`。
- 可测试：核心决策函数纯函数化，增加 Pester 覆盖主路径与边界条件。
- 一致日志：统一到信息/详细/警告/错误接口，`Write-Host` 仅用于最终结果摘要。

## 设计方案
- 结构重构：
  - 引入常量区：`$DEFAULTS = @{ CpuMaxModelGB = 8; MemoryMultiplier = 1.5; MinVramGB = 8 }`，集中策略（ai/downloadModels.ps1 顶部）。
  - 拆分函数：
    - `Get-ModelListFromConfig -ConfigPath`：加入参数验证与字段校验（ai/downloadModels.ps1:52–68 强化）。
    - `Test-ModelCanDownload -Model -GpuInfo -MemoryInfo -Policy`：去魔法常量，使用策略对象（ai/downloadModels.ps1:89–129 改造）。
    - `Select-EligibleModels -Models -GpuInfo -MemoryInfo -Policy`：封装筛选逻辑，返回可下载列表（新）。
    - `Invoke-ModelDownload -Models -Provider ollama`：下载执行，`[CmdletBinding(SupportsShouldProcess=$true)]` 支持 `-WhatIf/-Confirm`（ai/downloadModels.ps1:199–216 改造）。
    - `Write-Log -Level Info|Warn|Error|Verbose -Message`：统一输出（替代 `Write-ProgressMessage`，ai/downloadModels.ps1:28–39 合并）。
- 参数化与互斥：
  - 脚本入口 `param()` 添加：`-ConfigPath`、`-CpuMaxModelGB`、`-MemoryMultiplier`、`-MinVramGB`、`-Provider`（默认 `ollama`）、`-ListOnly`（与 `-WhatIf` 兼容）、`-Skip`（名称或ID数组）。
  - 使用 `ParameterSetName` 区分“仅列出”与“实际下载”。
- 配置校验：
  - 读取后校验每项：`name:string`、`modelId:string`、`size:number>0`、`vramRequired:number>=0`、`skip:boolean?`；缺失字段给出默认值与警告。
  - 若配置为空或无有效项，立即报错退出（ai/downloadModels.ps1:155–159）。
- 提供者抽象：
  - 定义轻量接口：`IModelProvider`（PowerShell 用函数组模拟）：`Test-CommandAvailable`、`Pull-Model -Id`、`Get-ModelSizeLimit`（可选）。
  - 先实现 `ollama` 提供者；未来可扩展到 `vllm`/`local-api` 等。

## 代码级改动清单
- 顶部加入 `Set-StrictMode -Version Latest` 与常量字典，统一策略引用。
- `Get-ModelListFromConfig`：加入 `-ConfigPath` 参数与字段完整性校验，`-ErrorAction Stop` 与 `try/catch` 细化错误消息。
- `Test-ModelCanDownload`：移除硬编码，改为使用 `-Policy`；macOS“统一内存”处理迁移至资源预处理阶段并可关闭/开启。
- 新增 `Select-EligibleModels`：负责合并 skip 与资源规则，输出 `PSCustomObject` 列表，便于后续统计与测试。
- `Invoke-ModelDownload`：实现 `SupportsShouldProcess`、失败重试（最多3次，指数退避），统计成功/失败。
- 统一日志：`Write-Log` 封装到 `Write-Host/Write-Verbose/Write-Warning/Write-Error`，入口通过 `-Verbose` 控制详细级别。

## 配置与数据校验
- 当 `size` 缺失：使用策略默认值并 `Write-Warning`。
- 当 `vramRequired` 缺失：根据 `size` 推导简单估算（如 `max(4, [int](size/2))`），并提示估算来源。
- 当 `skip` 存在：支持脚本 `-Skip` 额外输入合并。
- 输出计划列表时，支持 `-OutputPath` 导出为 JSON 供审阅与复用。

## 日志与输出
- 开始/资源/计划/下载/总结五段式输出；颜色仅用于最终摘要与关键提示，其余走 `Write-Information/Verbose`。
- 错误与警告明确区分：配置错误、资源不足、命令不可用（如 `ollama` 不可用则直接错误并提供安装提示）。

## 测试方案（Pester）
- 新建 `tests/downloadModels.Tests.ps1`，覆盖：
  - macOS 统一内存路径（ai/downloadModels.ps1:143–148）。
  - CPU 模式 8GB 限制与内存倍数策略（ai/downloadModels.ps1:113–121）。
  - skip 合并规则与 `ListOnly` 计划列表编制（ai/downloadModels.ps1:173–233）。
  - AMD 显存估算与 NVIDIA 检测分支（psutils/modules/hardware.psm1:96–137, 23–41）。
  - 提供者不可用时的错误处理与安装提示。

## 验证方式
- 使用 `-ListOnly -Verbose` 在三种环境模拟：`HasGpu=true/false`、不同内存档位，确认筛选结果与日志。
- `-WhatIf` 验证下载阶段不会执行但会显示计划与确认提示。
- 统计结果与导出计划 JSON比对，确保成功/跳过计数一致。

## 迁移与兼容
- 保持现有 `models.json` 格式兼容；新增字段按可选处理。
- 入口参数默认与现状一致，仅增强可选项，不破坏现有使用方法。

## 后续扩展
- 增加 `-Parallel`（限流并发下载，线程数可配）。
- 增加缓存与断点续传提示（若提供者支持）。
- 将脚本功能沉淀为 `psutils` 子模块，供其他脚本复用。

如确认以上方案，我将开始执行重构并补充测试，分阶段提交改动与验证结果。