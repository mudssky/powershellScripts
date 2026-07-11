# 修复 GitHub Actions (Pester Test) 全部报错

## 诊断结论

最近 3 次 `Pester Test` 运行在 **windows-latest** 上失败（macOS 全过、Node Vitest 1 项失败）。失败的根因可分成 4 类、共 13 个失败点，全部是 `e7dd930 feat(windows): 增加 Windows 安装流水线` 之后新增、且从未在 Windows CI 验证过的内容：

### 根因 A — 行尾符/哈希不一致（2 个 Pester 失败）
`.gitattributes` 只为 `*.ps1` 强制 `eol=lf`。GitHub Windows runner 默认 `core.autocrlf=true`，会把未声明 eol 的文本文件（`.psm1`/`.psd1`/`.env`/`.wslconfig`）检出成 CRLF：
- `远程 bootstrap manifest 覆盖最小资产且 hash 全部匹配`（`WindowsInstallPipeline.Tests.ps1:158`）：哈希是按本地 LF 内容算的，runner 上 CRLF 内容 → SHA256 不匹配。
- `Windows 11 22H2 配置与仓库模板一致`（`WindowsInstallPipeline.Tests.ps1:137`）：`ConvertTo-WindowsWslConfigContent` 用 `` `n ``(LF) 拼接，而 `Get-Content -Raw` 读到 CRLF 文件 → 字符串不同。

**修复**：扩展 `.gitattributes`，用 `* text=auto eol=lf` 对所有文本强制 LF（git 自动识别二进制，不误伤）。同时让本地与所有平台 checkout 行为一致。

### 根因 B — 09/WSL 管理员守卫未受 WhatIf 门控（2 个 Pester 失败）
`windows/09deployAutoHotkey.ps1:63` 和 `windows/wsl/Initialize-WslHost.ps1:70` 的 `if ($platform.IsAdministrator) { exit 10 }` 是**无条件**的，不像 05/06/08（`windowsInstall.psm1` 叶子脚本 line 37）用 `if (-not $WhatIfPreference -and ...)` 门控。GitHub windows-latest 以管理员（`runneradmin`）运行，所以 `-WhatIf` 仍触发 `exit 10`。
- `Core、字体、Full 和 AutoHotkey 叶子 WhatIf 不执行真实安装`（`WindowsInstallPipeline.Tests.ps1:206`，09 case 失败）
- `WSL WhatIf 不写配置也不调用 shutdown`（`WindowsInstallPipeline.Tests.ps1:221`）

规范 `.trellis/spec/infra/windows-install-pipeline.md` 明确："ARM64 或 Server 真实安装 → Blocked/10；**WhatIf/fixture 可生成计划**"。所以 WhatIt 下应放行。

**修复**：把 09/WSL 的管理员守卫改为 `if (-not $WhatIfPreference -and $platform.IsAdministrator) { ...; exit 10 }`，与 05/06/08 的平台守卫风格一致。

### 根因 C — managed-env adapter 在原生 Windows 上 throw（8 个 Pester 失败）
`brew`/`npm`(部分路径) 目标走 `ManagedEnvAdapter`，它在 `scripts/pwsh/misc/package-sources/adapters/ManagedEnvAdapter.psm1:208` 无条件 `throw 'managed-env shell adapter 暂不支持原生 Windows'`。该 adapter 写 `.zshrc`、设 `UnixFileMode`、`SHELL='/bin/zsh'`，本质只能跑在非 Windows。这 8 个测试在 macOS 全过、在 Windows 全挂：
- `PackageSources.Tests.ps1`: 325、366、413、467、559、596（Describe @202）；884、927（Describe @764）

**修复**：按本仓库既有约定给这 8 个 `It` 加 Windows 跳过。参照 `tests/PackageSourceBootstrap.Tests.ps1:75`（同 feature 区、同语义）和 `tests/LinuxInstallPipeline.Tests.ps1:475` 的 `It ... -Skip:(-not $IsLinux)` 写法，用 `-Skip:$IsWindows`。**不改 adapter 行为**（throw 是正确的，真实 Windows 用户本就不该走该 adapter）。

### 根因 D — homebrew.sh 命中 CI 预装的 Linuxbrew（1 个 Vitest 失败）
`shell/shared.d/homebrew.sh` 候选顺序把系统级 `/home/linuxbrew/.linuxbrew` 排在 `$HOME/.linuxbrew` 前。`ubuntu-latest` runner 预装了真 Linuxbrew，所以测试 `loads Linuxbrew from the managed shell fragment`（`linux-install-pipeline.test.ts:282`）在临时 HOME 伪造的 brew 被系统路径抢先。
- 本仓库已有 `POWERSHELL_SCRIPTS_FORCE_MISSING_*` 约定（apt/git/pwsh/brew-installer 共 4 个），`linux/01installHomeBrew.sh:34,40` 已支持 `POWERSHELL_SCRIPTS_FORCE_MISSING_BREW=1`，但 `homebrew.sh` 没有。

**修复**：给 `homebrew.sh` 加 `POWERSHELL_SCRIPTS_FORCE_MISSING_BREW=1` 短路（与安装器一致），并在该测试的 `execa` env 里经 `linuxEnv(workspace, { POWERSHELL_SCRIPTS_FORCE_MISSING_BREW: '1' })` 传入，使只认临时 fixture。

---

## 具体改动清单

1. **`.gitattributes`**（根因 A）
   - 把规则改为 `* text=auto eol=lf`（并保留/合并已有的 3 条显式规则）。git 自动识别二进制不转 CRLF。

2. **`windows/09deployAutoHotkey.ps1:63`**（根因 B）
   - `if ($platform.IsAdministrator) {` → `if (-not $WhatIfPreference -and $platform.IsAdministrator) {`

3. **`windows/wsl/Initialize-WslHost.ps1:70`**（根因 B）
   - `if ($platform.IsAdministrator) {` → `if (-not $WhatIfPreference -and $platform.IsAdministrator) {`

4. **`tests/PackageSources.Tests.ps1`**（根因 C，8 处）
   - 给 8 个 `It` 加 `-Skip:$IsWindows`：325、366、413、467、559、596、884、927 行的 `It '...' {` → `It '...' -Skip:$IsWindows {`

5. **`shell/shared.d/homebrew.sh`**（根因 D）
   - 在候选循环前加 `[ "${POWERSHELL_SCRIPTS_FORCE_MISSING_BREW:-}" = '1' ] && { unset ...; return 0 2>/dev/null || true; }` 风格的短路（被 source 时用 `return`，注意该文件被 source，用 `return 0`）。

6. **`scripts/bash/tests/linux-install-pipeline.test.ts:288-295`**（根因 D）
   - 给该测试的 `execa` env 增加 `POWERSHELL_SCRIPTS_FORCE_MISSING_BREW: '1'`（经 `linuxEnv(workspace, {...})`）。

## 验证步骤
- 本机执行 `pnpm test:pwsh:all`（macOS 上应全绿；PackageSources 的 8 个 Windows-skip 在 macOS 不触发，`-Skip:$IsWindows` 在 macOS 为 false 正常跑）。
- 执行 `pnpm test`（含 Vitest），确认 linux-install-pipeline 那个用例在本地 macOS 仍绿（本地无 `/home/linuxbrew`，加 FORCE_MISSING 后行为不变）。
- 执行 `pnpm qa`。
- 提交后由 CI 在 windows/ubuntu/macos 三平台复跑确认。

## 备注
- 全部为代码/测试改动，会执行 `pnpm qa`、`pnpm test:pwsh:all`、`pnpm test`。
- 不改 adapter 的 throw 行为（属正确语义），不改 homebrew.sh 的真实候选顺序（系统级 prefix 是规范要求）。