# Design — 抽象 fzf 交互命令生命周期

## 方案总览（中间力度）

两层抽象，各管一段：

```
fzf-helpers.sh
├─ fzf_pick_action   【增强】选条目 + 选动作（加 preview 参数）
└─ fzf_list_action   【新增】薄封装：列表→选择→解析→分派（面向同构命令）
        ↑ 调用方填 3 个回调: 取列表 / 解析选中行 / 动作分派

调用方迁移:
  tmux.sh      → fzf_list_action (同构, ~10行)
  zellij.sh    → fzf_list_action (同构, ~10行)
  bluetooth.sh → fzf_list_action (同构, ~10行)
  fzf-preview.sh
    fzf-open   → fzf_pick_action + preview (回流, 消灭内联 fzf)
    fzf-search → fzf_pick_action + preview (回流)
```

## 1. 增强 fzf_pick_action

**现状契约**：stdin 候选、`$1`=header、`$2`=expect_keys，全局变量 `FZF_PICK_ITEM`/`FZF_PICK_ACTION` 回传。

**增强点**：新增 `$3`=可选的 fzf 额外参数串（如 `--preview 'bat {}' --preview-window right:50%`）。底座拼装时，有 `$3` 则原样追加到 fzf 命令行，无则不传。

**为何这样设计**：
- 不破坏现有调用——`$3` 可选，旧的两参调用（tmux/zellij/bluetooth）行为不变。
- preview 命令串由调用方提供（它们才知道怎么预览自己的数据），底座只负责「原样传递」，不解析——保持底座中立。
- 全局变量回传机制保留（attach 等仍需当前 shell 执行）。

**契约（增强后）**：
```
入参:
  $1 header        fzf 顶部提示文本
  $2 expect_keys   逗号分隔的 --expect 键名, 空则不传 --expect
  $3 extra_opts    可选, fzf 额外参数串 (含 --preview 等), 空则不传
输入(stdin):
  候选条目每行一个
回传(全局变量):
  FZF_PICK_ITEM    选中整行
  FZF_PICK_ACTION  按下的 expect 键 (Enter 时为空)
返回码:
  0 正常选中 / 1 fzf 不可用·stdin 空·用户取消
```

## 2. 新增 fzf_list_action（薄封装）

面向 tmux/zellij/bluetooth 这种「列表→选择→解析→分派」的同构命令。

**契约（回调驱动，全用全局变量/约定，避免 bash 函数引用难题）**：

```
入参(全部用约定的全局函数名, 底座按名调用):
  $1 list_cmd     字符串: 产出候选列表的命令 (如 'tmux list-sessions')
  $2 tag          错误提示前缀 (如 'tmux' → 输出 [tmux] ...)
  $3 header       fzf header 文本
  $4 parser_cmd   字符串: 把 FZF_PICK_ITEM 整行解析为「真实值」的命令
                  (如 'cut -d: -f1' 或 awk/sed), 从 stdin 读选中行输出真实值
  $5 action_cmd   字符串: 接收 真实值($1) + 动作键($2) 后执行的命令分派器
                  —— 这里用「命令名」, 底座 call 它, 它内部 case 分派
约定:
  底座自动处理: fzf/底座/列表命令 存在性守护、空列表提示、取消处理
```

**为何用「命令名字符串」而非函数引用**：
- bash/zsh 传函数引用跨边界不可靠（`eval` 作用域陷阱）。
- 把分派逻辑做成一个独立命令函数（如 `_tmux_dispatch`），底座 `"$action_cmd" "$value" "$key"` 调用，干净。
- parser 同理：tmux 用 `cut -d: -f1`，bluetooth 用 `awk -F'\t' '{print $2}'`，都是现成外部命令，传命令串即可。

**数据流**：
```
list_cmd 产出候选 →(空则提示return)→ fzf_pick_action(header, ctrl-x)
  →(取消则return)→ FZF_PICK_ITEM 喂给 parser_cmd → 真实值
  → action_cmd 真实值 动作键  (action_cmd 内部 case 分派 attach/kill)
```

