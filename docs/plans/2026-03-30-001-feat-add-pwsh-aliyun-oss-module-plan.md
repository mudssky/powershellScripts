---
title: feat: add pwsh aliyun oss module
type: feat
status: active
date: 2026-03-30
origin: docs/brainstorms/2026-03-30-pwsh-aliyun-oss-module-brainstorm.md
---

# feat: add pwsh aliyun oss module

## Overview

本计划承接 `docs/brainstorms/2026-03-30-pwsh-aliyun-oss-module-brainstorm.md`，目标是在仓库中新增一套真正可复用的 PowerShell OSS 能力层，而不是只把 Bash 脚本翻译成另一个单文件入口。

交付物分成两层：

1. 在 `psutils/modules/oss.psm1` 中沉淀对象化的 OSS 公共能力，覆盖配置对象、V4 签名、轻量读操作、单文件上传和目录上传。
2. 在 `scripts/pwsh/network/aliyun-oss-put.ps1` 中提供薄脚本入口，复用模块能力并保留熟悉的脚本调用体验。

该计划直接继承 brainstorm 中已经确认的范围：首版仅依赖 PowerShell 内置 cmdlet 与 .NET 标准能力；目录上传只做“本地文件批量上传到目标前缀”；默认不覆盖；比 Bash 版更强调对象化输出、批量处理和后续扩展空间（see origin: `docs/brainstorms/2026-03-30-pwsh-aliyun-oss-module-brainstorm.md`）。

## Problem Frame

当前仓库已有一个 Bash 版 OSS 脚本 `scripts/bash/aliyun-oss-put.sh`，它适合资源受限环境里的“单文件、少依赖、直接执行”场景，但它刻意没有往可复用工具层发展。现在需要补齐的是另一条能力线：面向 PowerShell 自动化与 `psutils` 模块生态，提供更强的 OSS 公共 API、稳定测试面和更贴近 PowerShell 习惯的配置模型。

这个问题的重点不是“能不能发出一个 PUT 请求”，而是怎样在不引入第三方 SDK 的前提下，把以下几件事一起做对：

- 用 PowerShell / .NET 自己完成 OSS V4 签名、请求发送与响应解析。
- 把配置模型从 Bash 的参数 + 环境变量中心，转成 PowerShell 风格的显式参数与配置对象。
- 提供单文件与目录上传的公共 API，并把读操作一并设计成可复用能力，而不是只满足脚本入口。
- 让默认语义足够安全，尤其是“不覆盖已有对象”必须成为第一默认行为。
- 让测试既能稳定覆盖核心逻辑，又不把 CI 成功与否压在真实 OSS 网络环境上。

## Requirements Trace

- R1. 新增独立 `psutils/modules/oss.psm1`，作为 OSS 相关公共能力的唯一落点。
- R2. 所有签名、摘要、HTTP、文件流与响应解析都只使用 PowerShell 内置能力和 .NET 标准库，不依赖第三方 SDK 或外部工具。
- R3. 模块 API 以显式参数与配置对象为主，不把 dotenv / 环境变量作为主交互模型。
- R4. 首版支持 `AccessKeyId + AccessKeySecret`，可选 `SecurityToken`，并允许 `Bucket + Region` 自动推导目标地址，同时支持 `Endpoint` / `Host` 覆盖。
- R5. 提供单文件上传 API，并返回适合 PowerShell 管道消费的结果对象。
- R6. 提供目录上传 API，把本地目录递归映射到 OSS 前缀；首版不删除远端多余对象。
- R7. 默认不覆盖已有对象，仅在显式 `-Force` 或等价参数时允许覆盖。
- R8. 首版除上传外，还要有对象存在性检查、对象元信息读取与简单对象列举能力。
- R9. 在 `scripts/pwsh/network/` 下提供薄脚本入口，协议细节全部委托给 `oss.psm1`。
- R10. 新增模块与脚本要补齐 Pester 测试，核心正确性不能依赖真实 OSS 环境。
- R11. pwsh 版首发要明显比 Bash 版更偏“可复用工具层”，而不是只补一个等价脚本。

## Scope Boundaries

