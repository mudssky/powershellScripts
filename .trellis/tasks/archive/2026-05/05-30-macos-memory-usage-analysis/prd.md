# 分析 macOS 内存占用

## Goal

分析当前 macOS 系统内存占用状态，判断是否存在值得手动优化的高占用进程、常驻服务或 swap 压力，并将这轮实测经验沉淀到 `scripts/pwsh/devops/memory-diagnostics` 的 macOS 分析能力中。

## Requirements

- 基于当前系统只读指标进行分析，包括物理内存、内存压力、swap、压缩内存、主要进程 RSS/CPU 状态。
- 区分 macOS 自动内存管理下的正常缓存占用与真实压力信号，避免为了“空闲内存数字好看”而关闭必要程序。
- 识别可选优化项，例如长时间不用的前台应用、后台开发服务、自托管容器、登录项或代理服务。
- 不执行关闭进程、卸载软件、修改系统配置等破坏性操作；如需优化，仅给出建议和可回滚命令。
- 优化 `scripts/pwsh/devops/memory-diagnostics` 的 macOS 输出，使脚本能暴露本次人工分析中真正有用的信号：`memory_pressure`、压缩内存、完整进程名、Docker Desktop VM 上限、容器实际使用量和 macOS 专属建议。
- 保持脚本只读，不停止进程、不修改 Docker Desktop 配置、不修改登录项。
- 保持现有 JSON 输出兼容性：只新增字段和建议，不删除已有字段，不改变 Windows/Linux 现有行为。

## Acceptance Criteria

- [x] 记录本次分析的采样时间、系统版本、物理内存容量和关键内存指标。
- [x] 列出当前主要内存占用来源，并判断它们是否异常。
- [x] 给出按收益和风险排序的优化建议。
- [x] 明确说明 macOS 自动内存管理下哪些情况不需要手动干预。
- [x] macOS snapshot 能输出完整进程名，避免 `/Applications/Go`、`/Users/.../.` 这类截断名称。
- [x] macOS system 字段能包含 memory pressure、压缩内存、swap I/O、pageout 等判断真实压力的指标。
- [x] Docker 报告能在 macOS 上补充 Docker Desktop VM 内存上限，并能提示“VM 上限高但容器实际占用较低”的情况。
- [x] recommendations 能在 macOS 上区分正常缓存/自动管理与需要关注的 swap、压缩内存、Docker/IDE/浏览器常驻叠加。
- [x] 相关 Pester 测试覆盖新增解析逻辑和推荐规则。

## Confirmed Facts

- 采样时间：2026-05-30 04:34-04:38 CST。
- 系统版本：macOS 26.5，Build 25F71。
- 物理内存：16GB。
- 机器已连续运行约 7 天 17 小时。
- 当前 CPU 不忙：`top` 采样约 79.69% idle，负载约 2.01 / 1.94 / 1.78。
- `vm.swapusage` 显示 swap 总量 5GB，已用约 3.55GB。
- `memory_pressure` 显示系统范围可用比例约 42%；`top` 显示压缩内存约 7.25GB。
- 当前运行 9 个 Docker 容器：Forgejo、SearXNG、LobeHub、LiteLLM、Lobe network、ParadeDB、RustFS、Redis、New API。
- Docker VM 启动参数包含 `--memoryMiB 8092`，容器视角内存上限约 7.65GiB。
- Docker 容器当前合计使用约 2.51GiB，其中 LiteLLM 约 1.07GiB、LobeHub 约 470MiB、ParadeDB 约 311MiB、RustFS 约 248MiB、SearXNG 约 204MiB、Forgejo 约 146MiB。
- 进程分组估算：Docker 宿主侧约 2.1GiB，VS Code / vscode-server 约 2.0GiB，Chrome 约 1.7GiB，Node/npm/MCP 可见进程约 1.6GiB。
- 长驻登录项/后台项包括 Docker、Ollama、ToDesk、RustDesk、Tailscale、Clash Verge、VS Code 更新服务等。

## Findings

- 当前不是单个普通应用异常泄漏导致的内存问题，更像是开发工作站常驻栈叠加：Docker VM、自托管服务、VS Code/远程扩展、Chrome、MCP/Node 工具。
- 用户关于 macOS 自动管理内存的判断基本成立：仅凭“已用内存高”不应关闭程序；应优先看内存压力、swap 增长、卡顿、压缩内存和后台服务是否符合当前工作意图。
- 需要特别对待 Docker：macOS 可以回收缓存，但不会替用户判断自托管开发服务是否应常驻，也不会自动把 Docker VM 资源上限调小。
- 当前最有收益的优化方向是 Docker 资源上限和按需运行 compose 服务，其次是清理 VS Code/Node/MCP 常驻进程，再次才是浏览器标签页。
- 现有脚本在 macOS 上能运行并输出 JSON，但信息价值不足：Top 进程名称被 `ps` 默认宽度截断，recommendations 为空，缺少 `memory_pressure`、压缩内存、Docker Desktop VM 上限等 macOS 关键线索。
- `ps -ww -axo pid=,ppid=,rss=,vsz=,%mem=,comm=` 可以在本机输出完整可执行路径，适合作为 macOS Top 进程采集路径。

## Notes

- 用户倾向认为 macOS 会自动管理内存，不需要为了省内存关闭程序；分析需要验证这个判断在当前机器上是否成立。
- 当前采样环境：2026-05-30 04:34:38 CST，macOS 26.5，物理内存 16GB。
- 2026-05-30 决策：实现范围只优化 macOS 分析质量，不改 Windows/Linux 行为。
