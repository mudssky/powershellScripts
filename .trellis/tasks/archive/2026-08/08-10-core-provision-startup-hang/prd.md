# 修复 Core 安装启动卡顿

## Goal

让 `pnpm provision:core` 在执行耗时安装步骤时持续提供可见进度，不再因为根编排器静默缓冲子进程输出而表现为启动即卡死，同时保持 JSON 输出的单文档合同。

## Confirmed Facts

- 用户当前命令并未停在 pnpm 或根 `install.ps1` 启动阶段，而是已经执行到 macOS `07 profile-tools`。
- 进程树为 `pnpm provision:core` → `install.ps1` → `macos/07installProfileTools.ps1` → `fnm install --lts`。
- `fnm install --lts` 已运行超过 3 分钟，CPU 为 0%，并通过本机代理 `127.0.0.1:7890` 保持 TCP 连接，属于 Node.js LTS 下载/网络等待。
- `Invoke-InstallLeafProcess` 使用 `RedirectStandardOutput/RedirectStandardError` 加 `ReadToEndAsync()`，直到叶子退出后才返回全部输出；因此用户看不到已进入哪个步骤及已等待多久。
- 当前已安装 Node.js `v24.16.0 default`，但 Core 合同仍会执行 `fnm install --lts` 以确保 LTS；本任务不通过跳过安装来掩盖网络问题。

## Requirements

- Text 模式在每个叶子启动时立即输出步骤编号、ID 与执行命令，并在长时间运行时输出低频 elapsed heartbeat。
- JSON 模式 stdout 继续只包含最终单个 JSON document，不输出进度行。
- 进度实现不得绕过、取消或静默跳过 `fnm install --lts`，不得改变步骤状态、退出码、source 事务或结果摘要。
- 用户按 `Ctrl+C` 时仍能中断当前安装，不引入后台遗留安装进程。

## Acceptance Criteria

- [x] Text 模式执行耗时 fixture 时，在子进程结束前可观察到 `[Running]` 步骤行和 elapsed heartbeat。
- [x] `pnpm provision:core -WhatIf -SkipStep verify` 继续成功，并在最终汇总前显示步骤进度。
- [x] `-OutputFormat Json` stdout 仍可直接解析为单个 JSON document，且不含进度文本。
- [x] 既有 Core/Full、失败传播和 source cleanup 测试继续通过。

## Out of Scope

- 修改 fnm、Node.js 官方下载地址或用户代理配置。
- 因本机已有 Node.js 而跳过 LTS 安装合同。
- 为所有安装步骤设置武断的统一超时。
