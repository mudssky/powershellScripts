---
title: feat: add bash aliyun oss upload script
type: feat
status: active
date: 2026-03-18
origin: docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md
---

# feat: add bash aliyun oss upload script

## Overview

本计划用于为仓库新增一个最小可用的阿里云 OSS Bash 上传脚本，并同步补齐相关说明文档。

本次规划明确继承 brainstorm 的核心结论，不再重新讨论语言选型：

1. 首发实现使用 `bash + curl + openssl`，不引入 Python 运行时（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
2. 第一版只覆盖 `OSS` 单文件上传，不做目录上传、分片上传、续传、并发和复杂重试（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
3. 运行环境以 `Linux / macOS` 为主，优先“单文件、少依赖、直接执行”，不为 Windows 原生体验设计（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
4. 脚本放在现有 `scripts/bash/` 下，而不是硬塞进 `scripts/pwsh/` 或做成 SDK 式多文件结构（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
5. 文档必须同步更新到 [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md)，明确为什么这个场景下 Bash 比 Python 更合适（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
6. 脚本需要支持自动加载 `.env` / `.env.local`，用于读取 OSS 凭据与相关配置。

这不是在把仓库整体方向从 PowerShell 改成 Bash，而是在现有工具箱内补一个“外部依赖极少、直接可执行”的 OSS 上传入口。

## Problem Statement

当前仓库已经有 `scripts/pwsh/`、`scripts/python/`、`scripts/node/`、`scripts/ahk/`，甚至还有一个空的 `scripts/bash/` 目录，但并没有一个现成的 OSS 上传脚本，也没有 Bash 脚本的落地样例。

用户这次要的不是“完整云存储客户端”，而是一个能在 `Linux / macOS` 上快速使用的极简上传脚本。真正的难点不在命令行参数本身，而在以下几个实现风险：

- OSS 官方当前推荐的是 `V4` 签名，而不是更老的 `V1`。
- 官方文档明确建议“能用 SDK 就优先用 SDK”，手写签名属于不得不自己做时的 fallback。
- `PutObject` 虽然语义简单，但默认会覆盖同名对象，若不处理会给极简脚本带来误操作风险。
- 中国内地新 OSS 用户在 `2025-03-20` 之后访问数据 API 时存在域名策略变化，不能再假设“只要知道 region 就能自动拼 host 并稳定使用”。
- Bash 在签名、URL 编码、二进制 HMAC 链和 macOS / Linux 兼容性上都比 Python 脆弱得多，因此需要把边界和验证策略提前设计清楚。

换句话说，这次计划的重点不是“把 curl 命令拼出来”，而是把一个原本容易失控的 Bash 实现收敛成一个可维护的最小闭环。

## Research Summary

### Repo Research

- 仓库已存在空目录 `scripts/bash/`，因此无需新建顶层脚本分类，直接在该目录下新增脚本即可。
- [scripts/python/README.md](/home/administrator/projects/env/powershellScripts/scripts/python/README.md) 明确把 Python 方案定位为“跨平台自动化脚本”，并推荐 `PEP 723 + uv`。这恰好说明 Python 在本仓库里的定位更偏“带运行时、便于扩展”，与本次“只依赖系统工具”的约束不一致。
- [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md) 已把 Shell 描述为更适合“把若干命令串起来”的轻量脚本；本次计划需要为“极简 OSS 上传”补一条更具体的例外说明，即 API 有一定复杂度，但在需求被强力收窄时，Bash 仍然是合理选择。
- [README.md](/home/administrator/projects/env/powershellScripts/README.md) 与 [docs/scripts-index.md](/home/administrator/projects/env/powershellScripts/docs/scripts-index.md) 当前仍主要以 PowerShell 脚本为中心，不适合作为本次 Bash 脚本的主要落点。第一版更合适的做法是补 `scripts/bash/README.md` 或直接在目标文档中说明使用方式，而不是顺手把整个索引体系改一遍。
- 仓库已有明确的 dotenv 约定可复用：`scripts/pwsh/devops/start-container.ps1` 采用“先 `.env` 再 `.env.local`，后者覆盖前者”的层叠加载方式；`psutils/modules/env.psm1` 也已经把 `.env` / `.env.local` 作为常见配置入口。这意味着 Bash 版不应再发明一套新的文件命名规则。