- 首版不交付完整 OSS SDK，不在这一轮实现下载、删除、镜像同步、分片上传、断点续传或并发控制。
- 首版目录上传只做“本地文件递归上传到目标前缀”，不负责让远端前缀与本地目录完全一致。
- 首版不以 `.env` 文件或环境变量为主要入口；即使后续要补兼容，也不能反过来主导模块设计。
- 首版不要求与 Bash 版 CLI 契约完全同构；脚本命名可保持相近，但参数模型和输出风格以 PowerShell 习惯优先。
- 首版不把真实 OSS 联调测试纳入默认 QA / Pester 门禁。

## Context & Research

### Relevant Code and Patterns

- `psutils/psutils.psd1` 已经采用 `NestedModules + FunctionsToExport` 的明确导出模式，新增公共模块时需要同步更新导入与导出清单。
- `psutils/modules/selection.psm1` 与 `psutils/tests/selection.Tests.ps1` 提供了近期新增 `psutils` 模块的参考模式：模块内保留未导出 helper，公共 API 单独导出，测试同时覆盖模块语义和 manifest 导出。
- `tests/Invoke-Benchmark.Tests.ps1` 展示了当前仓库对脚本入口的测试风格：脚本级集成测试优先验证参数路由、取消路径和跨平台执行边界，底层行为则交给模块级测试覆盖。
- `scripts/pwsh/network/downWith.ps1` 与 `scripts/pwsh/devops/start-container.ps1` 展示了 `scripts/pwsh` 的脚本约定：帮助文档齐全、`[CmdletBinding()]` 明确、对副作用脚本启用 `SupportsShouldProcess`。
- `scripts/pwsh/devops/run.ps1` 会递归扫描 `scripts/pwsh/**/*.ps1`，因此新脚本放入 `scripts/pwsh/network/` 后可自动进入脚本发现体系，无需额外改造运行入口。
- `scripts/bash/aliyun-oss-put.sh` 已经沉淀出 Bash 版的核心业务边界，可作为“上传对象、目标定位、默认不覆盖、支持 STS”的行为基线，但不会成为 pwsh 版 API 设计的上限。

### Institutional Learnings

