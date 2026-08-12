# 架构与构建

## 包边界

`scripts/node` 是 pnpm workspace 中的独立 Node.js 工具包。源码、测试、构建配置
都位于包内，构建产物放入 `scripts/node/dist/`，面向用户的命令包装器放入仓库根
目录 `bin/`。

参考文件：

- `pnpm-workspace.yaml`
- `scripts/node/package.json`
- `scripts/node/rspack.config.ts`
- `scripts/node/generate-bin.ts`

## 源码布局

当前采用两种入口布局：

```text
scripts/node/
├── src/
│   ├── hello.ts                 # 顶层单文件入口
│   └── rule-loader/
│       ├── index.ts             # 目录型 CLI 入口
│       ├── cli.ts               # 参数解析和进程边界
│       ├── loader.ts            # 文件发现与规则解析
│       ├── formatters.ts        # 输出转换
│       ├── types.ts             # 跨模块数据契约
│       ├── utils.ts             # 无状态工具与错误类型
│       ├── converters/          # 目标格式适配
│       └── installers/          # 外部工具配置安装
└── tests/
    ├── rule-loader.test.ts
    ├── cli.test.ts
    └── rule-loader-installer.test.ts
```

新增单文件工具时放在 `src/<name>.ts`。需要多个内部模块的 CLI 使用
`src/<name>/index.ts` 作为唯一构建入口，其余文件保持为包内实现。不要为同一目录
里的每个内部模块创建独立入口。

## Rspack 入口发现契约

`scripts/node/rspack.config.ts` 中的 `scanDir()` 决定构建入口：

- `src/` 顶层的非 `index.ts` 文件分别生成一个入口。
- 子目录存在 `index.ts` 时，只把该 `index.ts` 注册为入口，不再递归暴露内部文件。
- 输出固定为 `dist/<entry>.cjs`，目标运行时为 Node.js。
- 每个入口由 `BannerPlugin` 添加 `#!/usr/bin/env node`。

因此，新增或移动入口时必须同步核对 Rspack 扫描结果。不要假设新建的任意 `.ts`
文件都会生成用户可执行命令。

## CLI 入口与库模块

目录型 CLI 的 `index.ts` 同时承担公开导出和直接执行。`rule-loader/index.ts` 会调用
`main()`，因此单元测试和其他内部模块应直接导入 `loader.ts`、`formatters.ts`、
`utils.ts` 等无启动副作用的文件；只有 CLI 集成测试才执行入口。

## 命令包装器

`scripts/node/generate-bin.ts` 遍历 `dist/*.cjs`，为每个入口生成：

- Unix shell 包装器：`bin/<name>`，通过相对路径调用 Node.js。
- Windows CMD 包装器：`bin/<name>.cmd`，使用 `%~dp0` 定位脚本。
- `COPY_JS=true` 时把 `.cjs` 复制到 `bin/`，否则包装器引用 `dist/`。

涉及构建目录、扩展名或入口命名的改动，必须同时检查 Rspack 输出与包装器生成逻辑。
不要手工维护 `dist/` 或 `bin/` 生成文件；两者均由构建流程产生并被 Git 忽略。

## 格式与模块系统

- `scripts/node/tsconfig.json` 使用 `strict: true`、`module: Preserve`、
  `moduleResolution: Bundler` 和 ES2022 目标。
- 源码使用 ESM `import`/`export`；Node.js 内置模块使用 `node:` 前缀。
- Biome 继承根目录 `biome.json`：2 空格、LF、单引号、推荐规则、自动整理 import。
- 打包产物使用 `.cjs` 兼容命令行执行环境，这不改变源码的 ESM 写法。

## 验证

新增或修改入口时至少执行：

```powershell
pnpm --filter node-script qa
pnpm --filter node-script build
```

再检查 `dist/` 与根目录 `bin/` 是否只生成预期入口。
