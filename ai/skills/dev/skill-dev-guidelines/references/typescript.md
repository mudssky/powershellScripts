# TypeScript Skill 开发

## 适用范围

当 skill 需要可维护 CLI、参数解析、业务规则测试、构建产物或 Node 生态依赖时，使用 TypeScript 脚本型结构。安装态必须能直接运行提交后的 `scripts/*.js`，不能要求用户安装依赖或构建源码。

## 目录结构

```text
ai/skills/dev/<skill-name>/
  SKILL.md
  package.json
  tsconfig.json
  src/
    <script>.ts
  tests/
    <script>.test.ts
  scripts/
    <script>.js
  references/
  examples/
```

`src/`、`tests/`、`package.json`、`tsconfig.json` 是开发态资产。`scripts/*.js` 是安装态入口，必须提交到仓库，且不要手工修改生成文件。

## 运行入口

`SKILL.md` 中示例命令必须指向分发产物：

```bash
node scripts/<script>.js [args]
```

不要让用户执行：

```bash
npx tsx src/<script>.ts
pnpm build
pnpm install
```

这些属于开发态动作，不是安装态前提。

## package.json

最少脚本参考：

```json
{
  "scripts": {
    "build": "tsc -p tsconfig.json --noEmit && node build.mjs",
    "test": "vitest run",
    "lint": "biome check src tests build.mjs package.json tsconfig.json",
    "format": "biome format --write src tests build.mjs package.json tsconfig.json",
    "check": "pnpm build && pnpm lint && pnpm test"
  }
}
```

本仓库根目录已经提供 `typescript`、`vitest`、`biome` 等共享工具。skill 子包不要重复声明这些根目录已有 dev dependency；只声明真正属于该 skill 的运行依赖或构建依赖。

## CLI 和构建

- TypeScript CLI 默认推荐使用 `cac` 处理选项、校验和 `--help`。
- 极简脚本可以用 Node 内置 `node:util` 的 `parseArgs`，避免引入不必要依赖。
- 构建产物优先打包为单文件 `scripts/<script>.js`。
- 默认不压缩构建产物，保留可读性。
- 构建面向现代 Node.js，不为了旧浏览器或旧 Node 做额外兼容降级。
- 修复问题时改 `src/` 和测试，再重新构建；不要手工修补 `scripts/*.js`。

## 配置和 secret

- 私有配置示例使用 `*.local.*` 时，确认真实文件被 `.gitignore` 或目录局部规则忽略。
- 用户级私有配置使用 `$XDG_CONFIG_HOME/<skill-name>/`，未设置时回退 `~/.config/<skill-name>/`。
- 配置查找优先级推荐为显式 `--config` > 当前项目目录 > XDG 用户配置目录。
- 不把全局私有配置放进 `~/.codex/`、`~/.claude/` 或 skill 安装目录。
- 不把真实密码、token、连接串写入可提交配置或示例。

## 测试和验证

在 skill 目录执行：

```bash
pnpm build
pnpm test
pnpm lint
node scripts/<script>.js --help
```

也可以运行聚合脚本：

```bash
pnpm check
```

测试应覆盖参数解析、核心业务规则、错误退出和配置优先级。新增默认配置查找路径时，应隔离 `HOME` / `XDG_CONFIG_HOME` 并覆盖显式路径、项目级路径、用户级路径之间的优先级。

代码改动完成后执行根目录 `pnpm qa`。如果只是 skill 文档改动，可按项目规则说明原因后跳过。
