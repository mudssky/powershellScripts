# JSON Diff Tool

一个功能强大的命令行工具，用于比较 JSON、JSONC 和 JSON5 文件的差异。支持多种输出格式，提供详细的差异分析和统计信息。

## 功能特性

- 🔍 **多格式支持**: 支持 JSON、JSONC（带注释的JSON）和 JSON5 格式
- 📊 **多种输出格式**: 表格、JSON、YAML、树形结构
- 🎨 **彩色输出**: 使用颜色区分不同类型的差异
- 📈 **统计信息**: 提供详细的差异统计
- 💾 **文件输出**: 支持将结果保存到文件
- 🔄 **递归比较**: 支持目录递归比较
- ⚡ **高性能**: 优化的比较算法，处理大型文件

## 安装

### 前置要求

- Node.js >= 16.0.0
- npm 或 yarn

### 本地安装

```bash
# 克隆项目
git clone <repository-url>
cd json-diff-tool

# 安装依赖
npm install

# 构建项目
npm run build

# 全局链接（可选）
npm link
```

## 使用方法

### 基本用法

```bash
# 比较两个JSON文件
json-diff file1.json file2.json

# 指定输出格式
json-diff file1.json file2.json --format table
json-diff file1.json file2.json --format json
json-diff file1.json file2.json --format yaml
json-diff file1.json file2.json --format tree

# 保存结果到文件
json-diff file1.json file2.json --output result.json

# 递归比较目录
json-diff dir1/ dir2/ --recursive

# 显示统计信息
json-diff file1.json file2.json --stats

# 禁用颜色输出
json-diff file1.json file2.json --no-color
```

### PowerShell 包装脚本

项目还提供了 PowerShell 包装脚本，方便在 Windows 环境中使用：

```powershell
# 使用 PowerShell 脚本
.\scripts\Compare-JsonFiles.ps1 -File1 "config1.json" -File2 "config2.json"

# 指定输出格式
.\scripts\Compare-JsonFiles.ps1 -File1 "config1.json" -File2 "config2.json" -Format "table"

# 递归比较目录
.\scripts\Compare-JsonFiles.ps1 -Directory1 "src" -Directory2 "backup" -Recursive

# 保存到文件
.\scripts\Compare-JsonFiles.ps1 -File1 "config1.json" -File2 "config2.json" -OutputFile "diff.json"
```

## 命令行选项

| 选项 | 简写 | 描述 | 默认值 |
|------|------|------|--------|
| `--format` | `-f` | 输出格式 (table, json, yaml, tree) | `table` |
| `--output` | `-o` | 输出文件路径 | - |
| `--recursive` | `-r` | 递归比较目录 | `false` |
| `--stats` | `-s` | 显示统计信息 | `false` |
| `--no-color` | - | 禁用颜色输出 | `false` |
| `--help` | `-h` | 显示帮助信息 | - |
| `--version` | `-v` | 显示版本信息 | - |

## 输出格式示例

### 表格格式 (默认)

```
┌─────────────────┬──────────┬───────────┬───────────┐
│ Path            │ Type     │ Old Value │ New Value │
├─────────────────┼──────────┼───────────┼───────────┤
│ name            │ MODIFIED │ Alice     │ Bob       │
│ age             │ ADDED    │ -         │ 25        │
│ email           │ REMOVED  │ alice@... │ -         │
│ settings.theme  │ MODIFIED │ dark      │ light     │
└─────────────────┴──────────┴───────────┴───────────┘

Statistics:
  Total changes: 4
  Added: 1
  Removed: 1
  Modified: 2
```

### JSON 格式

```json
{
  "differences": [
    {
      "path": "name",
      "type": "MODIFIED",
      "oldValue": "Alice",
      "newValue": "Bob"
    }
  ],
  "summary": {
    "total": 4,
    "added": 1,
    "removed": 1,
    "modified": 2
  }
}
```

### 树形格式

```
Differences:
├── name (MODIFIED: Alice → Bob)
├── age (ADDED: → 25)
├── email (REMOVED: alice@example.com → )
└── settings
    └── theme (MODIFIED: dark → light)
```

## 支持的文件格式

### JSON
标准的 JSON 格式文件。

```json
{
  "name": "example",
  "value": 123
}
```

