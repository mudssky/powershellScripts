### **前端字体知识速查表 (通用版)**

本速查表旨在帮助你掌握在任何 web 项目中处理字体的核心技术和最佳实践。

---

### **1. 基础概念：字体类型**

* **系统字体 (System Fonts)**: 用户操作系统中预装的字体（如 Arial, Helvetica, 微软雅黑, 苹方）。
  * **优点**: 无需下载，加载速度最快，零性能开销。
  * **缺点**: 无法保证在所有操作系统上显示一致，设计选择有限。
  * **CSS 示例**: `font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;`

* **网页字体 (Web Fonts)**: 存放在远程服务器或项目本地的字体文件，通过 CSS 的 `@font-face` 规则加载。
  * **优点**: 保证所有用户看到完全一致的品牌字体，设计选择无限。
  * **缺点**: 需要下载，会产生性能开销，需要进行优化。

---

### **2. 加载网页字体：`@font-face` 规则**

这是在 CSS 中声明并加载自定义字体的核心机制。

```css
@font-face {
  /* 1. 定义你的字体族名称，在 CSS 中通过这个名字使用它 */
  font-family: 'MyCustomFont';

  /* 2. 指定字体文件路径和格式 (最佳实践：WOFF2 优先) */
  src: 
    /* 现代浏览器首选，压缩率最高 */
    url('/fonts/my-font.woff2') format('woff2'),
    /* 兼容旧版浏览器的后备选项 */
    url('/fonts/my-font.woff') format('woff');

  /* 3. 关联字重和样式，以便 font-weight/font-style 能正确工作 */
  font-weight: 400; /* 或 normal */
  font-style: normal;

  /* 4. 定义加载策略，swap 是最佳实践 */
  font-display: swap;
}

/* 为粗体定义另一个 @font-face 规则 */
@font-face {
  font-family: 'MyCustomFont';
  src: 
    url('/fonts/my-font-bold.woff2') format('woff2'),
    url('/fonts/my-font-bold.woff') format('woff');
  font-weight: 700; /* 或 bold */
  font-style: normal;
  font-display: swap;
}

```



---

### **3. 字体格式对比**

| 格式 | 全称 | 推荐度 | 描述 |
| :--- | :--- | :--- | :--- |
| **WOFF2** | Web Open Font Format 2 | ⭐⭐⭐⭐⭐ **(首选)** | 专为 Web 设计，使用 Brotli 压缩，**文件体积最小**，加载最快。所有现代浏览器都支持。 |
| **WOFF** | Web Open Font Format | ⭐⭐⭐⭐ **(后备)** | 专为 Web 设计，压缩率良好，**兼容性极佳**，可作为兼容旧版浏览器的后备。 |
| **TTF / OTF** | TrueType / OpenType Font | ⭐⭐ (仅作源文件) | 桌面字体格式，**文件体积大**，不适合直接在生产环境的 Web 上使用。应作为生成 WOFF/WOFF2 的源文件。 |
| **EOT** | Embedded OpenType | (废弃) | 仅用于兼容古董级的 IE 浏览器 (IE8 及以下)。现代项目完全无需考虑。 |

---

### **4. 性能优化与加载策略 `font-display`**

`font-display` 决定了字体加载期间文本的显示方式，直接影响用户体验和核心网页指标。

| 值 | 行为描述 | 用户体验 | 建议 |
| :--- | :--- | :--- | :--- |
| `swap` | **立即使用后备字体，加载完后交换。** | **FOUT** (无样式文本闪烁)，但内容立即可见。 | ⭐⭐⭐⭐⭐ **(最佳实践)** |
| `block` | 短暂**隐藏文本** (~3s)，等待字体加载。 | **FOIT** (不可见文本闪烁)，体验差。 | ⭐ (不推荐) |
| `fallback`| 极短暂隐藏 (~100ms)，然后用后备字体，若超时则不再交换。| 在慢速网络下避免后期布局跳动。| ⭐⭐⭐ (特定场景可用) |
| `optional`| 极短暂隐藏 (~100ms)，若不能瞬时从缓存加载，则直接放弃。| 对性能影响最小，但用户可能看不到自定义字体。| ⭐⭐ (字体不重要时) |

---

### **5. 核心 CSS 字体属性**



*   `font-family`: 指定字体族。**务必提供一个后备字体栈**。

```css
    body {
      /* 浏览器会依次尝试，直到找到一个可用的字体 */
      font-family: 'MyCustomFont', 'Helvetica Neue', Arial, sans-serif;
    }
```

*   `font-weight`: 设置字重。值可以是 `normal`(400), `bold`(700)，或 100 到 900 的数字。它会匹配 `@font-face` 中定义的 `font-weight`。

*   `font-style`: 设置字体样式，主要是 `normal` (正常) 或 `italic` (斜体)。

*   `font-size`: 设置字体大小。推荐使用相对单位，如 `rem` 或 `em`，以获得更好的可访问性。

*   `line-height`: 设置行高。**最佳实践是使用一个无单位的数字**（如 `1.5`），它会根据 `font-size` 自动计算，避免继承问题。

*   `font` (简写属性): 可以一次性设置多个属性，但顺序很严格，且容易重置未指定的属性，需谨慎使用。
    ```css
    /* 顺序：font-style font-weight font-size/line-height font-family */
    p {
      font: italic 700 16px/1.5 'MyCustomFont', sans-serif;
    }
    ```

---

### **6. 进阶字体特性**

#### **可变字体 (Variable Fonts)**

一个字体文件包含了多个样式（如不同字重、字宽、斜度）。

*   **优点**: 大大减少 HTTP 请求次数和总体积，设计灵活性极高。
*   **CSS 使用**:
    ```css
    @font-face {
      font-family: 'MyVariableFont';
      src: url('my-variable-font.woff2') format('woff2-variations');
      font-weight: 100 900; /* 声明支持的字重范围 */
    }
    
    .heavy {
      /* 可以使用 100-900 之间的任意值，不再局限于 400/700 */
      font-weight: 850; 
    }
    ```

#### **OpenType 特性**

通过 `font-feature-settings` 或更现代的 `font-variant-*` 属性，可以开启字体中内置的高级排版功能。

*   **常见特性**:
    *   **连字 (Ligatures)**: 将特定字符组合（如 `fi`, `fl`）替换为单个优美的字形。`font-variant-ligatures: common-ligatures;` (默认开启)
    *   **字偶距微调 (Kerning)**: 调整特定字符对之间的间距（如 `AV`）。`font-kerning: normal;` (默认开启)
    *   **数字样式**: 等宽数字、比例数字、旧式数字等。`font-variant-numeric: tabular-nums;` (用于表格对齐)

```css
.price-table {
  /* 让表格中的所有数字等宽，确保小数点能完美对齐 */
  font-variant-numeric: tabular-nums;
}
```
