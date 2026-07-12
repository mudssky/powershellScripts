---
date: 2026-03-30
topic: pwsh-aliyun-oss-module
---

# PowerShell 版阿里云 OSS 模块与上传脚本

## Problem Frame

现有的 `scripts/bash/aliyun-oss-put.sh` 已经覆盖“资源受限环境中的极简单文件上传”场景，但它的设计前提就是能力收敛、依赖最少、适合在工具不完整的服务器上直接执行。

这次要补的是一条不同的产品线：为仓库内的 PowerShell 自动化场景提供一个更强、可复用、可测试的 OSS 能力层。它不是简单把 Bash 版翻译成 `.ps1`，而是要把 OSS 上传相关能力沉淀为 `psutils` 模块，在“只能使用 pwsh 内置方法”的约束下，支持对象化输入输出、单文件与目录上传、轻量读操作，以及后续继续扩展为小型 OSS 工具集的基础结构。

同时，这次还需要明确仓库落位：可复用逻辑进入 `psutils/modules/oss.psm1`，脚本入口保持轻量，放在 `scripts/pwsh` 下合适的分类目录中，优先复用模块而不是重复实现协议细节。

## Requirements

- R1. 提供独立的 `psutils/modules/oss.psm1` 模块，承载阿里云 OSS 相关的可复用能力，供 `scripts/pwsh` 脚本和后续其他 PowerShell 自动化直接复用。
- R2. 首版实现必须仅依赖 PowerShell 内置 cmdlet 与 .NET 标准能力完成摘要、签名、HTTP 请求、文件读取与响应处理，不依赖 `curl`、`openssl`、`Python`、`Node.js`、阿里云 CLI 或第三方 SDK。
- R3. 配置模型以 PowerShell 风格的显式参数或配置对象为主，而不是以 dotenv/环境变量驱动为核心交互方式。
- R4. 首版上传链路必须支持 `AccessKeyId + AccessKeySecret` 鉴权，并可选支持 `SecurityToken`；目标地址默认基于 `Bucket + Region` 推导，同时允许显式指定 `Endpoint` 或 `Host` 覆盖默认行为。
- R5. 提供单文件上传能力，覆盖本地文件到目标对象键的上传场景，并输出适合后续 PowerShell 管道处理的结果对象。
- R6. 提供目录上传能力，把本地目录中的文件批量映射到指定 OSS 前缀；首版只做“上传本地文件到目标前缀”，不负责删除远端多余对象，也不要求镜像同步。
- R7. 当目标对象已存在时，默认行为必须是失败；仅在用户显式传入覆盖参数（如 `-Force` 或等价选项）时才允许覆盖上传。
- R8. 首版模块除上传主链路外，还应提供轻量读操作，至少覆盖对象存在性检查、对象元信息读取与简单对象列举，方便脚本在上传前后做基本判断。
- R9. 在 `scripts/pwsh` 下提供薄脚本入口，建议落位于 `scripts/pwsh/network/`，脚本负责参数体验与调用编排，协议细节统一委托给 `psutils/modules/oss.psm1`。
- R10. 为新增模块与入口行为补充对应测试，至少覆盖签名/请求构造、配置模型、覆盖策略、目录上传映射、轻量读操作的主要分支；默认测试设计应尽量避免依赖真实 OSS 网络环境。
- R11. 相比 Bash 版，pwsh 版首发应更偏向“可复用工具层”，强调对象化结果、批量处理能力、清晰的错误边界和后续扩展空间，而不是仅追求最小可执行脚本。

## Success Criteria

- 可以在不借助外部二进制或第三方 SDK 的前提下，通过 PowerShell 完成单文件上传与目录上传。
- `psutils/modules/oss.psm1` 能被其他脚本直接复用，而不是只能服务单一入口脚本。
- 目录上传的默认语义清晰：只上传本地文件到目标前缀，不做远端删除同步。
- 覆盖策略清晰可预测：默认不覆盖，显式覆盖才执行替换。
- 首版测试能够在本地稳定验证大部分核心逻辑，不把正确性完全押给真实云端环境。
- 新入口脚本在仓库现有分类中有清晰落位，不需要为首版额外引入新的脚本大类。

## Scope Boundaries

- 首版不做“完整 OSS SDK”，不会在第一版同时交付下载、删除、镜像同步、断点续传、分片上传等更大能力面。
- 首版目录上传不负责让远端前缀与本地目录完全一致，不删除远端多余对象。
- 首版不要求以 `.env` 文件或环境变量作为主要使用方式；这些兼容能力即使后续需要，也不应主导 API 设计。
- 首版不为了和 Bash 版完全同构而牺牲 PowerShell 风格；脚本体验可以与 Bash 版不同，但能力边界要更强、更清晰。
- 首版不要求立即覆盖所有 OSS 对象操作，只覆盖上传主链路与少量高价值读操作。

## Key Decisions

- 模块边界采用独立文件 `psutils/modules/oss.psm1`，而不是把 OSS 能力散落到现有 `network.psm1` 中。
- 入口脚本建议放在 `scripts/pwsh/network/`，因为当前仓库已有网络类脚本分类，首版无需新建更大的 `cloud` 分类。
- 产品方向不是“翻译 Bash”，而是“做一层更强的 PowerShell OSS 工具能力”，并允许其后续逐步扩展。
- 配置入口采用 PowerShell 参数/对象优先，不把 dotenv 兼容当作核心体验。
- 鉴权首版支持 `AccessKeyId + AccessKeySecret`，并允许 `SecurityToken` 与 `Endpoint/Host` 覆盖。
- 目录上传采用追加式上传语义，只把本地文件批量推送到目标前缀，不做删除同步。
- 默认覆盖策略为“已存在则失败”，只有显式传入覆盖参数才允许覆盖。
- 首版命令集选择“上传主链路 + 轻量读操作”，而不是一次性铺开成完整对象管理工具集。

## Dependencies / Assumptions

- 假设阿里云 OSS 当前公开的签名与对象操作协议可以通过 PowerShell 内置能力稳定实现。
- 假设仓库现有 `psutils` 模块组织方式适合继续扩展单独的 `oss.psm1`，并通过 `psutils.psd1` 统一导出。
- 假设大部分测试可以通过 Mock、固定签名样例和本地文件夹夹具完成，而不是强依赖真实 OSS 环境。

## Outstanding Questions

### Resolve Before Planning

- 暂无。

### Deferred to Planning

- [Affects R1,R8][Technical] 首版具体导出的 cmdlet 命名方案如何设计，既符合 PowerShell 风格，又能和脚本入口命名保持清晰映射。
- [Affects R2,R4,R10][Technical] 具体 HTTP 层实现优先使用 `Invoke-RestMethod`、`Invoke-WebRequest` 还是更底层 .NET API，需要结合可测性与跨版本兼容性评估。
- [Affects R4,R5,R6][Technical] 上传相关结果对象的字段模型如何定义，才能同时兼顾脚本可读性和后续管道消费。
- [Affects R8,R10][Needs research] 轻量列举与元信息读取首版需要覆盖到什么粒度，才能在不显著膨胀接口面的前提下满足真实使用场景。
- [Affects R9,R10][Technical] 是否需要同时为 `scripts/pwsh/network` 入口补脚本级测试，还是以模块级测试为主、入口做轻量冒烟验证。
- [Affects R2][Needs research] 是否需要把 PowerShell 版本兼容范围收敛到 `pwsh 7+`，还是保持与当前 `psutils` 清单一致的更宽兼容面。

## Next Steps

→ /prompts:ce-plan for structured implementation planning