### JSONC
带注释的 JSON 格式文件。

```jsonc
{
  // 这是注释
  "name": "example",
  "value": 123 // 行尾注释
}
```

### JSON5
扩展的 JSON 格式，支持更灵活的语法。

```json5
{
  name: 'example',        // 无需引号的键名
  value: 123,            // 尾随逗号
  // 注释支持
}
```

## API 使用

### TypeScript/JavaScript

```typescript
import { FileParser, JsonComparator, OutputFormatter } from 'json-diff-tool';
import { OutputFormat } from 'json-diff-tool/types';

// 解析文件
const obj1 = await FileParser.parseFile('file1.json');
const obj2 = await FileParser.parseFile('file2.json');

// 比较对象
const comparator = new JsonComparator();
const result = comparator.compare(obj1, obj2);

// 格式化输出
const formatter = new OutputFormatter();
const output = formatter.format(result, OutputFormat.TABLE);
console.log(output);

// 保存到文件
await formatter.outputToFile(output, 'result.txt');
```

## 开发

### 项目结构

```
json-diff-tool/
├── src/                    # 源代码
│   ├── index.ts           # 入口文件
│   ├── parser.ts          # 文件解析器
│   ├── comparator.ts      # 比较器
│   ├── formatter.ts       # 输出格式化器
│   └── types.ts           # 类型定义
├── tests/                 # 测试文件
│   ├── parser.test.ts
│   ├── comparator.test.ts
│   ├── formatter.test.ts
│   └── setup.ts
├── scripts/               # PowerShell 脚本
│   └── Compare-JsonFiles.ps1
├── package.json
├── tsconfig.json
├── jest.config.js
└── README.md
```

### 可用脚本

```bash
# 开发
npm run dev          # 开发模式运行
npm run build        # 构建项目
npm run clean        # 清理构建文件

# 测试
npm test             # 运行测试
npm run test:watch   # 监视模式运行测试
npm run test:coverage # 生成覆盖率报告

# 代码质量
npm run lint         # 代码检查
npm run format       # 代码格式化
```

### 运行测试

```bash
# 运行所有测试
npm test

# 运行特定测试文件
npm test -- parser.test.ts

# 生成覆盖率报告
npm run test:coverage

# 监视模式
npm run test:watch
```

## 配置

### TypeScript 配置

项目使用 TypeScript 进行开发，配置文件为 `tsconfig.json`。

### Jest 配置

测试配置在 `jest.config.js` 中，包括：
- 覆盖率要求：80%
- 支持 TypeScript
- 自定义匹配器

## 性能

- **小文件** (< 1MB): 通常在 100ms 内完成
- **中等文件** (1-10MB): 通常在 1s 内完成
- **大文件** (> 10MB): 根据复杂度，可能需要几秒钟

## 限制

- 最大文件大小：建议不超过 100MB
- 嵌套深度：建议不超过 50 层
- 循环引用：基本支持，但可能影响性能

## 故障排除

### 常见问题

1. **文件解析失败**
   - 检查文件格式是否正确
   - 确认文件编码为 UTF-8
   - 验证 JSON 语法

2. **内存不足**
   - 减小文件大小
   - 使用流式处理（未来版本）

3. **性能问题**
   - 检查文件大小和复杂度
   - 考虑分批处理

### 调试

```bash
# 启用详细输出
DEBUG=json-diff:* json-diff file1.json file2.json

# 检查版本
json-diff --version

# 获取帮助
json-diff --help
```

## 贡献

欢迎贡献代码！请遵循以下步骤：

1. Fork 项目
2. 创建功能分支 (`git checkout -b feature/amazing-feature`)
3. 提交更改 (`git commit -m 'Add some amazing feature'`)
4. 推送到分支 (`git push origin feature/amazing-feature`)
5. 打开 Pull Request

### 代码规范

- 使用 TypeScript
- 遵循 ESLint 规则
- 编写测试用例
- 更新文档

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件。

## 更新日志

### v1.0.0
- 初始版本发布
- 支持 JSON、JSONC、JSON5 格式
- 多种输出格式
- PowerShell 包装脚本
- 完整的测试覆盖

## 作者

