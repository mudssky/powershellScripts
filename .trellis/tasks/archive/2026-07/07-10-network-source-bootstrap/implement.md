# 网络与镜像源实施计划

## 实施边界

本任务实现共享 source catalog、事务引擎、adapter、Stage 0 helper、兼容入口和测试。macOS、Windows、Linux/WSL 的 `03configureSources.*` 由对应平台任务实现；Nix flake/substituter 的真实 adapter 由 Nix 试点任务实现。

实施期间所有写入型测试使用临时 HOME、LOCALAPPDATA 和伪命令，不对本机真实 package source 执行 `Apply`。真实网络只通过显式 live diagnostics 验证。

## 有序清单

### 1. 冻结契约与 chsrc 能力矩阵

- [x] 针对最终采用的稳定版 chsrc 重新执行 `list targets`、逐 target `list/get/reset` 与 `set -dry`，更新 `research/chsrc-capability-audit.md`。
- [x] 确认首期 target 的 adapter 分配：chsrc、managed-env、chsrc-system、Docker、Unsupported 与 Nix extension point。
- [x] 定义 `package-sources.json` schema、事务 manifest schema、状态枚举、退出码和 JSON 输出 fixture。
- [x] 明确 Bootstrap/Runtime/Toolchain 阶段与平台 capability；默认 target 选择由平台薄包装拥有，不放进共享引擎。

审阅点：能力矩阵必须来自目标二进制行为；任何无法可靠读取原值或恢复的 target 保持 Unsupported，不用猜测性实现补齐表格。

### 2. 先建立确定性测试骨架

- [x] 扩展 `tests/Switch-Mirrors.Tests.ps1`，将旧 Docker 公共行为固定为兼容测试。
- [x] 新增 package-source engine Pester 测试，使用临时 HOME/LOCALAPPDATA、固定 probe 和伪 chsrc/native executable。
- [x] 新增 JSON schema/fixture 测试，确保 `-OutputFormat Json` 的 stdout 不混入日志。
- [x] 为 POSIX Stage 0 helper 新增 `scripts/bash` Vitest 覆盖；为 Windows helper增加 PowerShell 5.1 语法兼容和非 Windows 防护测试，真实 WinGet 行为留给 Windows smoke。

首批失败用例：Direct 零写入、China snapshot/幂等/Restore、Auto 无需换源、Auto 异常清理、orphan recovery、drift 拒绝、并发锁、secret 脱敏和 Docker 兼容参数。

### 3. 建立 catalog 与核心事务模块

- [x] 新增 `config/network/package-sources.json`，集中记录 target、平台、阶段、adapter、命令依赖、官方探测端点和恢复能力。
- [x] 新增 `config/network/package-sources.bootstrap.env`，仅保存 Stage 0 必需的非敏感 HTTPS 地址与固定版本/checksum 元数据。
- [x] 实现状态目录解析、严格权限、事务 ID、manifest 原子写入、独占锁、snapshot、hash 和日志脱敏。
- [x] 实现 Plan/Apply/Ensure/Status/Restore 状态机，以及 China 持久事务、Auto 临时事务、orphan 检测和 drift 阻断。
- [x] 实现 current-source 分类，Auto 对健康的 unmanaged custom source 返回 `External`，不覆盖用户配置。

回滚点：完成本阶段后只运行 fake adapter；若 manifest 合同需调整，先迁移 fixture 和 schema version，再进入真实 adapter。

### 4. 实现 adapter

- [x] 实现 chsrc capability adapter：版本检查、选择策略、apply/read/verify/restore 能力映射；target 矩阵来自 0.2.5 审计。
- [x] 实现 managed-env adapter，用于 Homebrew/rustup 等不能直接写 rc 的环境变量，并新增 `shell/shared.d/package-sources.sh` 只读加载本机 env 文件。
- [x] 实现 chsrc command/system adapter，覆盖 npm/pnpm/pip/go 与 Ubuntu/Debian/Arch；winget 仅由 Windows Stage 0 helper 管理，Stage 1 明确 Unsupported。
- [x] Cargo/uv 保持 Unsupported 并输出结构化 TOML 说明，不覆盖现有用户配置。
- [x] 把现有 Docker `/v2/` 探活、200/401 判断、JSON 合并和重启提示迁入 Docker adapter，默认 URL 改读 catalog。
- [x] 定义 Nix extension point 和 Unsupported 占位，不在本任务写入 nix.conf、registry 或 channel。

