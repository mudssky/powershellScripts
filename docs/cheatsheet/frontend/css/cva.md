### CVA (class-variance-authority) 速查表

`cva` 是一个用于创建和管理 UI 组件样式变体 (variants) 的强大工具，尤其适合与 Tailwind CSS 结合使用。

#### 1. 安装

```bash
# npm
npm install class-variance-authority

# yarn
yarn add class-variance-authority

# pnpm
pnpm add class-variance-authority
```

#### 2. 核心函数 `cva()`

`cva` 函数是库的唯一入口，用于创建样式变体配置。

**基本结构:**

```typescript
import { cva } from "class-variance-authority";

const componentVariants = cva(
  // 1. 基础样式 (Base Class) - 可选
  "base-class-1 base-class-2",

  // 2. 配置对象 (Config Object) - 必需
  {
    // 2a. 变体 (Variants)
    variants: {
      // 变体组: "variantName"
      intent: {
        // 变体选项: "optionName"
        primary: "intent-primary-classes",
        secondary: "intent-secondary-classes",
      },
      size: {
        small: "size-small-classes",
        medium: "size-medium-classes",
      },
    },

    // 2b. 复合变体 (Compound Variants) - 可选
    compoundVariants: [
      {
        intent: "primary",
        size: "medium",
        className: "compound-classes-for-primary-medium",
      },
    ],

    // 2c. 默认变体 (Default Variants) - 可选
    defaultVariants: {
      intent: "primary",
      size: "medium",
    },
  }
);
```

#### 3. TypeScript 集成 (`VariantProps`)

使用 `VariantProps` 从 `cva` 配置中自动推断类型，实现完全的类型安全。

```typescript
import { cva, type VariantProps } from "class-variance-authority";

// 假设 buttonVariants 是你的 cva 配置
const buttonVariants = cva(/* ... */);

// 从 cva 配置中提取变体属性的类型
type ButtonProps = VariantProps<typeof buttonVariants>;

// ButtonProps 类型现在是:
// {
//   intent?: "primary" | "secondary" | null | undefined;
//   size?: "small" | "medium" | null | undefined;
// }

// 在 React 组件中使用
import React from "react";

export interface IButtonProps 
  extends React.ButtonHTMLAttributes<HTMLButtonElement>,
    ButtonProps {}

export const Button: React.FC<IButtonProps> = ({
  className,
  intent,
  size,
  ...props
}) => (
  <button 
    className={buttonVariants({ intent, size, className })} 
    {...props} 
  />
);
```

#### 4. 如何调用变体函数

调用你创建的 `cva` 实例会返回一个包含所有适用样式的字符串。

```jsx
// 假设 buttonVariants 是你的 cva 配置

// 应用 primary intent 和 medium size (或者默认值)
<Button /> 
// => class="... base ... intent-primary ... size-medium ... compound ..."

// 指定变体
<Button intent="secondary" size="small" />
// => class="... base ... intent-secondary ... size-small ..."

// 传入额外的 className
<Button intent="primary" className="m-4" />
// => class="... base ... intent-primary ... size-medium ... compound ... m-4"
```

#### 5. 高级技巧与模式

**a. 移除变体样式**

向变体属性传递 `null` 或 `undefined` 可以阻止该变体的样式被应用。

```typescript
const variants = cva("p-4", {
  variants: {
    color: {
      blue: "bg-blue-500",
      red: "bg-red-500",
    },
  },
});

variants({ color: "blue" }); // => "p-4 bg-blue-500"
variants({ color: null });   // => "p-4"
```

**b. 响应式变体**

`cva` 本身不直接处理响应式，但你可以利用 CSS 框架（如 Tailwind）的响应式前缀来定义变体。

```typescript
const panel = cva("w-full", {
  variants: {
    padding: {
      normal: "p-4",
      loose: "p-8 md:p-12", // 使用 Tailwind 的 md: 前缀
    },
  },
});

panel({ padding: "loose" }); // => "w-full p-8 md:p-12"
```

**c. 与 `clsx` 或 `tailwind-merge` 结合**

虽然 `cva` 能合并传入的 `className`，但在复杂场景下，使用 `tailwind-merge` 可以智能地处理 Tailwind CSS 类名的冲突，防止样式被意外覆盖。

```bash
npm install clsx tailwind-merge
```

```typescript
import { cva } from "class-variance-authority";
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

// 创建一个辅助函数 cn()
function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

// 在组件中使用
const Button: React.FC<IButtonProps> = ({ className, intent, size, ...props }) => (
  <button 
    // 使用 cn 函数包裹 cva 的输出
    className={cn(buttonVariants({ intent, size }), className)} 
    {...props} 
  />
);
```*   `clsx`: 优雅地处理条件类名。
*   `tailwind-merge`: 合并并解决 Tailwind 类名冲突（例如，`px-2` 和 `px-4` 同时存在时，它会保留最后一个）。

---
