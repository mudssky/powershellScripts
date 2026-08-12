# Implementation Plan

## 1. Externalize the guide template

- 新建 `scripts/pwsh/devops/browser-debug/browser-debug-guide.template.html`，迁移现有页面骨架、CSS、SVG 和 JavaScript。
- 在 `runtime.ps1` 增加模板路径解析与固定占位符替换，保留动态内容 HTML 编码。
- 增加模板缺失和未解析占位符错误测试。

## 2. Replace misleading LAN connection data

- 调整 `New-BrowserDebugGuideSnapshot`：原生 endpoint 始终基于 `127.0.0.1` 和实际 CDP 端口。
- 停止从网卡 IPv4 推导 Ready direct connections 与 LAN Agent Prompt。
- 保留请求模式/监听地址作为元数据，并增加 `nativeLanReachable=false` 状态。

## 3. Add LAN-only Tailscale and SSH guidance

- LAN 快照按实际 CDP 端口生成 Tailscale Serve enable/status/disable 命令。
- LAN 快照按实际 CDP 端口生成远端执行的通用 `ssh -L` 命令、探测 URL、Playwright attach 和 Agent Prompt。
- LAN 页面显著渲染原生直连不可用提示和两种替代方案。
- Local 页面不显示通用远程方案，避免增加无关噪声。
- 保留并单独渲染 registry 中已有 SSH configurations。

## 4. Update contracts and tests

- 更新 `.trellis/spec/pwsh-scripts/package/browser-debug-cli.md`：真实监听证据优先、LAN 直连不可用、外部模板、Tailscale/SSH 指南合同。
- 更新 `tests/BrowserDebugProfile.Tests.ps1`：
  - 外部模板加载与占位符完整性；
  - 不再渲染虚假 LAN endpoint；
  - LAN 页 Tailscale 三条命令使用实际端口；
  - LAN 页 `ssh -L` 命令及远端本地 endpoint；
  - Local 页不显示 LAN 失效警告或通用远程方案；
  - 原有 SSH 配置仍渲染；
  - 快捷方式属性与 registry 路径保持不变；
  - HTML 编码、敏感信息排除、复制控件与原子写入回归。

## Validation

1. Browser Debug 专项：
   `Invoke-Pester -Path tests/BrowserDebugProfile.Tests.ps1 -Output Detailed`
2. Profile 窄测：按仓库现有 Profile loading/mode 测试命令执行。
3. PowerShell 全门禁：
   `pnpm test:pwsh:all`
4. 项目质量门禁：
   `pnpm qa`
5. 真实 smoke：
   - 从非仓库当前目录启动 LAN 快捷方式对应命令；
   - 确认生成 HTML 只将回环 CDP 标为 Ready；
   - 确认 LAN 页面包含按实际端口生成的 Tailscale 与 `ssh -L` 命令；
   - 确认 Local 页面没有 LAN 失效警告；
   - 不实际改动 Tailscale Serve 配置。

## Risk and Rollback Points

- 模板路径错误会导致 guide 生成降级 warning；浏览器启动不得被改判失败。
- 占位符替换必须使用唯一 token，避免动态文本意外二次替换。
- 不运行 `tailscale serve reset`，不改变现有 5001/8443 Serve 配置。
- 不修改桌面快捷方式或 registry，避免引入无关迁移风险。
