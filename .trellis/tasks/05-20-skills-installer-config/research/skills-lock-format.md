# skills lock 文件格式调研

## 结论摘要

`skills` CLI 已经有 lock 文件概念，可以覆盖一部分“多设备同步已安装 skill”的需求。设计上应尽量贴近它的格式，而不是发明完全不同的配置结构。

## 资料来源

* 本机全局 lock：`C:\Users\mudssky\.agents\.skill-lock.json`
* Context7 `/vercel-labs/skills` lock file API 文档

## 现有 lock 类型

* Global lock: `~/.agents/.skill-lock.json`
  * 用于 global installs。
  * 本机示例版本为 `version: 3`。
* Local/project lock: `skills-lock.json`
  * 位于项目根目录。
  * 用于 project-scoped installs。
  * 文档说明应提交到版本控制，支撑跨机器复现。

## Global lock 示例字段

```json
{
  "version": 3,
  "skills": {
    "find-skills": {
      "source": "vercel-labs/skills",
      "sourceType": "github",
      "sourceUrl": "https://github.com/vercel-labs/skills.git",
      "skillPath": "skills/find-skills/SKILL.md",
      "skillFolderHash": "c2f31172b6f256272305a5e6e7228b258446899f",
      "installedAt": "2026-02-10T06:29:08.304Z",
      "updatedAt": "2026-02-10T06:29:08.304Z"
    }
  },
  "dismissed": {
    "findSkillsPrompt": true
  },
  "lastSelectedAgents": ["codex", "claude-code"]
}
```

## 对本任务的影响

* `source`、`sourceType`、`sourceUrl`、`skillPath`、`pluginName` 这些字段适合作为配置/状态模型参考。
* `skillFolderHash`、`installedAt`、`updatedAt` 是安装后状态，不应由手写配置维护。
* `lastSelectedAgents` 可启发默认 agent 列表，但我们的配置仍需要显式默认值和 CLI 覆盖。
* project 模式应考虑读取/检查项目根 `skills-lock.json`，global 模式读取 `~/.agents/.skill-lock.json`。

## 推荐调整

* 保留 `ai/skills/skills.config.json` 作为期望状态配置，但让其结构贴近 lock：
  * `version`
  * `scope`
  * `agents`
  * `skills` object，以 skill 名为 key
  * 每项包含 `source`、`sourceType`、可选 `sourceUrl`、`skillPath`、`pluginName`、`agents`
* 安装前状态检查读取对应 lock：
  * `global` -> `~/.agents/.skill-lock.json`
  * `project` -> `<repo>/skills-lock.json`
* 安装后不要手写 lock；让 `npx skills add` 更新官方 lock。
* dry-run 展示配置期望状态与 lock 当前状态的差异。

## 风险

* 直接依赖 lock 内部字段可能受 `skills` CLI 版本影响。MVP 应只把 lock 作为状态检查来源，真正安装和 lock 更新仍委托 CLI。
* lock version 当前为 3，旧版本可能被 CLI 清空重建；脚本应把不支持的 lock version 标为 unknown 状态，而不是自行迁移。