- `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md` 说明跨平台 PowerShell 测试不能默认沿用 Windows 语义；凡是会影响 `PATH`、shebang、执行位或平台特定命令的逻辑，都要通过可控 seam 和真实 Unix 假体来验证。
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md` 说明外部命令与网络能力必须放到稳定 seam 后再测试，默认门禁更适合验证“模块语义 + 可控集成链路”，而不是依赖环境恰好存在某个工具。
- `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md` 给出新增公共模块的经验：应先沉到 `psutils`，通过显式公共 API 提供复用面，再由脚本做薄接入；同时避免在轻量探测路径上引入高成本命令发现。

### External References

- Alibaba Cloud OSS V4 签名文档（Last Updated: 2026-03-20）明确要求在 `Authorization` 中携带 `OSS4-HMAC-SHA256` 格式的 V4 签名；如果不使用 SDK，需要自行实现该签名流程。
- Alibaba Cloud `PutObject` 文档（Last Updated: 2026-03-06）明确指出单次简单上传最大为 5 GB、默认会覆盖同名对象、`x-oss-forbid-overwrite=true` 可阻止覆盖、`x-oss-meta-*` 与 `x-oss-tagging` 可用于元数据与标签。
- Alibaba Cloud `HeadObject` 文档说明对象不存在时返回 `404 NoSuchKey`，适合作为 `Test-OssObject` 与默认非覆盖上传的预检查基础。
- Alibaba Cloud `ListObjectsV2` 文档说明 `prefix`、`delimiter`、`ContinuationToken`、`encoding-type=url` 的行为，可直接指导轻量列举 API 的请求与解析设计。
- Alibaba Cloud `Regions and endpoints` 文档（Last Updated: 2026-03-24）说明 2025-03-20 起，中国内地新 OSS 用户执行数据 API 操作必须优先使用自定义域名（CNAME）；因此模块必须允许显式 `Endpoint` / `Host` 覆盖，而不能只相信 `Bucket + Region` 自动拼接。

## Key Technical Decisions

- **公共模块边界固定为 `psutils/modules/oss.psm1`**：不把 OSS 能力塞进现有 `network.psm1`，避免网络通用工具和云存储对象操作混在一起。
- **脚本入口命名沿用 `aliyun-oss-put` 心智，但实现升级为多参数集薄入口**：新增 `scripts/pwsh/network/aliyun-oss-put.ps1`，通过单文件与目录两个参数集调用模块公共 API。
- **导出的公共命令采用 PowerShell 风格而不是 Bash 风格**：首版公共 surface 规划为 `New-OssContext`、`Test-OssObject`、`Get-OssObjectInfo`、`Get-OssObjectList`、`Publish-OssObject`、`Publish-OssDirectory`。
- **底层 HTTP 传输统一走受控的 .NET `HttpClient` 封装**：相比 `Invoke-RestMethod` / `Invoke-WebRequest`，`HttpRequestMessage` 更适合稳定处理 `HEAD`、`PUT`、流式文件上传、自定义头、响应头读取与错误对象归一化；测试时通过内部 transport seam Mock，而不是直接 Mock .NET 静态调用。
- **默认不覆盖采用“双保险”策略**：当未显式 `-Force` 时，先调用 `Test-OssObject` 做存在性预检查，再在 `PUT` 请求头中携带 `x-oss-forbid-overwrite=true`。这样既满足“默认失败”，又尽量缩小预检查与写入之间的竞争窗口；版本控制 bucket 对该头无效的限制需要在结果与文档中说明。
- **上传函数支持 `ShouldProcess`**：`Publish-OssObject`、`Publish-OssDirectory` 与脚本入口都应启用 `SupportsShouldProcess`，让 `-WhatIf` / `-Confirm` 成为 PowerShell 原生安全阀。
- **目录上传默认 fail-fast，但返回结构化逐项结果**：一旦某个文件失败，默认停止后续上传并抛出包含已完成项与失败项的结构化错误/结果，以保持默认语义简单、可诊断。
- **配置对象优先于环境变量**：`New-OssContext` 负责把 `Bucket`、`Region`、`Endpoint` / `Host`、鉴权信息和默认头配置归一为一个对象，公共 API 统一接受 `-Context`；脚本入口再把显式参数映射到该对象。
- **对象读操作只覆盖高价值轻量能力**：`Test-OssObject` 用于布尔存在性检查；`Get-OssObjectInfo` 用于读取响应头/元信息；`Get-OssObjectList` 用于基于 `prefix` / `delimiter` 的对象列举，不延伸到下载或删除。
- **尽量维持当前 `psutils` 可移植编码风格，但验证目标以 PowerShell 7 为准**：实现避免无必要的 7-only 语法糖；默认测试与脚本执行语义仍以仓库现有的 pwsh 7 host / Linux Docker 路径为准。

## Open Questions

### Resolved During Planning

- **公共 API 命名是否直接沿用 Bash 风格？**  
  否。脚本入口保留 `aliyun-oss-put.ps1` 便于发现，但模块公共 API 采用 `Verb-Oss*` 风格的 PowerShell 命名。

- **HTTP 层是否继续使用 `Invoke-RestMethod` / `Invoke-WebRequest`？**  
  否。首版计划使用内部 `HttpClient` 封装，以获得更稳定的请求/响应控制面与更清晰的测试 seam。

- **默认“不覆盖”只靠 `x-oss-forbid-overwrite` 是否足够？**  
  不足够。首版需要 `HEAD` 预检查 + `x-oss-forbid-overwrite=true` 组合，兼顾显式行为和服务端约束。

- **脚本入口放在哪个分类？**  
  放在 `scripts/pwsh/network/`，复用现有脚本分类与 `run.ps1` 的自动发现能力。

- **测试是否需要同时覆盖模块级和脚本级？**  
  需要。模块级测试负责签名、请求构造、目录映射和结果对象；脚本级测试负责参数集、`ShouldProcess`、入口路由和用户可见行为。

### Deferred to Implementation

- **结果对象最终字段命名**：例如上传结果中的 `RequestId`、`ETag`、`VersionId`、`ResolvedHost`、`RelativePath` 是否全部暴露，以及字段命名大小写如何统一，适合在实际编码时结合现有对象风格细化。
- **`Get-OssObjectList` 的分页便利层具体形态**：计划保留 `ContinuationToken` / `MaxKeys` 基础参数，并允许实现阶段决定是否额外提供 `-All` 便利开关。
- **元数据与标签参数的最终 PowerShell 输入形态**：当前计划偏向使用 `hashtable` / `IDictionary`，具体是否再引入额外格式校验 helper 可在编码时决定。
- **脚本输出摘要的精简程度**：计划上保留对象化结果为主、控制台摘要为辅，但最终展示字段与颜色策略留到实现阶段按实际体验微调。

## High-Level Technical Design

> *This illustrates the intended approach and is directional guidance for review, not implementation specification. The implementing agent should treat it as context, not code to reproduce.*

```text
scripts/pwsh/network/aliyun-oss-put.ps1
  -> 解析参数集（单文件 / 目录）
  -> New-OssContext
  -> Publish-OssObject / Publish-OssDirectory

