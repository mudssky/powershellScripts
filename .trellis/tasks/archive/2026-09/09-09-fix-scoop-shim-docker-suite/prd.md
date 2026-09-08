# 修复 docker 套件中 Windows scoop shim 测试失败

## Goal

修复 `pnpm test:pwsh:all`（docker 套件）中 `Windows 声明式 package catalog.Windows 验证 JSON 不包含 Scoop Information stream` 稳定失败的问题，使全量测试在 Linux CI/容器环境恢复绿色。宿主机 `pnpm qa` 下同一测试通过，仅容器环境失败。

## Reproduction

- `docker compose -f docker-compose.pester.yml run --rm pester-full ...`（`test:pwsh:all` / `test:pwsh:linux:full`）稳定失败。
- 失败点：`tests/WindowsInstallPipeline.Tests.ps1:386` 附近，`$result.ExitCode | Should -Be 0`。
- 底层错误：`windows/pwsh/Test-InstallState.ps1:173` 执行 `& scoop list` 时
  `Program 'scoop' failed to run: ... start process '/tmp/Pester_*/scoop-shim/scoop' ... No such file or directory`。
- 已验证与工作区改动无关：stash 后在干净 master（c10f43b6）容器内复跑同样失败（27 passed / 1 failed）。

## Suspected Root Cause

测试在临时目录创建 scoop shim 供 Linux 容器内执行；PowerShell 在 Linux 上启动外部"脚本"进程依赖可执行位与 shebang。报错 `No such file or directory` 出现在 start-process 阶段，典型为 shim 缺少执行位/解释器声明，或 shim 写入时机早于 PATH 探测但内容为空。需阅读该测试的 shim 构造代码与 `windows/pwsh/Test-InstallState.ps1` 的 `HasScoop` 分支确认。

## Root Cause（已实证，2026-09-09）

- **结论：不是 shim 构造问题，而是容器 `/tmp` 挂载 `noexec`。**
- `docker-compose.pester.yml` 对两个服务声明了 `tmpfs: - /tmp`。Docker 对 `--tmpfs` 的默认挂载选项含 `noexec`（容器内 `findmnt /tmp` 实测为 `rw,nosuid,nodev,noexec,relatime`）。
- Pester `$TestDrive` 位于 `/tmp/Pester_*`，`tests/WindowsInstallPipeline.Tests.ps1` 的用例在 `$TestDrive/scoop-shim/scoop` 写入带 `#!/usr/bin/env sh` shebang 并 `chmod +x` 的 shim（构造本身正确，WSL 宿主机可执行）。但 noexec 挂载下 `execve` 一律失败，pwsh/.NET 将启动失败包装为误导性的 `No such file or directory`。
- 容器内对照实验：
  - 同一 shim（exec 位 + shebang 均正确）放 `/tmp` → 启动失败，报错与套件失败完全一致；
  - 同一 shim 放 `/workspace`（ext4 bind mount，无 noexec）→ 执行成功。
- **修复**：compose 中显式声明 `tmpfs: - /tmp:exec`（fast 与 full 两个服务），保留 Docker 其余默认选项（rw,nosuid,nodev）。测试代码与 `windows/pwsh/Test-InstallState.ps1` 均未改动。

## Requirements

- 容器环境下该测试稳定通过，或在确认其语义只属于 Windows 宿主时以仓库认可的 skip 标记显式跳过（不得静默失败）。
- 不改变 `windows/pwsh/Test-InstallState.ps1` 在真实 Windows 上的行为。

## Acceptance Criteria

- [x] `pnpm test:pwsh:all` 全绿（2026-09-09 统一验收：host 945/0，linux 容器 943/0，exit 0）。
- [x] 失败机理在 PRD 或 spec 中留档（shim 构造、Linux 进程启动约束；见 Root Cause 段）。

## Notes

- 发现于任务 `09-09-fix-verify-containskey-noninteractive` 的全量验证阶段。
