在 Monorepo（多包仓库）项目中配置 `lint-staged.config.js` 通常比单体项目稍微复杂一些，因为你需要处理**不同的子项目（packages）**、**不同的工具配置**以及**文件路径（绝对路径 vs 相对路径）**的问题。

以下是三种常见的配置策略，从简单到灵活，你可以根据你的项目规模选择最适合的一种。

### 策略一：根目录统一配置（推荐用于中小型项目）

如果你的 Monorepo 结构比较标准（例如所有包都在 `packages/` 或 `apps/` 下），并且各包使用的 Lint 规则比较统一，你可以直接在根目录的 `lint-staged.config.js` 中使用 Glob 模式匹配不同路径。

**优点**：配置集中，一目了然。
**缺点**：如果不同包的命令差异很大，配置文件会变得很长。

在根目录创建 `lint-staged.config.js`：

```javascript
module.exports = {
  // 对 apps/frontend 目录下的文件运行特定命令
  'apps/frontend/**/*.{js,jsx,ts,tsx}': [
    'eslint --fix',
    'prettier --write'
  ],

  // 对 packages/ui 库目录下的文件运行特定命令
  'packages/ui/**/*.{js,jsx,ts,tsx}': [
    'eslint --fix',
    'prettier --write'
  ],

  // 对根目录下的配置文件（如 config 文件夹）运行 Prettier
  '*.{json,md,yml}': ['prettier --write']
}
```

---

### 策略二：利用“就近原则”分散配置（最推荐，解耦性最好）

`lint-staged` 有一个特性：它会使用**离被暂存文件最近的**配置文件。你可以利用这一点，只在根目录安装 `lint-staged` 和 `husky`，但在每个子包中放置具体的配置。

**优点**：完全解耦，每个包自己管理自己的 Lint 规则，互不干扰。
**缺点**：需要在每个包里维护一个小配置文件。

**步骤：**

1. **根目录**：只配置 Husky 触发 `lint-staged`。
    * 安装：`npm install -D lint-staged husky`
    * `.husky/pre-commit`: `npx lint-staged`
    * **注意**：根目录的 `package.json` 中**不要**写 `lint-staged` 配置，也不要放 `lint-staged.config.js`（除非用于处理根目录文件）。

2. **子包目录**（例如 `packages/ui/`）：
    创建一个 `.lintstagedrc.json` 或 `lint-staged.config.js`：

    ```json
    {
      "*.{ts,tsx}": ["eslint --fix", "prettier --write"]
    }
    ```

3. **另一个子包**（例如 `apps/web/`）：
    创建它自己的配置：

    ```json
    {
      "*.{js,ts}": ["eslint --fix"]
    }
    ```

当你在根目录提交代码时，`lint-staged` 会自动遍历暂存的文件，发现文件属于 `packages/ui`，就会去用 `packages/ui/.lintstagedrc.json` 里的规则。

---

### 策略三：使用函数式配置（最灵活，适用于 Nx/Turbo 等复杂场景）

如果你的 Monorepo 工具（如 Nx 或 Turborepo）要求命令在根目录执行，或者对文件路径有特殊要求（例如有些工具只接受相对路径），你可以导出一个**函数**。

这种方式允许你动态生成命令。

**场景**：你需要对暂存的文件运行 `eslint`，但必须基于项目根目录运行，且只针对暂存的文件。

根目录 `lint-staged.config.js`:

```javascript
const path = require('path');

module.exports = {
  // 匹配所有 JS/TS 文件
  '**/*.{js,jsx,ts,tsx}': (filenames) => {
    // 1. 将绝对路径转换为相对于根目录的相对路径
    // 很多 Monorepo 工具在处理绝对路径时会出问题
    const relativeFiles = filenames
      .map((f) => path.relative(process.cwd(), f))
      .join(' ');

    // 2. 返回命令数组
    // 这里可以根据需要决定是分包运行还是统一运行
    // 例如，如果你使用 Next.js，可能需要指向特定配置
    return [
      `eslint --fix ${relativeFiles}`,
      `prettier --write ${relativeFiles}`
    ];
  },

  // 针对特定类型文件的特殊处理
  '**/*.{css,scss}': (filenames) => {
    const relativeFiles = filenames
      .map((f) => path.relative(process.cwd(), f))
      .join(' ');
    return `stylelint --fix ${relativeFiles}`;
  }
}
```

### 常见问题与注意事项

1. **`husky` 安装位置**：
    务必确保 `husky` 和 `lint-staged` 是安装在 **根目录 (Root)** 的 `devDependencies` 中。Git Hooks 是属于整个仓库的，不是属于某个子包的。

2. **路径问题**：
    默认情况下，`lint-staged` 传给命令的是**绝对路径**（如 `/Users/name/project/packages/a/index.ts`）。
    * 大多数标准工具（`eslint`, `prettier`）都能很好地处理绝对路径。
    * 如果你使用 `next lint` 或某些特定的构建工具，它们可能期望相对路径。如果遇到报错找不到文件，请尝试使用策略三中的 `path.relative` 方法转换。

3. **TypeScript 类型检查**：
    在 `lint-staged` 中运行 `tsc` (TypeScript检查) 通常比较棘手，因为 `tsc` 需要整个项目的上下文，而 `lint-staged` 只是传递了几个文件名。
    * **建议**：不要在 `lint-staged` 中运行全量 `tsc`（太慢）。
    * **或者**：使用 `bash -c tsc --noEmit`（不传文件名，只检查全量，如果项目小的话）。
    * **Nx用户**：可以使用 `nx affected --target=typecheck` 来只检查受影响的项目。

**总结建议**：

* 如果是**Lerna / Yarn Workspaces / PNPM Workspaces**：优先尝试**策略二（分散配置）**。它最符合 Monorepo 模块化的精神。
* 如果是**Nx / Turborepo**：通常需要**策略一**或**策略三**，因为这些工具更倾向于从根目录统一编排任务。

turborepo如果是刚起步的项目，可以采用策略一。主要是为了速度，采用策略一会启动多个eslint实例。包多了以后占用很多。
我们包少的情况，用策略二也是没问题的

批量卸载子项目的husky lint-staged，只保留根目录的就可以了

```
pnpm -r --filter "!." uninstall husky lint-staged
```
