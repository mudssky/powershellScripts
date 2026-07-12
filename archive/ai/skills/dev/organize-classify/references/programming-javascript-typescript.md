# JavaScript / TypeScript 项目目录结构

## 先识别

- 是否有 `package.json`、workspace 配置、`tsconfig.json`、构建工具、测试工具和框架配置。
- 是库、CLI、Node 服务、前端应用、全栈框架项目还是 monorepo。
- 如果使用 Next.js、Nuxt、SvelteKit、Remix、NestJS、Express generator 等框架，先查框架官方目录约定。

## 常见库结构

```text
package/
  package.json
  src/
    index.ts
    feature.ts
  tests/
    feature.test.ts
  dist/
```

规则：

- `src/index.ts` 或 package `exports` 是公开 API 面。
- `dist` 是构建产物；除非项目明确提交产物，不手工编辑。
- `package.json` 的 `main`、`module`、`types`、`exports`、`bin` 决定入口和发布结构。

## 常见 CLI 结构

```text
package/
  src/
    cli.ts
    core/
    commands/
  bin/
    tool.js
  tests/
```

入口负责参数解析和退出码，核心逻辑放 `core` 或命令模块中。

## 常见应用结构

不使用框架约定时，可按功能或层组织：

```text
src/
  app/
  features/
  shared/
  infra/
  config/
  tests/
```

或：

```text
src/
  api/
  services/
  domain/
  adapters/
  config/
```

选择功能切片还是架构分层，取决于团队查找路径和变更方式。

## Monorepo

常见分组：

```text
apps/
packages/
tools/
configs/
```

或沿用现有 workspace。不要只因为存在多个 `package.json` 就重排，先读 workspace 配置。

## 避免

- `utils` 无限膨胀。共享能力要有边界，例如 `shared/date`、`shared/fs`。
- 把框架生成目录改成个人偏好结构。
- 移动文件后忘记更新 import alias、tsconfig paths、package exports、bin 路径和测试配置。
