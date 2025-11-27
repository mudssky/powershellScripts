这是一份关于 Lua 模块化（Module）组织与编写的速查表（Cheatsheet）。Lua 的模块机制非常灵活，本质上是“利用 Table 和 Closure（闭包）来管理作用域”。

---

# Lua 模块化组织 Cheatsheet

## 1. 标准模板 (The Golden Standard)

这是目前 Lua (5.1+) 最推荐的模块写法。**不要使用** 已废弃的 `module()` 函数。

```lua
-- 文件名: mymodule.lua
local M = {} -- 1. 定义模块表

-- 2. 定义私有变量/函数 (Local)
local default_scale = 1.5
local function helper()
    return "I am hidden"
end

-- 3. 定义公开变量/函数 (绑定到 M)
M.version = "1.0"

function M.say_hello(name)
    -- 可以访问私有变量
    return "Hello " .. name .. ", scale: " .. default_scale
end

function M.get_helper()
    return helper()
end

-- 4. 返回模块表
return M
```

---

## 2. 调用模块

```lua
-- main.lua
local mymod = require("mymodule") -- 这里的字符串对应文件名(不带.lua)

print(mymod.version)       -- 输出: 1.0
print(mymod.say_hello("Lua")) 
-- print(mymod.helper())   -- 报错/nil，因为 helper 是 local 的
```

---

## 3. 文件目录与路径管理

Lua 使用点号 `.` 来分隔目录，使用 `package.path` 来查找文件。

### 目录结构示例

```text
project/
├── main.lua
├── config.lua
└── utils/
    ├── init.lua    <-- 特殊文件
    ├── math.lua
    └── string.lua
```

### 引用方式

```lua
local conf = require("config")        -- 加载 config.lua
local umath = require("utils.math")   -- 加载 utils/math.lua
local utils = require("utils")        -- 加载 utils/init.lua (类似 index.js)
```

### 什么是 `init.lua`?

当 `require("folder_name")` 时，Lua 会尝试查找 `folder_name/init.lua`。这允许你将一个文件夹作为一个整体模块导出。

**utils/init.lua 示例:**

```lua
local M = {}
M.math = require("utils.math")
M.string = require("utils.string")
return M
```

---

## 4. 面向对象风格 (Class Module)

如果你需要模块作为一个“类”来生成实例：

```lua
-- person.lua
local Person = {}
Person.__index = Person -- 元表索引指向自己

-- 构造函数
function Person.new(name, age)
    local self = setmetatable({}, Person)
    self.name = name
    self.age = age
    return self
end

-- 成员方法 (使用 : 语法)
function Person:speak()
    print("My name is " .. self.name)
end

return Person
```

**使用:**

```lua
local Person = require("person")
local p1 = Person.new("Alice", 30)
p1:speak()
```

---

## 5. 高级技巧与坑点

### 避免全局污染 (Global Pollution)

**错误写法:**

```lua
-- mymodule.lua
function GlobalFunc() end -- 糟糕！这会污染全局环境 _G
```

**正确写法:**
始终在变量和函数前加 `local`，或者显式赋值给模块表 `M`。

### 循环依赖 (Circular Dependencies)

如果 A require B，且 B require A，会导致栈溢出或返回 nil。

* **解决:** 将公共部分提取到模块 C，或者在一个模块内部通过 `local` 延迟加载。

### 重新加载模块 (Hot Reloading)

Lua 默认会缓存模块在 `package.loaded` 中，再次 `require` 不会重新执行文件。
如果开发中需要热重载：

```lua
function reload_module(module_name)
    package.loaded[module_name] = nil
    return require(module_name)
end
```

### 添加自定义搜索路径

如果你的模块不在标准路径下：

```lua
-- 在 require 之前添加
package.path = package.path .. ";./libs/?.lua;./src/?.lua"
```

---

## 6. 几种常见的写法变体

### 变体 A: 尾部返回 (最常用)

```lua
local M = {}
function M.foo() end
return M
```

### 变体 B: 局部函数导出 (性能稍好)

这种写法在文件内部调用 `foo` 时稍微快一点（因为是 local 调用），最后统一导出。

```lua
local function foo() end
local function bar() end

return {
    foo = foo,
    bar = bar
}
```

### 变体 C: 直接返回函数 (单一职责)

如果模块只做一件事：

```lua
-- logger.lua
return function(msg)
    print("[LOG]: " .. msg)
end

-- 使用
local log = require("logger")
log("Something happened")
```

---

## 7. 模块查找顺序

当执行 `require("mod")` 时，Lua 按以下逻辑查找：

1. 检查 `package.loaded["mod"]` 是否已有缓存。
2. 检查 `package.preload["mod"]` 是否有预加载器。
3. 搜索 `package.path` (Lua 文件)。
    * `mod.lua`
    * `mod/init.lua`
4. 搜索 `package.cpath` (C 库 .so/.dll)。

---

## 总结最佳实践

1. **文件即模块**：一个文件对应一个模块。
2. **Local First**：所有变量默认 `local`，只有需要导出的才放入返回表。
3. **返回 Table**：文件末尾始终 `return M`。
4. **无副作用**：`require` 一个模块不应产生打印日志或修改全局变量等副作用，只应返回定义。
