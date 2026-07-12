# Tailscale DERP Policy Script Design

## Summary

本设计把仓库内的 `scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1` 从“本地调用 `tailscale up` 切换当前节点 DERP 配置”的脚本，改造成“离线编辑 tailnet policy 文件中 `derpMap`”的官方作法入口。

目标入口保持单脚本形态，但职责改为：

- 读取本地 tailnet policy 文件
- 在其中新增、更新或删除脚本受管的 `derpMap` Region
- 输出变更摘要与后续提交提示

目标命令形态为：

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -ServerIp 203.0.113.10 `
  -PolicyPath ./tailnet-policy.hujson
```

```powershell
./scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1 `
  -Reset `
  -PolicyPath ./tailnet-policy.hujson
```

本设计不再尝试通过本地 `tailscale up --derp-map-url=... --tls-skip-verify` 修改客户端状态，因为当前官方公开 CLI 与文档都不把这条路径作为跨平台支持方案。

## Context

仓库当前已经存在一套基于本地 CLI 参数的实现与文档：

- `scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1`
- `tests/Set-TailscaleDerp.Tests.ps1`
- `docs/cheatsheet/network/tailscale/index.md`
- `docs/superpowers/specs/2026-04-20-tailscale-custom-derp-script-design.md`

但经过本地验证与官方文档核对，当前现实约束已经很明确：

- `tailscale up --help` 的公开参数中没有 `--derp-map-url`
- `tailscale up --help` 的公开参数中没有 `--tls-skip-verify`
- 官方推荐的自定义 DERP 入口是 tailnet policy 中的 `derpMap`
- `derpMap` 属于 tailnet 级配置，而不是单台客户端的本地临时开关

这意味着仓库当前实现所依赖的前提已经失效，继续围绕本地 `tailscale up` 做兼容补丁没有长期价值。

## Goals

- 把脚本改造成符合当前官方作法的 DERP 配置入口
- 继续保留单脚本体验，降低用户修改 `derpMap` 的门槛
- 支持通过参数生成单 Region + 单 Node 的 `derpMap` 配置
- 只修改脚本受管的目标 Region，尽量不影响用户其它 policy 内容
- 提供 `-Reset` 能力，删除脚本受管的目标 Region
- 支持 `-WhatIf` / `-Confirm`
- 补齐新的单元测试，并同步修正文档与旧设计说明

## Non-Goals

- 不再调用 `tailscale up`、`tailscale set` 或其它本地 CLI 去应用 DERP
- 不直接修改当前机器上的 Tailscale 在线状态
- 不直接调用 Tailscale Admin API
- 不负责自动上传或提交 policy 到 Tailscale Admin Console
- 不生成完整的 tailnet policy 模板
- 不支持多 Region / 多 Node 的复杂交互式编排
- 不保留旧实现中的 `derp.json` 与 `derp-state.json` 受管文件模型

## Chosen Approach

采用“单脚本 + 本地 policy 文件编辑 + 受管 Region 更新”的方案。

### Why This Approach

相比直接调用 Tailscale API，这条路径更适合当前仓库：

- 不需要引入 API token、权限管理和线上误改风险
- 变更可以走本地文件 diff，更容易审阅和回滚
- PowerShell 测试可以完全离线运行
- 与官方推荐的 `derpMap` 配置方式一致

### High-Level Flow

#### Apply Flow

1. 校验 `-PolicyPath` 存在且可读取
2. 解析现有 tailnet policy 文件
3. 校验 `-ServerIp` 与 DERP 参数合法
4. 生成单 Region + 单 Node 的 `derpMap` 片段
5. 将受管 `RegionID` 写入 `policy.derpMap.Regions`
6. 输出规范化后的 policy 文件
7. 返回变更摘要，并提示用户提交到 Admin Console 或 GitOps

#### Reset Flow

1. 校验 `-PolicyPath` 存在且可读取
2. 解析现有 tailnet policy 文件
3. 删除脚本受管的目标 `RegionID`
4. 如果删除后 `Regions` 为空，则移除整个 `derpMap`
5. 输出规范化后的 policy 文件
6. 返回变更摘要，并提示用户提交到 Admin Console 或 GitOps

