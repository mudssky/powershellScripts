# Shell shared.d Package Guidelines

> 适用于 `shell/shared.d/*.sh` 下的 bash/zsh 双 shell 配置片段。
> 这些片段经 `deploy.sh` 软链接到 `~/.bashrc.d/`，bash 与 zsh 都会 source。

## Scope

* 包路径：`shell/shared.d`
* shell 专属片段（`zle`/`bind -x` 等）属于 `shell/{bash,zsh}.d/`，不在本包
* 部署机制：`shell/deploy.sh`（glob `*.sh` 软链 + rc 加载器）

## Pre-Development Checklist

- [ ] **双 shell 兼容**：禁用 `zle`/`bind -x`/`mapfile`/zsh-only 数组语法；只用 `[[ ]]`/`local`/`case`/`$(...)` 等两者都支持的特性。
- [ ] **条件式守护**：工具替换用 `command -v X >/dev/null 2>&1`，无 `else` 即回退系统原命令（需求："没安装时回退"）。
- [ ] **不破坏性 alias**：语法不兼容的工具（`find→fd`、`grep→rg`）**不做 alias**，当独立命令用——alias 会炸掉依赖原语法的脚本/命令。只有行为兼容的（`bat→cat`，管道自动退化）才 alias。
- [ ] **加载顺序无关**：函数体内引用其它文件的函数时，确认函数定义为惰性（source 时只定义、调用时才解析），不依赖 `*.sh` glob 顺序。若必须保证顺序，用文件名前缀数字而非隐式依赖。
- [ ] **解析 CLI 输出前先找机器可读选项**：优先使用 `--json`、`--porcelain`、`--format`/`-F`、`--short`、`--no-formatting` 等无样式/结构化输出；展示列可以丰富，但真实参数必须从稳定字段解析，避免 ANSI 颜色或展示文案混入真实参数。
- [ ] **加任何 init 前，先全局 grep**：`eval "$(zoxide init ...)"`、`eval "$(starship init ...)"` 等初始化代码极易跨文件重复。新增前先 `grep -r "<tool>" shell/` 确认未被别处初始化（见下方 Anti-pattern）。

## Interactive Command Lifecycle（交互命令必读）

`shared.d` 的 fzf 交互命令遵循固定生命周期：

```
准备(工具守护+取数据) → 选择(fzf+预览+动作) → 解析(选中行→真实值) → 执行(动作分派)
```

**已有底座（`fzf-helpers.sh`），优先复用，不要重写样板**：

| 底座 | 适用场景 | 契约要点 |
|------|----------|----------|
| `fzf_pick_action` | 通用「选条目+选动作」，需自定义 preview/后续逻辑 | stdin 喂候选、`$1` header、`$2` expect_keys、`$3` 可选 extra_opts(透传 preview)；全局变量 `FZF_PICK_ITEM`/`FZF_PICK_ACTION` 回传 |
| `fzf_list_action` | 「列表→选择→解析→分派」同构命令（会话/设备管理类） | 回调驱动：`$1` 列表命令、`$3` header、`$4` parser_cmd、`$5` action_cmd 分派器函数名 |

**新增交互命令时**：
1. 先判断它属于「同构列表类」（→ 用 `fzf_list_action`，只填 3 个回调）还是「自定义形态类」（→ 用 `fzf_pick_action` + preview）。
2. **禁止内联 fzf 调用 + 手写 `--expect` 解析块**——这正是被消除的样板 #3/#4。若发现自己在写 `read key; read line <<EOF`，说明该回流底座了。
3. 动作分派写成独立的 `_xxx_dispatch` 函数（`fzf_list_action` 按名回调），集中领域知识。

**为何从生命周期视角设计**（本次重构的教训）：
底座最初只抽象了「attach 要在当前 shell 执行」这一个约束（催生全局变量回传），没从「命令生命周期」视角设计，导致 5 个命令各重复 5 段样板。抽象的准绳是**完整覆盖生命周期的一个阶段**，而非只覆盖某个单点约束——否则调用方仍要手写周边样板。

## Naming Convention

- 主函数用完整描述性名（`tmux-sessions`/`fzf-open`/`fzf-search`），自解释。
- 高频短命令可加条件 alias（`fo='fzf-open'`），但主名必须是描述性的。
- 内部辅助函数加下划线前缀（`_tmux_dispatch`/`_fp_preview_cmd`）。
- 按领域一文件（`tmux.sh`/`zellij.sh`/`bluetooth.sh`），跨领域复用件单独立文件（`fzf-helpers.sh`）。

## Quality Check

- 代码逻辑改动：在 bash 与 zsh 下 `source` 后验证关键路径（降级/空列表/取消/正常选中）。
- 只改文案/注释：无需验证。
- `pnpm qa` 不覆盖 `shared.d`（无自动化测试），靠手工验证。
- 公共接口必须带规范中文注释（功能/入参/返回值/非直观设计意图），符合 AGENTS.md。

## Anti-Patterns

### ❌ 重复初始化（`eval "$(tool init)"` 跨文件重复）

**症状**：工具被多个 `shared.d` 文件各 `eval init` 一次，导致数据库锁竞争、函数重复定义。

**真实案例**：zoxide 曾同时在 `zz-prompt.sh` 和 `modern-tools.sh` 各 `eval "$(zoxide init ...)"`。

**预防**：加任何 init 前 `grep -r "<tool> init" shell/`。init 代码集中在 `zz-prompt.sh`（prompt 类）或专用文件，其它文件只写说明注释指向它。

### ❌ 顶层工具守护导致函数未定义

**症状**：把 `if ! command -v tmux; then return 0` 放在文件**顶层**，工具未装时整个文件被跳过、函数没定义，调用得到 `command not found`（exit 127）。

**正确**：守护放**函数体内**，函数恒定义，工具缺失时给友好提示 + exit 0。

### ❌ 内联 fzf 调用绕开底座

**症状**：命令函数里手写 `fzf --expect=... $(...)` + `read key; read line <<EOF` 解析块。

**正确**：回流 `fzf_pick_action`（用 `$3` 传 preview），或用 `fzf_list_action`。

### ❌ 解析带 ANSI 样式的 CLI 展示输出

**症状**：`zellij list-sessions` 在 TTY 中输出彩色会话名，`cut -d' ' -f1` 得到的第一列包含 ANSI 转义码，传给 `zellij attach` 后报「会话不存在」。

**正确**：先查看工具是否提供机器可读/无格式选项；zellij 会话列表使用 `zellij list-sessions --no-formatting` 去掉颜色，tmux 会话列表使用 `tmux list-sessions -F` 固定列格式，再从稳定字段解析真实会话名。

## Out of Scope

- `bash.d`/`zsh.d` 的 widget/快捷键（zle/readline 专属）。
- `scripts/bash/`（独立包，有自己的 vitest 测试规范，见 `bash-scripts` spec）。
