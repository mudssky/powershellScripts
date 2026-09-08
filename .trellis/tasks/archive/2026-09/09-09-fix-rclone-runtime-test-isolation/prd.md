# 修复 RcloneOps 测试对仓库真实 .runtime 路径的写依赖（host/docker lane 冲突）

## Goal

消除 `tests/RcloneOps.Tests.ps1` 对仓库内真实路径 `config/service/oss/rclone/.runtime/` 的写依赖，使 `pnpm test:pwsh:all` 的 host lane（mudssky）与 linux 容器 lane（root，bind mount 同一仓库）可以并发/先后运行而不互相污染。

## Reproduction（2026-09-09 实证）

1. docker lane（root）运行时，被测脚本在仓库真实路径创建 `config/service/oss/rclone/.runtime/webui.pid`，目录属主变为 root:root 755 并随 `--rm` 容器退出残留在 bind mount 里。
2. host lane（mudssky）运行"停止 WebUI 时会清理过期 PID 文件"用例时，无法在该 root 属主目录下创建/删除 pid 文件 →
   `UnauthorizedAccessException: Access to the path '.../rclone/.runtime/webui.pid' is denied`（`tests/RcloneOps.Tests.ps1:288`），host lane 整体 exit 1。
3. 移除 root 目录后单跑该文件 17/17 通过——失败纯由跨 lane 目录属主污染触发。

## Root Cause

测试通过真实仓库路径（而非 TestDrive/重定向）写入被测脚本的运行时状态目录；该路径同时被 docker lane 以 root 身份使用，产生属主冲突。属于测试隔离缺陷，不是被测脚本缺陷。

## Requirements

- `tests/RcloneOps.Tests.ps1` 涉及 `.runtime/webui.pid` 的用例改为隔离写法：优先把运行时目录重定向到 `$TestDrive`（若被测函数支持路径参数/env 重定向，跟随仓库既有测试的重定向模式）；不支持重定向时，用例内对真实路径做"创建→验证→清理 + 兜底恢复属主"的严格自清理。
- 不改变 `rclone-ops.ps1` 生产行为。
- 修复后 host 与 docker lane 无论谁先谁后、是否交错，该文件均绿。

## Acceptance Criteria

- [x] 模拟污染场景：先以 root（容器内）触发一次目录创建，再以普通用户跑 `tests/RcloneOps.Tests.ps1` → 通过（implement 阶段 17/17）。
- [x] `pnpm qa` 通过（Pester 219/0，vitest 112 通过）。
- [x] `pnpm test:pwsh:all` host 与 linux 两 lane 同时全绿（host 945/0，linux 943/0，exit 0）。

## Notes

- 发现于 09-09 两任务修复后的 `test:pwsh:all` 统一验收阶段；临时补救（删除 root 目录）已执行，仓库文件无残留改动。
