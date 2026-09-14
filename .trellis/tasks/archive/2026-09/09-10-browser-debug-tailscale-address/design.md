# Design — browser-debug 指南自动探测 Tailscale 地址

## 架构与边界

- 探测逻辑独立成新函数 `Get-BrowserDebugTailscaleAddress`（runtime.ps1），平台无关；LAN 模式 CLI 边界已限定 Windows，函数本身不做平台分派（非 Windows 无 `tailscale` 可执行文件自然返回 `$null`）。
- `New-BrowserDebugGuideSnapshot` 仅在 `mode -eq 'lan'` 分支调用探测函数；local 指南保持降噪合同不变。
- 渲染层 `ConvertTo-BrowserDebugGuideHtml` 仅按快照新增字段条件渲染别名行与未检测提示；模板 `browser-debug-guide.template.html` 无需改动（动态内容全部经 `command-field` copyField 注入）。

## 数据流与合同

### 探测函数

```text
Resolve-BrowserDebugTailscaleAddress [[-StatusInvoker] <scriptblock>] → [pscustomobject]@{ ipv4; magicDnsName; hostName } | $null
```

- 可执行文件定位：`Get-Command tailscale.exe`（Windows）/ `tailscale`（其余平台），`-ErrorAction SilentlyContinue`；未找到返回 `$null`。
- 默认 invoker 用 `System.Diagnostics.Process` 运行 `tailscale status --json`（只读守护进程查询），stdout 重定向，`WaitForExit(3000)` 超时后 Kill 并返回 `$null`。
- 解析：`Self.TailscaleIPs` 中取第一个落在 100.64.0.0/10（CGNAT，100.64.0.0–100.127.255.255）的 IPv4；`Self.DNSName` 去尾点后非空则作为 `magicDnsName`；`Self.HostName` 为 `hostName`，为空时回退 `magicDnsName` 首段，且必须匹配主机名字符集（字母数字与连字符）才采用。无 CGNAT IPv4 时整体返回 `$null`。
- 任何异常（无 daemon、非零退出、JSON 解析失败、超时）一律返回 `$null`，绝不 throw；guide 生成失败仍只追加 warning（现有合同）。
- 测试注入：`-StatusInvoker` 接收脚本块返回 JSON 字符串或抛错，Pester 测试用它构造确定性用例。

### 快照扩展（tailscale 对象新增字段）

| 字段 | 检测成功 | 检测失败 |
|---|---|---|
| `endpoint` | `http://<ipv4>:<actualPort>` | `http://<本机 MagicDNS 或 Tailscale IP>:<actualPort>`（现状占位符） |
| `hostnameEndpoint` | `http://<hostName>:<actualPort>`（如 `http://macmini:21229`） | `$null` |
| `aliasEndpoint` | `http://<magicDnsName>:<actualPort>` | `$null` |
| `detected` | `$true` | `$false` |

`probeUrl`、`playwrightCommand`、`agentPrompt` 继续从 `endpoint` 派生，因此 copy 即用；`enableCommand`/`statusCommand`/`disableCommand` 合同不变。

### 渲染

- `hostnameEndpoint` 非空：在 "Tailnet endpoint" 字段后追加 `主机名别名 endpoint`（tone `connect`）可复制字段；`aliasEndpoint` 非空再追加 `MagicDNS 别名 endpoint`（主机名在前，用户确认可读性最高）。
- `detected -eq $false`：Tailscale 区块 note 追加"未在本机检测到可用的 Tailscale（未安装或未登录），endpoint 为占位符，请自行替换"。
- 动态值全部经现有 `$encode` HTML 编码（含 `@` 加固）。

## 兼容与权衡

- 快照新增字段为纯增量；`commands.ps1:434` 调用点签名不变。
- 安全权衡：Tailnet IPv4/域名写入本机 `guides/*.html` 属网络拓扑信息，非 Cookie/Token 级敏感数据；文件与 registry 同级、仅限本机，风险可接受，且页面继续不执行任何命令。
- `tailscale status --json` 为只读查询，不违反 spec "禁止自动执行网络暴露命令" 的 Bad case。
- 现有测试 `tests/BrowserDebugProfile.Tests.ps1:805` 禁止页面出现 `http://100.*:21229` 的断言需要更新：CGNAT 段（100.64/10）现在合法出现在 Tailscale Serve 区块，仍禁止 172.*/192.168.* 及非 CGNAT 的 100.x 作为"原生直连"endpoint。

## 回滚

纯代码回滚：还原 runtime.ps1、tests、spec、docs 即可；registry/schema/快捷方式/SSH 均不受影响。