### Institutional Learnings

最相关的仓库内经验来自 [linux-macos-powershell-tooling-tests-system-20260314.md](/home/administrator/projects/env/powershellScripts/docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md)：

- 不要隐式假设平台上一定有某个外部命令或某种执行语义；需要显式探测并在缺失时给出稳定错误。
- Unix 平台的 shebang、`PATH`、可执行位和临时目录行为必须按真实环境建模，不能偷懒复用其他平台假设。

这对 Bash 脚本意味着：

- 使用 `#!/usr/bin/env bash`，不硬编码 `/bin/bash` 以外的路径。
- 不能依赖 Bash 4 才有的特性来换取实现便利，否则 macOS 默认 Bash 环境会立刻掉坑。
- 不要把认证信息放在命令行参数里，避免被 shell history 或进程列表泄露。

### External Research

这次规划必须参考官方 OSS 文档，因为接口和访问策略存在明显的时效性：

1. 官方 `Signature Version 4 (Recommended)` 文档明确说明：发起请求时应在 `Authorization` 请求头中携带 `V4` 签名；如果能用 SDK，应优先使用 SDK，只有不能用 SDK 时才手写实现。该页还给出了官方 SDK 的 V4 签名实现源码入口。
2. 官方 `PutObject` 文档在 `2026-03-06` 更新，明确说明：
   - 单次简单上传最大支持 `5 GB`；
   - 默认会覆盖同名对象；
   - 可通过 `x-oss-forbid-overwrite` 阻止覆盖；
   - `Content-MD5` 是可选的，若设置则 OSS 会校验。
3. 官方 `Regions and endpoints` 文档说明：自 `2025-03-20` 起，中国内地新 OSS 用户执行数据 API 操作时，默认公共域名会受到限制，通常需要改用自定义域名（CNAME）。这意味着脚本不能只接受 `region` 然后自行拼默认公共 host。
4. 官方 Python / Go SDK 的 V4 signer 源码显示，签名逻辑至少包含以下关键点：
   - 请求头包含 `x-oss-date`、`Date`、`x-oss-content-sha256: UNSIGNED-PAYLOAD`；
   - 若使用 STS，还需 `x-oss-security-token`；
   - scope 为 `<YYYYMMDD>/<region>/oss/aliyun_v4_request`；
   - 签名算法为 `OSS4-HMAC-SHA256`；
   - canonical URI 采用 `/<bucket>/<key>` 形式。

这几条外部事实直接决定了计划的参数设计、默认行为和验证策略。

## Proposed Solution

采用与 brainstorm 一致的主线：在 `scripts/bash/` 下新增一个单文件 OSS 简单上传脚本，并补充最小文档面。

建议的交付范围如下：

### 1. 脚本落点

- 新增 `scripts/bash/aliyun-oss-put.sh`
- 可选新增 `scripts/bash/README.md`

第一版不做以下事情：

- 不接入 `Manage-BinScripts.ps1`
- 不生成 Windows `.cmd` 或 PowerShell shim
- 不做 multipart upload
- 不做目录同步 / 批量上传
- 不引入第三方 Bash 框架、测试框架或 SDK

### 2. 脚本职责

脚本只负责一个动作：把一个本地文件作为单个对象上传到 OSS。

脚本还需要承担一项很小但必要的配置发现职责：在当前工作目录中自动读取 `.env` 与 `.env.local`，用于补齐 OSS 访问所需的环境变量。

建议的输入边界：

- 必填参数
  - `--file`
  - `--bucket`
  - `--key`
  - `--region`
  - `--host`
- 可选参数
  - `--content-type`
  - `--overwrite`
  - `--verbose`
  - `--debug-signing`
- 凭据来源
  - `ALIYUN_ACCESS_KEY_ID`
  - `ALIYUN_ACCESS_KEY_SECRET`
  - `ALIYUN_SECURITY_TOKEN`（可选，支持 STS）

建议的配置优先级：

1. 当前 shell 中已存在的环境变量
2. `.env.local`
3. `.env`

