# 代码示例

以下示例来自当前 `scripts/node` 实现，用于说明本包的首选形状。新增代码时应复用这些
边界，而不是复制完整实现。

## 选项对象与明确返回类型

来源：`scripts/node/src/rule-loader/loader.ts`

```ts
export async function loadRules(
  options: LoadOptions = {},
): Promise<TraeRule[]> {
  const cwd = options.cwd ?? process.cwd()
  const rulesDir = options.rulesDir
    ? path.resolve(cwd, options.rulesDir)
    : path.resolve(cwd, DEFAULT_RULES_DIR)

  // 加载、解析并返回领域对象
}
```

要点：可选输入集中在命名选项对象；默认值在边界解析；异步返回值写出完整泛型类型。

## 纯格式化分派

来源：`scripts/node/src/rule-loader/formatters.ts`

```ts
export function formatOutput(
  rules: TraeRule[],
  options: FormatOptions = {},
): string {
  const format = options.format ?? 'markdown'

  if (format === 'json') {
    return formatJson(rules, options)
  }

  return formatMarkdown(rules, options)
}
```

要点：分派函数不读取文件、不写 stdout，只把输入转换为返回值；具体格式由独立函数
负责。

## 接口与注册表扩展

来源：`scripts/node/src/rule-loader/installers/types.ts` 和
`scripts/node/src/rule-loader/installers/index.ts`

```ts
export interface Installer {
  name: string
  install(options: InstallerOptions): Promise<void>
}

export const installers: Record<string, Installer> = {
  claude: new ClaudeInstaller(),
}
```

要点：新增目标实现同一接口并登记到唯一注册表；CLI 从注册表派生可选目标。

## unknown 错误缩小

来源：`scripts/node/src/rule-loader/installers/claude.ts`

```ts
} catch (error: unknown) {
  if (
    error &&
    typeof error === 'object' &&
    'code' in error &&
    error.code !== 'ENOENT'
  ) {
    throw error
  }
}
```

要点：捕获外部错误后先检查形状；只吞掉明确允许恢复的“文件不存在”，其他错误继续
传播。

## 临时目录隔离 CLI 测试

来源：`scripts/node/tests/cli.test.ts`

```ts
const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'node-script-cli-'))

try {
  return runCommand(process.execPath, args, { cwd: tempDir })
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true })
}
```

要点：集成测试显式控制工作目录和输入，并保证清理，不读取或修改开发者真实配置。

## 业务默认值的顺序

来源：`scripts/node/src/rule-loader/loader.ts`

```ts
const matchPatterns = extractMatchPatterns(metadata)
const hasGlobs = matchPatterns !== undefined && matchPatterns.length > 0
const alwaysApply = metadata.alwaysApply ?? !hasGlobs
```

要点：先标准化输入，再应用显式配置优先的默认规则。修改此类顺序时需同步类型说明和
测试用例。
