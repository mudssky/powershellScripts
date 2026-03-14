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

# 完整模式（含代码覆盖率，适合提交前验证）
pnpm test:pwsh:full
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

### 完整本地验证（Host + Linux）

推荐直接运行跨环境聚合入口：

```bash
# 并发执行 host full + Linux full
pnpm test:pwsh:all
```

如需手动串行验证：

```bash
pnpm test:pwsh:full && pnpm test:pwsh:linux:full
```

## Test Modes

| 命令 | 环境 | 覆盖率 | 用途 |
|------|------|--------|------|
| `pnpm test:pwsh:fast` | Host | ❌ | 日常快速迭代 |
| `pnpm test:pwsh:qa` | Host | ❌ | `qa:pwsh` 使用的快速质量门子集 |
| `pnpm test:pwsh:full` | Host | ✅ | Host 平台完整验证 |
| `pnpm test:pwsh:linux:fast` | Linux 容器 | ❌ | Linux 平台快速验证 |
| `pnpm test:pwsh:linux:full` | Linux 容器 | ✅ | Linux 平台完整验证 |
| `pnpm test:pwsh:all` | Host + Linux 容器 | ✅ | 提交前跨环境完整验证 |
| `pnpm test:pwsh:serial` | Host | ❌ | 调试发现阶段挂起 |
| `pnpm test:pwsh:debug` | Host | ❌ | 详细调试输出 |
| `pnpm test:pwsh:profile` | Host | ❌ | Profile 专项测试 |

## Artifact Isolation

Host 和容器测试的输出隔离策略：

- **Host 测试**输出到项目根目录 `testResults.xml`
- **Linux 容器测试**输出到 Docker named volume `pester-results` 中的 `testResults-linux.xml`
- 可通过环境变量 `PESTER_RESULT_PATH` 自定义 host 输出路径

两者可安全并发运行，不会产生文件冲突。

## Platform-Specific Coverage

| 平台 | Host 测试 | 容器测试 | 说明 |
|------|-----------|----------|------|
| Windows | ✅ 全部（含 `windowsOnly`） | ✅ 通用 | Windows 特有测试仅在 host 运行 |
| macOS | ✅ 通用（排除 `windowsOnly`） | ✅ 通用 | 通过容器覆盖 Linux 行为 |
| Linux | ✅ 通用（排除 `windowsOnly`） | ✅ 通用 | 容器或直接 host 均可 |

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

**判断 Docker 是否可用**：

```bash
docker info > /dev/null 2>&1 && echo "Docker OK" || echo "Docker unavailable"
```

> **建议**：如果改动涉及 `scripts/pwsh/**`、`profile/**`、`psutils/**`、`tests/**/*.ps1`、`PesterConfiguration.ps1` 或 `docker-compose.pester.yml`，提交前优先运行 `pnpm test:pwsh:all`。若 Docker 不可用，至少执行 `pnpm test:pwsh:full`，并依赖 CI 或 WSL 补 Linux 覆盖。
