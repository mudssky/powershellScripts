# Local Cross-Platform Pester Testing

本文档描述如何在本地同时验证 host 平台（Windows/macOS）和 Linux 容器中的 Pester 测试。

## Prerequisites

- **PowerShell 7+** (`pwsh`) 已安装
- **Pester 5+** 已安装（`pnpm pester:install`）
- **Docker** 已安装并运行（仅 Linux 容器测试需要）
- **pnpm** 已安装

## Quick Start

### Host 测试（当前平台）

```bash
# 快速模式（无代码覆盖率，适合日常迭代）
pnpm test:pwsh:fast

# 显式 coverage 模式（推荐）
pnpm test:pwsh:coverage

# 完整模式（兼容保留，当前等价于 coverage）
pnpm test:pwsh:full

# Host 完整断言（不含 coverage，与 all 的 host 路径一致）
pnpm test:pwsh:full:assertions

# Host assertions 路径慢测排行（默认不含 coverage）
pnpm test:pwsh:slowest

# 显式 coverage 路径慢测排行
pnpm test:pwsh:coverage:slowest
```

### Linux 容器测试

```bash
# 首次使用：构建 Docker 镜像
pnpm test:pwsh:linux:build

# 快速模式
pnpm test:pwsh:linux:fast

# 完整模式
pnpm test:pwsh:linux:full
```

> 当前 `pnpm test:pwsh:linux:full` 聚焦 Linux 容器内的 full 断言回归，不再承担本地 coverage 收尾；
> coverage 责任由 `pnpm test:pwsh:coverage` 提供，`pnpm test:pwsh:full` 作为兼容保留入口等价于该命令，
> 以规避容器内 Pester coverage 收尾异常。

### 完整本地验证（Host + Linux）

推荐直接运行跨环境聚合入口：

```bash
# 并发执行 host assertions-only + Linux full
pnpm test:pwsh:all
```

如需手动串行验证：

```bash
pnpm test:pwsh:full:assertions && pnpm test:pwsh:linux:full
```

## Test Modes

| 命令 | 环境 | 覆盖率 | 用途 |
|------|------|--------|------|
| `pnpm test:pwsh:fast` | Host | ❌ | 日常快速迭代 |
| `pnpm test:pwsh:qa` | Host | ❌ | `qa:pwsh` 使用的快速质量门子集 |
| `pnpm test:pwsh:coverage` | Host | ✅ | Host 平台显式 coverage 验证 |
| `pnpm test:pwsh:full` | Host | ✅ | `coverage` 的兼容保留入口 |
| `pnpm test:pwsh:full:assertions` | Host | ❌ | Host 平台完整断言，不含 coverage |
| `pnpm test:pwsh:linux:fast` | Linux 容器 | ❌ | Linux 平台快速验证 |
| `pnpm test:pwsh:linux:full` | Linux 容器 | ❌ | Linux 平台完整断言验证 |
| `pnpm test:pwsh:all` | Host + Linux 容器 | ❌ | 提交前跨环境完整断言验证 |
| `pnpm test:pwsh:serial` | Host | ❌ | 调试发现阶段挂起 |
| `pnpm test:pwsh:debug` | Host | ❌ | 详细调试输出 |
| `pnpm test:pwsh:profile` | Host | ❌ | Profile 专项测试 |

## Diagnostic Benchmarks

默认 `pnpm test:pwsh:all` 只承担提交前的功能与跨平台断言门禁；
性能比较、实现路径对照这类诊断型工作流，统一走 benchmark 入口。

```bash
# 对比帮助搜索的自定义解析与 Get-Help 路径
pnpm benchmark -- help-search
```

该 benchmark 适合在优化 `psutils/modules/help.psm1`、`Search-ModuleHelp` 或相关测试热点时手动运行，
但它不属于默认 full 门禁的一部分。

## Artifact Isolation

Host 和容器测试的输出隔离策略：

- **Host 测试**输出到项目根目录 `testResults.xml`
- **Linux 容器测试**输出到 Docker named volume `pester-results` 中的 `testResults-linux.xml`
- 可通过环境变量 `PESTER_RESULT_PATH` 自定义 host 输出路径

两者可安全并发运行，不会产生文件冲突。

## Platform-Specific Coverage

| 平台 | Host 测试 | 容器测试 | 说明 |
|------|-----------|----------|------|
| Windows | ✅ 全部（含 `windowsOnly`）+ `pnpm test:pwsh:coverage` | ✅ 通用断言 | Windows 特有测试与规范化 coverage 由 Windows host 路径承担 |
| macOS | ✅ 通用（排除 `windowsOnly`）+ 可选 host coverage | ✅ 通用断言 | 通过容器补 Linux 断言验证 |
| Linux | ✅ 通用（排除 `windowsOnly`）+ 可选 host coverage | ✅ 通用断言 | 容器或直接 host 均可 |

## Docker Image

- 基于 `mcr.microsoft.com/powershell:lts-ubuntu-22.04`
- 预装 Pester 模块
- 配置文件：`Dockerfile.pester` + `docker-compose.pester.yml`

重建镜像：

```bash
pnpm test:pwsh:linux:build
```

## Fallback: Docker Unavailable

当 Docker 不可用时（未安装、未启动、或公司网络限制）：

1. **Host 测试仍然完全可用**：所有 `pnpm test:pwsh:*` 的 host 命令不依赖 Docker
2. **Linux 验证依赖 CI**：跳过 `pnpm test:pwsh:linux:*` 与 `pnpm test:pwsh:all`，依赖 GitHub Actions CI 矩阵中的 `ubuntu-latest` 作为 Linux 验证
3. **WSL 备选**（仅 Windows）：如果有 WSL2 环境，可以直接在 WSL 中运行 `pnpm test:pwsh:full` 作为 Linux 验证的替代方案
4. **如需显式 coverage 门槛验证**：额外执行 `pnpm test:pwsh:coverage`

**判断 Docker 是否可用**：

```bash
docker info > /dev/null 2>&1 && echo "Docker OK" || echo "Docker unavailable"
```

> **建议**：如果改动涉及 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1` 或 `docker-compose.pester.yml`，提交前优先运行 `pnpm test:pwsh:all`。若需要显式 coverage 门槛验证，再补 `pnpm test:pwsh:coverage`。若 Docker 不可用，至少执行 `pnpm test:pwsh:full`，并依赖 CI 或 WSL 补 Linux 断言验证。
