# Package Source 事务与 Adapter 规范

> 本规范记录 `Switch-Mirrors.ps1`、Stage 0 helper、target catalog、事务 manifest 与 shell 受管环境文件之间的可执行合同。

## Scenario: 跨平台安装前准备 package source

### 1. Scope / Trigger

- Trigger: 修改 `config/network/package-sources*`、`scripts/pwsh/misc/Switch-Mirrors.ps1`、`scripts/pwsh/misc/package-sources/**`、`Invoke-PackageSourceBootstrap.ps1`、`scripts/bash/package-source-bootstrap.sh` 或 `shell/shared.d/package-sources.sh`。
- Scope: macOS、Windows、Linux/WSL 安装链的 source 计划、应用、补应用、状态与恢复；字体、CLI、Profile 等叶子安装脚本不拥有镜像 URL。
- Design intent: 官方网络正常时零写入；需要国内镜像时集中应用，并且只恢复本仓库实际修改的资源。

### 2. Signatures

Stage 1 公共入口：

```powershell
./scripts/pwsh/misc/Switch-Mirrors.ps1 `
  -Action Plan|Apply|Ensure|Status|Restore `
  -Mode Direct|China|Auto `
  -Phase Bootstrap|Runtime|Toolchain|Optional `
  -Target <string[]> `
  -TransactionId <string> `
  -Selection Auto|First|<provider> `
  -OutputFormat Text|Json `
  [-WhatIf] [-Force]
```

Stage 0 入口：

```bash
./scripts/bash/package-source-bootstrap.sh \
  --mode Direct|China|Auto --target brew [--dry-run] -- command args...
```

```powershell
powershell.exe -NoProfile -File ./scripts/pwsh/misc/Invoke-PackageSourceBootstrap.ps1 `
  -Action Run|Status|Restore `
  -Mode Direct|China|Auto `
  -Target winget `
  [-DryRun] [-FilePath <command>] [-ArgumentList <string[]>]
```

稳定 JSON result 字段：`Target`、`Mode`、`Phase`、`Adapter`、`Status`、`Source`、`Persistent`、`TransactionId`、`Message`、`Rollback`。

状态目录：