## 3. 迁移后的调用方形态

### tmux.sh（迁移后 ~12 行）
```bash
_tmux_dispatch() {        # 动作分派器: $1=会话名 $2=动作键
  case "$2" in
    ctrl-x) tmux kill-session -t "$1" ;;
    *) [ -n "$TMUX" ] && tmux switch-client -t "$1" || tmux attach-session -t "$1" ;;
  esac
}
tmux-sessions() {
  command -v tmux >/dev/null 2>&1 || { printf '%s[tmux]%s 未安装\n' ...; return 0; }
  fzf_list_action 'tmux list-sessions' 'tmux' \
    '[Enter]:attach | [Ctrl-x]:kill' \
    'cut -d: -f1' _tmux_dispatch
}
```

### bluetooth.sh（迁移后）
```bash
_bluetooth_dispatch() {
  case "$2" in
    ctrl-x) blueutil --disconnect "$1" ;;
    *) blueutil --connect "$1" ;;
  esac
}
bluetooth() {
  [ "$(uname -s)" = Darwin ] || { ...; return 0; }
  fzf_list_action 'blueutil --paired | _bt_parse_to_display' 'bt' \
    '[Enter]:连接 | [Ctrl-x]:断开' \
    'awk -F"\t" "{print \$2}"' _bluetooth_dispatch
}
```
> bluetooth 的列表命令需含「解析+拼显示行」的预处理，仍保留 `_bt_parse_device` 辅助。

### fzf-open / fzf-search（回流增强后的 fzf_pick_action）
不再内联 fzf，改用：
```bash
fzf_pick_action '[Enter]:编辑 | [Ctrl-x]:系统打开' 'ctrl-x' \
  "--preview '$(_fp_preview_cmd)' --preview-window right:50%:wrap"
# 然后读 FZF_PICK_ITEM/FZF_PICK_ACTION 分派
```

## 4. 各样板消除情况

| 样板 # | 消除方式 | 状态 |
|---|---|---|
| 1 工具守护 | tmux/zellij/bluetooth 仍需各自守护领域工具；fzf/底座守护下沉到底座 | 部分消除 |
| 2 空列表提示 | `fzf_list_action` 内统一处理 | ✅ 全消除 |
| 3 fzf 输出解析 | 全部走 `fzf_pick_action`，不再各处手写 | ✅ 全消除 |
| 4 取消处理 | 底座统一 | ✅ 全消除 |
| 5 选中行解析 | 用 parser_cmd 命令串声明，不手写 | ✅ 全消除 |

## 5. 兼容性与回归

- `fzf_pick_action` 加第三参是**纯向后兼容**扩展（旧两参调用行为不变），tmux/zellij/bluetooth 迁移到 `fzf_list_action` 后不再直接调 `fzf_pick_action`，但底层仍经它。
- **回归重点**（逐项手工验证，写入 implement.md）：
  - tmux 无会话/未装的提示文案与退出码不变。
  - bluetooth 的 `[✓已连]/[ 未连]` 状态前缀显示不变（这是显示行拼接，仍由列表命令侧处理）。
  - fzf-open 的 Ctrl-x 系统打开、Enter 编辑器跳转行号不变。
  - 各命令的退出码（取消=0、缺工具=0）不变。

## 6. 风险与回滚

- **风险点**：bash/zsh 中「命令名字符串」回调的引号/转义（parser_cmd 含 awk 时转义易错）→ implement 阶段逐个实测。
- **回滚**：纯重构，不改用户可见行为；若新底座出问题，回退三个文件到上一个 commit 即可。

## 7. 取舍说明

- **为何不为 fzf-open/search 也做薄封装**：它们形态不同——fzf-open 要系统打开/编辑器，fzf-search 要行号跳转，与「会话列表」差异大，强行塞进 `fzf_list_action` 会让该函数的 parser/action 回调变成「万能开关」，反而更累赘。让它们回流 `fzf_pick_action` + preview 参数，是它们最自然的归宿。
