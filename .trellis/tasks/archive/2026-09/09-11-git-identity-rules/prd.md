# Git 身份规则化：gitconfig 脚本按本地配置驱动

## Goal

让 git 提交身份由 `includeIf` 规则按 remote URL 自动决定，`gitconfig_personal.ps1` 从"逐仓写入身份"改为"安装规则 + 审计 + 清理覆盖"，身份数据放进一份不提交的本地配置。

## Background

公司 GitLab（`gitlab.xhgjdev.com`）要求真名 + 企业邮箱，个人 GitHub / Gitee 用个人身份。本机全局身份是个人身份，靠脚本逐仓写入公司身份来切换，有三个问题：

- 根目录 `gitconfig_company.ps1`（未跟踪）的 `-Recurse` 会把当前目录下所有仓库（含个人仓）无差别写成公司身份。仓库里的 `config/git/renameCommit.ps1` / `.sh` 正是为"误切换造成个人信息泄露"准备的抢救脚本。
- `scripts/pwsh/misc/gitconfig_personal.ps1` 默认写**全局**个人身份，`-local` 给当前仓写个人邮箱，是同一问题的镜像。
- 新 clone 的仓库全靠人记得跑脚本，漏了就用错身份提交；已推送的 commit 不能 amend 改回来。

WSL 侧已手工配好四条 `includeIf "hasconfig:remote.*.url:..."`，八种 remote 形态实测通过；Windows 侧 `C:/Users/mudssky/.gitconfig` 仍是纯个人身份、无规则。

## Requirements

### R1 配置与代码分离

- 身份数据放 `config/git/gitconfig.local.json`，不提交（已被 `.gitignore` 现有的 `*.local.json` 覆盖，不新增条目）。
- 同目录提供全占位符的 `gitconfig.local.example.json` 并提交，沿用仓库既有 `.local.example` 配对模式。
- 配置声明 profile（name / email / hosts）与默认 profile；`hosts` 是 `includeIf` 规则的来源。
- 脚本本体不含任何真实姓名或邮箱。

### R2 脚本能力

扩展 `scripts/pwsh/misc/gitconfig_personal.ps1`，不新增脚本文件、不改文件名：

- `-ShowCurrent` [`-Recurse`]：只读审计，报告期望 profile、实际生效值**及其来源文件**、是否存在仓库级覆盖、规则是否未覆盖。
- `-InstallRules`：把配置渲染成 `includeIf` 写入当前平台 `~/.gitconfig`，并生成 `~/.gitconfig-<profile>`。
- `-ClearLocal`：清除当前仓库的仓库级 `[user]` 覆盖，不递归。
- `-Profile <name>` [`-Local`]：兜底手工写入，用于规则覆盖不到的 remote（如 IP 形式）。
- 移除"无参数即写全局个人身份"的旧默认行为，改为打印审计结果。

### R3 安全边界

- 写 `~/.gitconfig` 前创建带可读时间戳的 `.bak`（AGENTS.md 第 5 条）。
- 写入类操作支持 `-WhatIf`。
- 不批量写入身份；`-Recurse` 只用于只读扫描。
- 不改写任何已有提交历史。

### R4 收尾

- 删除根目录 `gitconfig_company.ps1` 及 `.gitignore` 中对应条目。
- 更新 `README.md` 与 `docs/scripts-index.md` 中该脚本的描述。

## Constraints

- 配置加载走 `psutils/modules/config.psm1` 的 `Resolve-ConfigSources`，不自写 JSON 解析（`.trellis/spec/pwsh-scripts/package/config-loading.md`）。
- 保持原有 `-local` / `-showCurrent` 调用方式可用。
- 不在本次处理 IP 形式的公司入口（`192.168.27.234`、`192.168.27.159:18080`）；审计应把它们报成"规则未覆盖"而非静默。

## Acceptance Criteria

- [ ] `config/git/gitconfig.local.example.json` 已提交且只含占位符；`gitconfig.local.json` 未被跟踪
- [ ] 脚本本体 `git grep` 不到任何真实企业邮箱或姓名
- [ ] `-ShowCurrent -Recurse` 能对公司仓、个人仓、无 remote 目录三类分别给出正确的期望身份、实际值和来源文件
- [ ] `-ShowCurrent` 能把"值碰巧正确但来自仓库级覆盖"标记为可清理，而不是判成健康
- [ ] `-InstallRules` 为每个 host 渲染四条模式，含 `git@<host>:*` 与 `git@<host>:*/**`；Windows 与 WSL 两侧执行结果一致
- [ ] `-InstallRules` / `-ClearLocal` 在 `-WhatIf` 下不产生任何文件写入，实际执行前生成 `.bak`
- [ ] 个人 GitHub / Gitee 仓身份不受影响；`~/.gitconfig` 既有 `[credential]`、`[safe]` 段落原样保留
- [ ] `tests/GitConfigPersonal.Tests.ps1` 覆盖规则匹配、规则渲染、审计判定、配置来源优先级、`-WhatIf`
- [ ] `pnpm qa` 与 `pnpm test:pwsh:all` 通过
- [ ] 根目录 `gitconfig_company.ps1` 已删除，README 与 scripts-index 描述已更新

## Notes

- git 的 `**` 只有紧跟 `/` 或位于模式开头时才跨路径分隔符。SSH scp 写法 `git@host:group/repo.git` 里 `**` 前面是 `:`，会退化成普通 `*` 而匹配失败——这是实测踩到的坑，必须由渲染逻辑展开成 `:*` 与 `:*/**` 两条，并写进 spec。
- 判断"实际生效身份"必须读 `--show-origin` 的来源文件；只比对邮箱字符串会把硬编码覆盖误判为健康。