也就是说，脚本会按 `.env` -> `.env.local` 的顺序读取文件层配置，但不会让文件值反向覆盖用户已经显式导出的环境变量。

其中 `--host` 应定义为“实际发起请求的 host”，而不是简单等价于 region 派生值。这样才能同时兼容：

- `bucket.oss-<region>.aliyuncs.com`
- 自定义域名 / CNAME
- 未来可能的网络接入形态调整

### 3. 默认安全策略

第一版建议默认开启“防误覆盖”而不是默认覆盖：

- 默认发送 `x-oss-forbid-overwrite: true`
- 显式传入 `--overwrite` 时才改为允许覆盖

原因很直接：

- `PutObject` 默认覆盖同名对象，这对“极简单文件上传脚本”来说是最容易踩中的高风险默认值。
- 这是比“先 HeadObject 再上传”更简单且更符合 OSS 原生能力的做法。
- 如果目标 bucket 已开启 versioning，该头可能不生效；脚本应在文档和错误提示中把这一点说清楚，而不是假装自己能兜底所有 bucket 策略。

## Technical Approach

### Architecture

执行链路应保持非常窄：

```text
用户执行脚本
  -> 校验参数 / 凭据 / 依赖
  -> 计算对象路径与请求头
  -> 生成 V4 canonical request / string-to-sign / signature
  -> 调用 curl 执行 PUT
  -> 解析结果并输出简洁摘要
```

本次不会引入中间状态存储；本地副作用仅限临时变量和可选调试输出，远端副作用仅限目标对象的创建或覆盖。

### Dotenv Loading

建议把 dotenv 支持收敛为一个非常保守的子集：

- 只在当前工作目录查找 `.env` 与 `.env.local`
- 若两者都存在，先读取 `.env`，再读取 `.env.local`
- 只解析 `KEY=VALUE` 形式
- 忽略空行与 `#` 注释行
- 仅在目标环境变量当前为空时，才从文件层补值

不建议第一版直接 `source .env`，原因有两个：

- `.env` 不是可信 shell 脚本格式，直接 `source` 等于允许任意命令执行
- shell 语法、引用规则和 dotenv 语法并不完全等价，后续会制造隐蔽兼容问题

因此实现层应自己做一个小型 parser，只接受受控格式，而不是把文件当成脚本执行。

### Request Construction

建议采用以下实现策略：

1. URL 与签名输入拆开看待
   - 请求 URL 使用 `https://<host>/<encoded-object-key>`
   - canonical URI 继续按官方 SDK 逻辑使用 `/<bucket>/<key>`
   - 第一版实现必须用“与官方 SDK 同输入比对签名结果”的方式验证这一点，而不是靠主观猜测

2. 统一使用 `openssl` 完成 hash / HMAC
   - 避免引入 `sha256sum` / `shasum` 的 GNU/BSD 差异
   - 通过“中间密钥都转 hex”规避 Bash 处理二进制 HMAC 链的脆弱性

3. 统一使用保守的 Bash 语法
   - 不使用关联数组
   - 不使用 `mapfile`
   - 不依赖 GNU 专属 `sed -r`、`date --iso-8601` 等能力

4. 对象 key 做明确的 URL 编码
   - 保留 `/` 作为层级分隔
   - 对空格、中文和其他保留字符做 percent-encoding
   - 文档需要说明“对象名”和“本地文件名”不是一回事，用户不要把路径编码责任留给 curl 猜

### Signature Implementation Notes

基于官方文档与 SDK 源码，第一版签名逻辑应显式覆盖这些要点：

- 算法名：`OSS4-HMAC-SHA256`
- `x-oss-date`
- `Date`
- `x-oss-content-sha256: UNSIGNED-PAYLOAD`
- `x-oss-security-token`（仅在 STS 时）
- `content-type` 与所有 `x-oss-*` 头参与签名
- scope：`<date>/<region>/oss/aliyun_v4_request`
- canonical request -> SHA256 -> string-to-sign -> 四段 HMAC 派生 key

其中最需要提前规避的实现坑是：

- raw binary HMAC 中间结果不能直接安全地在 shell 变量里来回传
- header 名必须 lowercase 后排序
- 可选头是否参与签名必须和实际请求完全一致
- 调试输出不能把 `Authorization` 头和密钥完整打印到终端
- dotenv 读取不能通过 `source` 直接执行文件内容

