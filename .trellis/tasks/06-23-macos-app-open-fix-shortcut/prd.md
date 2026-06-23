# macOS 应用打不开右键修复快捷指令

## Goal

在 macOS 安装流程中新增一个可批量安装的 Finder 右键快捷指令/服务，用于处理下载后的 `.app` 无法打开、疑似 Gatekeeper 或 quarantine 阻断的问题。用户可以在 Finder 中选中一个或多个 `.app` 后右键执行，工具先输出诊断信息，再按设计边界处理隔离属性并尝试打开应用。

用户价值：把一次性终端修复命令沉淀成可复用的 macOS 右键动作，减少每次遇到“打不开软件”时重复查命令、猜权限原因的成本。

## Confirmed Facts

- 现有 macOS 安装流程位于 `macos/`，包含 `04installApps.ps1`、`05deployHammerspoon.sh`、`06verifyInstall.zsh`、`07configureLoginItems.zsh`，目前没有 Finder 右键快捷指令/Quick Action 的目录或安装步骤。
- `macos/04installApps.ps1` 通过 Homebrew 安装 `supportOs` 包含 `macOS` 且 `tag` 包含 `macbook` 的应用；这次需求不是新增 Homebrew app，而是新增可部署的本机自动化资产。
- `macos/INSTALL.md` 已按安装步骤记录执行方式、验证方式和失败处理；新增快捷指令安装项应进入这个文档的 macOS 流程。
- 既有记忆中的 `.app` 打不开处理顺序是：先查 `xattr` 是否有 `com.apple.quarantine`，再跑 `spctl -a -vv`，再跑 `codesign --verify --deep --strict --verbose=2` 或类似签名检查，最后才对可信 app 执行 `xattr -dr com.apple.quarantine`。
- 用户提供的参考脚本支持批量处理参数中的 `.app`，对非 `.app` 跳过，并执行 Gatekeeper 检查、签名检查、移除隔离属性和 `open`。

## Requirements

- 在 `macos/` 下新增一个专门存放快捷指令/右键动作资产的目录，命名应能清楚表达用途。
- 提供一个 Finder 右键可调用的项目，用于处理选中的一个或多个 `.app`。
- 提供批量安装入口，将该右键动作安装到当前用户可用的位置。
- 右键动作应支持多选 `.app`，对非目录或非 `.app` 输入安全跳过并输出说明。
- 动作执行时应输出至少三类诊断信息：Gatekeeper 检查、签名检查、隔离属性处理结果。
- 文档应说明安装方式、使用方式、适用边界和风险边界。
- 实现应遵循仓库现有 macOS zsh 脚本风格：`set -euo pipefail`、中文公共接口注释、可读日志、必要时支持 dry-run 或可验证输出。

## Acceptance Criteria

- [x] 仓库存在 `macos/` 下的快捷指令/右键动作目录，并包含“处理 macOS 应用打不开”的项目资产。
- [x] 有一个批量安装命令可把该项目安装到当前用户 Finder 右键动作可发现的位置。
- [x] Finder 选中一个或多个 `.app` 后右键可触发该动作；脚本能逐个处理传入路径。
- [x] 非 `.app` 输入不会执行 quarantine 清理，并会给出跳过原因。
- [x] 对 `.app` 输入会执行 `spctl` 和 `codesign` 诊断，并按最终安全策略处理 `com.apple.quarantine`。
- [x] `macos/INSTALL.md` 记录新增步骤的执行方式、验证方式、失败处理和权限/安全说明。
- [x] 完成实现后执行根目录 `pnpm qa`；若改动涉及 pwsh 内容，额外执行 `pnpm test:pwsh:all`。

## Out of Scope

- 不全局关闭 Gatekeeper。
- 不修改 macOS 系统安全策略。
- 不把该动作注册为所有文件类型的默认打开方式。
- 不处理非 `.app` bundle 的修复，例如 `.pkg`、`.dmg`、命令行二进制或浏览器下载配置。

## Open Questions

- 已决策：右键动作默认自动修复，仅处理传入的 `.app`；先输出 Gatekeeper 和签名诊断，再清除 `com.apple.quarantine` 并尝试打开应用。文档必须明确只对可信来源应用使用。

## Notes

- 这项任务跨安装脚本、Finder 右键动作资产、文档和验证路径，后续进入实现前应补 `design.md` 与 `implement.md`。
