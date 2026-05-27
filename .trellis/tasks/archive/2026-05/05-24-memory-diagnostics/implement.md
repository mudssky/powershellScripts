# 内存异常分析脚本实施计划

## Checklist

- [x] 阅读相关规范：`pwsh-scripts/package/index.md`、`pwsh-scripts/package/config-loading.md`、`psutils/package/index.md`。
- [x] 创建 `scripts/pwsh/devops/memory-diagnostics/` 目录结构和 `tool.psd1`。
- [x] 实现 `main.ps1` 命令分发、help、snapshot、sample 参数。
- [x] 实现跨平台报告骨架、warning/recommendation 结构和 JSON 输出。
- [x] 实现 Windows 系统层、进程层、驱动/服务层采集。
- [x] 实现 Linux/macOS 基础采集和缺失命令降级。
- [x] 实现 Docker 容器内存采集和不可用状态。
- [x] 实现 recommendations 阈值规则，覆盖高进程占用、commit/kernel pool 异常、Docker 线索。
- [x] 实现采样模式。
- [x] 增加 Pester 测试覆盖结构归一化、阈值建议、Docker 降级、入口输出。
- [x] 运行验证命令并修复问题。

## Validation Commands

```powershell
pnpm qa
pnpm test:pwsh:all
```

如果 Docker 不可用：

```powershell
pnpm test:pwsh:full
```

并在结果说明中标注 Linux 覆盖依赖 CI 或 WSL。

## Risky Areas

- Windows CIM 字段单位不一致，尤其 `Win32_PerfFormattedData_PerfOS_Memory` 中 commit 与 pool 字段需要统一转 GB。
- macOS/Linux 系统命令输出随版本和 locale 变化，解析函数必须可测试、可降级。
- `docker stats --format json` 在不同 Docker 版本表现可能不同，需要容错到表格解析或返回不可用状态。
- 采样模式不能因为单次采集失败中断整个序列，应把失败写入对应 sample 的 warning。

## Review Gate

规划已确认第一版输出 `recommendations` 结论字段。开始实现前需由用户明确批准进入实现阶段。