## CLI Contract

脚本文件保持不变：

`scripts/pwsh/network/tailscale/Set-TailscaleDerp.ps1`

### Primary Parameters

- `-ServerIp <string>`：Apply 模式必填，与 `-Reset` 互斥
- `-Reset`：Reset 模式开关，与 `-ServerIp` 互斥
- `-PolicyPath <string>`：必填，目标 tailnet policy 文件路径

### DERP Parameters

- `-RegionId <int>`：默认 `900`
- `-RegionCode <string>`：默认 `cn-custom`
- `-NodeName <string>`：默认 `cn-node`
- `-DerpPort <int>`：默认 `8443`
- `-StunPort <int>`：默认 `3478`

### Output Parameters

- `-OutputPath <string>`：可选，允许把结果写到新文件而不是覆盖 `-PolicyPath`
- `-PrintSnippet`：可选，只输出本次生成的 `derpMap` 片段，不落盘；该模式下不要求 `-PolicyPath`
- `-PassThru`：可选，返回结构化结果对象，便于脚本链路继续消费

### Execution Semantics

- 默认采用 `CmdletBinding(SupportsShouldProcess = $true)`
- 支持 `-WhatIf`
- 支持 `-Confirm`
- 当用户既不传 `-ServerIp` 也不传 `-Reset` 时直接失败
- 当用户同时传入 `-ServerIp` 与 `-Reset` 时直接失败
- `-PrintSnippet` 只允许在 Apply 模式下使用，且不能与 `-Reset` 同时出现
- `-PrintSnippet` 与 `-OutputPath` 互斥

## Policy File Model

### Input Requirements

第一版要求：

- 常规 Apply / Reset 模式下，`-PolicyPath` 指向已存在的本地 policy 文件
- 文件内容必须是可解析的 JSON 或 HuJSON 结构
- 顶层必须是对象

如果文件不存在，脚本直接失败，不自动生成整份 policy 模板。

唯一例外是 `-PrintSnippet` 模式：

- 该模式不读取现有 policy
- 只根据输入参数生成 `derpMap` 片段
- 不写文件

### Format Strategy

第一版采用“解析成数据结构后整体规范化重写”的实现方式。

这意味着：

- 脚本会保留语义，但不保证保留原始注释
- 脚本会规范化输出格式与缩进
- 字段顺序可能按脚本输出逻辑稳定化，而不是保持原文件顺序

这样做的代价是格式会漂移，但优点是实现和测试成本可控，足以支撑第一版落地。

文档中必须明确写出这一行为，避免用户误以为脚本会完全保留原始 HuJSON 注释与排版。

## DERP Map Contract

脚本生成的受管 Region 保持单 Region + 单 Node 结构：

```json
{
  "derpMap": {
    "Regions": {
      "900": {
        "RegionID": 900,
        "RegionCode": "cn-custom",
        "Nodes": [
          {
            "Name": "cn-node",
            "RegionID": 900,
            "HostName": "203.0.113.10",
            "DERPPort": 8443,
            "STUNPort": 3478,
            "InsecureForTests": true
          }
        ]
      }
    }
  }
}
```

字段规则如下：

- `RegionID` 使用 `-RegionId`
- `RegionCode` 使用 `-RegionCode`
- `Name` 使用 `-NodeName`
- `HostName` 使用 `-ServerIp`
- `DERPPort` 使用 `-DerpPort`
- `STUNPort` 使用 `-StunPort`
- `InsecureForTests` 第一版固定为 `true`

第一版不扩展到多 Node 或多 Region 编辑器。

## Managed Scope And Conflict Rules

脚本只管理一个目标 `RegionID`，默认值为 `900`。

### Apply Rules

- 如果 `derpMap` 不存在，则创建 `derpMap`
- 如果 `derpMap.Regions` 不存在，则创建 `Regions`
- 如果目标 `RegionID` 不存在，则新增该 Region
- 如果目标 `RegionID` 已存在，则覆盖该 Region
- 其它 Region 保留不动

### Reset Rules

- 只删除目标 `RegionID`
- 其它 Region 保留不动
- 如果删除后 `Regions` 为空，则移除整个 `derpMap`