审阅点：每个 adapter 都必须证明可读取原状态、验证应用结果并恢复；不满足三项条件的 target 不能标为 supported。

### 5. 扩展公共入口并保留兼容

- [x] 将 `Switch-Mirrors.ps1` 改为 `Plan|Apply|Ensure|Status|Restore` 公共入口，默认 `Mode=Direct`、`OutputFormat=Text`，非法组合在写入前失败。
- [x] JSON 模式只输出稳定 document 到 stdout，警告/诊断走 stderr；返回对象包含 target、phase、adapter、status、source、persistence、transaction 和 rollback。
- [x] 兼容 `-Target docker -UseChinaMirror`、`-Disable`、`-DryRun`、`-WhatIf` 与 `-MirrorUrls`，兼容层只做参数映射。
- [x] 为人工 `Restore -Force` 增加 drift 当前文件的额外时间戳备份，自动流水线不得传 Force。

### 6. 实现 Stage 0 helper

- [x] 新增 `scripts/bash/package-source-bootstrap.sh`，支持 POSIX Homebrew 的 Direct/China/Auto、preview 和进程级环境自动清理。
- [x] 新增 Windows PowerShell 5.1 兼容的 `Invoke-PackageSourceBootstrap.ps1`，只处理 winget Stage 0 结构化 snapshot、应用和恢复。
- [x] Stage 1 使用事务 manifest；POSIX Stage 0 无持久写入，Windows Stage 0 保留最初 snapshot，PowerShell 7/chsrc 就绪后使用 Apply/Ensure。
- [x] 禁止默认路径直接 pipe 远程 installer；固定 chsrc 稳定版本与 SHA-256 元数据，实际安装优先使用平台包管理器或已校验资产。

### 7. 文档与下游合同

- [x] 重写 `docs/换源脚本使用说明.md`，说明模式、动作、JSON 输出、状态目录、恢复、drift、Stage 0 和旧参数迁移。
- [x] 更新 `docs/scripts-index.md`，删除“首期只支持 Docker”的过期表述。
- [x] 给平台任务提供 `03configureSources.*` 调用顺序和退出码映射；给统一编排器提供 Auto `finally`、China rollback command 和 Ensure 合同。
- [x] 给 Nix 任务记录 extension interface，不承诺 chsrc nix-channel 等同 flake/substituter。

### 8. 验证与交付门禁

- [x] 运行目标 Pester：`PackageSources`、`PackageSourceBootstrap`、`Switch-Mirrors` 共 30 passed。
- [x] 运行 POSIX helper 测试：`pnpm test:bash`，21 passed。
- [x] 运行 PowerShell 全平台门禁：`pnpm test:pwsh:all`，host 656 passed、Linux 658 passed。
- [x] 运行仓库根门禁并修复问题：`pnpm qa`，125 passed。
- [x] 本机只执行 Plan/Status、fixture 和临时目录演练；未对真实 source 执行 China/Auto Apply。
- [x] 在文档和 spec 中记录 Windows WinGet、Linux 真实系统源 smoke 缺口，由对应平台流水线任务在目标环境完成。

## 高风险文件与回滚

- `scripts/pwsh/misc/Switch-Mirrors.ps1`：保留旧参数测试，出现回归时可继续通过兼容层调用同一 Docker adapter，不恢复双实现。
- `shell/shared.d/package-sources.sh`：只加载本机受管 env 文件；不得包含 URL、修改 rc 或影响 Direct 模式。
- 用户 source 配置：所有真实写入前 snapshot，Restore 先校验 after hash；drift 默认停止，Force 仅供人工使用。
- 系统包源：测试默认使用 fixture；实际 Linux/Windows 写入留到目标平台 smoke test，不在 macOS 开发机模拟系统文件。

## 开始实施前检查

- [x] 用户已审阅并批准 `prd.md`、`design.md` 与本文件。
- [x] 当前 macOS 规划任务指针已通过 `task.py finish` 清除，但任务状态保持 `planning`。
- [x] 已执行 `task.py start 07-10-network-source-bootstrap`，任务状态变为 `in_progress`。
- [x] 已加载 `trellis-before-dev`，读取 `pwsh-scripts`、`bash-scripts`、`shell-shared` 与跨层复用规范。
