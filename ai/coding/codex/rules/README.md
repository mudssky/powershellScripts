# Codex Rules

`rules/` 目录下的所有 `.rules` 文件都会被 Codex 自动加载。

这些文件的目标是：

- 让高频、低风险、可复用的命令按类别集中管理
- 让项目特例、一次性命令和暂时不适合泛化的规则留在 `default.rules`
- 在减少审批的同时，保留对系统级、发布类、破坏性命令的保守边界

## 语法

最小可用规则：

```python
# 允许以 `pnpm add` 开头的命令
prefix_rule(pattern=["pnpm", "add"], decision="allow")

```

约定：

- 只使用 `#` 独占一行的注释
- `pattern` 按命令参数前缀匹配
- 优先使用“最小但稳定”的前缀，不要为了省事把边界放得过宽
- 当前只维护 `decision="allow"` 规则

## 文件分工

- `pnpm.rules`
  说明：通用、低风险、可复用的 `pnpm` 开发命令
  不放：项目路径 `-C`、发布类、生产验证类、外部脚手架下载类

- `uv.rules`
  说明：通用、低风险、可复用的 `uv` 安装、同步和常见开发运行命令
  不放：需要保守处理的特殊迁移脚本边界说明之外的高风险例外

- `git.rules`
  说明：只读和低风险写入到 `commit` 的 Git 命令
  不放：`push`、`reset`、`rebase`、`checkout --` 等高风险命令

- `bash-readonly.rules`
  说明：直接执行的只读 shell 命令，如 `rg`、`ls`、`cat`
  不放：带副作用的写操作、复杂 shell 包装、带重定向/管道的 `bash -lc`

- `network.rules`
  说明：`curl` 相关只读网络访问
  不放：明显危险的下载执行链路；复杂 shell 包装的 `curl`

- `process.rules`
  说明：常见本地等待和安全进程控制模式
  不放：任意命令包装器的宽泛放行；项目专用的复杂启动脚本

- `docker.rules`
  说明：查询和检查类 Docker 命令
  不放：`docker build`、发布、镜像推送或其他更重的副作用操作

- `windows.rules`
  说明：Windows 环境下常见的只读 `cmd` / `powershell` / `pwsh` 查询命令
  不放：`Remove-*`、`Set-*`、`Copy-Item`、`Move-Item`、`New-Item`、`Start-Process`，以及过宽的 `-Command` 前缀

- `default.rules`
  说明：特例层
  放这里的规则通常具备以下一种或多种特征：
  - 项目路径、端口、URL、脚本名硬编码
  - 一次性或短期特例
  - 边界还不够稳定，暂时不适合抽成通用规则
  - 风险偏高，但当前又需要明确保留

## 新规则放哪里

优先按这个顺序判断：

1. 这是通用、低风险、可复用的命令吗？
   是：放进对应专项文件。

2. 这是某个命令族里“很像通用规则但其实绑定特定项目路径/端口/脚本”的规则吗？
   是：先留在 `default.rules`。

3. 这是系统级、发布类、破坏性、或边界仍不清楚的命令吗？
   是：先留在 `default.rules`，不要为了省审批直接放宽。

4. 这个规则已经被更短、更稳定的前缀覆盖了吗？
   是：删除重复规则，避免双处维护。

## 维护约定

- 每个规则文件顶部都写清楚“放什么 / 不放什么”
- 非显而易见的规则前，补一行注释说明原因
- 从 `default.rules` 迁移规则时，要顺手删除重复项
- 如果某一类项目特例持续变多，再评估是否拆出新的专项文件

## 验证

运行：

```bash
bash scripts/validate-codex-rules.sh

```

这个脚本会做轻量 smoke validation：

- 验证当前 `rules/` 目录可以被 Codex 加载
- 验证 `#` 注释不会导致规则解析失败
- 验证新增 `.rules` 文件会被自动加载
- 验证故意注入的坏规则能被检测出来