### User Experience

第一版输出应保持克制：

- 成功时输出：bucket、key、host、ETag、request-id
- 失败时输出：HTTP 状态码、OSS 错误码、request-id、简短诊断建议
- `--debug-signing` 仅在显式开启时输出 canonical request / string-to-sign，并对敏感值做脱敏

不建议第一版就做彩色输出、进度条或复杂日志级别体系。

## Implementation Phases

### Phase 1: Contract and Layout

**目标**

- 固定脚本位置、CLI 契约和文档边界，避免实现过程中不断改输入模型。

**主要任务**

- 在 `scripts/bash/` 下确定目标脚本文件名
- 明确必填参数、可选参数和环境变量名称
- 明确 dotenv 搜索范围、支持格式与优先级：`shell env > .env.local > .env`
- 约定默认不覆盖、显式 `--overwrite` 才允许覆盖
- 明确第一版不接入 `bin`、不支持 multipart、不支持批量上传
- 决定是否新增 `scripts/bash/README.md`

**Success Criteria**

- 参数契约稳定，不再需要额外向用户追问“host 到底怎么传”“凭据放哪”
- 文档范围明确，只更新必要说明，不顺带重构全仓库脚本索引

### Phase 2: V4 Signer and PUT Request

**目标**

- 让 Bash 版签名和上传路径在技术上闭环。

**主要任务**

- 依赖探测：`bash`、`curl`、`openssl`
- 参数校验与帮助输出
- 解析 `.env` / `.env.local` 并合并到配置上下文
- 文件存在性校验与对象 key 标准化
- 生成 `x-oss-date`、`Date`、`x-oss-content-sha256`
- 构造 canonical request / string-to-sign / signature
- 发送 `curl --request PUT --upload-file`
- 处理 `x-oss-forbid-overwrite`
- 支持 STS token

**Success Criteria**

- 脚本能对单个本地文件发起合法的 `PutObject`
- 缺参数、缺依赖、缺凭据、签名错误、HTTP 错误都能以非零退出码失败

### Phase 3: Verification and Hardening

**目标**

- 把“能跑”提升为“能被信任”。

**主要任务**

- 增加离线签名比对入口
- 使用官方 V4 文档中的 `PutObject` 示例参数
- 或直接与官方 SDK 的同请求输出做比对
- 进行 live smoke test
  - 上传一个小文本文件到测试 bucket
  - 覆盖“新对象成功上传”和“同名对象被拒绝覆盖”两个场景
- 验证 `.env`、`.env.local`、当前 shell 环境三层配置优先级符合预期
- 验证 object key 中空格 / 中文 / 子路径的 URL 编码
- 在 macOS 与 Linux 至少各验证一次脚本启动与帮助输出

**Success Criteria**

- 签名结果与官方示例 / SDK 一致
- 成功上传与防覆盖失败都能稳定复现
- 对特殊字符对象名没有明显编码错误

### Phase 4: Documentation

**目标**

- 让脚本的适用边界和选择理由在仓库内可查。

**主要任务**

- 更新 [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md)
  - 增加“极简 OSS 上传”场景说明
  - 明确为什么这里仍然选择 Bash 而不是 Python
  - 明确何时应升级到 Python 或 SDK
- 如有必要，新增 `scripts/bash/README.md`
  - 给出最小示例命令
  - 说明凭据环境变量
  - 说明中国内地新用户自定义域名要求

**Success Criteria**

- 仓库内能直接查到“为什么选 Bash、怎么用、什么时候不该再用 Bash”

## Alternative Approaches Considered

### Pure Python

**Rejected because**

- 与“只依赖系统工具”的约束冲突（see brainstorm: `docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md`）。
- 对当前极简范围来说，Python 带来的结构化收益不足以覆盖其运行时前提。

### Direct SDK / ossutil

**Rejected because**

- 用户这次要的就是单文件 Bash 脚本，不是要求安装现成 CLI。
- 官方虽然更推荐 SDK，但本计划的前提就是“在不能引入 SDK 的条件下，收敛一个最小实现”。

### One-shot curl Without Local Signing Logic

**Rejected because**

