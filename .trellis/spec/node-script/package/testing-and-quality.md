# 测试与质量

## 测试边界

包内测试由 `scripts/node/vitest.config.ts` 管理：

- 只发现 `tests/**/*.test.ts`。
- 使用 Node.js 环境。
- 单测试超时为 10 秒。
- 测试 API 从 `vitest` 导入，不使用 `node:test`。

行为修改应覆盖业务逻辑、模块契约和用户可见 CLI 行为；不为纯文档排版或无业务逻辑
的结构创建测试。

## 单元测试

纯函数和模块行为直接导入具体实现文件。`tests/rule-loader.test.ts` 是以下场景的参考：

- 表格驱动地覆盖宽松 YAML、glob 提取、ID 和分类转换。
- 对默认值、显式覆盖和过滤逻辑分别断言。
- 检查 Markdown/JSON 的稳定字段，而不是只做快照。
- 使用 `rejects.toThrow(RuleLoadError)` 验证领域错误。

格式化器测试应检查关键语义，例如是否包含完整规则、是否只输出索引、JSON 是否省略
正文；不要只断言“返回了字符串”。

## CLI 集成测试

`tests/cli.test.ts` 通过子进程执行入口，验证 `--version`、`--help` 和真实命令输出。
测试优先用 `tsx` 运行源码，只有源码入口不存在时才回退到已构建命令，因此日常测试
不依赖预先生成 `dist/`。

需要文件系统状态时：

- 使用独立临时目录作为 `cwd`。
- 显式创建命令所需目录结构和最小输入。
- 在 `finally` 或测试生命周期清理目录。
- 子进程 stdout/stderr 分开捕获；失败消息包含退出码和实际输出。

不要依赖开发者真实的 `.trae/rules`、用户配置或根目录 `bin/` 内容。

## I/O 与交互测试

安装器测试参考 `tests/rule-loader-installer.test.ts`：

- 使用 `vi.mock()` 隔离 `fs/promises` 和 `inquirer`。
- 每个用例前重置 mock，每个用例后恢复 spy。
- 同时覆盖新建、合并、去重、用户拒绝和 `force` 模式。
- 对写入内容执行 `JSON.parse()` 后验证结构，不比较格式化字符串。

修改配置合并逻辑时，必须证明已有未知字段保留且重复运行不会新增重复项。

## 质量门禁

包内快速验证：

```powershell
pnpm --filter node-script typecheck:fast
pnpm --filter node-script check
pnpm --filter node-script test:fast
```

等价组合命令：

```powershell
pnpm --filter node-script qa
```

涉及入口发现、打包格式或包装器时额外执行：

```powershell
pnpm --filter node-script build
```

提交前执行根目录 `pnpm qa`。如果只修改文案，可按仓库规则跳过项目 QA，但仍需检查
Markdown 链接、索引和占位符。

## 禁止做法

- 不要从带启动副作用的 `rule-loader/index.ts` 做单元测试导入。
- 不要在共享模块调用 `process.exit()` 或直接读取 `process.argv`。
- 不要用真实用户目录或本地配置作为测试 fixture。
- 不要只测试成功路径；默认推断、缺失目录、拒绝写入和幂等合并都是现有契约。
- 不要手工编辑 `dist/` 或 `bin/` 来修复构建结果。