- macOS/Linux：`${XDG_STATE_HOME:-$HOME/.local/state}/powershellScripts/package-sources/`
- Windows：`$env:LOCALAPPDATA\powershellScripts\package-sources\`

### 3. Contracts

- `Direct` 是默认模式：不探测、不创建事务、不修改或重置现有 source。
- `China` 创建持久事务；重复 Apply 复用最初 snapshot；保持到显式 Restore。
- `Auto` 保留健康官方源和健康外部自定义源；官方源连续失败时才创建临时事务，根编排器必须在 `finally`/`trap` 中 Restore。
- `Plan` 和 `Status` 只读；写动作搭配 `-WhatIf` 必须降级为 `Plan`/`Status`，不能依赖未调用的 `ShouldProcess` 自动保护。
- Restore 先比较当前 hash 与 after hash：相同才恢复；drift 返回 10。已恢复事务再次 Restore 必须幂等返回成功。
- chsrc 的最低版本来自 catalog，当前为 `0.2.5`；版本、target capability、scope 和 option 顺序必须在 adapter 外层校验。
- macOS/Linux 的 `brew` 与跨平台 `rustup` 使用 managed-env adapter：chsrc 只写隔离 HOME，adapter 只提取 catalog 白名单 HTTPS 变量，禁止修改真实 shell rc。
- `npm`、`pnpm`、`pip`、`go` 使用 chsrc command adapter；`debian`、`ubuntu`、`arch` 使用系统文件 snapshot；Docker 使用仓库自有 JSON adapter。
- `winget` Stage 1、`uv`、Cargo、Nix 在可靠结构化恢复实现前返回 Unsupported；不得写猜测性配置。
- Windows Stage 0 只使用 `Microsoft.WinGet.Client` 结构化 cmdlets，首次 snapshot 不得被 China 重跑覆盖，成功 Restore 后删除 snapshot。
- `shell/shared.d/package-sources.sh` 只允许 Homebrew/rustup 已知变量和 HTTPS 值，不能 `eval`、`source` 或导出任意变量名。
- 新机顺序固定为：package manager -> PowerShell 7/chsrc bootstrap -> Stage 1 sources -> CLI/fonts/profile。macOS 物理编号为 `02 pwsh`、`03 sources`，避免 source 引擎依赖自身尚未安装的运行时。
- 未实现 Linux 原生 Stage 0 系统源 adapter 时，PowerShell 7/chsrc 前的 China/Auto 必须返回 Blocked，不能静默回退 Direct。
- 默认 QA 仅使用临时 HOME、伪命令和 fixture；真实 China/Auto Apply 必须获得单独明确批准。
- PackageSources Pester 只保留参数、JSON/退出码、`-WhatIf` 和 legacy Docker 的少量 CLI 子进程合同；事务、drift、orphan、Auto 和 adapter 行为直接调用 `Invoke-PackageSourceAction`。
- 进程内测试默认将 `PackageSources`/`DockerAdapter` 内的 `Invoke-WebRequest` Mock 为失败；需要探活的用例必须显式覆盖并断言调用。
- Linux Pester 容器的 `/tmp` 为 `noexec`；Bash 伪命令必须放到仓库内 `tests/.tmp-executables/` 的唯一临时目录，并在 `AfterAll` 清理。状态、HOME 和配置 fixture 仍放在 `$TestDrive`。
- 统一 Pester 配置只将 `Remove-Item:ProgressAction` 默认为 `SilentlyContinue`，避免 PowerShell 7.5 的 `Removed x of y files` TestDrive 清理进度干扰断言查看；不得全局禁用 `$ProgressPreference` 或丢弃 stdout。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| 未传 Mode | 等价 `Direct`，零探测、零写入 |
| 非 Direct 的 Plan 遇到未实现 adapter | `Unsupported`，退出 10，不创建事务 |
| chsrc 缺失或低于 catalog 下限 | `Blocked`，退出 10，不创建事务 |
| Auto 遇到健康 unmanaged source | `External`，保持不变 |
| Auto 遇到不可用 unmanaged source | `ExternalUnavailable`，退出 10，拒绝覆盖 |
| China 重复 Apply 同一 active transaction | `AlreadyApplied`，不再次调用 adapter |
| Restore 时 current hash 不等于 after hash | `Drifted`/`Blocked`，退出 10，保留当前文件 |
| 已 Restored 事务再次 Restore | 返回成功，不重复写文件 |
| Auto adapter 应用失败 | 立即恢复已修改资源；恢复失败标记 `RestoreFailed` |
| Auto owner 已退出 | Status 为 `Orphaned` 且退出 10；下次 Auto Apply 先恢复 |
| `Apply -WhatIf` 或旧 Docker `-WhatIf` | 只返回计划，不创建状态目录 |
| 参数组合缺少 Target/TransactionId | `InvalidArguments`，退出 2 |
| Windows Stage 0 缺管理员或结构化 cmdlets | `Blocked`，退出 10，不解析表格文本 |

### 5. Good/Base/Bad Cases

- Good: macOS China 模式先用 Stage 0 helper 包装 PowerShell 安装，再由 `03configureSources` 创建事务，后续 npm 出现时用 Ensure 补应用。
- Good: Auto 编排器保存 transaction ID，并在成功、失败和可捕获中断的 `finally` 中 Restore。
- Base: Direct 模式仍运行 source 步骤并输出结构化 no-op，便于统一汇总。
- Bad: 在字体、CLI 或 Profile 脚本中硬编码镜像 URL。
- Bad: 用 chsrc 直接修改真实 `~/.zshrc`、覆盖完整 Cargo/uv TOML，或用 `nix-channel` 冒充 flake substituter。
- Bad: 只看 manifest 不校验当前文件 hash，或 Restore 时粗暴 reset 用户后来修改的配置。

### 6. Tests Required

- Pester：Direct 零写入、China snapshot/幂等/重复 Restore、Auto Official/External/ExternalUnavailable、orphan、drift、锁与低版本 chsrc。
- Pester：JSON stdout 单文档、参数退出 2、Unsupported 退出 10、旧 Docker 兼容参数与模块级 Web mock。
- Pester：Windows Stage 0 保持 PowerShell 5.1 可解析；真实 WinGet source 行为由 Windows runner smoke test 验证。
- Pester：新增网络调用时，未显式覆盖的请求必须由默认失败 Mock 拦截，禁止依赖开发机联网状态。
- Benchmark：`pnpm benchmark -- package-sources-test -Iterations 3 -AsJson` 输出平台、PowerShell 版本、样本、平均值、中位数和最慢值；CI 只验证微型 fixture 输出合同，不设绝对耗时门槛。
- Vitest：POSIX Stage 0 的 Direct/China/Auto 环境作用域；bash/zsh shell loader 只加载白名单 HTTPS export 且不执行任意内容。
- Shell：`bash -n` 与 `zsh -n` 均通过。
- 项目门禁：`pnpm test:bash`、`pnpm test:pwsh:all`、`pnpm qa`。
- 默认测试不得访问真实镜像或修改本机 package source。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 叶子安装脚本直接覆盖用户 npm 配置，既无 snapshot，也无法处理 drift。
npm config set registry https://mirror.example/npm/
Install-PackageManagerApps -Tag core
```

#### Correct

```powershell
$source = ./scripts/pwsh/misc/Switch-Mirrors.ps1 `
    -Action Apply `
    -Mode China `
    -Target npm `
    -TransactionId core-sources `
    -OutputFormat Json | ConvertFrom-Json

if ($source.ExitCode -ne 0) {
    throw 'npm source 未准备完成，停止依赖网络的安装步骤'
}

Install-PackageManagerApps -Tag core
```

理由：镜像选择、snapshot、验证、状态和回滚集中在统一引擎；叶子脚本只消费已准备好的 target。
