> Superseded on 2026-04-20 by `docs/superpowers/specs/2026-04-20-tailscale-derp-policy-script-design.md`.
>
> 本文档描述的 `tailscale up --derp-map-url` / `--tls-skip-verify` 路线已不再作为仓库推荐实现。
> 后续实现请以 tailnet policy 中的 `derpMap` 编辑方案为准。

# Tailscale Custom DERP Script Design

## Summary

本设计为仓库新增一个跨平台 PowerShell 脚本，用于一键把当前设备切换到用户指定公网 IP 的自建 DERP 配置，并提供对应的一键取消能力。

目标入口为：

- `scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 -ServerIp <公网IP>`
- `scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 -Reset`

其中：

- `-ServerIp` 模式负责生成自定义 DERP JSON 并应用到当前 Tailscale 节点
- `-Reset` 模式负责取消本脚本管理的自定义 DERP，恢复到应用前的普通 Tailscale 配置

本次“取消”不等价于 `tailscale down`，不会主动断开 Tailscale 网络，只负责撤销本脚本引入的 DERP 定制。

## Context

仓库内已经具备两块相关基础：

- `scripts/pwsh/network/tailscale/` 目录已经预留，但还没有实际脚本
- `docs/cheatsheet/network/tailscale/index.md` 已经沉淀了基础 Tailscale 运维命令，适合补充新入口说明

用户给出的目标行为是：

```json
{
  "Regions": {
    "900": {
      "RegionID": 900,
      "RegionCode": "cn-custom",
      "Nodes": [
        {
          "Name": "cn-node",
          "RegionID": 900,
          "HostName": "你的服务器公网IP",
          "DERPPort": 8443,
          "STUNPort": 3478,
          "InsecureForTests": true
        }
      ]
    }
  }
}
```

```bash
tailscale up --derp-map-url=file:///root/derp.json --tls-skip-verify
```

但本地验证发现一个现实约束：

- 当前环境的 `tailscale 1.96.4` 在 `tailscale up --help` 与 `tailscale set --help` 中都没有公开列出 `--derp-map-url` 与 `--tls-skip-verify`
- `tailscale set` 虽然支持“只改显式设置”的局部更新语义，但当前公开帮助里并不支持上述两个 DERP 相关 flag

这说明脚本设计不能假设所有客户端都具备该能力，也不能把“取消”设计成只删除 JSON 文件就算完成。

## Goals

- 提供一个单脚本跨平台入口，同时支持应用与取消
- 支持用户通过参数传入自建 DERP 服务器公网 IP
- 自动生成符合目标结构的 DERP JSON 文件
- 自动把 JSON 路径转换成跨平台可用的 `file://` URI
- 在应用前保存当前 Tailscale 基线配置，确保取消时能够恢复到应用前状态
- 当当前 Tailscale CLI 不支持目标 flag 时，直接给出明确、可操作的错误
- 为核心逻辑补充 Pester 测试，并补充仓库内 Tailscale 文档

## Non-Goals

- 不负责安装 Tailscale 或启动 `tailscaled`
- 不负责 Tailscale 登录、认证、Auth Key 管理或 Tailnet 初始化
- 不负责自动提权到管理员或 root
- 不尝试支持任意复杂的 DERP 多节点拓扑，本次只覆盖“单 Region + 单 Node + 用户指定服务器 IP”
- 不把“取消”实现成 `tailscale down`
- 不修改系统级全局 Tailscale 配置文件布局，只管理脚本自己的受控文件

## Chosen Approach

采用“单脚本 + 受管 DERP JSON + 受管基线状态文件”的方案。

核心流程分为两条：

### Apply Flow

1. 校验当前 `tailscale` 命令存在
2. 校验 `-ServerIp` 输入合法
3. 读取当前 Tailscale 偏好，生成“应用前基线快照”
4. 依据用户输入生成受管 `derp.json`
5. 基于基线快照构造 `tailscale up` 参数，并追加自定义 DERP 参数
6. 应用成功后写入受管状态文件，记录：
   - 应用前基线偏好
   - 由脚本生成的“基线恢复参数”
   - 当前生效的 DERP JSON 路径与服务器 IP

### Reset Flow

1. 读取受管状态文件
2. 用状态文件中保存的“基线恢复参数”执行恢复命令
3. 恢复成功后删除受管 `derp.json` 与状态文件

之所以不把取消实现成“重新读取当前 prefs 再反推恢复命令”，是因为：

- 应用后的当前状态已经混入了自定义 DERP 修改
- 目标 flag 本身可能属于实验/隐藏能力，未必能稳定从公开 prefs 中反推出完整恢复语义
- 以“应用前快照”为准，恢复语义最清晰，也最容易验证

## CLI Contract

脚本文件：

`scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1`

参数设计：

