# 网络与镜像源技术设计

## 目标与边界

本任务提供跨平台 package source 的统一策略、状态、事务和 adapter 接口。平台安装脚本只声明网络模式与目标，不保存镜像 URL，也不自行备份或恢复 source。

本任务不安装业务软件、不搭建镜像站、不接管本地代理。Nix flake/substituter 由 Nix 子任务按本设计的事务接口接入，不使用 chsrc 的 `nix-channel` 行为冒充完整 Nix 方案。

## 分层架构

```text
Stage 0 native adapter
  -> 解决 Git/平台包管理器/PowerShell/chsrc 的 bootstrap source
  -> 写入统一 transaction manifest

Stage 1 Switch-Mirrors.ps1
  -> 读取策略与 target catalog
  -> chsrc capability adapter / dedicated adapter
  -> snapshot -> apply -> verify -> status
  -> China: 保持 active，等待 Restore
  -> Auto: root orchestrator finally 中 Restore
```

chsrc 是主要换源执行器，但统一状态、事务与恢复由仓库掌握。Stage 0 在 chsrc 尚未安装时使用极小的原生 adapter；chsrc 可用后再处理公共语言生态 target。

## 文件边界

- `config/network/package-sources.json`
  - target、平台、阶段、adapter 类型、官方探测端点、所需命令、恢复能力和可选 chsrc target。
  - chsrc 已内置的镜像 URL 不复制到此文件。
- `config/network/package-sources.bootstrap.env`
  - 只保存 Stage 0 无法通过 chsrc 获得的少量、非敏感、HTTPS 地址。
  - POSIX 与 Windows PowerShell 5.1 helper 只解析受限的 `KEY=VALUE` 子集；Stage 1 再通过共享 config resolver 读取。
- `scripts/pwsh/misc/Switch-Mirrors.ps1`
  - 保留现有公共入口，扩展为 `Plan|Apply|Status|Restore|Ensure`。
  - 兼容旧 Docker 参数并输出迁移提示。
- `scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1`
  - 保持 Windows PowerShell 5.1 兼容，只处理 Windows Stage 0 所需 source。
  - 不加载 PowerShell 7 模块，也不复制 Stage 1 的 target 选择逻辑。
- `scripts/pwsh/misc/package-sources/PackageSources.psm1`
  - target 选择、事务、snapshot、drift 检测、adapter 调用和结构化结果。
- `scripts/pwsh/misc/package-sources/adapters/*.psm1`
  - chsrc、managed-env、native-command、Docker 和后续 Nix adapter。
- `scripts/bash/package-source-bootstrap.sh`
  - POSIX Homebrew Stage 0 helper，只为被包装命令注入进程级环境；进程结束即恢复，因此不创建持久 manifest。
- 平台 `03configureSources.*`
  - 由 macOS、Windows、Linux/WSL 子任务创建并保持薄包装，只传 mode、phase、targets、transaction id 和 preview 参数。
  - 本任务只提供调用合同、示例和测试 fixture，不提前创建平台编号脚本。

## 命令接口

PowerShell 入口：

```powershell
./scripts/pwsh/misc/Switch-Mirrors.ps1 `
  -Action Plan|Apply|Status|Restore|Ensure `
  -Mode Direct|China|Auto `
  -Phase Bootstrap|Runtime|Toolchain `
  -Target <string[]> `
  -TransactionId <string> `
  -Selection Auto|First|<provider> `
  -OutputFormat Text|Json `
  -WhatIf
```

行为：

- `Plan`：只解析 target、探测条件与将修改的配置，不写入。
- `Apply`：创建或复用事务并应用当前 phase 可用 target。
- `Ensure`：工具安装后按事务意图补应用 deferred target，不重新随机选择已健康 source。
- `Status`：只读输出当前 source、事务状态、drift 和回滚入口。
- `Restore`：只恢复指定事务中由本仓实际修改且未发生 drift 的 target。
- `Status` 与 `Restore` 不要求 `Mode`；`Restore` 必须显式给出 transaction id，不自动猜测 latest active transaction。
- 公共入口在任何写入前校验 `Plan`、`Apply`、`Ensure`、`Status`、`Restore` 的必需参数与非法组合，参数错误返回 2。

结构化结果至少包含 `Target`、`Mode`、`Phase`、`Adapter`、`Status`、`Source`、`Persistent`、`TransactionId`、`Message`。

`Text` 为人工默认输出；`Json` 模式只在 stdout 输出一个稳定 JSON document，诊断日志写入 stderr，供 POSIX helper、平台 `03` 和根编排器可靠解析。