- 如果把签名生成交给外部工具或外部服务，这个脚本就不再满足“单文件、直接可执行、少依赖”的目标。

## SpecFlow Analysis

### User Flow Overview

1. 用户在 Linux / macOS 上准备一个本地文件
2. 用户可选择在当前目录准备 `.env` / `.env.local`，或提前导出环境变量
3. 用户提供 bucket、key、region、host
4. 脚本合并 `shell env` 与 `.env` / `.env.local`
5. 脚本生成签名并执行 `PUT`
6. OSS 返回成功或失败
7. 用户从终端得到明确结果，而不是只看一长串 curl 噪音

### Edge Cases

- 本地文件不存在
- 对象 key 含空格、中文或多层路径
- 同名对象已存在
- bucket 开启 versioning，`x-oss-forbid-overwrite` 不产生预期保护
- STS token 缺失或过期
- `.env` 与 `.env.local` 同时存在且值冲突
- `.env` 中包含注释、空格、引号或无效行
- 使用中国内地 bucket，但 host 配置仍指向默认公共域名
- 自定义域名证书无效，HTTPS 失败

### Key Planning Decision

为了减少后续返工，计划先把“上传成功”之外的两类失败也纳入第一版设计：

- `FileAlreadyExists` 这一类可预期业务失败
- 认证 / 域名 / 签名不匹配导致的 `403` / `400`

否则用户第一次遇到失败时，Bash 版脚本很容易退化成“能发请求，但定位不了问题”的半成品。

## System-Wide Impact

### Interaction Graph

- 用户执行 `scripts/bash/aliyun-oss-put.sh`
- 脚本读取环境变量和本地文件
- 脚本通过 `openssl` 计算签名
- 脚本通过 `curl` 向 OSS 发起 `PutObject`
- OSS 在目标 bucket 内写入对象或拒绝请求

### Error & Failure Propagation

- 本地校验失败：脚本应直接 `exit 1`
- 签名或认证失败：`curl` 返回非零或 HTTP 错误，脚本应透出状态码与 OSS 错误信息
- 覆盖冲突：应以业务错误形式失败，而不是被误判成网络错误

### State Lifecycle Risks

- 主要远端风险是误覆盖现有对象
- 主要本地风险是把敏感 header 或密钥打印到终端 / history
- 新增的本地风险是 dotenv 处理不当导致“文件值覆盖显式环境变量”或“把 dotenv 当 shell 执行”
- 第一版几乎没有本地持久状态，因此不需要复杂清理机制

### API Surface Parity

本次只新增 Bash 脚本入口，不同步为 Python / Node / PowerShell 再做一套同能力封装。这样可以避免在尚未验证需求强度之前把仓库 API 面扩成多实现并存。

### Integration Test Scenarios

- 用长期 AccessKey 上传一个新对象
- 对同名对象重复上传，验证默认防覆盖
- 显式 `--overwrite` 后验证覆盖成功
- 使用 `ALIYUN_SECURITY_TOKEN` 执行上传
- 使用包含空格 / 中文的 object key 上传

## Acceptance Criteria

### Functional Requirements

- [x] 新增 `scripts/bash/aliyun-oss-put.sh`
- [x] 脚本支持单文件 `PutObject` 上传
- [x] 脚本只依赖系统常见工具：`bash`、`curl`、`openssl`
- [x] 凭据默认从环境变量读取，而不是命令行参数
- [x] 脚本支持自动读取当前工作目录中的 `.env` 与 `.env.local`
- [x] 脚本支持显式传入 `bucket`、`key`、`region`、`host`
- [x] 脚本支持 STS token
- [x] 脚本默认防覆盖，只有显式 `--overwrite` 才允许覆盖

### Non-Functional Requirements

- [ ] 脚本语法兼容 Linux / macOS 常见 Bash 环境，避免 Bash 4 专属语法
- [x] 错误输出简洁可定位，不泄露敏感凭据
- [ ] 对象 key 的 URL 编码行为稳定
- [x] dotenv 加载遵循 `shell env > .env.local > .env`，且不通过 `source` 直接执行文件

### Quality Gates

