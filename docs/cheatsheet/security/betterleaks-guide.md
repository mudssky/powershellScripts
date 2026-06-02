# Betterleaks 使用指南

## 一、它是什么

**Betterleaks** 是 Gitleaks 原作者团队推出的**新一代密钥扫描器**，用于在代码、Git 仓库、文件系统中检测被硬编码的密码、API Key、Token 等机密信息。由 Aikido Security 赞助开发。

相比 Gitleaks 主要的进化点：

| 特性 | 说明 |
|------|------|
| **CEL 过滤** | 用 [CEL（Common Expression Language）](https://cel.dev) 写规则过滤，可访问 git author、commit message、文件路径等上下文 —— 比 Gitleaks 的 `[[allowlist]]` 表达力强得多 |
| **密钥有效性验证** | 在规则里直接发 HTTP 请求，验证扫到的密钥是不是**真的活跃可用** |
| **Token 效率过滤** | 用 BPE 分词判断字符串「像不像人类自然语言」，降低自然语言导致的误报 |
| **极速扫描** | 默认并行化 + Aho-Corasick 关键字预过滤 + RE2 |
| **轻量便携** | 单个小体积二进制，可嵌入任何系统 |

---

## 二、安装

按你的环境选一种即可：

```bash
# macOS / Linux（Homebrew）
brew install betterleaks
# 或
brew install betterleaks/tap/betterleaks

# Fedora
sudo dnf install betterleaks

# Docker
docker pull ghcr.io/betterleaks/betterleaks:latest

# 源码构建（需要 Go）
git clone https://github.com/betterleaks/betterleaks
cd betterleaks
make build
```

---

## 三、基本用法（5 种扫描模式）

### 1. 扫描 Git 仓库（最常用）
```bash
betterleaks git /path/to/repo -v --git-workers=16
```
- `-v`：输出详细信息（发现的每条 finding）
- `--git-workers=16`：并行 worker 数，按 CPU 核数调

### 2. 扫描本地目录或单个文件
```bash
betterleaks dir /path/to/file/or/dir -v
```
适合扫描非 Git 项目、构建产物、配置目录等。

### 3. 扫描 GitHub 组织 / 用户 / 资源
```bash
# 扫整个组织
betterleaks github https://github.com/betterleaks

# 扫某用户，并包含 issue / PR / actions / release / gist
betterleaks github https://github.com/cooluser123456789 \
  --include issues,prs,actions,releases,gists

# 扫某个具体 PR（只扫评论，不扫描描述）
betterleaks github https://github.com/betterleaks/betterleaks/pull/113
```
> 扫 GitHub 需要 Token，通常通过环境变量 `GITHUB_TOKEN` 提供。

### 4. 扫描标准输入（pipeline 友好）
```bash
cat some_file.txt | betterleaks stdin -v
```
适合 CI 中扫单个文件、日志、临时片段。

### 5. 退出码
```
0    - 没有泄漏
1    - 发现泄漏或出错
126  - 未知 flag
```
可用 `--exit-code` 自定义。CI 流水线一般直接靠这个非 0 退出码来阻断合并。

---

## 四、配置文件 `.betterleaks.toml`

Betterleaks 的精髓在于配置 —— **过滤和验证都是用 CEL 写的代码逻辑**，不是简单的正则白名单。

> 建议先花 30 分钟看一遍 [CEL 语言](https://cel.dev) 再写过滤规则。

把以下文件放到仓库根目录命名为 `.betterleaks.toml`：

```toml
# 全局 prefilter：在做正则匹配之前先跑，可访问 attributes
# 用于快速排除明显不需要扫的资源（图片、node_modules、机器人提交等）
prefilter = '''
(matchesAny(attributes[?"path"].orValue(""), [
  r"""(?i)\.(?:bmp|gif|jpe?g|png|svg|tiff|pdf|exe)$""",
  r"""(?:^|/)node_modules(?:/.*)?$""",
  r"""(?:^|/)vendor(?:/.*)?$"""
]))
|| attributes[?"git.author_name"].orValue("") == "renovate[bot]"
'''

# 全局 filter：对每一条 candidate secret 跑一次
# 命中此条件的 finding 会被丢弃（视为误报）
filter = '''
containsAny(finding["secret"], [
  "EXAMPLE",
  "CHANGEME",
  "YOUR_API_KEY_HERE",
  "0000000000000000"
])
'''

# === 规则定义 ===
[[rules]]
id          = "github-fine-grained-pat"
description = "GitHub Fine-Grained PAT，可能导致仓库未授权访问"
regex       = '''github_pat_\w{82}'''
keywords    = ["github_pat_"]

# 规则级 filter：只对当前规则生效
filter = '''
(
    attributes[?"git.author_name"].orValue("") == "ci-runner" &&
    attributes[?"path"].orValue("").startsWith("mocks/") &&
    finding["secret"].contains("TESTING")
)
|| (entropy(finding["secret"]) <= 3.0)
'''

# 异步验证：发请求看密钥是否真的有效
validate = '''
cel.bind(r,
  http.get("https://api.github.com/user", {
    "Accept": "application/vnd.github+json",
    "Authorization": "token " + secret
  }),
  r.status == 200 && r.json.?login.orValue("") != "" ? {
    "result": "valid",
    "username": r.json.?login.orValue(""),
    "name": r.json.?name.orValue(""),
    "scopes": r.headers[?"x-oauth-scopes"].orValue("")
  } : r.status in [401, 403] ? {
    "result": "invalid",
    "reason": "Unauthorized"
  } : unknown(r)
)
'''
```

**几个关键概念，务必区分清楚**：

| 项 | 执行时机 | 可访问数据 | 用途 |
|---|---|---|---|
| `prefilter` | 正则匹配**之前** | 只能访问 `attributes`（路径、作者、commit msg 等） | 快速跳过无需扫的资源，省 CPU |
| `filter` | 正则匹配**之后** | `attributes` + `finding`（如 `finding["secret"]`、`finding["match"]`） | 排除误报 |
| `validate` | filter 通过**之后** | finding 数据 + `http.*` 等 | 异步发 HTTP 验证密钥是否真有效 |

完整默认规则可参考官方仓库 [`config/betterleaks.toml`](https://github.com/betterleaks/betterleaks/blob/main/config/betterleaks.toml)，详细配置文档见 [`docs/config.md`](https://github.com/betterleaks/betterleaks/blob/main/docs/config.md)。

---

## 五、典型 CI 集成（GitHub Actions 示例）

```yaml
name: secret-scan
on: [push, pull_request]

jobs:
  betterleaks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0   # 扫全部历史需要完整 git 历史
      - name: Run Betterleaks
        run: |
          docker run --rm -v $PWD:/repo ghcr.io/betterleaks/betterleaks:latest \
            git /repo -v --exit-code=1
```
扫到任何有效泄漏即 `exit 1`，PR 会被自动标红、阻断合并。

---

## 六、忽略文件 `.betterleaksignore`

仓库根目录放一个 `.betterleaksignore`，写入要忽略的 **finding 指纹**（每行一个），即可永久豁免已审阅过的误报。指纹会在 `-v` 输出里给出。

---

## 七、建议的上手路线

1. `brew install betterleaks`（或 docker pull）
2. 进项目目录 `betterleaks git . -v` 跑一次，先看默认规则能扫出什么
3. 把误报加入 `.betterleaksignore`，或在 `.betterleaks.toml` 里用 `filter` 表达式批量处理
4. 给最关心的密钥类型（GitHub PAT、AWS、自家内部 token）加上 `validate` 主动验活
5. 在 CI 中以 `--exit-code=1` 接入流水线，做合并前阻断

---

参考来源：

[^1]: [Betterleaks 官方 GitHub 仓库 README](https://github.com/betterleaks/betterleaks)
[^2]: [Regex is (almost) all you need —— 检测引擎原理博客](https://lookingatcomputer.substack.com/p/regex-is-almost-all-you-need)
[^3]: [CEL 表达式语言官网](https://cel.dev)