### Marker Strategy

第一版不向 policy 结构中额外写入私有 marker 字段。

受管范围仅由以下信息定义：

- `RegionID`
- `RegionCode`
- 用户显式参数

这样可以避免往官方结构中注入额外字段，降低与未来 policy 语法冲突的风险。

## Error Handling

脚本的错误边界从“本地 Tailscale CLI 能否识别参数”切换为“policy 文件是否可安全修改”。

### Preflight Errors

以下情况直接失败，且不落盘：

- `-PolicyPath` 未提供
- `-PolicyPath` 不存在
- policy 文件为空
- policy 文件无法解析
- 顶层结构不是对象
- `-ServerIp` 非法
- `RegionId`、`DerpPort`、`StunPort` 超出合理范围

### Write Safety

脚本需要先在内存中生成完整结果，只有全部校验通过才写入目标文件。

如果用户提供 `-OutputPath`：

- 原始 `-PolicyPath` 只读
- 新内容写到 `-OutputPath`

如果用户未提供 `-OutputPath`：

- 直接覆盖 `-PolicyPath`
- 仍然通过 `ShouldProcess` 控制写入

### Result Object

如果用户提供 `-PassThru`，建议返回结构化结果，例如：

- `Mode`：`Apply` / `Reset`
- `PolicyPath`
- `OutputPath`
- `RegionId`
- `Changed`：是否发生实际变更
- `RemovedDerpMap`：Reset 后是否移除了整个 `derpMap`
- `Summary`

## Testing Strategy

### Unit Tests

`tests/Set-TailscaleDerp.Tests.ps1` 需要从“本地 CLI 驱动”重构到“policy 文件驱动”。

重点覆盖：

- 能在无 `derpMap` 的 policy 中新增受管 Region
- 能更新已存在的受管 Region
- 能保留其它 Region 不动
- `-Reset` 只删除目标 Region
- `-Reset` 在删空 `Regions` 后会移除整个 `derpMap`
- policy 文件不存在时失败
- 非法 JSON/HuJSON 时失败
- `-PrintSnippet` 只输出片段不落盘
- `-PrintSnippet` 在未提供 `-PolicyPath` 时仍可工作
- `-OutputPath` 不覆盖原文件
- `-WhatIf` 不写文件

### Repository Verification

按仓库要求，完成实现后需要运行：

- `pnpm qa`
- `pnpm test:pwsh:all`

## Documentation Impact

以下文档需要同步更新：

- `docs/cheatsheet/network/tailscale/index.md`
- `docs/superpowers/specs/2026-04-20-tailscale-custom-derp-script-design.md`

其中旧设计文档需要明确标注已被本设计取代，避免后续继续沿用本地 `tailscale up --derp-map-url` 路线。

文档更新重点：

- 删除本地 `tailscale up --derp-map-url` 用法
- 改为说明脚本编辑的是 tailnet policy 中的 `derpMap`
- 补充“提交到 Admin Console / GitOps”的后续步骤
- 说明脚本会规范化输出 policy 文件格式

## Risks And Trade-offs

- 第一版会规范化重写 policy 文件，可能丢失原注释和手工排版
- 不直接调用 API，意味着最后一步仍需要人工提交
- 只管理一个受管 Region，复杂多 Region 场景仍需人工介入

这些取舍是有意为之，因为第一版的首要目标是把路径切回官方支持方案，而不是一次性做成全自动 policy 运维平台。

## Open Questions

- 后续是否需要增加可选的 API 提交模式，例如 `-ApplyViaApi`
- 后续是否需要支持从现有 `derpMap` 中做更细粒度的多 Region / 多 Node 合并
- 后续是否需要引入 HuJSON 保真编辑能力，尽量保留原文件注释与格式

## Decision

本设计确定把 `Set-TailscaleDerp.ps1` 的职责正式切换为：

- 编辑本地 tailnet policy 文件中的 `derpMap`
- 不再依赖本地 `tailscale up`
- 不再依赖 `--derp-map-url` / `--tls-skip-verify`

这条路线与当前官方公开作法一致，也是当前仓库最稳妥、最可验证的落地方向。
