# 实施计划

## 1. 固化测量入口

- 扩展 `scripts/pester-duration-report.mjs`，支持唯一 NUnit3 输入/输出和 JSON artifact。
- 添加解析测试，覆盖 ANSI 日志、NUnit3 test-case、host/linux lane、失败退出码和无耗时行。
- 记录改动前约 718.6 秒基线与本任务 research 数据。

## 2. 优化 Windows 命令能力发现

- 在 Windows install 模块中复用直接加载的 `Find-ExecutableCommand` 批量解析外部命令。
- 把 WinGet source cmdlet 改为一次模块级能力解析，并保留 AutoHotkey 路径 fallback。
- 为 present/missing、PATH 变化、Scoop cmd shim、WinGet module export 和完整 `CommandAvailability` 添加测试。
- 运行 command-discovery benchmark，保存前后结构化样本。

## 3. 拆分 Windows 测试层

- 平台矩阵全部提供完整 command map，不触发真实环境扫描。
- 清单与结果合同保留模块内测试。
- 删除与 unit 断言重复的叶子/verify 子进程场景，只保留参数、JSON、退出码、写入边界等入口 smoke；拆文件不作为性能收益依据。
- 单文件目标：原 253 秒热点降到 90 秒以内，且 unit 文件不执行真实缺失命令发现。

## 4. 优化 InstallOrchestrator 测试

- 抽取稳定的 process-result fixture。
- 对状态机、依赖、source transaction、restore 和重跑命令 Mock `Invoke-InstallLeafProcess`，断言调用顺序、参数和次数。
- 保留真实 UTF-8、多流、Running、中断进程树和一个 Core smoke。
- 目标：原 80 秒文件降到 30 秒以内。

## 5. 优化 Linux/macOS 平台测试

- 把清单选择、平台环境和 verify 名称来源迁移到模块内测试。
- 每个平台只保留必要的参数错误、WhatIf/JSON/exit 入口 smoke。
- 将清单选择和 verify 名称来源改为模块内测试，入口只保留必要 smoke；当前串行 Pester 下避免无收益拆分。
- 目标：Linux 原 78 秒降到 40 秒以内，macOS Windows-host 子集原 50 秒降到 25 秒以内。

## 6. 优化 psutils API Boundary

- 聚合模块只导入一次完成 diagnostic visibility 与 help 合同。
- 子模块动态用例避免重复完整 manifest import/remove。
- 目标：原 33 秒降到 15 秒以内。

## 7. 增加 all 门禁预检与清理

- 增加统一 all runner，在启动 concurrently 前验证 Docker/Compose。
- Docker 缺失时快速失败并输出 fallback 命令；可用时保持 host/linux 分 lane。
- 验证中断不会遗留 pnpm、Pester、安装 fixture 子进程或 `.install-tests.*`。

## 8. 验证与性能验收

- 分块运行受影响测试与 `pnpm qa`。
- 运行 `pnpm test:pwsh:full` coverage-on 3 次，输出 JSON 样本，报告中位数和最慢值。
- 验收：中位数 <= 360 秒，且相对 718.6 秒改善 >= 40%，coverage >= 50%。
- Docker 可用时运行 `pnpm test:pwsh:all`；不可用时记录预检结果并说明 Linux 覆盖依赖 CI/WSL。
- 最后执行 `git diff --check`、AST/格式检查和全量慢项报告。

## 回滚点

- 每个编号步骤形成独立逻辑提交候选；若某层引入行为缺口，可只回退对应测试分层或 runner，不回退已验证的命令发现优化。