退出码沿用安装契约：0 成功/无需变更，1 执行或验证失败，2 参数错误，10 缺少权限、工具或发生需人工处理的 drift。

## 模式语义

### Direct

- 默认模式，不测速、不换源、不创建事务。
- 不重置用户已有自定义 source，也不自动恢复此前由 China 创建的事务；恢复必须显式执行。
- Status 仍可报告当前 source 是否由本仓管理。

### China

- 创建持久事务，按 target 应用国内镜像。
- 重复 Apply 复用 active transaction；已应用且验证健康的 target 不重新测速或改写。
- 保持到显式 Restore。新的 China provider 选择仍以原始 pre-China snapshot 为回滚基线。

### Auto

- 先读取实际 source；健康且未受本仓管理的自定义 source 标记为 `External` 并保持不变。
- 对官方或默认 source 的受控端点执行两次有界探测；默认单次 5 秒，任一探测成功即保持官方 source。
- 只有连续失败或超时的 target 才进入临时事务，不因单次延迟永久改源。
- root 编排器必须在 `finally` 中 Restore Stage 1 Auto 事务；POSIX Stage 0 的环境变量只存在于被包装子进程，Windows Stage 0 在 `finally` 中恢复结构化 snapshot。
- SIGKILL 或主机崩溃无法执行 trap；下一次 Status/Apply 检测 orphaned Auto transaction 并在开始新事务前恢复或返回 Blocked。

## 事务与状态

状态目录：

- macOS/Linux：`${XDG_STATE_HOME:-$HOME/.local/state}/powershellScripts/package-sources/`
- Windows：`$env:LOCALAPPDATA\powershellScripts\package-sources\`

每个事务目录包含：

```text
<transaction-id>/
  manifest.json
  snapshots/
  logs/
