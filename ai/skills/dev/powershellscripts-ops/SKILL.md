---
name: powershellscripts-ops
description: 管理 powershellScripts 仓库运维任务时使用，包括项目依赖安装、Docker Compose 服务生命周期、日志状态排查、环境变量示例文件，以及维护本地 powershellscripts-ops skill。
---

# PowerShellScripts Ops

## 使用场景

当用户要处理本仓库内的运维工作时使用本 skill，尤其是：

- 项目依赖安装：根目录初始化、PowerShell 模块、Node/Bash 工具构建、pnpm QA。
- 本 skill 维护：新增运维域、更新 reference、刷新 `agents/openai.yaml`、校验 skill 结构。

## 工作流

1. 先确认用户要处理的运维域，再只读取对应 reference。
2. 先按“仓库定位”解析并进入仓库根目录，再执行仓库命令。
3. 优先使用仓库已有脚本，不直接手写复杂 `docker compose` 参数。
4. 涉及 `.env`、`.env.local`、API key、数据库密码时，只引用变量名和示例文件，不输出真实值。
5. 修改配置后执行最小必要验证；如果操作依赖 Docker、上游额度、密钥或网络，明确说明验证边界。
6. 对代码或项目文件变更，遵守根目录质量规则：通常完成后运行 `pnpm qa`，pwsh 相关改动再按项目规则追加 PowerShell 测试。

## 仓库定位

全局安装后的 skill 目录可能只是 `ai/skills/dev/powershellscripts-ops` 的复制副本，不能把当前 skill 目录当作仓库根目录。

执行仓库任务前按以下顺序定位仓库：

1. 优先读取环境变量 `POWERSHELLSCRIPTS_REPO`。
2. 未设置时使用兜底路径 `/Users/mudssky/projects/env/powershellScripts`。
3. 确认候选目录存在，并且包含 `ai/skills/Install-Skills.ps1` 或 `.git`。
4. 如果候选目录不可用，先要求用户提供当前仓库路径，不在猜测目录中执行写入、停止服务、迁移或删除操作。

## 安装同步

本 skill 的维护来源是 `ai/skills/dev/powershellscripts-ops`。需要安装或刷新到全局 agent 时，从仓库根目录执行：

```powershell
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name powershellscripts-ops -DryRun
pwsh -NoProfile -File ./ai/skills/Install-Skills.ps1 -Name powershellscripts-ops -Yes
```

不推荐把本 skill 额外安装到项目 scope；它已经绑定本仓库路径，重复安装到全局和项目会产生两个同功能入口。

## Reference 选择

- 项目安装、依赖、QA：读取 `references/project-install.md`。
- 修改本 skill 或新增运维域：读取 `references/skill-maintenance.md`。

> 已迁出本仓的长期自托管服务（LiteLLM / LobeHub / Forgejo / n8n）与 Windows OpenSSH Server 的速查已归档到 `references/deprecated/`，仅供排障参考，实际运维以现仓库为准。

## 操作边界

- 不把真实 secret 写入 skill、任务文档、提交信息或最终答复。
- 不默认停止、删除 volume、迁移数据或执行破坏性 Docker 操作；这类操作需要用户明确要求。