- `-ServerIp <string>`：应用模式，必填且与 `-Reset` 互斥
- `-Reset`：取消模式，与 `-ServerIp` 互斥
- `-RegionId <int>`：默认 `900`
- `-RegionCode <string>`：默认 `cn-custom`
- `-NodeName <string>`：默认 `cn-node`
- `-DerpPort <int>`：默认 `8443`
- `-StunPort <int>`：默认 `3478`
- `-OutputPath <string>`：可选，自定义受管 `derp.json` 输出路径

脚本需要支持 `CmdletBinding(SupportsShouldProcess = $true)`，从而自然兼容：

- `-WhatIf`
- `-Confirm`

默认入口只允许两种模式：

- `-ServerIp ...`
- `-Reset`

如果两者都没传，或同时传入，脚本直接报错。

## Managed Files

### DERP JSON

默认受管路径使用跨平台用户目录，而不是硬编码 `/root/derp.json`：

- Linux/macOS：`~/.config/powershell-scripts/tailscale/derp.json`
- Windows：`%APPDATA%/powershell-scripts/tailscale/derp.json`

如果用户显式传入 `-OutputPath`，则优先使用用户指定路径。

### State File

脚本还会维护一个配套状态文件，例如：

- Linux/macOS：`~/.config/powershell-scripts/tailscale/derp-state.json`
- Windows：`%APPDATA%/powershell-scripts/tailscale/derp-state.json`

状态文件至少记录：

- `AppliedAt`
- `ServerIp`
- `DerpJsonPath`
- `DerpMapUri`
- `RestoreArgs`
- `BaselinePrefs`
- `CliVersion`

其中 `RestoreArgs` 是取消时最关键的数据，因为它代表“应用前可恢复的命令参数集合”。

## DERP JSON Contract

脚本生成的 JSON 保持固定骨架，只替换用户指定字段与端口参数：

- `RegionID` 使用 `-RegionId`
- `RegionCode` 使用 `-RegionCode`
- `Name` 使用 `-NodeName`
- `HostName` 使用 `-ServerIp`
- `DERPPort` 使用 `-DerpPort`
- `STUNPort` 使用 `-StunPort`
- `InsecureForTests` 固定为 `true`

本次不支持多节点或多 Region 组合输入，避免把“单机一键应用”做成半成品配置编排器。

## Path And URI Handling

脚本不能把用户路径原样拼接进 `file://`。

需要统一处理：

- Windows 盘符路径，例如 `C:\Users\Alice\AppData\Roaming\...`
- 带空格路径
- Linux/macOS 的绝对路径

因此脚本需要先把目标路径标准化为绝对路径，再转换成合法 URI，例如：

- Linux: `file:///home/alice/.config/powershell-scripts/tailscale/derp.json`
- macOS: `file:///Users/alice/.config/powershell-scripts/tailscale/derp.json`
- Windows: `file:///C:/Users/Alice/AppData/Roaming/powershell-scripts/tailscale/derp.json`

## Compatibility Strategy

由于当前本地 `tailscale` 帮助输出中未公开列出目标 flag，本设计把兼容性处理定义为显式责任，而不是隐含假设。

### Apply Compatibility

应用流程中，脚本需要捕获 `tailscale` 的参数错误。

如果命令报出类似：

- `flag provided but not defined`
- `unknown flag`

则脚本要把原始错误包装成更明确的提示，说明当前客户端不支持：

- `--derp-map-url`
- `--tls-skip-verify`

并提示用户升级或切换到支持这两个参数的 Tailscale 构建。

### Reset Compatibility

取消流程同样依赖状态文件中保存的恢复参数。如果恢复命令因为 CLI 版本变化而失败，脚本应保留状态文件与 DERP JSON，不做清理，避免用户丢失恢复依据。

## Baseline Snapshot And Restore

### Why Snapshot

`tailscale up` 在带参数时要求传入“完整期望设置集”。因此：

- 如果脚本只追加 DERP 相关参数而不考虑用户现有设置，可能触发 CLI 拒绝
- 即便命令成功，也可能让用户误丢此前启用的 `--ssh`、`--accept-routes`、`--hostname` 等设置

所以脚本必须先读取当前偏好，再生成可恢复的基线参数。

### Snapshot Source

优先使用：

`tailscale debug localapi GET /localapi/v0/prefs`

因为它直接返回结构化 JSON，更适合作为测试输入和状态快照。

### Supported Restore Mapping

脚本需要把基线偏好映射成一组显式恢复参数。第一阶段只支持当前仓库需要的公开稳定字段，例如：

- `ControlURL` -> `--login-server`
- `CorpDNS` -> `--accept-dns`
- `RouteAll` -> `--accept-routes`
- `ExitNodeIP` -> `--exit-node`
- `ExitNodeAllowLANAccess` -> `--exit-node-allow-lan-access`
- `RunSSH` -> `--ssh`
- `ShieldsUp` -> `--shields-up`
- `Hostname` -> `--hostname`
- `AdvertiseRoutes` -> `--advertise-routes`
- `AdvertiseTags` -> `--advertise-tags`
- `NoSNAT` -> `--snat-subnet-routes=false`

