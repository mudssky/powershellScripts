# shell/shared.d: 抽象 fzf 交互命令生命周期以消除样板

## Goal

当前 5 个 fzf 交互命令（tmux-sessions / zellij-sessions / bluetooth / fzf-open / fzf-search）每个函数体都重复着 5 段几乎相同的样板代码。底座 `fzf_pick_action` 只抽象了"选条目+选动作"这一步，没覆盖一个交互命令的完整生命周期。目标：把重复样板下沉到底座，让调用方只剩"声明式"的数据来源与动作分派。

## User Value

- 新增一个 fzf 命令只需写 ~10 行声明式代码，而不是复制粘贴 ~40 行样板。
- 行为一致性自动保证（空列表提示、取消处理、错误前缀格式），而不是各函数各写各的。
- 未来加新命令时，心智负担从"记得写全 5 段守护"降为"填两个回调"。

## 第一性原理分析（根因定位）

**问题重述**：不是"需要重构 fzf 函数"，而是"底座抽象层级太低，只覆盖 fzf 调用本身，没覆盖交互命令的完整生命周期"。

**累赘的 5 段重复样板（逐文件比对实证）**：

| # | 样板代码 | 重复位置 |
|---|---|---|
| 1 | 连续 3-4 个 `command -v` 工具守护（fzf/底座/领域工具） | tmux·zellij·bluetooth·fzf-open·fzf-search 全部 |
| 2 | "收集候选 → 空 → 友好提示 + return 0" | 全部 5 个 |
| 3 | fzf 输出解析块（`read key; read line` + heredoc） | fzf-open 内联重抄一遍，底座内部还有一份 |
| 4 | `$? -ne 0 → 用户取消 → return 0` | 全部 |
| 5 | 选中项二次解析（`%%:*` / `%% *` / `#*$'\t'` 各异） | tmux/zellij/bluetooth 各写一遍 |

**真相**：一个交互命令的生命周期固定为 4 步 ——
`准备(守护+取数据) → 选择(fzf+预览+动作) → 解析(选中行→真实值) → 执行(动作分派)`。
其中"选择"和"解析"可由底座统一吃掉，调用方只声明"数据怎么来、选中后怎么执行"。

**挑战假设**：底座现在为何漏了？因为最初设计时只盯着"attach 要在当前 shell 执行"这一个约束（催生了全局变量回传），没从"命令生命周期"视角设计。这是合理的演进——先跑通再加抽象。

## Confirmed Facts

- `fzf_pick_action` 当前契约：stdin 喂候选、`$1`=header、`$2`=expect_keys，经全局变量 `FZF_PICK_ITEM`/`FZF_PICK_ACTION` 回传。
- `fzf-open` 因需 `--preview`/`--preview-window`，绕开了底座，自己内联了完整的 fzf 调用 + `--expect` 解析（样板 #3/#4 在此重复）。
- tmux/zellij/bluetooth 三者结构高度同构：取会话/设备列表 → fzf → 切出真实值 → case 分派。差异仅在"列表命令"和"选中行解析规则"。
- 5 个函数的错误前缀格式一致：`%s[<tag>]%s <msg>`。

## Requirements（草案，待确认后定稿）

1. 提供更高层底座（待定形，见 design.md），覆盖交互命令的「选择+解析」两步，把样板 #2/#3/#4/#5 下沉。
2. 工具守护（样板 #1）也由底座统一处理，调用方声明依赖的工具列表。
3. 支持自定义 fzf 参数（尤其 `--preview`/`--preview-window`），让 fzf-open 不再需要绕开底座。
4. 现有 5 个命令迁移到新底座后，行为与当前完全一致（含降级、退出码、提示文案）。
5. 保持 bash/zsh 双 shell 兼容。

## Acceptance Criteria

- [ ] 新底座能以声明式方式表达现有 5 个命令，每个命令函数体 ≤ ~15 行。
- [ ] 样板 #2/#3/#4/#5 在调用方不再手写。
- [ ] fzf-open 不再内联 fzf 调用，改用新底座。
- [ ] 迁移后 5 个命令的降级路径、提示文案、退出码与当前一致（逐项回归）。
- [ ] bash + zsh 双 shell source + 验证全绿。
- [ ] 公共接口带规范中文注释（AGENTS.md）。

## Out of Scope

- 改变现有命令的用户可见行为/按键映射。
- 给 `shared.d` 引入自动化测试框架（沿用现状手工验证）。
- 触及 `bash.d`/`zsh.d` 的 fzf-history widget（那是 zle/readline 专属，与命令式函数范式不同）。

## Resolved Decisions

- ✅ **重构力度（Q1）= 中间**：增强 `fzf_pick_action`（加 preview 支持 + 统一解析），让 fzf-open/fzf-search 回流底座；另为 tmux/zellij/bluetooth 这 3 个同构命令抽一个薄封装 `fzf_list_action`（列表→选择→解析→分派），调用方只填「取列表命令 + 解析规则 + 动作分派」三个回调。吃掉 ~80% 重复，风险可控。fzf-open/search 因形态不同（preview/编辑器跳转）不强塞进薄封装，而是回流增强后的 `fzf_pick_action`。

## Open Questions

无阻塞。
