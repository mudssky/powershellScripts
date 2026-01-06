### 1. ⚡️ 万能组件测试模板 (Copy-Paste)

这是最通用的模板，包含了 `next/navigation` 的 Mock，适用于绝大多数 Client Components。

```tsx
// src/components/YourComponent.test.tsx
import { render, screen, fireEvent } from '@testing-library/react'
import { describe, it, expect, vi } from 'vitest'
import YourComponent from './YourComponent'

// 🛡️ 防报错 Mock：解决 useRouter/useSearchParams 导致的报错
vi.mock('next/navigation', () => ({
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), back: vi.fn() }),
  useSearchParams: () => ({ get: vi.fn(() => 'mock_value') }),
  usePathname: () => '/mock-path',
}))

describe('YourComponent', () => {
  // 🟢 策略 1：冒烟测试 (最省事，只测不崩)
  it('should render without crashing', () => {
    const { container } = render(<YourComponent />)
    expect(container).toBeTruthy()
  })

  // 🟡 策略 2：快照测试 (测结构变动)
  it('matches snapshot', () => {
    const { container } = render(<YourComponent />)
    expect(container).toMatchSnapshot()
  })

  // 🔴 策略 3：交互测试 (测点击/输入)
  it('handles user interaction', () => {
    render(<YourComponent />)
    const btn = screen.getByRole('button', { name: /submit/i })
    fireEvent.click(btn)
    expect(btn).toBeDisabled() // 示例断言
  })
})
```

---

### 2. 🛠 常用 Mock 代码段

Next.js 特有的组件和 API 在 JSDOM 中通常无法运行，需要 Mock。

#### Mock `next/image`

`next/image` 经常因为懒加载属性在测试环境中报错，建议替换为普通 `img`。

```tsx
vi.mock('next/image', () => ({
  __esModule: true,
  default: (props: any) => {
    // eslint-disable-next-line @next/next/no-img-element
    return <img {...props} alt={props.alt} />
  },
}))
```

#### Mock `next/link`

虽然通常能跑，但如果涉及复杂路由预加载逻辑，可以简化它。

```tsx
vi.mock('next/link', () => ({
  __esModule: true,
  default: ({ href, children }: any) => <a href={href}>{children}</a>,
}))
```

#### Mock 第三方库 (如 Zustand, React-Query)

如果组件用了复杂的 Store，不要在测试里初始化 Store，直接 Mock hook 的返回值。

```tsx
// 假设组件用了 useUserStore
import * as storeHooks from '@/stores/userStore'

it('renders user name', () => {
  // 劫持 hook 返回值
  vi.spyOn(storeHooks, 'useUserStore').mockReturnValue({
    user: { name: 'Batman' },
    isLoading: false
  })

  render(<UserProfile />)
  expect(screen.getByText('Batman')).toBeInTheDocument()
})
```

---

### 3. ⚙️ Server Actions / Logic 测试

不要 `render` Server Action，直接当做 `async function` 测。

```tsx
// src/actions/login.test.ts
import { describe, it, expect, vi, afterEach } from 'vitest'
import { loginAction } from './login'
import { db } from '@/lib/db'

// Mock 数据库/API 调用
vi.mock('@/lib/db', () => ({
  db: { user: { findUnique: vi.fn() } }
}))

describe('loginAction', () => {
  afterEach(() => { vi.clearAllMocks() })

  it('returns error on invalid credentials', async () => {
    // 模拟数据库返回 null
    (db.user.findUnique as any).mockResolvedValue(null)

    const formData = new FormData()
    formData.append('email', 'wrong@test.com')

    const result = await loginAction(formData)
    expect(result).toEqual({ error: 'User not found' })
  })
})
```

---

### 4. 📝 常用 API 速查

#### 查询元素 (Queries)

| API | 描述 | 场景 |
| :--- | :--- | :--- |
| `screen.getByText(/Hello/i)` | 按文本内容找 | 按钮、标题、段落 |
| `screen.getByRole('button', {name: /Save/})` | 按角色找 (推荐) | 按钮、链接、输入框 |
| `screen.getByTestId('custom-id')` | 按 `data-testid` 找 | 实在找不到时用这个兜底 |
| `screen.queryByText(...)` | 查找元素 | **断言元素不存在**时用 (返回 null) |

#### 断言 (Matchers)

| API | 描述 |
| :--- | :--- |
| `expect(el).toBeInTheDocument()` | 元素存在于 DOM |
| `expect(el).toHaveTextContent('text')` | 包含特定文本 |
| `expect(el).toHaveClass('bg-red-500')` | 检查 CSS 类名 (Tailwind) |
| `expect(btn).toBeDisabled()` | 检查按钮是否禁用 |
| `expect(fn).toHaveBeenCalledWith(arg)` | 检查函数(Mock)是否被调用 |

#### 用户操作 (User Event)

推荐使用 `fireEvent` (简单) 或 `userEvent` (更真实)。

```tsx
import { fireEvent } from '@testing-library/react'
// import userEvent from '@testing-library/user-event' // 也可以用这个

// 点击
fireEvent.click(screen.getByRole('button'))

// 输入
fireEvent.change(screen.getByPlaceholderText('Email'), {
  target: { value: 'test@test.com' }
})
```

---

### 5. ⚠️ 避坑指南

1. **Async Server Components (Page.tsx)**:
    * **不要测！** Vitest 渲染 `async` 组件非常麻烦。
    * **策略**：把 Page 里的内容拆分成 `<ClientView data={data} />`，然后去测 `<ClientView />`。
2. **`window is not defined`**:
    * 确保 `vitest.config.ts` 里设置了 `environment: 'jsdom'`。
3. **Alias (`@/components`) 报错**:
    * 确保 `vitest.config.ts` 里加了 `plugins: [tsconfigPaths()]`。

### 6. 配置备忘 (Setup)

**package.json**

```json
"scripts": {
  "test": "vitest",
  "test:run": "vitest run", 
  "test:ui": "vitest --ui"
}
```

**vitest.config.ts**

```ts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: './vitest.setup.ts',
  },
})
```

**vitest.setup.ts**

```ts
import '@testing-library/jest-dom'
import { cleanup } from '@testing-library/react'
import { afterEach } from 'vitest'

afterEach(() => { cleanup() })
```

| 测试层级 | 测试对象 | 策略 | 工具 | 推荐指数 |
| :--- | :--- | :--- | :--- | :--- |
| **纯逻辑/工具函数** | `utils/*.ts`, `hooks/*.ts` | **详细测试**。逻辑不容易变，且容易测，收益最高。 | Vitest | ⭐⭐⭐⭐⭐ |
| **通用 UI 组件** | Button, Card, Navbar (Client) | **快照测试**。`expect(container).toMatchSnapshot()`。保证基础积木不崩。 | Vitest | ⭐⭐⭐⭐ |
| **业务复杂组件** | 包含表单、复杂交互的组件 | **冒烟测试**。`render(<Comp />)` 保证能打开即可。 | Vitest | ⭐⭐⭐ |
| **页面 (Pages)** | `app/**/page.tsx` | **放弃 Vitest，改用简单的 E2E**。只写一个脚本：打开首页 -> 检查标题。 | Playwright | ⭐⭐⭐⭐⭐ |
