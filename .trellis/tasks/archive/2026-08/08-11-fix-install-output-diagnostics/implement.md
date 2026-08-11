# 实施计划

## 修改步骤

1. 先新增红测：构造长中文 stdout/stderr、跨缓冲区 UTF-8 字符和延迟退出 fixture，通过真实 `Invoke-InstallLeafProcess` 路径断言当前乱码。
2. 重构 `Invoke-InstallLeafProcess`：并发复制 stdout/stderr 原始字节，进程退出后显式 UTF-8 解码；保留一次步骤启动提示、JSON 静默和中断进程树清理，删除 elapsed heartbeat 常量、状态与周期输出。
3. 为 `Invoke-PackageInstallCommand` 增加有界失败输出尾部，非零退出消息包含命令、退出码和关键错误；成功返回值与参数边界不变。
4. 扩展 `Install-PackageManagerApps` 测试：第一项失败、第二项继续成功，Failed result 保留可操作诊断且不自动重试。
5. 更新进度测试：Text 模式在叶子退出前只出现一次启动行且不含 `elapsed=`，JSON 模式无进度；保留中断后无遗留进程测试。
6. 扩展根编排器摘要测试：长成功日志不能挤掉失败项，脱敏和最大长度仍有效，Text/JSON 输出合同不变。
7. 更新 `.trellis/spec/infra/install-orchestrator.md`，删除 15 秒 heartbeat 合同并明确有限轮询只用于中断；若共享安装器合同发生变化，同步补充 Windows 安装流水线规范。

## 验证命令

```powershell
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./tests/InstallOrchestrator.Tests.ps1
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./psutils/tests/install.Tests.ps1
pwsh -NoProfile -File ./scripts/pwsh/devops/Invoke-PesterMode.ps1 -Mode qa -Path ./tests/WindowsInstallPipeline.Tests.ps1
pwsh -NoProfile -File ./install.ps1 -Preset Core -Step sources -NetworkMode Direct -WhatIf
pnpm qa
pnpm test:pwsh:all
git diff --check
```

真实 Scoop 安装不属于自动测试或本任务验收命令；实现完成后只报告可供人工选择的 `-Step core-cli` 重跑命令。

## 重点文件与回滚点

- `scripts/pwsh/install/InstallOrchestrator.psm1`：输出捕获、摘要选择和中断清理，风险最高。
- `psutils/modules/install.psm1`：共享应用安装命令与单项失败结果，需保持调用兼容。
- `tests/InstallOrchestrator.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`tests/WindowsInstallPipeline.Tests.ps1`：回归边界。
- `.trellis/spec/infra/install-orchestrator.md`、`.trellis/spec/infra/windows-install-pipeline.md`：最终可执行合同。

若输出捕获变更导致死锁、JSON 污染或中断清理回归，优先回滚该步骤，不保留半套兼容分支。