对于不在这份映射内、且检测为非默认状态的字段，脚本应在应用前直接失败，并指出当前版本尚不能安全托管这台机器的全部 Tailscale 偏好。

也就是说：

- 宁可拒绝应用
- 也不在“不知道怎么恢复”的前提下修改用户网络配置

## Command Construction

### Apply Command

应用命令的语义是：

1. 先带上“应用前基线恢复参数”
2. 再叠加自定义 DERP 参数

目标效果类似：

```bash
tailscale up <restore-args...> --derp-map-url=file:///.../derp.json --tls-skip-verify
```

### Reset Command

取消命令不通过重新推导当前状态，而是直接重放状态文件里保存的 `RestoreArgs`：

```bash
tailscale up <restore-args...>
```

这样“取消”表达的是：

- 恢复到应用前的配置
- 不显式附带自定义 DERP 参数

如果恢复成功，再删除受管文件。

## Validation Rules

脚本至少需要校验以下内容：

- `tailscale` 命令存在且可执行
- `-ServerIp` 为合法 IPv4、IPv6 或符合主机名基本格式
- 端口号在 `1..65535`
- `-OutputPath` 指向的目录可创建
- 应用模式下，如果已存在旧状态文件，需要明确判定是覆盖、拒绝，还是先提示用户 `-Reset`

本设计选择保守策略：

- 如果检测到已有活动状态文件，且没有显式 `-Reset`，则直接失败
- 先要求用户取消旧配置，再应用新 IP

这样能避免“连续覆盖”导致状态文件与真实网络状态错位。

## Error Handling

需要主动覆盖的失败场景包括：

- `tailscale` 未安装
- `tailscale` 命令不可访问本地守护进程
- `-ServerIp` 非法
- 目录创建失败
- DERP JSON 写入失败
- 无法获取当前 `prefs`
- 当前 `prefs` 含有脚本暂不支持恢复的非默认字段
- `tailscale` CLI 不识别 `--derp-map-url` 或 `--tls-skip-verify`
- `-Reset` 时状态文件不存在
- `-Reset` 恢复失败

其中：

- `-Reset` 恢复失败时，必须保留状态文件与 DERP JSON
- 只有在恢复命令成功后，才能清理受管文件

## Testing Strategy

本次改动会涉及 `scripts/pwsh/**` 与 `tests/**/*.ps1`，实现阶段需要执行：

```powershell
pnpm qa
pnpm test:pwsh:all
```

测试覆盖至少包含以下几类：

### Path And JSON Tests

- DERP JSON 内容正确嵌入用户指定 IP
- 默认路径在不同平台上的解析结果正确
- 绝对路径能正确转换为 `file://` URI

### Snapshot And Restore Tests

- 给定一份 `prefs` JSON，能够生成稳定的 `RestoreArgs`
- 当 `prefs` 中出现当前不支持恢复的非默认字段时，函数会失败
- 状态文件能正确保存并读取 `RestoreArgs`

### Command Construction Tests

- 应用模式命令包含 `RestoreArgs`
- 应用模式命令追加 `--derp-map-url=...`
- 应用模式命令追加 `--tls-skip-verify`
- 取消模式命令只重放 `RestoreArgs`，不再包含 DERP 参数

### Failure Handling Tests

- 当 `tailscale` 返回未知 flag 错误时，会输出明确兼容性提示
- 当恢复失败时，不会删除状态文件
- 当已有活动状态文件时，重复应用会被拒绝

## Documentation Changes

实现完成后，需要更新：

`docs/cheatsheet/network/tailscale/index.md`

补充内容至少包括：

- 一键应用自建 DERP 的示例
- 一键取消并恢复默认 Tailscale 行为的示例
- “当前客户端若不支持 `--derp-map-url` / `--tls-skip-verify`，脚本会直接报错”的兼容性说明

## Risks And Trade-offs

### Experimental Flag Risk

最大的风险不是 PowerShell 本身，而是 Tailscale CLI 对这两个参数的支持状态可能因版本或发行渠道不同而变化。

因此本设计把“显式失败并提示兼容性问题”视为正确行为，而不是缺陷。

### Restore Coverage Risk

脚本不应承诺“无条件恢复所有 Tailscale 高级配置”。相反，它应当：

- 先判断当前配置是否在可恢复支持范围内
- 超出范围时拒绝应用

这比“先改了再说”要安全得多。

### State File Coupling

取消流程依赖状态文件，这是一个有意为之的约束。代价是：

- 如果用户手工删除状态文件，脚本将无法安全恢复

但好处更重要：

- 恢复语义清晰
- 不需要在“应用后状态”上做不可靠反推

## Open Questions

- 未来是否要支持“强制覆盖已有状态文件”的高级模式；本次先不做
- 未来是否要支持多 Region / 多 Node DERP JSON；本次先不做
- 如果后续验证到某些 Tailscale 构建确实公开支持 `tailscale set --derp-map-url`，后续可以把实现进一步收敛为局部更新，不必再依赖 `tailscale up` 的完整参数回放
