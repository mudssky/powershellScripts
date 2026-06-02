# skills CLI 与仓库结构调研

## 结论摘要

`vercel-labs/skills` 是一个 npm CLI 包，包名和命令都是 `skills`，用于查找、安装和同步 agent skills。它不是主要的 skill 集合仓库；README 和 Context7 文档中的示例通常从 `vercel-labs/agent-skills` 安装具体 skill。

## 资料来源

* Context7 library: `/vercel-labs/skills`
* GitHub: `https://github.com/vercel-labs/skills`
* npm package metadata: `skills@1.5.7`

## CLI 能力

* 安装 GitHub 仓库中的 skills：
  * `npx skills add vercel-labs/agent-skills`
  * `npx skills add vercel-labs/agent-skills@react-best-practices`
  * `npx skills add vercel-labs/agent-skills#main -g -y --agent claude-code`
* 支持指定目标 agent：
  * `npx skills add vercel-labs/agent-skills -a claude-code -a opencode`
* 支持多种来源：
  * GitHub shorthand：`owner/repo`
  * GitHub URL
  * repo 中的直接 skill 路径
  * GitLab URL
  * 任意 git URL
  * 本地路径
* 支持查找：
  * `npx skills find "react performance"`
* 支持实验性同步：
  * `npx skills experimental_sync -y --agent claude-code`
  * 用途是扫描 `node_modules` 内含 `SKILL.md` 的包，并同步到项目 agent skill 目录。

## 对本仓库设计的影响

* 我们可以把 `npx skills add ...` 作为安装后端，而不是重写远程下载和 agent 目录探测。
* `ai/skills` 下的配置文件可以声明来源、skill 名称、目标 agent、是否全局安装、是否确认交互和是否强制覆盖。
* `vercel-labs/skills` 本身适合作为安装工具依赖；实际默认示例来源应考虑 `vercel-labs/agent-skills` 或配置里显式写用户想要的来源。
* 本地开发目录可以作为 `npx skills add ./ai/skills/dev/<skill-name>` 的来源，或者由项目脚本复制/链接到多个 agent 目标目录。

## 风险与待验证点

* `experimental_sync` 仍标为 experimental，不宜作为 MVP 的唯一机制。
* CLI 的目标 agent 名称需要在实现前通过 `npx skills --help` / `npx skills add --help` 固化测试。
* 如果用户希望完全离线或无 Node 依赖，才需要实现纯 PowerShell 复制安装后端；首版可以先包装 `npx skills`。
