# Lua 语法速查表 (Cheatsheet)

## 1. 变量与基本数据类型

- 推荐：使用局部变量，避免污染全局作用域

```lua
local a = 10
local b = true
local s = "hello"
local t = { 1, 2, 3 }
local f = function(x) return x * 2 end
local n = nil
```

- 基本类型：`nil`、`boolean`、`number`、`string`、`table`、`function`

## 2. 控制结构

- if-then-elseif-else

```lua
local x = 5
if x > 10 then
    print("big")
elseif x > 5 then
    print("medium")
else
    print("small")
end
```

- while 循环

```lua
local i = 0
while i < 3 do
    print(i)
    i = i + 1
end
```

- repeat-until 循环

```lua
local i = 0
repeat
    i = i + 1
until i == 3
```

- for 数值型循环

```lua
for i = 1, 5 do
    print(i)
end

for i = 10, 1, -2 do
    print(i)
end
```

- for 泛型循环（遍历表）

```lua
local arr = { "a", "b", "c" }
for i, v in ipairs(arr) do
    print(i, v)
end

local dict = { name = "lua", version = 5.4 }
for k, v in pairs(dict) do
    print(k, v)
end
```

## 3. 表（table）操作

- 创建与初始化（数组与字典）

```lua
local arr = { 10, 20, 30 }
local dict = { a = 1, b = 2 }
```

- 插入与删除（数组）

```lua
local arr = { 10 }
table.insert(arr, 20)
table.insert(arr, 1, 5)
local last = table.remove(arr)
local first = table.remove(arr, 1)
```

- 遍历

```lua
local arr = { 10, 20, 30 }
for i, v in ipairs(arr) do
    print(i, v)
end

local dict = { a = 1, b = 2 }
for k, v in pairs(dict) do
    print(k, v)
end
```

- 删除字典键

```lua
local dict = { a = 1, b = 2 }
dict.a = nil
```

- 数组与字典用法区分
  - 数组：顺序索引从 `1` 开始，使用 `ipairs`、`table.insert`、`table.remove`
  - 字典：键值对结构，使用 `pairs`，删除通过设为 `nil`

## 4. 函数定义与调用

- 基本定义与调用

```lua
local function add(x, y)
    return x + y
end

local r = add(2, 3)
```

- 多返回值

```lua
local function divmod(a, b)
    return math.floor(a / b), a % b
end

local q, m = divmod(10, 3)
```

- 可变参数（...）

```lua
local function sum(...)
    local total = 0
    for i = 1, select("#", ...) do
        total = total + select(i, ...)
    end
    return total
end

local s = sum(1, 2, 3)
```

## 5. 常用标准库函数

- 字符串处理（string）

```lua
local s = "hello lua"
local len = #s
local sub = string.sub(s, 1, 5)
local found = string.find(s, "lua")
local replaced = string.gsub(s, "lua", "world")
local formatted = string.format("%s-%d", "id", 100)
```

- 表操作（table）

```lua
local arr = { "a", "b", "c" }
local joined = table.concat(arr, ",")
table.sort(arr)
```

- 基础 I/O（io）

```lua
for line in io.lines("input.txt") do
    print(line)
end

local f = assert(io.open("out.txt", "w"))
f:write("ok\n")
f:close()
```

## 6. 注释与基本运算符

```lua
-- 单行注释
--[[
多行注释
]]

-- 算术: + - * / ^ %
local a, b = 3, 2
print(a + b, a ^ b, a % b)

-- 比较: < <= > >= == ~= (不等号是 ~=)
print(a ~= b, a >= b)

-- 拼接: .. ；长度: #
local s = "lu" .. "a"   -- "lua"
print(#s)                 -- 3
```

## 7. 布尔与空值规则（推荐）

```lua
-- 只有 false 和 nil 为假；0 为真
print(0 and true)  -- true

-- 默认值惯用法：or
local input
local v = input or "default" -- input 为 nil/false 时使用默认值

-- 保护性判断
if v then print("有值") end
```

## 8. 字符串常用操作（最小集合）

```lua
local s = "hello lua"
local sub = string.sub(s, 1, 5)     -- "hello"
local pos = string.find(s, "lua")   -- 返回起止位置或 nil
local replaced = string.gsub(s, "lua", "world")
local fmt = string.format("%s-%02d", "id", 7) -- "id-07"
-- 注：字符串不可变；使用 .. 或 string 库生成新字符串
```

## 9. 函数与方法（: 语法与 self）

```lua
-- 方法定义与调用（推荐）：: 会自动传入 self
local T = {}
function T:new(name)
  local o = { name = name }
  setmetatable(o, { __index = self })
  return o
end
function T:say()
  print(self.name)
end

local t = T:new("Lua")
t:say()  -- 等价于 T.say(t)

-- 闭包：捕获外部局部变量
local function counter()
  local c = 0
  return function() c = c + 1; return c end
end
local next = counter()
print(next(), next()) -- 1, 2
```

## 10. 作用域与块（局部优先）

```lua
-- 始终优先使用 local，避免污染全局
local x = 1

-- 块作用域：do ... end
do
  local x = 2
  print(x) -- 2（外层 x 不受影响）
end
print(x)   -- 1
```

## 11. 表的常用模式（数组/字典与实用操作）

```lua
-- 数组（索引从 1 开始）与字典
local arr = { "a", "b", "c" }
local dict = { a = 1, b = 2 }

-- 遍历（推荐：数组用 ipairs，字典用 pairs）
for i, v in ipairs(arr) do print(i, v) end
for k, v in pairs(dict)  do print(k, v) end

-- 删除字典键：设为 nil
dict.a = nil

-- 浅拷贝（常用）：
local function clone(t)
  local r = {}
  for k, v in pairs(t) do r[k] = v end
  return r
end
local dict2 = clone(dict)
```

## 12. 实用模式与最佳实践

```lua
-- 保护性断言（加载文件/资源）
local f = assert(io.open("out.txt", "w"))
f:write("ok\n")
f:close()

-- 最小副作用：模块的 require 不应打印或改全局（详见 module.md）
-- 仅在需要时 require，默认会缓存（再次 require 不会重复执行）
```

## 13. 交叉引用

- 模块组织与 OOP 细节：参见 `module.md`（标准模板、Class 风格、查找顺序等）。
