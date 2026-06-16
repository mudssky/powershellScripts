# 通用项目启动 skill 实施计划

## Implementation Checklist

- [x] 创建 `ai/skills/dev/project-launcher/` 目录结构：`SKILL.md`、`package.json`、`tsconfig.json`、`build.mjs`、`src/`、`tests/`、`scripts/`。
- [x] 复用 `database-query` 的 TypeScript skill 工程模式：`cac`、`rolldown`、Vitest、Biome、单文件 `scripts/project-launcher.js` 分发产物。
- [x] 实现共享类型：配置、服务候选、启动计划、诊断项、tmux pane 映射、session 元数据、JSON 输出结构。
- [x] 实现配置读取：显式 `--config`、项目 `project-launch.local.json`、项目 `project-launch.config.json`；保留 XDG 用户级路径扩展点。
- [x] 实现 `${env:NAME}` 解析和输出脱敏，避免把 secret 直接展示在 plan/doctor/start 输出中。
- [x] 实现 `--save` 写回 `project-launch.local.json`：默认不覆盖同名 service，`--overwrite` 才替换，写前创建时间戳 `.bak`。
- [x] 实现零配置发现：Maven/Gradle/Spring Boot 单服务、多模块服务候选、ignored/unknown 模块分类。
- [x] 实现计划生成：单服务、多服务、`--service`、`--all`、一次性 `--name --command`、reload 策略、串行 prepare。
- [x] 实现 doctor：tmux、java、Maven/Gradle wrapper/global CLI、端口占用、外部依赖 checkCommand。
- [x] 实现 tmux 命令生成：`new-session -d`、`split-window`、`send-keys`、`select-layout tiled`、`attach` 命令。
- [x] 实现 session 元数据：`.project-launcher/session.json` 创建、读取、配置 hash、复用判断、冲突报错、stop 限制。
- [x] 实现 `.gitignore` 检查与 `init --write-gitignore`。
- [x] 实现 text/json 输出格式，确保 `plan`、`doctor`、`start` 的 JSON 字段稳定。
- [x] 编写中文 `SKILL.md`：使用时机、工作流程、命令示例、边界、tmux 交互说明和资源引用。
- [x] 构建生成 `scripts/project-launcher.js`，不要手工修改生成文件。

## Test Plan

- [x] `pnpm -C ai/skills/dev/project-launcher build`
- [x] `pnpm -C ai/skills/dev/project-launcher lint`
- [x] `pnpm -C ai/skills/dev/project-launcher test`
- [x] `node ai/skills/dev/project-launcher/scripts/project-launcher.js --help`
- [x] `node ai/skills/dev/project-launcher/scripts/project-launcher.js plan --format json` 使用测试 fixture 或临时目录 smoke。
- [x] 根目录 `pnpm qa`

## Unit Test Coverage

- [x] 配置查找优先级：显式配置 > 项目 local > 项目 config；无配置时仍可零配置发现。
- [x] `--save` 首次写入、备份、同名报错、`--overwrite` 替换。
- [x] 零配置发现：单模块 Spring Boot、Maven 多模块服务、Gradle 子项目服务、library/parent/common 模块不自动启动。
- [x] 多服务无 `--service`/`--all` 时只输出计划不启动。
- [x] 启动计划：串行 prepare、长期 tmux command、并发构建风险提示、`--allow-parallel-build` 放行。
- [x] 热重载：`auto`、`off`、`command` 三种策略。
- [x] 端口诊断：空闲、占用、无法识别进程但能识别端口。
- [x] tmux 命令生成：三服务 pane 平铺、attach 命令、session 名 `pl-<project-slug>`。
- [x] session 冲突：元数据匹配复用，不匹配报错，缺失元数据报错。
- [x] `.gitignore`：默认只提示，`init --write-gitignore` 写入。
- [x] JSON 输出结构：`session`、`attachCommand`、`services`、`diagnostics` 字段稳定。

## Risky Files Or Rollback Points

- `ai/skills/dev/project-launcher/scripts/project-launcher.js` 是生成产物，只能由 build 生成。
- `project-launch.local.json` 写回逻辑必须限制在目标项目本机私有配置，并创建 `.bak`。
- `.project-launcher/session.json` 是运行态文件，不应被提交到业务项目。
- `stop` / `--replace` / `--force` 涉及 tmux session 生命周期，必须依赖元数据保护。
- `init --write-gitignore` 是少数会修改目标项目文件的命令，默认路径不能自动触发。

## Validation Notes

- 如果本机没有 tmux，真实 `start` 端到端可只验证到诊断失败与命令生成；tmux 集成可通过命令生成单元测试覆盖，并在说明中标注未执行真实 tmux。
- 这个任务不涉及 pwsh 相关路径，正常情况下不需要 `pnpm test:pwsh:all`。
- 若只完成规划文档不写代码，不需要执行 `pnpm qa`；进入实现后按项目规则执行。

## Review Gate Before Start

- [x] 用户确认 `prd.md`、`design.md`、`implement.md` 的 MVP 范围。
- [x] `task.py start 06-16-project-launch-skill` 后再开始代码实现。
