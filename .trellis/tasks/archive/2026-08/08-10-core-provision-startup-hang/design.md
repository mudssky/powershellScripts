# 技术设计

## 根因

`Invoke-InstallLeafProcess` 会异步读取 stdout/stderr，但同步无限等待子进程退出。读取任务避免管道死锁，却不会把任何进度转发到父终端。真实运行已进入 `07 profile-tools` 的 `fnm install --lts`，网络等待被表现为根命令无输出。

## 边界

- `install.ps1` 根据 `OutputFormat` 决定是否启用人类可读进度。
- `Invoke-InstallOrchestrator` 接收 `ShowProgress` 开关，并把步骤上下文传给叶子进程执行器。
- `Invoke-InstallLeafProcess` 保持 stdout/stderr 捕获；等待期间只由父进程生成受控进度，不转发可能包含敏感信息的任意叶子输出。
- JSON 模式不启用进度，因此 stdout 单文档合同和叶子日志隔离保持不变。

## 进度合同

Text 模式在启动叶子前写入 stderr：

```text
[Running] 07 profile-tools: <安全展示命令>
```

若子进程持续运行，每 15 秒写入一次：

```text
[Running] 07 profile-tools elapsed=30s
```

stderr 用于即时诊断；最终 Text 汇总继续写 stdout。进度只包含已由 `Format-InstallCommand` 生成的安全命令和 elapsed，不包含子进程原始输出。

## 中断与资源

等待循环使用有限时长 `WaitForExit(milliseconds)`，只用于 heartbeat，不设置安装超时。PowerShell 中断或异常路径必须终止仍在运行的直接子进程树，再释放 `Process`，防止 fnm 等下载进程遗留。

## 兼容性

- `ShowProgress` 默认关闭，模块级调用者和现有测试行为不变。
- Text CLI 显式开启；JSON CLI 显式关闭。
- 步骤结果、退出码、事务与最终汇总结构不变。
