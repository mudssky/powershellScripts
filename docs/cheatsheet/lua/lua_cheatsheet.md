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

