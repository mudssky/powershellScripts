# 模块契约

## 数据流

`rule-loader` 的主路径保持以下分层：

```text
Commander CLI
  -> loadRules(options)
  -> TraeRule[]
  -> formatOutput(rules, options)
  -> stdout
```

转换命令在加载后进入 `AntigravityConverter`，安装命令通过 `installers` 注册表选择
具体 `Installer`。参数解析、文件 I/O、数据转换和进程退出不要混在同一个辅助函数中。

参考文件：

- `scripts/node/src/rule-loader/cli.ts`
- `scripts/node/src/rule-loader/loader.ts`
- `scripts/node/src/rule-loader/formatters.ts`
- `scripts/node/src/rule-loader/converters/antigravity.ts`
- `scripts/node/src/rule-loader/installers/index.ts`

## CLI 边界

`createCli()` 只定义 Commander 命令、选项、默认值和动作；`main(argv)` 负责解析传入
参数。需要测试或复用时显式传入 `argv`，不要在业务函数里读取 `process.argv`。

CLI 动作负责：

- 把 Commander 的原始选项转换为明确的加载、格式化或安装选项。
- 输出最终结果或面向用户的错误消息。
- 在不可恢复错误时设置非零退出结果。

可复用模块不得调用 `process.exit()`。退出行为留在 `cli.ts` 或入口文件，便于单元测试
直接调用加载器、格式化器和安装器。

## 加载器

`loadRules(options)` 是文件系统到领域对象的边界：

- `cwd` 默认为 `process.cwd()`，规则目录默认为 `.trae/rules`。
- 输入只扫描规则目录顶层的 `*.md` 和 `*.mdx`。
- Frontmatter 由 `gray-matter` 和 `parseLooseYaml()` 解析。
- `globs` 优先于 `glob`；存在匹配模式且未显式声明时，`alwaysApply` 默认为
  `false`，否则默认为 `true`。
- 对外路径统一为 `/` 分隔符，避免 Windows 路径泄漏到输出协议。
- 规则目录不存在是整体失败；单文件解析失败会被收集，详细模式下输出警告，并继续
  返回成功解析的规则。

修改默认值或推断顺序时，必须同步 `types.ts` 的说明、格式化结果和
`tests/rule-loader.test.ts`。

## 格式化器

`formatOutput()`、`formatMarkdown()` 与 `formatJson()` 接收完整数据并返回字符串。
除 JSON 时间戳外，格式化函数不负责读取文件、解析 CLI 或写入 stdout。

- Markdown 默认输出全局规则正文和条件规则索引。
- `fullMode` 把全部规则作为正文输出，不再生成条件索引。
- `includeHeader: false` 只移除装饰性头部，不改变规则内容。
- JSON 输出摘要和 `contentLength`，不暴露完整规则正文。

输出字段、标题或默认格式属于用户可见契约，修改时必须更新对应断言和文档。

## 转换器

转换器接收 `TraeRule[]` 和明确的输出目录，不重新扫描源文件。Antigravity 转换器把
Trae 元数据映射为目标 `trigger`，使用 `gray-matter` 序列化 Frontmatter，并以规则
ID 作为文件名。

当前批量转换对单条规则采用继续执行策略：某条规则写入失败时记录错误，其他规则仍
继续转换。新增转换目标时应建立独立转换器，不要把目标格式分支塞进加载器或通用
格式化器。

## 安装器

所有安装器实现 `Installer`：

```ts
interface Installer {
  name: string
  install(options: InstallerOptions): Promise<void>
}
```

实现类放入 `installers/<target>.ts`，并在 `installers/index.ts` 的 `installers` 注册表
中登记。CLI 通过注册表列出、验证和调用目标，不维护第二份目标名称列表。

配置安装遵循 `ClaudeInstaller` 的现有行为：保留未知字段、只追加缺失 hook、重复执行
不产生重复项、交互确认前展示差异、`force` 模式跳过询问。不要用全量对象覆盖用户
已有配置。