psutils/modules/oss.psm1
  -> Resolve-OssEndpoint / Resolve-OssHeaders / Resolve-OssObjectKey
  -> Build canonical request + string-to-sign + Authorization
  -> Invoke-OssHttpRequest (HttpClient seam)
  -> Parse response headers / XML / error payload
  -> Return PSCustomObject results

Read path:
  Test-OssObject      -> HEAD /ObjectName -> 404 => $false, 2xx => $true
  Get-OssObjectInfo   -> HEAD /ObjectName -> normalize headers + metadata
  Get-OssObjectList   -> GET /?list-type=2&prefix=... -> parse XML page

Write path:
  Publish-OssObject
    -> if -not Force: Test-OssObject + x-oss-forbid-overwrite=true
    -> PUT /ObjectName with file stream, metadata, tags, content-type
    -> return upload result

  Publish-OssDirectory
    -> enumerate files recursively
    -> map relative path to key prefix using '/'
    -> per file: Publish-OssObject
    -> accumulate results, fail-fast on first error by default
```

## Implementation Units

- [ ] **Unit 1: 建立 `oss.psm1` 模块契约与导出面**

**Goal:**  
为 OSS 能力建立清晰的模块边界、公共 API 名称、配置对象与结果对象约定，让后续签名、上传和脚本入口都基于同一套 contract 演进。

**Requirements:**  
R1, R3, R4, R8, R11

**Dependencies:**  
None

**Files:**
- Create: `psutils/modules/oss.psm1`
- Modify: `psutils/psutils.psd1`
- Modify: `psutils/README.md`
- Test: `psutils/tests/oss.Tests.ps1`

**Approach:**
- 在 `oss.psm1` 中先定义首版公共 surface：`New-OssContext`、`Test-OssObject`、`Get-OssObjectInfo`、`Get-OssObjectList`、`Publish-OssObject`、`Publish-OssDirectory`。
- `New-OssContext` 负责归一化鉴权与寻址配置，输出供后续命令消费的上下文对象；公共命令优先接受 `-Context`，必要时保留直传参数便利层。
- 结果对象统一采用 `PSCustomObject`，避免过早引入自定义类增加模块复杂度。
- 在 `psutils/psutils.psd1` 中同步更新 `NestedModules` 与 `FunctionsToExport`，并在 `psutils/README.md` 增补 OSS 模块说明。

**Execution note:**  
先从失败的 manifest / export 测试开始，固定公共 surface，再进入后续实现。

**Patterns to follow:**
- `psutils/modules/selection.psm1`
- `psutils/tests/selection.Tests.ps1`
- `psutils/psutils.psd1`

**Test scenarios:**
- `psutils.psd1` 显式导出新的 OSS 公共函数。
- `New-OssContext` 能正确保留 `Bucket`、`Region`、`Endpoint` / `Host`、`SecurityToken` 等配置。
- 缺少必要鉴权或目标信息时抛出清晰异常，而不是延迟到传输层才失败。
- `ShouldProcess` 能力只出现在写操作函数上，读函数保持纯读取语义。

**Verification:**
- 新模块能够被 `Import-Module .\psutils\psutils.psd1` 正常加载。
- 公共函数名、配置对象和导出清单稳定，后续单元不再需要反复改 contract。

- [ ] **Unit 2: 实现 V4 签名、传输 seam 与轻量读操作**

**Goal:**  
把 OSS V4 请求构造与发送路径做成可测的底层能力，并先落地读操作，为上传和默认非覆盖策略提供稳定基础。

**Requirements:**  
R2, R4, R8, R10

**Dependencies:**  
Unit 1

**Files:**
- Modify: `psutils/modules/oss.psm1`
- Test: `psutils/tests/oss.Tests.ps1`

**Approach:**
- 在模块内实现未导出的请求辅助函数，例如 host/endpoint 解析、canonical request 构造、HMAC 派生、`Authorization` 头生成、通用请求头合并和响应归一化。
- 传输层通过一个内部 `Invoke-OssHttpRequest` seam 调用 `HttpClient`，返回统一的状态码、响应头、响应体和 request id 信息，便于 Pester Mock。
- `Test-OssObject` 使用 `HEAD` 并仅把 `404 NoSuchKey` 归一为 `$false`；其他 4xx / 5xx 继续上抛。
- `Get-OssObjectInfo` 读取 `ETag`、`Content-Length`、`Last-Modified`、`Content-Type`、版本信息和 `x-oss-meta-*` 元数据。
- `Get-OssObjectList` 使用 `list-type=2`，首版覆盖 `Prefix`、`Delimiter`、`MaxKeys`、`ContinuationToken`，并把 `Contents`、`CommonPrefixes` 与分页信息解析成结构化对象。

**Execution note:**  
以固定输入的签名测试和 mocked transport 测试为主，避免一上来依赖真实网络。

**Patterns to follow:**
- `psutils/tests/selection.Tests.ps1` 中对模块 helper 的 Mock 方式
- `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`
- `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md`

**Test scenarios:**
- `Authorization` 头包含正确的 `OSS4-HMAC-SHA256 Credential=...` 结构，`SecurityToken` 存在时能进入签名头集合。
- `Bucket + Region` 默认 host 推导与显式 `Endpoint` / `Host` 覆盖都能正确构造请求 URL。
- `Test-OssObject` 在 `404 NoSuchKey` 时返回 `$false`，在 `200 OK` 时返回 `$true`。
- `Get-OssObjectInfo` 能从 `HEAD` 响应头中提取基础字段与用户元数据。
- `Get-OssObjectList` 能正确解析 `Prefix`、`CommonPrefixes`、`Contents`、`IsTruncated` 和 `NextContinuationToken`。

**Verification:**
- 不访问真实 OSS 的情况下，签名与请求构造逻辑可被稳定回归。
- 读操作已经足以支撑后续默认非覆盖上传和脚本前后置检查。

- [ ] **Unit 3: 实现对象上传与目录上传工作流**

**Goal:**  
交付真正可用的写操作 API，覆盖单文件上传、目录映射上传、默认不覆盖、元数据/标签透传和结构化结果输出。

**Requirements:**  
R2, R4, R5, R6, R7, R10, R11

**Dependencies:**  
Unit 2

**Files:**
- Modify: `psutils/modules/oss.psm1`
- Test: `psutils/tests/oss.Tests.ps1`

**Approach:**
- `Publish-OssObject` 接受本地文件路径、对象键、上下文对象及可选上传参数，如 `ContentType`、`Metadata`、`Tags`、`StorageClass`。
- 默认路径先做 `Test-OssObject` 预检查；若对象已存在则在本地直接失败，不发送 `PUT`；真正发送请求时附带 `x-oss-forbid-overwrite=true` 以降低竞争窗口风险。
- `-Force` 分支跳过预检查，并允许省略 `x-oss-forbid-overwrite=true`。
- `Publish-OssDirectory` 负责目录遍历、相对路径计算、`\` 到 `/` 的 key 归一化、前缀拼接和逐文件调用 `Publish-OssObject`。
- 目录上传返回逐文件结果集合；默认遇到首个失败停止，保留已成功项与失败项上下文。

**Execution note:**  
写操作单元优先从 `-WhatIf`、默认非覆盖和目录映射这些最容易回归的场景切入，再补 happy path。

**Patterns to follow:**
- `scripts/pwsh/filesystem/renameLegal.ps1`
- `tests/Sync-PathFromBash.Tests.ps1`
- `scripts/bash/aliyun-oss-put.sh`

**Test scenarios:**
- 文件不存在时在本地失败，不发送网络请求。
- 目标对象不存在且未指定 `-Force` 时，执行 `PUT` 并返回包含 `ETag` / `RequestId` 的结果对象。
- 目标对象已存在且未指定 `-Force` 时，本地失败并保证未发起 `PUT`。
- 指定 `-Force` 时跳过默认阻止逻辑，允许上传覆盖。
- `-WhatIf` / `ShouldProcess` 路径下不发送真实请求，并给出正确的操作描述。
- 目录上传能把嵌套目录、空格文件名、中文文件名映射到正确的 OSS key 前缀。
- 元数据与标签被正确转成 `x-oss-meta-*` 与 `x-oss-tagging` 相关请求内容。

**Verification:**
- 单文件与目录上传行为都能通过本地 Pester 稳定回归。
- 默认“不覆盖”语义和 `-Force` 例外语义明确可预测。

- [ ] **Unit 4: 提供薄脚本入口并补齐脚本级测试与文档**

**Goal:**  
把 `oss.psm1` 的公共能力包装成仓库可直接执行的 pwsh 脚本入口，并完成脚本发现与使用文档更新。

**Requirements:**  
R3, R5, R6, R7, R9, R10

**Dependencies:**  
Unit 1, Unit 2, Unit 3

**Files:**
- Create: `scripts/pwsh/network/aliyun-oss-put.ps1`
- Create: `tests/AliyunOssPut.Tests.ps1`
- Modify: `docs/scripts-index.md`
- Modify: `README.md`
- Modify: `psutils/README.md`
- Test: `tests/AliyunOssPut.Tests.ps1`

**Approach:**
- `aliyun-oss-put.ps1` 使用两个参数集：单文件上传参数集和目录上传参数集，共享鉴权、bucket、region、endpoint/host、`-Force`、`-WhatIf` 等参数。
- 脚本入口只负责参数验证、创建 `New-OssContext`、调用 `Publish-OssObject` 或 `Publish-OssDirectory`、以及输出适量摘要；不要在脚本层重写签名或请求逻辑。
- 为了贴近 PowerShell 体验，脚本应支持 `SupportsShouldProcess`，并在帮助文档里明确“默认不覆盖”“目录上传只追加不删除远端”的行为。
- 更新 `docs/scripts-index.md` 和 `README.md` 中与脚本发现相关的说明；在 `psutils/README.md` 增补 OSS 模块示例，强调它是可复用 API，而不仅是脚本专用 helper。

**Patterns to follow:**
- `scripts/pwsh/network/downWith.ps1`
- `scripts/pwsh/devops/start-container.ps1`
- `tests/Invoke-Benchmark.Tests.ps1`

**Test scenarios:**
- 单文件参数集正确路由到 `Publish-OssObject`，并把共享参数映射到 `New-OssContext`。
- 目录参数集正确路由到 `Publish-OssDirectory`，并保留前缀、`-Force`、`-WhatIf` 等行为。
- 缺少必要参数时抛出清晰错误，而不是进入半初始化状态。
- `-WhatIf` 下脚本不调用真实写操作。
- 新脚本落位于 `scripts/pwsh/network/` 后，能够被现有脚本发现机制识别。

**Verification:**
- 用户可以直接运行 `pwsh -File ./scripts/pwsh/network/aliyun-oss-put.ps1 ...` 执行单文件或目录上传。
- 文档和脚本入口都明确反映模块真实能力与限制，不需要读源码才能理解行为边界。

## System-Wide Impact

- **Interaction graph:** `scripts/pwsh/network/aliyun-oss-put.ps1` 将成为新的 OSS 入口脚本；`psutils/psutils.psd1` 增加新的公共模块导出；`scripts/pwsh/devops/run.ps1` 会自动发现该脚本而无需额外改造。
- **Error propagation:** 传输层应把 HTTP 状态码、OSS 错误码、`x-oss-request-id` 和关键响应头归一进异常 / 结果对象；只有 `Test-OssObject` 的 `404 NoSuchKey` 被有意吸收为布尔 `false`。
- **State lifecycle risks:** 目录上传存在“部分文件已成功、后续文件失败”的自然风险；首版通过 fail-fast + 已完成结果集合减少诊断成本，但不会自动回滚远端对象。
- **API surface parity:** Bash 版脚本仍保留其“资源受限环境入口”的定位；pwsh 版通过 `oss.psm1` 新增公共 API，不反向重构 Bash 版。
- **Integration coverage:** 模块级测试验证签名、请求与映射逻辑；脚本级测试验证参数集和 `ShouldProcess`；默认门禁不覆盖真实 OSS 网络联调。

## Risks & Dependencies

- **V4 签名与 canonical request 容易因 header 排序、URI 编码或 STS 头处理出错。**  
  缓解：使用固定输入的签名夹具与官方文档结构做比对，把签名构造拆成可独立断言的 helper。

- **中国内地 region 的域名策略变化会让“自动拼 host”在部分新账户下失效。**  
  缓解：显式支持 `Endpoint` / `Host` 覆盖，并在脚本帮助与文档里把该限制说清楚。

- **默认不覆盖的预检查路径存在并发竞争窗口。**  
  缓解：预检查后仍发送 `x-oss-forbid-overwrite=true`；在文档中说明版本控制 bucket 对该头的限制以及 race 并非完全可消除。

- **目录上传如果把所有行为都揉进脚本入口，会快速失去可测试性。**  
  缓解：坚持“脚本薄、模块厚”，目录遍历、key 映射和逐项结果都放进 `oss.psm1`。

- **若测试直接依赖真实 OSS，会让 `pnpm test:pwsh:all` 变脆。**  
  缓解：默认测试全部 Mock transport seam；若后续需要 live smoke，应通过专用环境变量和独立命令启用，不纳入默认门禁。

## Documentation / Operational Notes

- 本计划实现后，文档至少需要同步更新 `psutils/README.md` 与 `docs/scripts-index.md`；`README.md` 只做必要的脚本发现或模块能力补充，不扩散成大规模文档重写。
- 该改动会触及 `scripts/pwsh/**`、`psutils/**` 与 `tests/**/*.ps1`，因此执行阶段需要遵循仓库约定跑 `pnpm qa`，并在提交前跑 `pnpm test:pwsh:all`；若本机 Docker 不可用，需要在结论中明确 Linux 覆盖依赖 CI 或 WSL。
- 首版不设计默认 live credential 通路；如果后续要做真实环境 smoke test，应优先设计成手动 opt-in，而不是自动从环境变量取密钥并联网。

## Sources & References

- **Origin document:** `docs/brainstorms/2026-03-30-pwsh-aliyun-oss-module-brainstorm.md`
- **Related code:** `scripts/bash/aliyun-oss-put.sh`
- **Related code:** `psutils/psutils.psd1`
- **Related code:** `psutils/modules/selection.psm1`
- **Related code:** `psutils/tests/selection.Tests.ps1`
- **Related code:** `tests/Invoke-Benchmark.Tests.ps1`
- **Related code:** `scripts/pwsh/devops/run.ps1`
- **Institutional learning:** `docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md`
- **Institutional learning:** `docs/solutions/workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md`
- **Institutional learning:** `docs/solutions/developer-experience/benchmark-interactive-selection-psutils-20260314.md`
- **External docs:** `https://www.alibabacloud.com/help/en/oss/developer-reference/recommend-to-use-signature-version-4`
- **External docs:** `https://www.alibabacloud.com/help/en/oss/developer-reference/putobject`
- **External docs:** `https://www.alibabacloud.com/help/en/oss/developer-reference/headobject`
- **External docs:** `https://www.alibabacloud.com/help/en/oss/developer-reference/listobjects-v2`
- **External docs:** `https://www.alibabacloud.com/help/en/oss/user-guide/regions-and-endpoints`