- [ ] 至少完成一次离线签名校验
- [x] 至少完成一次真实 OSS 上传 smoke test
- [x] 更新 [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md)
- [x] 若新增 `scripts/bash/README.md`，其示例命令与最终脚本参数保持一致

## Success Metrics

- 用户可以在不安装 Python / SDK 的前提下，用一条命令上传一个小文件到 OSS。
- 用户可以只准备 `.env` / `.env.local` 而不手动 `export`，仍然完成上传。
- 用户第一次遇到“对象已存在”“凭据错误”“host 配错”时，能从脚本输出中直接定位大类问题。
- 文档能够明确回答“为什么这里选 Bash”“什么时候该换 Python / SDK”。

## Dependencies & Prerequisites

- 有权限的 OSS bucket 与可用凭据
- `oss:PutObject` 权限；若使用标签、KMS 等扩展头，则还需要相应权限
- 一个可实际访问的 `host`
  - 对中国内地新 OSS 用户，若受 `2025-03-20` 之后的域名策略影响，需要准备自定义域名
- 本地安装 `bash`、`curl`、`openssl`

## Risk Analysis & Mitigation

- **风险：V4 签名实现细节出错**
  - 缓解：先做离线签名比对，再做 live smoke
- **风险：默认公共域名在中国内地新账号下不可用**
  - 缓解：把 `host` 设计为显式输入，并在文档中写出 `2025-03-20` 的策略变化
- **风险：误覆盖现有对象**
  - 缓解：默认发送 `x-oss-forbid-overwrite: true`
- **风险：macOS 与 Linux 的命令行为差异**
  - 缓解：尽量只用 `bash`、`curl`、`openssl` 和最基础的 POSIX 工具，不依赖 GNU 扩展
- **风险：dotenv 处理方式不安全或优先级反直觉**
  - 缓解：使用严格的 `KEY=VALUE` parser；文件层按 `.env` -> `.env.local` 合并；已存在的 shell 环境变量不被文件覆盖
- **风险：Bash 代码可维护性快速恶化**
  - 缓解：明确升级阈值。一旦需求升级到批量上传、multipart、复杂重试、目录同步，就转向 Python 或官方 SDK

## Documentation Plan

- 主文档： [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md)
  - 新增 OSS 极简上传场景
  - 说明 Bash 方案边界
  - 说明 `.env` / `.env.local` 加载规则与优先级
  - 标明升级到 Python / SDK 的触发条件
- 可选局部文档：`scripts/bash/README.md`
  - 只覆盖使用方式、环境变量与 `.env` / `.env.local` 规则，不写长篇教程

## Sources & References

### Origin

- **Brainstorm document:** [2026-03-18-aliyun-oss-upload-script-brainstorm.md](/home/administrator/projects/env/powershellScripts/docs/brainstorms/2026-03-18-aliyun-oss-upload-script-brainstorm.md)

### Internal References

- [scripts/python/README.md](/home/administrator/projects/env/powershellScripts/scripts/python/README.md)
- [docs/跨平台单文件脚本最佳实践.md](/home/administrator/projects/env/powershellScripts/docs/跨平台单文件脚本最佳实践.md)
- [README.md](/home/administrator/projects/env/powershellScripts/README.md)
- [linux-macos-powershell-tooling-tests-system-20260314.md](/home/administrator/projects/env/powershellScripts/docs/solutions/test-failures/linux-macos-powershell-tooling-tests-system-20260314.md)

### External References

- Alibaba Cloud OSS: Signature Version 4 (Recommended)
  - https://www.alibabacloud.com/help/en/oss/developer-reference/recommend-to-use-signature-version-4
- Alibaba Cloud OSS: PutObject
  - https://www.alibabacloud.com/help/en/oss/developer-reference/putobject
- Alibaba Cloud OSS: Regions and endpoints
  - https://www.alibabacloud.com/help/en/oss/user-guide/regions-and-endpoints
- Official OSS Python SDK V4 signer
  - https://raw.githubusercontent.com/aliyun/alibabacloud-oss-python-sdk-v2/master/alibabacloud_oss_v2/signer/v4.py
- Official OSS Go SDK V4 signer
  - https://raw.githubusercontent.com/aliyun/alibabacloud-oss-go-sdk-v2/master/oss/signer/v4.go
