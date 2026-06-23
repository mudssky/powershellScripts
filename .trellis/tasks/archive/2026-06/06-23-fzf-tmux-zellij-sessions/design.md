# Design — fzf 驱动的 tmux/zellij 会话管理

## 架构与边界

```
shell/shared.d/
├─ fzf-helpers.sh   # 通用底座：fzf_pick_action + 统一的颜色/echo 辅助
├─ tmux.sh          # tmux-sessions：tmux 会话 attach/kill
└─ zellij.sh        # zellij-sessions：zellij 会话 attach/kill
```

- `shared.d` 经 `deploy.sh` 软链到 `~/.bashrc.d/`，bash/zsh 都 source → **必须 POSIX 友好、双 shell 兼容**，禁用 `zle`/`bind -x`/`[[ ... ]]` 的 zsh-only 扩展（`[[ ]]` bash 也支持，安全；不用 zsh 数组特有语法）。
- 三个文件互相无硬顺序依赖：`tmux.sh`/`zellij.sh` 依赖 `fzf-helpers.sh` 提供的底座。`deploy.sh` 按文件名 glob 同步，加载顺序由 rc 里的 `*.sh` glob 决定——为避免「tmux.sh 先于 fzf-helpers.sh 被 source」导致底座未定义，**底座调用处用「运行时检查 + 延迟定义」兜底**（见下文「健壮性」）。

## 数据流与契约

### 底座函数 `fzf_pick_action`（fzf-helpers.sh）

职责：把「一组条目」交给 fzf，让用户选一个条目 + 一个动作，把两者返回给调用方。

**入参（约定）**：
- `$1`：管道输入的候选条目（每行一个，已含显示文本）。底座从 stdin 读取，不在参数里传，避免超长。
- `$2`：header 提示文本（显示在 fzf 顶部，说明各按键动作）。
- `$3`：`--expect` 的按键定义（如 `ctrl-x`），多键用逗号分隔 `ctrl-x,ctrl-d`。`Enter` 固定走「accept」语义不算在内。

**输出契约**：通过全局变量回传（命令替换 `$()` 会丢 attach 所需的当前 shell 状态，attach 必须在当前 shell 执行，故不用 `$()` 取返回值）：
- 回传变量 `FZF_PICK_ITEM`：用户选中的条目原文（含显示前缀，调用方需自行提取真实会话名）。
- 回传变量 `FZF_PICK_ACTION`：用户按下的 expect 键（如 `ctrl-x`）；按 Enter 时为空字符串。
- 退出码：用户正常选中返回 0；Esc/无选中/无 fzf 返回非 0。

> 设计权衡：为何用全局变量而非 `echo`？因为 attach 必须在**当前 shell 进程**执行（`exec tmux attach` / `tmux attach` 接管当前终端），若用 `item=$(fzf_pick_action ...)` 子 shell，attach 会在子 shell 里发生、退出即丢终端。全局变量是 bash/zsh 双兼容、唯一能在当前 shell 传「两项返回值」的方式，与 `fzf-history` 用 `BUFFER`/`READLINE_LINE` 的当前-shell 语义同源。

### tmux-sessions（tmux.sh）

数据流：
1. `command -v tmux` / `command -v fzf` 守护，缺失则 `return`。
2. `sessions=$(tmux list-sessions 2>/dev/null -F '#{session_name}')`；无会话（非 0 退出）→ 打印「无活动会话」并 return。
3. 把会话名经管道喂给 `fzf_pick_action`，header 标注 `[Enter]:attach | [Ctrl-x]:kill`。
4. 读 `FZF_PICK_ITEM`/`FZF_PICK_ACTION`：
   - action 空 → `tmux attach-session -t "$item"`（在当前 shell 执行）。
   - action = `ctrl-x` → `tmux kill-session -t "$item"`，提示已删除。
5. 退出码传递。

> 显示行用 `tmux list-sessions -F '#{session_name}: #{session_windows} windows (#{?session_attached,attached,detached})'` 给出更友好预览，但提取真实会话名时按 `:` 截断或改用单独的字段查询——**决策：显示与取值分离**，显示行带附加信息，回传时让调用方按 `:` 前缀切，或底座约定「显示行首字段即真实值」。见下「健壮性」。

### zellij-sessions（zellij.sh）

- `zellij list-sessions` 输出形如 `dev [ExitStatus: ...]` 或 `dev (current)`，需按空白首字段切会话名。
- attach：`zellij attach "$name"`；kill：`zellij kill-session "$name"`（zellij ≥0.40 支持，旧版用 `zellij delete-session`）→ 做 `zellij kill-session` 不存在时降级提示。
- 其余结构与 tmux.sh 对称。

## 健壮性与降级

- **底座延迟定义兜底**：`tmux.sh`/`zellij.sh` 顶部加 `command -v fzf_pick_action >/dev/null 2>&1 || return`；若因 source 顺序问题底座未定义，领域文件静默不加载，而不是报错（与目录「工具缺失安静降级」约定一致）。
- **无会话**：`tmux list-sessions` 无会话时退出码 1 并输出 `no server running`，脚本捕获后打印友好提示，退出码 0。
- **会话名提取**：显示行可能带附加信息（窗口数、attached 状态）。**决策**——底座契约统一为「整行回传，调用方负责解析自己的输出格式」，保持底座中立。tmux/zellij 各自按自己工具输出格式切首个字段。
- **fzf 不可用**：底座内部首行 `command -v fzf >/dev/null 2>&1 || return 1`；领域命令捕获后提示「请先安装 fzf」。

## 兼容性

- bash 3.2（macOS 默认）/ bash 4+ / zsh 5+ 均兼容：只用 `[[ ]]`、`local`、`case`、全局变量、`$(...)`，不使用关联数组、`mapfile`、zsh-only 语法。
- macOS 与 Linux 双平台：tmux/zellij 子命令跨平台一致；颜色用目录现有的 `\033[...m` 风格（见 `deploy.sh`）。

## 取舍说明

- **为何不做成 widget（快捷键）**：widget 需要 `zle`（zsh）或 `bind -x`（bash），属于 shell 专属，必须放 `zsh.d`/`bash.d`，与「放 shared.d 给两边用」的目标冲突。故 MVP 只提供命令式函数（`tmux-sessions`），快捷键绑定留待后续在 `zsh.d`/`bash.d` 各加一份（明确列 Out of Scope）。
- **为何 attach 不用 `exec`**：`exec tmux attach` 会替换当前 shell 进程，退出 attach 后终端直接关闭。用普通 `tmux attach-session` 退出后回到原 shell，更符合「临时 attach」直觉。若你偏好退出即关终端，可后续加开关。

## 回滚

纯新增文件（`fzf-helpers.sh`/`tmux.sh`/`zellij.sh`），不改动任何现有文件。回滚 = 删这三个文件 + 重新跑 `deploy.sh`（或手动删 `~/.bashrc.d/` 下对应软链）。