**mudssky** - [GitHub](https://github.com/mudssky)

## 致谢

- [json5](https://github.com/json5/json5) - JSON5 解析支持
- [commander](https://github.com/tj/commander.js) - 命令行接口
- [chalk](https://github.com/chalk/chalk) - 终端颜色支持
- [cli-table3](https://github.com/cli-table/cli-table3) - 表格输出
- [js-yaml](https://github.com/nodeca/js-yaml) - YAML 输出支持

## 功能特性

- 🔍 支持多种 JSON 格式：JSON、JSONC、JSON5
- 📊 多种输出格式：表格、JSON、YAML、树形结构
- 🎨 彩色输出，易于阅读
- 🔧 灵活的比较选项
- 📝 详细的差异报告

## 安装

```bash
# 安装依赖
npm install

# 构建项目
npm run build
```

## 使用方法

### 基本用法

```bash
# 比较两个 JSON 文件
json-diff file1.json file2.json

# 比较多个文件
json-diff file1.json file2.jsonc file3.json5
```

### 输出格式

```bash
# 表格格式（默认）
json-diff file1.json file2.json --output table

# JSON 格式
json-diff file1.json file2.json --output json

# YAML 格式
json-diff file1.json file2.json --output yaml

# 树形结构
json-diff file1.json file2.json --output tree
```

### 高级选项

```bash
# 显示未更改的值
json-diff file1.json file2.json --show-unchanged

# 忽略数组顺序
json-diff file1.json file2.json --ignore-order

# 限制比较深度
json-diff file1.json file2.json --depth 5

# 使用正则表达式过滤路径
json-diff file1.json file2.json --filter "user\\.(name|email)"

# 详细输出
json-diff file1.json file2.json --verbose
```

## 命令行选项

| 选项 | 简写 | 描述 | 默认值 |
|------|------|------|--------|
| `--output <format>` | `-o` | 输出格式 (table\|json\|yaml\|tree) | table |
| `--show-unchanged` | `-u` | 显示未更改的值 | false |
| `--ignore-order` | `-i` | 忽略数组顺序 | false |
| `--depth <number>` | `-d` | 最大比较深度 | 10 |
| `--filter <pattern>` | `-f` | 路径过滤正则表达式 | - |
| `--verbose` | `-v` | 详细输出 | false |
| `--help` | `-h` | 显示帮助信息 | - |
| `--version` | `-V` | 显示版本信息 | - |

## 支持的文件格式

### JSON
标准的 JSON 格式文件。

### JSONC
JSON with Comments，支持单行注释 (`//`) 和多行注释 (`/* */`)。

### JSON5
扩展的 JSON 格式，支持：
- 注释
- 尾随逗号
- 单引号字符串
- 十六进制数字
- 多行字符串

## 输出示例

### 表格格式
```
┌─────────────┬──────────┬─────────────┬─────────────┐
│ Path        │ Type     │ Old Value   │ New Value   │
├─────────────┼──────────┼─────────────┼─────────────┤
│ user.name   │ modified │ "John"      │ "Jane"      │
│ user.age    │ added    │ -           │ 25          │
│ user.email  │ removed  │ "@test.com" │ -           │
└─────────────┴──────────┴─────────────┴─────────────┘
```

### JSON 格式
```json
{
  "files": ["file1.json", "file2.json"],
  "differences": [
    {
      "path": "user.name",
      "type": "modified",
      "oldValue": "John",
      "newValue": "Jane"
    }
  ],
  "summary": {
    "added": 1,
    "removed": 1,
    "modified": 1,
    "unchanged": 5
  }
}
```

## 开发

### 项目结构

```
json-diff-tool/
├── src/
│   ├── index.ts          # 主入口文件
│   ├── types.ts          # 类型定义
│   ├── parser.ts         # 文件解析器
│   ├── comparator.ts     # 比较算法
│   ├── formatter.ts      # 输出格式化
│   └── cli.ts           # 命令行接口
├── dist/                # 编译输出
├── tests/               # 测试文件
├── package.json
├── tsconfig.json
└── README.md
```

### 开发命令

```bash
# 开发模式
npm run dev

# 构建
npm run build

# 测试
npm test

# 清理
npm run clean
```

## 许可证

MIT License

## 作者

mudssky

## 贡献

欢迎提交 Issue 和 Pull Request！