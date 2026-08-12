# 类型与错误处理

## 类型组织

跨模块的数据契约集中在功能目录的 `types.ts`。`rule-loader/types.ts` 定义规则元数据、
领域对象、加载选项、格式化选项和 CLI 选项；加载器、格式化器和转换器都从这里导入。

只在单个实现文件中使用的结构保留为局部类型，例如
`installers/claude.ts` 的 `ClaudeConfig`。不要把私有配置形状提升为公共类型，也不要在
多个文件重复声明同一个跨模块对象。

## 函数契约

新增或修改函数时必须写明标准参数与返回值说明。公开函数使用 TSDoc，并在有默认值、
副作用或异常时一并说明：

```ts
/**
 * 根据选项加载规则。
 *
 * @param options - 工作目录、规则目录与过滤选项
 * @returns 解析并过滤后的规则列表
 * @throws {RuleLoadError} 规则目录不存在
 */
export async function loadRules(
  options: LoadOptions = {},
): Promise<TraeRule[]> {
  // ...
}
```

复杂业务注释使用中文解释设计意图或兼容原因，不逐行翻译基础语法。参考
`loader.ts` 中 `alwaysApply` 推断顺序和 `tsconfig.json` 中模块解析说明。

## 严格类型规则

- 保持 `strict: true`，不要用 `any` 绕过外部输入。
- 外部错误、Frontmatter 扩展字段和未知配置使用 `unknown`，在访问前缩小类型。
- 可选字段用 `?` 表达；默认值在模块边界通过 `??` 或参数默认值统一解析。
- 固定枚举值使用字符串联合类型，例如 `ConversionTarget` 和
  `AntigravityRuleMetadata['trigger']`。
- 注册表使用 `Record<string, Installer>`，实现类通过 `implements Installer` 校验契约。
- Node.js 路径、环境变量和进程类型使用 `@types/node` 提供的标准类型。

类型断言只用于已经由解析器或局部构造保证的边界，例如 gray-matter 的 `data as
TraeRuleMetadata`。不要用断言替代输入校验，也不要把未检查的 JSON 直接当成完整配置。

## 错误模型

`RuleLoadError` 表示规则加载阶段的领域错误，并通过 `cause?: unknown` 保留原始错误链；
`RuleParseError` 在消息和属性中携带文件路径。自定义错误必须设置稳定的 `name`。

CLI 采用分层处理：

- 已知领域错误输出可操作消息；详细模式可继续输出 `cause`。
- 普通 `Error` 输出其消息。
- 非 Error 抛出值输出稳定的“未知错误”消息。
- 不可恢复失败由 CLI 边界转为非零退出结果。

读取外部配置时先把捕获值视为 `unknown`，通过对象检查和字段存在性识别 `ENOENT`。
只有“文件不存在”可转为空配置，解析失败、权限错误等必须继续抛出。参考
`installers/claude.ts`。

## 路径与序列化边界

- 内部文件操作使用 `path.resolve()`、`path.join()` 和 `path.relative()`。
- 写入用户可见 JSON、Markdown 或命令协议前，把路径分隔符规范为 `/`。
- JSON 配置使用 `JSON.stringify(value, null, 2)` 保持可读格式。
- Frontmatter 使用 `gray-matter` 解析和生成，不手工拼接 YAML。
