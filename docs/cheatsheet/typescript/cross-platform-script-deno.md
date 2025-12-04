使用 TypeScript 编写跨平台、单文件、可直接执行的脚本，目前的**最佳实践是使用 Deno**（或者 Google 的 `zx` 库）。

传统的 Node.js 需要 `package.json`、`node_modules` 文件夹以及编译步骤（`tsc`），这违背了“轻量级脚本”的初衷。而 **Deno** 天生支持 TypeScript，支持 URL 导入依赖（无需 `node_modules`），并且拥有强大的权限控制。

以下是实现方案：

---

### 方案一：使用 Deno (推荐，原生支持 TS)

Deno 是 Node.js 之父开发的现代运行时，完美符合你的“单文件引入依赖”和“直接执行”的需求。

#### 1. 编写脚本 (`script.ts`)

在 Deno 中，你可以直接在代码顶部 `import` 依赖（支持 CDN URL 或 `npm:` 前缀），无需 `npm install`。

```typescript
#!/usr/bin/env -S deno run --allow-net --allow-read --allow-env

/**
 * 解释器说明 (Shebang):
 * 1. #!/usr/bin/env -S : 使用 env 的 -S 选项来传递参数 (Linux/macOS 必需)。
 * 2. deno run : 运行命令。
 * 3. --allow-... : Deno 默认沙盒隔离，必须显式赋予网络、读取文件等权限。
 */

// --- 依赖管理 (单文件核心) ---
// 直接从 URL 或 npm 导入，Deno 会在第一次运行时缓存它们
import { format } from "https://deno.land/std@0.208.0/datetime/mod.ts";
import { green, bold } from "https://deno.land/std@0.208.0/fmt/colors.ts";
// 甚至可以直接引用 npm 包
import figlet from "npm:figlet"; 

// --- 主逻辑 ---
async function main() {
    // 1. 打印 ASCII 艺术字
    const text = await new Promise<string>((resolve, reject) => {
        figlet("Hello TS Script", (err, data) => {
            if (err) reject(err);
            else resolve(data || "");
        });
    });
    
    console.log(green(text));

    // 2. 平台检测
    const os = Deno.build.os; // "darwin", "linux", "windows"
    console.log(`Running on: ${bold(os.toUpperCase())}`);

    // 3. 执行 Shell 命令 (跨平台调用)
    const cmd = os === "windows" ? ["powershell", "-c", "echo 'Hi from PS'"] : ["echo", "Hi from Bash"];
    
    const command = new Deno.Command(cmd[0], {
        args: cmd.slice(1),
    });
    
    const { code, stdout } = await command.output();
    console.log(`Command output: ${new TextDecoder().decode(stdout).trim()}`);
}

// 支持 Top-level await
await main();
```

#### 2. 实现直接执行

**Linux / macOS:**

```bash
chmod +x script.ts
./script.ts
```

*注意：第一次运行时，Deno 会自动下载并缓存 import 的依赖，之后运行速度会很快。*

**Windows:**
Windows 不支持 Shebang。你有两个选择：

* **方法 A (推荐): 编译为 exe**
    Deno 可以将脚本打包成独立的二进制文件（包含运行时），这样不需要对方安装 Deno 也能跑。

    ```powershell
    deno compile --allow-net --allow-read --allow-env --output mytool script.ts
    # 生成 mytool.exe (Windows) 或 mytool (Linux/Mac)
    .\mytool.exe
    ```

* **方法 B: 使用 cmd 包装器**
    创建一个 `script.cmd` 文件：

    ```batch
    @deno run --allow-net --allow-read --allow-env "%~dp0script.ts" %*
    ```

---

### 方案二：使用 Google `zx` (适合重度 Shell 交互)

如果你写脚本的主要目的是为了替代 Bash/PowerShell 来调用系统命令，Google 的 `zx` 库是最佳选择。它封装了 Node.js，让 Shell 操作极其简单。

虽然它依赖 Node.js，但它也支持 Markdown 里的 TS 代码块，或者直接运行 `.mjs/.ts`。

#### 1. 安装 zx

```bash
npm install -g zx
```

#### 2. 编写脚本 (`script.mjs` 或 `script.ts`)

`zx` 最大的特点是可以通过 `$` 直接调用 shell 命令。

```typescript
#!/usr/bin/env zx

// 依赖无需手动 import，zx 自动注入了 $, fs, path, chalk 等常用库
// 如果需要额外依赖，依然建议配合 npm 安装，不如 Deno 方便

async function main() {
    // 直接调用 shell，类似 bash
    await $`echo "Hello from zx!"`

    // 获取命令输出
    const branch = await $`git branch --show-current`
    echo(chalk.blue(`Current branch is: ${branch}`))

    // 跨平台处理
    if (process.platform === 'win32') {
        await $`powershell -c Get-Date`
    } else {
        await $`date`
    }
}

main()
```

#### 3. 执行

```bash
chmod +x script.mjs
./script.mjs
```

---

### 方案三：使用 Node.js 22+ (原生支持，但依赖管理较弱)

Node.js v22 增加了 `--experimental-strip-types` 标志，可以直接运行 TypeScript 文件，而无需 `ts-node`。

**缺点**：Node.js 依然不支持像 Deno 那样的 URL import。如果你的脚本需要第三方库（比如 `lodash`），你依然得创建一个 `package.json` 并运行 `npm install`。这使得它不适合“单文件脚本”。

**脚本示例 (`script.ts`):**

```typescript
#!/usr/bin/env node --experimental-strip-types

// Node 只能 import 本地 node_modules，不能 import URL
// import _ from "lodash"; // 只有在 npm install 后才有效

const msg: string = "Hello Native Node TS";
console.log(msg);
```

---

### 总结：最佳实践对比

| 特性 | **Deno (推荐)** | **Google zx** | **Node.js (原生)** |
| :--- | :--- | :--- | :--- |
| **单文件依赖** | ✅ **完美** (支持 `import "https://..."`) | ❌ (通常需 `package.json`) | ❌ (需 `package.json`) |
| **类型支持** | ✅ 原生 TS | ✅ 支持 TS/JS | ✅ (v22+ 实验性支持) |
| **Shell 交互** | 需使用 `Deno.Command` (略繁琐) | ✅ **极佳** (使用 `$` 语法) | 需使用 `child_process` (繁琐) |
| **跨平台执行** | ✅ (可编译成单一 Binary) | 需安装 Node 和 zx | 需安装 Node |
| **权限安全** | ✅ (默认禁止网络/文件访问) | ❌ (无沙盒) | ❌ (无沙盒) |

### 最终建议

1. **对于通用工具脚本**：使用 **Deno**。
    * 它解决了依赖地狱，代码拷给别人就能跑（只要对方有 Deno）。
    * 如果对方连 Deno 都不想装，你可以用 `deno compile` 把它变成一个 `.exe` 给对方。

2. **对于主要是为了调用 Shell 命令的脚本**：使用 **zx**。
    * 代码写起来最像 Bash，最简洁。

3. **在 Windows 上直接执行**：
    * 最优雅的方式是 `deno compile` 生成 exe。
    * 或者是写一个同名的 `.cmd` 或 `.bat` 文件来引导执行。