```

manifest 记录 schema version、mode、persistence、createdAt、status、tool/chsrc version 和 target 状态。配置原文不写入 manifest；可能包含 npm token 等敏感数据的文件只复制到权限受限的 snapshots。

manifest、catalog 派生状态和 adapter 写入采用同目录临时文件加原子替换。状态根目录使用跨平台独占锁；同一时刻只允许一个 Apply/Ensure/Restore 修改 source，Plan/Status 只能读取已完成的 manifest。

Unix 状态目录使用 0700、snapshot 使用 0600；Windows 使用当前用户 ACL。日志不输出配置全文、认证信息或环境变量 secret。

每个 target 记录：

- 修改前文件是否存在、路径、权限和 SHA-256。
- 修改后 SHA-256、adapter、实际 source 与验证结果。
- 恢复方式与是否需要提权/重启。

Restore 规则：

1. 当前 hash 等于事务 after hash：恢复 snapshot，或删除事务创建的新文件。
2. 当前 hash 已变化：标记 `Drifted`，默认拒绝覆盖并返回 10。
3. `-Force` 仅允许显式人工调用，仍先为 drifted 当前文件创建额外备份。
4. 恢复后重新读取 source，成功才把 target 标为 Restored。

## target 与阶段

| 阶段 | 目标 | 说明 |
|---|---|---|
| Bootstrap | Git fetch、Homebrew、winget、Ubuntu/Debian、Arch | chsrc 可能尚不可用，使用原生 adapter |
| Runtime | brew、winget、npm、pnpm、pip、uv、Cargo、rustup、Go | 优先 chsrc，按 capability 选择专用 adapter |
| Toolchain | 安装后才出现的 npm/pnpm/Cargo/Go 等 | `Ensure` 根据已有事务意图补应用，不重复测速 |
| Optional | Docker、Nix | Docker 保留自有 adapter；Nix 由 Nix 任务接入 |

不可用命令的 target 标记 `Deferred`，不是成功。依赖该 target 的安装步骤在使用前调用统一 `Ensure`；镜像逻辑仍集中在 engine，不复制到叶子脚本。

## chsrc adapter

- 使用稳定版，不默认安装 upstream `pre` 版本。
- 优先通过 Homebrew、Scoop、WinGet、AUR 安装；缺少系统包时允许使用仓库固定版本、架构与 SHA-256 的官方 release 资产。
- 禁止在 unattended 默认路径中直接 pipe 远程 installer 到 shell/PowerShell。
- 每次使用前检查版本、target 列表和 target capabilities；unsupported target 交给专用 adapter。
- 默认 `Selection=Auto` 时只在 target 首次应用时让 chsrc 测速选源，之后读取并验证已选 source；`First` 或 provider 可显式覆盖。
- 对 chsrc 会直接修改 shell rc、缺少 reset、只打印手工配置或与仓库现有机制冲突的 target，不直接调用 set。

## 专用 adapter

### Homebrew / rustup managed env

- 不允许 chsrc 直接写 `.zshrc`/`.bashrc`。
- adapter 写入 `~/.config/powershellScripts/package-sources.env`，修改前按时间戳备份并纳入事务。
- tracked `shell/shared.d/package-sources.sh` 只负责安全 source 该本机文件，不包含镜像 URL。
- Stage 0 写入后在当前进程立即 source；shell 部署后负责后续终端加载。

### Cargo

- 实施前基于目标 Cargo/chsrc 版本验证是否能可靠写入。
- 若仍需专用实现，只管理带明确 marker 的 TOML block，修改前备份并验证 `cargo search`/registry；不得用字符串覆盖整个用户 config。

### Docker

- 保留现有 `/v2/` 探活、200/401 判定、结构化 JSON 写入和重启提示。
- 将默认地址移到集中配置，接入统一 transaction/restore；不再同时让 chsrc 管理 Docker。

### Windows/Linux 系统源

- winget 使用 source 命令并记录原 source；Ubuntu/Debian、Arch 修改前备份系统配置并要求明确提权。
- Windows Stage 0 helper 必须能在 Windows PowerShell 5.1 运行；PowerShell 7 就绪后所有后续操作转交统一模块。
- 不支持或未验证的 Scoop、Chocolatey、PowerShell Gallery 只报告 Unsupported/Direct，不写猜测性镜像。
- 发行版识别与具体文件路径由对应 adapter 拥有，不在通用 engine 分支堆叠。

### Nix

- 仅定义 adapter 接口和事务格式。
- Nix 子任务按 flake/substituter/registry 当前机制实现，禁止调用 chsrc nix-channel 作为替代。

## 镜像与官方回退

- 只允许 HTTPS source；不允许跳过 TLS 校验。
- chsrc 内置镜像由 chsrc 维护；专用/Bootstrap 地址集中在配置文件并带 target、用途和验证端点。
- China 模式镜像不可用时返回失败/Blocked，不静默改回官方后继续并误报 China 已生效。
- Auto 模式镜像也不可用时恢复原 source；若官方端点仍不可用，依赖网络的后续步骤 Blocked。

## 兼容现有 Switch-Mirrors

旧调用继续可用：

- `-Target docker -UseChinaMirror` 映射为 `-Action Apply -Mode China -Target docker`。
- `-Disable` 映射为该 Docker 管理事务的 Restore。
- `-DryRun` 映射为 WhatIf/Plan。

兼容层只解析旧参数并调用新 engine，Docker 业务逻辑只有一个实现。

## 与统一编排器的合同

- 编排器把 mode 和 transaction id 传给 platform `03` 与后续 `Ensure`。
- China transaction id 写入最终汇总并显示 Restore 命令。
- Auto transaction 必须注册 finally restore；恢复失败使整体结果至少为 Blocked。
- source target 未应用或验证失败时，依赖该 target 的步骤不得继续安装并声称成功。

## 测试策略

- Pester 使用临时 HOME/LOCALAPPDATA、模拟 chsrc/native commands 和固定 probe 响应。
- 覆盖 Direct 零写入、China 幂等/Restore、Auto 成功清理/异常清理/orphan recovery、drift 拒绝、secret 不进日志。
- 现有 Docker 测试迁移到 adapter 层并保留 200/401、不可达、dry-run 不写测试。
- CI 默认不访问真实镜像；live probe 独立为显式诊断命令，不纳入确定性 QA。
- POSIX helper 在 bash/zsh 下验证参数、dry-run、trap 和 manifest 兼容。
- Windows Stage 0 helper 在 Windows PowerShell 5.1 兼容语法下验证 Direct/China/Auto、preview 和失败退出码。
- JSON 输出使用 schema fixture 验证，避免日志混入 stdout 或下游依赖临时属性。

## 安全与回滚

- 不执行未固定版本/未校验来源的远程安装脚本。
- 不把 auth token、完整 npmrc/pip config 内容写进日志或 manifest。
- 不用 Restore 粗暴 reset 用户配置；只恢复本仓事务 snapshot。
- 任何 drift、权限不足、adapter capability 不匹配都返回 Blocked，由用户决定是否 Force。
