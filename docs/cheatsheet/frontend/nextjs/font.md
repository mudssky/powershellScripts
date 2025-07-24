### Next.js 字体使用速查表 (Cheatsheet)

本速查表旨在帮助你快速在 Next.js 项目中使用 `next/font` 模块来优化并管理字体，涵盖 Google Fonts 和本地字体，以及在 CSS 和 Tailwind CSS 中的应用。


---


### **核心优势**

使用 `next/font` 可以：

* **自动优化字体**：减少文件大小，提升加载速度。
* **隐私保护**：字体文件在构建时下载并与静态资源一同托管，无需向 Google 等外部服务器发送请求。
* **防止布局偏移 (Layout Shift)**：通过自动计算后备字体的样式，实现零布局偏移的平滑加载。

---

### **1. 定义字体 (推荐在 `app/fonts.ts`)**

创建一个专门的文件来管理和导出所有字体实例，避免在多个文件中重复加载。

#### **Google Fonts**

* 从 `next/font/google` 导入字体。
* 字体名称中的空格用下划线 `_` 代替 (例如, `Roboto Mono` 变为 `Roboto_Mono`)。
* 使用 `variable` 选项来创建 CSS 变量，便于在 CSS 中使用。

```typescript
// app/fonts.ts
import { Inter, Lusitana, Roboto_Mono } from 'next/font/google';

export const inter = Inter({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-inter', // 定义 CSS 变量
});

export const lusitana = Lusitana({
  weight: ['400', '700'],
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-lusitana',
});

export const roboto_mono = Roboto_Mono({
  subsets: ['latin'],
  display: 'swap',
  variable: '--font-roboto-mono',
});
```

#### **本地字体 (Local Fonts)**

* 将字体文件（推荐 `.woff2` 格式）放置在项目目录中（例如 `public/fonts`）。
* 从 `next/font/local` 导入 `localFont` 函数。
* 通过 `src` 属性指定字体文件的路径。

```typescript
// app/fonts.ts
import localFont from 'next/font/local';

export const myCustomFont = localFont({
  src: './fonts/my-custom-font.woff2', // 路径相对于此文件
  display: 'swap',
  variable: '--font-custom',
});

// 如果字体有多种字重
export const myOtherFont = localFont({
  src: [
    {
      path: './fonts/other-font-regular.woff2',
      weight: '400',
      style: 'normal',
    },
    {
      path: './fonts/other-font-bold.woff2',
      weight: '700',
      style: 'normal',
    },
  ],
  variable: '--font-other',
});
```

---

### **2. 全局应用字体**

在根布局文件 `app/layout.tsx` 中，将所有字体的 CSS 变量应用到 `<html>` 标签上。

```tsx
// app/layout.tsx
import type { Metadata } from 'next';
import { inter, lusitana } from '@/app/ui/fonts'; // 导入字体
import './globals.css';

export const metadata: Metadata = {
  title: 'My App',
  description: 'An app with custom fonts.',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className={`${inter.variable} ${lusitana.variable}`}>
      <body>{children}</body>
    </html>
  );
}
```

---

### **3. 在样式中使用字体**

#### **标准 CSS 或 CSS Modules**

在你的全局 CSS 文件 `globals.css` 中，使用 `var()` 函数来引用之前定义的字体变量。

```css
/* app/globals.css */
body {
  font-family: var(--font-inter); /* 设置默认字体 */
  font-weight: 400;
}

h1, h2, h3 {
  font-family: var(--font-lusitana); /* 为标题设置不同字体 */
  font-weight: 700;
}

.mono-text {
  font-family: var(--font-roboto-mono); /* 特定类使用另一种字体 */
}

.custom-font-text {
  font-family: var(--font-custom); /* 使用本地字体 */
}
```

#### **Tailwind CSS (v3)**

1.  **配置 `tailwind.config.js`**

    在 `theme.extend.fontFamily` 中扩展字体，将 CSS 变量作为值。

    ```javascript
    /** @type {import('tailwindcss').Config} */
    module.exports = {
      content: [
        './pages/**/*.{js,ts,jsx,tsx,mdx}',
        './components/**/*.{js,ts,jsx,tsx,mdx}',
        './app/**/*.{js,ts,jsx,tsx,mdx}',
      ],
      theme: {
        extend: {
          fontFamily: {
            // 将 sans-serif 字体设置为 Inter
            sans: ['var(--font-inter)'],
            // 添加一个新的 lusitana 字体
            serif: ['var(--font-lusitana)'],
            // 添加一个新的 mono 字体
            mono: ['var(--font-roboto-mono)'],
          },
        },
      },
      plugins: [],
    };
    ```

2.  **在组件中使用**

    现在你可以直接使用 Tailwind 的功能类来应用字体。

    ```jsx
    // 在你的组件中
    function MyComponent() {
      return (
        <div>
          <p class="font-sans">这是一个段落 (Inter).</p>
          <h1 class="font-serif">这是一个标题 (Lusitana).</h1>
          <code class="font-mono">这是一段代码 (Roboto Mono).</code>
        </div>
      );
    }
    ```

#### **Tailwind CSS (v4)**

在 Tailwind CSS v4 中，配置方式发生了变化，不再需要 `tailwind.config.js` 文件，而是直接在 CSS 文件中使用 `@theme` 规则定义字体变量。<mcreference link="https://tailwindcss.com/docs/font-family" index="4">4</mcreference>

1.  **在 CSS 中配置字体**

    在你的主 CSS 文件中，使用 `@theme` 块来定义字体。

    ```css
    /* app/globals.css */
    @import "tailwindcss";

    @theme {
      --font-sans: "Inter", sans-serif;
      --font-serif: "Lusitana", serif;
      --font-mono: "Roboto Mono", monospace;
    }
    ```

2.  **在组件中使用**

    使用方式与 v3 相同。

    ```jsx
    // 在你的组件中
    function MyComponent() {
      return (
        <div>
          <p class="font-sans">这是一个段落 (Inter).</p>
          <h1 class="font-serif">这是一个标题 (Lusitana).</h1>
          <code class="font-mono">这是一段代码 (Roboto Mono).</code>
        </div>
      );
    }
    ```

 **3.禁用 Preflight (可选)**

如果你想完全禁用 Tailwind 的基础样式 (Preflight)，以便使用自己的或现有的基础样式，你可以通过修改 CSS 的导入方式来实现。<mcreference link="https://tailwindcss.com/docs/preflight" index="1">1</mcreference>

默认情况下，`@import "tailwindcss";` 会包含 `preflight.css`。

```css
/* 默认导入 */
@import "tailwindcss";
```

要禁用它，你需要分别导入 Tailwind 的各个部分，并省略 `preflight.css`：

```css
/* 禁用 Preflight 的导入方式 */
@import "tailwindcss/theme.css" layer(theme);
@import "tailwindcss/utilities.css" layer(utilities);

/* 你可以在这里添加自己的基础样式 */
@layer base {
  h1 {
    font-size: 2em;
  }
}
```

---

### **4. 单个组件或页面应用字体 (可选)**

如果你不想全局加载某个字体，可以在需要它的组件或页面中直接应用其 `className`。

```tsx
// app/some-page/page.tsx
import { roboto_mono } from '@/app/ui/fonts';

export default function Page() {
  return (
    <main>
      <h1>常规字体</h1>
      <p className={roboto_mono.className}>
        这部分文字将使用 Roboto Mono 字体。
      </p>
    </main>
  );
}
```



