# 技术设计

## 问题分解

本任务修复两个相邻但职责不同的缺陷：

1. 根编排器把叶子进程的合法 UTF-8 字节读取成损坏字符串。
2. 包安装批次把大量过程日志和失败诊断混在步骤级文本中，最终 1024 字符摘要可能无法保留真正失败项。

修复应分别落在进程边界和包安装结果边界，不能通过修改 Scoop 配置、隐藏 delta 或自动重试掩盖问题。

## 数据流与边界

```text
叶子 pwsh/bash/zsh
  -> stdout/stderr UTF-8 字节流
  -> Invoke-InstallLeafProcess 并发字节收集与有限轮询
  -> 显式 UTF-8 解码为 Stdout/Stderr
  -> 叶子结构化失败摘要
  -> Protect-InstallDiagnostic 脱敏与有界截断
  -> Text/JSON 最终 document
```

### 进程输出捕获

- 保留 `ProcessStartInfo.ArgumentList`、stdout/stderr 重定向、250ms 有限轮询和中断清理。
- Text 模式只在进程成功启动后写入一次安全 `[Running] <number> <id>: <command>`；删除 `elapsed=<seconds>s` 周期输出及对应 heartbeat 状态。
- 不再依赖 `StreamReader.ReadToEndAsync()` 对长多字节文本进行异步解码；stdout/stderr 分别通过 `BaseStream.CopyToAsync()` 并发复制到独立内存流。
- 子进程退出并等待复制任务完成后，使用无 BOM UTF-8 显式解码。测试锁定中文、长文本和跨缓冲区多字节字符不会出现 `U+FFFD`。
- stdout/stderr 必须同时开始读取，避免任一管道缓冲区填满导致死锁。
- 清理顺序保持：异常或中断时终止进程树，有限等待回收，再释放进程和内存流。250ms 轮询只用于响应 PowerShell 中断，不构成安装超时或用户可见进度。

### 包安装失败诊断

- `Invoke-PackageInstallCommand` 继续接受受限命令字符串并保持参数数组调用，不改变对外的成功退出码语义。
- 执行期间维护有界输出尾部，只为失败诊断保留最近的有效文本；成功路径不把整段日志塞入结构化结果。
- 非零退出或异常生成稳定消息，至少包含安装命令、退出码和输出尾部。`Install-PackageManagerApps` 继续把该消息写入对应应用的 Failed result，并继续处理后续应用。
- Windows `05installCoreCli.ps1` 的最终输出仍是逐项结果；失败项必须形成紧凑摘要，使根编排器无需从整个 Scoop 更新日志猜测失败原因。
- 根编排器对最终摘要继续统一执行 secret 脱敏和长度限制。失败项优先于普通成功/进度文本；不把任意原始流直接写入 JSON document。

## 兼容性

- Text 模式仍立即写一次 `[Running]` 启动行，不再写 elapsed heartbeat，也不实时转发叶子原始输出。
- JSON 模式 stdout 仍只有一个最终 document，stderr 不出现 Text 进度。
- `Succeeded`、`Failed`、`Blocked`、退出码、source transaction、重跑命令和 Core/Full 步骤图不变。
- Scoop 单项失败后继续安装后续项；不新增自动重试。
- 不改变 Windows Core 精确 13 项、delta 包名、bucket 或 aria2 配置。

## 风险与回滚

- 风险：字节流任务未并发启动会造成管道死锁。测试使用同时写入较大 stdout/stderr 的 fixture 锁定。
- 风险：输出尾部捕获改变原生命令的可见流行为。实现时必须保留步骤启动提示，或把变化限制在当前本就由根编排器缓冲的安装调用中，并用窄测验证。
- 风险：失败尾部包含 secret。最终步骤摘要仍经过 `Protect-InstallDiagnostic`；测试覆盖现有 token/password/secret/api key 规则。
- 回滚：恢复原 `StreamReader` 读取和原包安装异常消息即可；不涉及配置迁移、用户数据或 Scoop 状态变更。
