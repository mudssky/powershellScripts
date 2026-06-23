# shell/shared.d: fzf 驱动的 tmux/zellij 会话管理

## Goal

在 `shell/shared.d/` 中新增一套交互式会话管理便捷命令，借助 `fzf` 对 **tmux** 和 **zellij** 的会话进行列表、attach、kill 等操作。先封装一个通用的 fzf 选择/动作底座函数，再基于它扩展 tmux 与 zellij 的具体命令。

## User Value

- 免记 `tmux ls` / `zellij ls` + 手动复制粘贴 session 名再 `attach`。
- 统一交互范式：一个列表 → 按键选择动作（attach / kill / ...），与现有 `fzf-history` 的 `--expect` 多动作风格一致。
- bash 与 zsh 双兼容（`shared.d` 同时被两种 rc 加载）。

## Confirmed Facts（来自代码库）

- `shell/shared.d/*.sh` 经 `deploy.sh` 软链接到 `~/.bashrc.d/`，`.bashrc` 与 `.zshrc` 都会 source 它 → **必须 bash+zsh 兼容**，不能使用 `zle` / readline `bind -x` 等 shell 专属结构（那些属于 `zsh.d`/`bash.d`）。
- 现有 fzf 范式（`shell/{bash,zsh}.d/fzf-history`）：用 `--expect=ctrl-e,ctrl-y` 对同一选中项区分多种动作，并用 `--header` 说明按键；`python.sh` 的 `uv-iu` 用 `--multi --preview`。
- 目录风格约定：按领域分文件（`ai.sh`/`python.sh`/`node.sh`/`java.sh`），函数前有中文注释头，`command -v X &> /dev/null` 做存在性守护，平台/工具不可用时安静降级。
- 目前 `shared.d` 没有任何 tmux/zellij 的 shell 级封装（`project-launcher` 技能里的 tmux 用法是 TS 编程式，与此无关；另有一份 `docs/cheatsheet/terminal/Zellij.md` 速查表）。
- `shell/.gitignore` 忽略 `*.local.sh`（本机专用片段）。
- `bash-scripts` spec 只覆盖 `scripts/bash`，不覆盖 `shell/shared.d`；本任务沿用该目录既有约定，不引入新测试规范。

## Requirements（草案，待确认后定稿）

1. 提供一个通用 fzf 底座函数（待定名，如 `_fzf_select`/`fzf_pick`），输入：标题行的列表 + 动作定义，输出：选中项与所选动作；工具缺失时静默跳过并给出提示。
2. 基于底座实现 tmux 会话管理命令：至少 `tmux-attach`（列出 `tmux ls` 的会话，选择后 attach）与 `tmux-kill`/在列表内一并 kill；无会话时给出友好提示。
3. 基于底座实现 zellij 会话管理命令：`zellij-attach`（列出 `zellij list-sessions`，选择后 attach）与对应 kill。
4. 兼容 bash 与 zsh；当 tmux/zellij/fzf 任一缺失时整体不报错。
5. 命令命名风格与目录现有 alias/函数一致（小写连字符，例如 `tmux-attach`）。

## Acceptance Criteria

- [ ] `tmux-attach` 能在存在 ≥1 个 tmux 会话时列出并 attach 到选中会话；无会话时打印提示且退出码 0。
- [ ] 可对选中会话执行 kill（具体交互方式待 Q3 定稿）。
- [ ] `zellij-attach` 同理支持 zellij。
- [ ] 在未安装 tmux / zellij / fzf 的环境下 source 该文件不产生错误。
- [ ] 同时在 bash 与 zsh 下 source 后，命令均可正常调用。
- [ ] 函数均带规范中文注释（公共接口标注功能/入参/返回值，符合 AGENTS.md）。

## Out of Scope（初稿）

- 窗口(window)/面板(pane) 级别操作、布局(layout) 启动（与 `project-launcher` 技能职责重叠）。
- 新建带命名的会话（`tmux new -s`/`zellij --session`）的交互式封装（可作为后续迭代）。
- 自定义快捷键绑定（属于 `zsh.d`/`bash.d`，不在 `shared.d` 范围）。
- 对 `shared.d` 引入自动化测试（沿用目录现状，仅靠手工验证）。

## Resolved Decisions

- ✅ **交互形态（Q1）= 单列表多动作**：采用与 `fzf-history` 一致的 `--expect` 多动作范式。一个命令（如 `tmux-sessions`）列出会话，`Enter`=attach、`Ctrl-x`=kill。**底座函数必须支持「选条目 + 选动作 → 返回两者」**，而非仅返回条目。

## Open Questions（阻塞定稿）

1. （Q2）模块拆分粒度 —— 见下方「设计决策」。
2. （Q3）是否需要「新建会话」入口（attach 列表里追加一个 `[create new]` 假条目，输入名字后创建并 attach）。

## Resolved Decisions

- ✅ **交互形态（Q1）= 单列表多动作**：采用与 `fzf-history` 一致的 `--expect` 多动作范式。一个命令（如 `tmux-sessions`）列出会话，`Enter`=attach、`Ctrl-x`=kill。**底座函数必须支持「选条目 + 选动作 → 返回两者」**，而非仅返回条目。
- ✅ **文件拆分（Q2）= 拆三件**：`fzf-helpers.sh`（通用底座，如 `fzf_pick_action`）+ `tmux.sh` + `zellij.sh`。符合目录「一文件一领域」约定，底座可被未来其它 fzf 场景复用。
- ✅ **新建会话入口（Q3）= MVP 不做**：MVP 只处理已存在会话（attach/kill）。新建会话留给后续迭代（日常新建多用 `project-launcher` 技能或直接手敲，非高频）。

## Open Questions

无阻塞。
