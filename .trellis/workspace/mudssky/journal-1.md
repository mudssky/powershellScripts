# Journal - mudssky (Part 1)

> AI development session journal
> Started: 2026-05-07

---



## Session 1: 拆分 pnpm workspace 包边界

**Date**: 2026-05-08
**Task**: 拆分 pnpm workspace 包边界
**Package**: node-script
**Branch**: `master`

### Summary

按 QA/语言域拆分 workspace 与 Trellis package/spec 边界；新增 bash、pwsh、psutils 包声明与各包规范文档。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1e612a9` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 2: 修复 rclone Vitest 空测试套件

**Date**: 2026-05-08
**Task**: 修复 rclone Vitest 空测试套件
**Package**: bash-scripts
**Branch**: `master`

### Summary

将 rclone 旁路测试切换到 Vitest API，固定被导入 shebang 脚本 LF 行尾，并补充 Node/Vitest 脚本测试规范。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `3911093` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 3: rathole 配置模板与维护脚本

**Date**: 2026-05-13
**Task**: rathole 配置模板与维护脚本
**Branch**: `master`

### Summary

新增 config/network/rathole 裸二进制 + PM2 模板、白名单转发文档和 start.ps1 维护脚本；记录 infra 约定，并按配置/文档不测原则移除模板内容断言，只保留 start.ps1 逻辑测试。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `38dd0f9` | (see git log) |
| `3c9b174` | (see git log) |
| `4a77e6f` | (see git log) |
| `8c72b5a` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 4: GitHub CLI download installer

**Date**: 2026-05-17
**Task**: GitHub CLI download installer
**Branch**: `master`

### Summary

Implemented a cross-platform PowerShell GitHub Release CLI downloader and installer with JSON config, example betterleaks config, tests, and full PowerShell QA.

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ea4044c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 5: 拆分 skills 安装器私有模块

**Date**: 2026-05-21
**Task**: 拆分 skills 安装器私有模块
**Branch**: `master`

### Summary

修复 skills 安装器外部命令与已安装检查语义，抽取 psutils 通用执行、配置对象与路径解析 helper，并将 Install-Skills.ps1 的领域逻辑拆分到 ai/skills/private 私有脚本。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `c1291c1` | (see git log) |
| `f2b24b6` | (see git log) |
| `a5e11df` | (see git log) |
| `b6faff8` | (see git log) |
| `ea21a8d` | (see git log) |
| `4134cab` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 6: 归档 rclone、内存诊断与 Claude profile 任务

**Date**: 2026-05-27
**Task**: 归档 rclone、内存诊断与 Claude profile 任务
**Branch**: `master`

### Summary

归档已完成的 rclone WebUI 自动挂载、内存异常诊断脚本、Claude Code 多 key 切换工具三个 Trellis 任务。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `dd811b0` | (see git log) |
| `5cf6840` | (see git log) |
| `3a82adc` | (see git log) |
| `7506acd` | (see git log) |
| `bd0966c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 7: LiteLLM claw agent fallback

**Date**: 2026-05-28
**Task**: LiteLLM claw agent fallback
**Branch**: `master`

### Summary

新增 claw-plan / claw-glmplan-5.1 OpenAI 兼容入口与 DeepSeek v4 flash 最大思考兜底，更新 LiteLLM 配置、环境变量示例、文档和网关规范，并完成本地 smoke 验证。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `1eff4c5` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 8: 创建仓库运维 Skill

**Date**: 2026-05-28
**Task**: 创建仓库运维 Skill
**Branch**: `master`

### Summary

新增 repo-ops skill，覆盖 LiteLLM、LobeHub、项目依赖安装和后续 skill 维护流程，并完成校验与 QA。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `dec8040` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 9: 整理 Hermes 官方安装目录

**Date**: 2026-05-28
**Task**: 整理 Hermes 官方安装目录
**Branch**: `master`

### Summary

按官方布局恢复 Hermes 程序目录，使用仓库内 HERMES_HOME 保存本地状态，补充 ignore、README 和 infra spec。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `996aa6e` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 10: Hermes 本地私有仓库管理

**Date**: 2026-05-28
**Task**: Hermes 本地私有仓库管理
**Branch**: `master`

### Summary

将 ai/agents/hermes 调整为主仓库忽略、Hermes 目录自持本地私有 git 仓库的布局；初始化 Hermes 私有仓库并提交首版配置与技能快照。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `3a970d2` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 11: macOS 内存诊断与 pwshfmt 回退修复

**Date**: 2026-05-30
**Task**: macOS 内存诊断与 pwshfmt 回退修复
**Branch**: `master`

### Summary

优化 macOS memory-diagnostics 输出，补充 memory_pressure、压缩内存、Docker Desktop VM 上限和建议规则；修复 pwshfmt-rs strict fallback 通过 PowerShell 适配层递归调用自身的问题。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `c03da80` | (see git log) |
| `f5a3c4d` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 12: 数据库查询技能开发

**Date**: 2026-05-31
**Task**: 数据库查询技能开发
**Branch**: `master`

### Summary

新增 database-query skill，包含统一 CLI、SQL guard、上下文发现、凭据桥接、底层客户端文档与安装提示，并归档相关 Trellis 任务。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `ee9ae9f` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 13: 创建通用整理分类技能

**Date**: 2026-05-31
**Task**: 创建通用整理分类技能
**Branch**: `master`

### Summary

新增 organize-classify 文档型 skill，提供通用整理分类流程、风险边界、方法论 reference，以及 Python、JavaScript/TypeScript、Go、Rust、JVM、.NET、脚本型项目的通用目录结构参考。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `e78a885` | (see git log) |
| `3fa292e` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 14: database-query 开箱即用体验

**Date**: 2026-06-01
**Task**: database-query 开箱即用体验
**Branch**: `master`

### Summary

允许 defaultDatabase 省略 databases，新增 init-config，强化 doctor 安装决策提示，并更新 Codex 全局 skill 安装态。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `f5647e4` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 15: 改进 database-query CLI 与全局安装

**Date**: 2026-06-01
**Task**: 改进 database-query CLI 与全局安装
**Branch**: `master`

### Summary

新增 database-query config paths/current，统一 doctor 与执行计划的客户端探测，修复 SQLite 无 database 执行路径，安装并验证 MySQL/PostgreSQL/SQLite CLI，安装 database-query 到 Codex 全局 skill。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `0a0636c` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete


## Session 16: Docker 管理 skill 封装

**Date**: 2026-06-01
**Task**: Docker 管理 skill 封装
**Branch**: `master`

### Summary

新增 docker-management 纯文档 skill，覆盖 Windows Docker Desktop/Rancher Desktop/WSL2-CLI+Portainer 选型、迁移、运维和排障；刷新 linux/wsl2 配置模板并退役旧 proxy.sh。

### Main Changes

(Add details)

### Git Commits

| Hash | Message |
|------|---------|
| `056846d` | (see git log) |
| `c020e66` | (see git log) |

### Testing

- [OK] (Add test results)

### Status

[OK] **Completed**

### Next Steps

- None - task complete
