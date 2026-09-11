# Git Identity Rules Guidelines

> 本规范记录 `scripts/pwsh/misc/gitconfig_personal.ps1` 与 `config/git/gitconfig.local.json` 的身份 profile、`includeIf` 规则渲染与审计判定契约。

## Scenario: 按 remote 地址自动选择 Git 提交身份

### 1. Scope / Trigger

- Trigger: 修改 `scripts/pwsh/misc/gitconfig_personal.ps1`、`config/git/gitconfig.local.example.json` 或 `tests/GitConfigPersonal.Tests.ps1` 中与 profile 匹配、规则渲染、身份审计有关的逻辑；或需要新增一个公司 / 个人 Git 平台。
- Scope: 身份数据在不提交的 `config/git/gitconfig.local.json`；规则安装到各平台自己的 `~/.gitconfig`；脚本本体不含任何真实姓名或邮箱。
- Design intent: 公司仓用真名 + 企业邮箱、个人仓用个人身份，这件事必须由 Git 按 remote 地址自动判定，而不是靠人记得在每个新 clone 里跑一次脚本——漏跑就会用错身份提交，且已推送的 commit 不能 amend 改回来。

### 2. Signatures

- `pwsh ./scripts/pwsh/misc/gitconfig_personal.ps1 [-ShowCurrent] [-Recurse] [-Path <dir>]`
- `pwsh ./scripts/pwsh/misc/gitconfig_personal.ps1 -InstallRules [-WhatIf]`
- `pwsh ./scripts/pwsh/misc/gitconfig_personal.ps1 -ClearLocal [-WhatIf]`
- `pwsh ./scripts/pwsh/misc/gitconfig_personal.ps1 -ProfileName <name> [-Local]`

### 3. Contracts

- 配置顶层是 `profiles` 与 `default`；每个 profile 必须有 `name` 与 `email`，`hosts` 可选。
- 只有带 `hosts` 的 profile 参与自动匹配并渲染成规则；没有 `hosts` 的 profile 只能由 `-ProfileName` 手工指定。
- 配置加载走 `psutils/modules/config.psm1` 的 `Resolve-ConfigSources`，不自写 JSON 解析。嵌套的 profile 定义由脚本自己规范化（`ConvertTo-ConfigHashtable` 只做浅层转换）。
- 写入类动作（`-InstallRules` / `-ClearLocal` / `-ProfileName`）必须支持 `-WhatIf`；写 `~/.gitconfig` 前创建带可读时间戳的 `.bak`。
- 规则安装用 `git config -f <目标文件>` 逐键写入，不手工拼接文件文本，以保留 `[credential]`、`[safe]` 等既有段落；同名 key 覆盖使得重复安装天然幂等。
- 默认行为是只读审计。不提供批量写入身份的入口：`-Recurse` 只用于扫描，`-ClearLocal` 只作用于当前仓库。
- 全局默认身份不由本脚本改写；规则只负责在命中的 remote 上覆盖它。

### 4. includeIf 模式渲染：`**` 不跨 `/` 的陷阱

`hasconfig:remote.*.url:` 的条件值按 wildmatch + `WM_PATHNAME` 匹配：`*` 不跨越 `/`，
`**` 只有在**紧跟 `/` 或位于模式开头**时才跨越 `/`，否则退化成普通 `*`。

SSH 的 scp 简写 `git@host:group/repo.git` 里 `**` 前面是冒号，因此：

| 模式 | `git@host:group/repo.git` | `git@host:repo.git` |
|---|:---:|:---:|
| `git@host:**` | ✗ 不匹配（`**` 退化，不跨 `/`） | ✓ |
| `git@host:*` | ✗ | ✓ |
| `git@host:*/**` | ✓ | ✗ |

所以每个 host 必须渲染成四条，缺一不可：

```text
git@<host>:*          # scp 简写，单级路径
git@<host>:*/**       # scp 简写，带分组的多级路径
ssh://git@<host>/**   # 显式 ssh scheme
https://<host>/**     # https
```

判例：只写 `git@gitlab.xhgjdev.com:**` 时，`git@gitlab.xhgjdev.com:digital-rd-governance/onboarding-sandbox.git`
不命中，仓库静默落回全局个人身份；而单级路径的仓库命中，看起来"规则是生效的"。

### 5. 审计判定：必须读来源文件，不能只比对值

判断身份是否健康时必须用 `git config --show-origin --get user.email` 读**来源文件**，
并用 `git config --local --get` 单独判断是否存在仓库级覆盖。只比对邮箱字符串会把
"值碰巧正确但来自硬编码的仓库级 `[user]`"误判成健康——这类仓库换台机器重新 clone 就会用错身份。

| 状态 | 含义 |
|---|---|
| `OK` | 规则生效，身份正确 |
| `LocalOverride` | 身份正确但靠仓库级覆盖维持，可 `-ClearLocal` 交还规则 |
| `RuleGap` | 仓库级覆盖顶着一个规则期望之外的身份，说明该 remote 未被任何 `hosts` 覆盖 |
| `Mismatch` | 生效身份与期望 profile 不符，且不是仓库级覆盖造成的 |
| `NoIdentity` | 未配置 `user.email` |

### 6. 平台边界

- WSL 与 Windows 各有独立的 `HOME` 和 `~/.gitconfig`，规则必须**各安装一次**；只在一侧安装会让另一侧的提交静默使用全局默认身份。
- 规则文件里的 `path` 是所在平台的本地路径。不要在 WSL 里把规则写进 Windows 的 `~/.gitconfig`：写进去的会是 `/mnt/c/...`，Windows 的 Git 不认。需要在 Windows 侧安装时，用 Windows 的 `pwsh.exe` 执行。
- 通过 UNC（`\\wsl.localhost\...`）执行脚本会被 Windows 执行策略拦截，需要一次性 `-ExecutionPolicy Bypass`，不要为此改系统级策略。

### 7. Validation & Error Matrix

| Condition | Expected Behavior |
|-----------|-------------------|
| 配置文件不存在 | 抛错并指向 `gitconfig.local.example.json`，不回退到内置身份 |
| profile 缺 `name` 或 `email` | 抛错，指出是哪个 profile |
| `default` 指向未定义的 profile | 抛错 |
| profile 没有 `hosts` | 跳过规则渲染，不报错 |
| 规则未安装 | 审计输出提示缺失条数并指引 `-InstallRules`，不把未安装报成身份写错 |
| `-Recurse` 但本机没有 fd | 抛错说明依赖，不静默只扫当前目录 |
| 目标仓库没有仓库级覆盖时 `-ClearLocal` | 打印说明并返回 `$false`，不视为错误 |

### 8. Tests Required

- 每种 remote 形态（scp 多级 / scp 单级 / `ssh://` / `https://` / 其它平台 / IP 入口 / 无 remote）到期望 profile 的匹配。
- 规则渲染必须断言同时含 `:*` 与 `:*/**` 两条，防止回归成单条 `:**`。
- 审计五种状态各一例，重点覆盖"值正确但来自仓库级覆盖"判成 `LocalOverride`。
- `-WhatIf` 下不产生任何文件写入；实际执行时生成 `.bak` 且保留无关段落。
- 重复 `-InstallRules` 后规则条数不增长（幂等）。
