# AI Agent 配置复用片段

这个目录提供给其他 Dev Container 模板复用的 Codex / Claude Code 配置片段。

## 适用场景

* 希望容器里直接运行 `codex` 或 `claude`。
* 希望复用宿主已有登录态、模型配置、规则、skills 或插件。
* 希望容器运行态不污染宿主配置目录。

## 使用方式

1. 把 `devcontainer.fragment.jsonc` 里的片段合并到目标模板的 `devcontainer.json`。
2. 把 `../java8/scripts/bootstrap-host-configs.sh` 复制到目标项目的 `.devcontainer/scripts/`。
3. 确认 `postCreateCommand` 会执行 `bash .devcontainer/scripts/bootstrap-host-configs.sh`。

## 默认策略

* 宿主 `~/.codex` 只读挂载到 `/mnt/host-configs/codex`。
* 宿主 `~/.claude` 只读挂载到 `/mnt/host-configs/claude`。
* 宿主 `~/.claude.json` 只读挂载到 `/mnt/host-configs/claude.json`。
* 容器内安装 Codex / Claude Code CLI。
* 容器内 `~/.codex` 与 `~/.claude` 保留日志、会话和临时文件的写入空间。

如果要在容器里重新登录或修改全局设置，请临时把对应挂载改成读写，操作完成后再恢复只读。
