既然接受使用 `package.json`，且场景是**“一个 Git 仓库管理多个独立脚本”**（类似工具箱 Monorepo），最佳实践的核心在于：**利用 npm 的 `bin` 字段映射和 `tsx` 运行时**。

这种方案既能利用 npm 庞大的生态，又能解决 Windows/Linux 的跨平台执行问题，且无需手动编译。

以下是构建**“脚本工具箱”**的最佳实践指南：

### 1. 核心工具选择

* **运行时**: **[tsx](https://github.com/privatenumber/tsx)**
  * 它是现代版的 `ts-node`，基于 esbuild，速度极快，支持原生 ESM，无需配置即可直接运行 TypeScript 文件。
* **命令行框架**: **[Commander.js](https://github.com/tj/commander.js)** 或 **CAC**
  * 为了让脚本看起来像专业的 CLI 工具（支持 `-h`, `--help`, 参数解析），不要手动解析 `process.argv`。
* **交互库**: **Inquirer** (交互式问答) 或 **Chalk** (彩色输出)。

### 2. 项目结构规划

建议结构如下，所有依赖统一管理，脚本按文件隔离：

```text
my-scripts-repo/
├── package.json       # 核心：定义依赖和命令映射
├── tsconfig.json      # TS 配置
├── scripts/           # 脚本目录
│   ├── clean-logs.ts  # 脚本 A
│   ├── deploy.ts      # 脚本 B
│   └── utils.ts       # 公共函数（可被引用）
└── README.md
```

### 3. 配置步骤 (关键)

#### 第一步：初始化与安装

```bash
mkdir my-scripts && cd my-scripts
npm init -y
# 安装开发依赖 (运行器)
npm install -D tsx typescript @types/node
# 安装运行时依赖 (工具库)
npm install commander chalk
```

#### 第二步：配置 `package.json` 的 `bin` 字段

这是实现“命令行直接调用”的魔法所在。npm 会根据 `bin` 字段，在 Windows 上生成 `.cmd` 包装器，在 Unix 上生成软链接。

```json
{
  "name": "my-toolbox",
  "version": "1.0.0",
  "type": "module", 
  "bin": {
    "sys-clean": "./scripts/clean-logs.ts",
    "sys-deploy": "./scripts/deploy.ts"
  },
  "scripts": {
    "test": "echo 'Error: no test specified' && exit 1"
  },
  "dependencies": {
    "chalk": "^5.3.0",
    "commander": "^11.1.0"
  },
  "devDependencies": {
    "tsx": "^4.7.0",
    "typescript": "^5.3.0",
    "@types/node": "^20.10.0"
  }
}
```

*注意：`"type": "module"` 是现代 Node 开发的标准，建议开启。*

#### 第三步：编写脚本的最佳模版

在 `scripts/clean-logs.ts` 中。为了跨平台直接执行，Shebang 必须写对。

```typescript
#!/usr/bin/env -S npx tsx

/**
 * 上面的 Shebang 解释：
 * 1. #!/usr/bin/env -S : Linux/Mac 必须，用于分割参数。
 * 2. npx tsx : 调用项目本地安装的 tsx 来运行此文件。
 *    (即使全局没装 tsx，只要项目里装了就能跑)
 */

import { Command } from 'commander';
import chalk from 'chalk';
import path from 'path';
import fs from 'fs';

const program = new Command();

program
  .name('sys-clean')
  .description('清理日志文件的 CLI 工具')
  .version('1.0.0')
  .argument('[target]', '目标目录', '.') // 默认当前目录
  .option('-d, --dry-run', '仅模拟运行，不删除文件')
  .action((targetDir, options) => {
    
    const absPath = path.resolve(process.cwd(), targetDir);
    console.log(chalk.blue(`正在扫描目录: ${absPath}`));

    if (options.dryRun) {
      console.log(chalk.yellow('>> 模拟模式 (Dry Run) <<'));
    }

    // 模拟业务逻辑
    if (fs.existsSync(absPath)) {
        console.log(chalk.green(`成功清理: ${absPath}`));
    } else {
        console.error(chalk.red('错误: 目录不存在'));
        process.exit(1);
    }
  });

program.parse();
```

### 4. 如何实现“终端直接执行”

现在的目标是：在任何目录下输入 `sys-clean` 都能运行。

#### 方法 A：本地开发调试 (推荐)

在当前项目根目录下运行：

```bash
npm link
```

**原理**：

1. npm 会读取 `package.json` 的 `bin` 字段。
2. 它会将 `sys-clean` 和 `sys-deploy` 注册到你系统的全局 PATH 中。
3. Windows 下会自动生成 `sys-clean.cmd`，内容是用 `node` 调用 `tsx` 执行你的 TS 文件。

**使用**：
打开任意新的终端窗口：

```bash
sys-clean --help
sys-clean ./logs -d
```

#### 方法 B：通过 npx 临时执行 (适合他人使用)

如果你的同事拉取了仓库，不想 `npm link` 污染全局命令，他们可以这样：

```bash
# 在项目根目录
npx tsx scripts/clean-logs.ts --help
```

或者你可以封装 npm scripts：

```json
"scripts": {
  "clean": "tsx scripts/clean-logs.ts",
  "deploy": "tsx scripts/deploy.ts"
}
```

然后运行 `npm run clean -- --dry-run`。

### 5. 跨平台兼容性细节

1. **Shebang (`#!/usr/bin/env -S npx tsx`)**:
    * **Linux/macOS**: 直接运行脚本文件（如 `./scripts/clean-logs.ts`）时，这行起作用。它会告诉系统用 `npx tsx` 来解释该文件。
    * **Windows**: Windows 内核完全忽略 Shebang。但是，当你运行 `npm link` 时，npm 生成的 `sys-clean.cmd` 脚本会负责调用 Node。所以这行代码在 Windows 上也是安全的（被视为注释）。

2. **路径问题**:
    * 始终使用 `path.join()` 或 `path.resolve()`，不要手动拼接字符串（如 `dir + "/" + file`），这在 Windows 上会出问题。

### 6. 总结清单

要实现最佳的 `package.json` 脚本管理方案：

1. [ ] **使用 `tsx`**: 它是目前运行 TS 脚本最快、最省心的方式。
2. [ ] **配置 `bin`**: 在 `package.json` 里把命令名映射到文件路径。
3. [ ] **正确的 Shebang**: 头部加上 `#!/usr/bin/env -S npx tsx`。
4. [ ] **使用 `npm link`**: 在本地开发机上“安装”这些脚本，实现全局调用。
5. [ ] **保持依赖统一**: 所有脚本共享根目录的 `node_modules`，避免每个脚本都要 `npm install`。

这种方式非常适合团队内部维护一套 Ops/DevOps 工具库。
