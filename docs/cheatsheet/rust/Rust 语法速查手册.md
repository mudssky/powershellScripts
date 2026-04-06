---

# 🦀 Rust 语法速查手册 (Cheatsheet)

---

## 1. 变量与基本类型

```rust
// ==================== 变量绑定 ====================
let x = 5;              // 不可变（默认）
let mut y = 10;          // 可变
y = 20;                  // ✅ mut 才能重新赋值
let x = "hello";         // ✅ Shadowing（遮蔽），同名变量可以重新绑定，甚至换类型

const MAX_SIZE: u32 = 100;       // 常量（编译时确定，必须标注类型，SCREAMING_SNAKE_CASE）
static GLOBAL: &str = "hello";   // 静态变量（全局生命周期 'static）

// ==================== 标量类型 ====================
let a: i8  = -128;       // 有符号整数：i8, i16, i32(默认), i64, i128, isize
let b: u8  = 255;        // 无符号整数：u8, u16, u32, u64, u128, usize
let c: f64 = 3.14;       // 浮点数：f32, f64(默认)
let d: bool = true;      // 布尔
let e: char = '🦀';      // 字符（4字节 Unicode）

// 数字字面量技巧
let hex   = 0xff;        // 十六进制
let octal = 0o77;        // 八进制
let bin   = 0b1010;      // 二进制
let byte  = b'A';        // 字节（u8）
let big   = 1_000_000;   // 下划线分隔，提高可读性
let typed = 42u64;       // 字面量后缀标注类型

// ==================== 复合类型 ====================
// 元组 (Tuple) - 固定长度，可以存不同类型
let tup: (i32, f64, char) = (42, 6.28, 'x');
let (a, b, c) = tup;     // 解构
let first = tup.0;       // 索引访问

// 数组 (Array) - 固定长度，同一类型，栈上分配
let arr: [i32; 3] = [1, 2, 3];
let zeros = [0; 5];      // [0, 0, 0, 0, 0]
let first = arr[0];      // 索引访问（越界会 panic）

// 切片 (Slice) - 对数组/Vec 的引用视图
let slice: &[i32] = &arr[1..3];   // [2, 3]
let slice2 = &arr[..2];           // [1, 2]
let slice3 = &arr[1..];           // [2, 3]

// ==================== 字符串 ====================
let s1: &str = "hello";               // 字符串切片（不可变引用，存在栈/只读区）
let s2: String = String::from("hi");   // 堆上的字符串（可增长、可修改）
let s3 = "hello".to_string();         // &str → String
let s4: &str = &s2;                   // String → &str（自动解引用）

let combined = format!("{} {}", s1, s2);  // 拼接字符串（不消耗所有权）
let mut s = String::from("hello");
s.push(' ');                   // 追加字符
s.push_str("world");          // 追加字符串
```

---

## 2. 函数与闭包

```rust
// ==================== 函数 ====================
fn add(a: i32, b: i32) -> i32 {   // 参数必须标注类型，-> 返回类型
    a + b                          // 最后一个表达式就是返回值（不加分号！）
}

fn print_hello() {                 // 无返回值（返回 ()，即 unit 类型）
    println!("Hello!");
}

fn early_return(x: i32) -> &'static str {
    if x > 0 { return "positive"; }   // 提前返回用 return
    "non-positive"
}

// 参数模式
fn first((x, _): (i32, i32)) -> i32 { x }   // 解构参数

// ==================== 闭包 (Closure) ====================
let add      = |a, b| a + b;              // 自动推断类型
let add_typed = |a: i32, b: i32| -> i32 { a + b };  // 显式标注
let greet    = || println!("hi");          // 无参数

// 闭包捕获环境变量
let name = String::from("Rust");
let greet  = || println!("{}", name);      // 借用捕获（&name）
let greet2 = move || println!("{}", name); // 移动捕获（name 的所有权转移到闭包）
// 此后 name 不可用了

// 闭包作为参数（三种 trait）
fn apply_fn(f: impl Fn(i32) -> i32, x: i32) -> i32 { f(x) }       // 不可变借用捕获
fn apply_fnmut(mut f: impl FnMut(i32), x: i32) { f(x) }           // 可变借用捕获
fn apply_fnonce(f: impl FnOnce() -> String) -> String { f() }      // 消耗捕获

// 闭包作为返回值
fn make_adder(x: i32) -> impl Fn(i32) -> i32 {
    move |y| x + y
}
```

---

## 3. 控制流

```rust
// ==================== if / else ====================
if x > 0 {
    println!("positive");
} else if x == 0 {
    println!("zero");
} else {
    println!("negative");
}

let val = if condition { "yes" } else { "no" };   // if 是表达式！可以赋值

// ==================== loop / while / for ====================
// loop - 无限循环
let result = loop {
    counter += 1;
    if counter == 10 {
        break counter * 2;    // break 可以返回值！
    }
};

// 嵌套循环标签
'outer: loop {
    'inner: loop {
        break 'outer;         // 跳出外层循环
    }
};

// while
while x < 100 {
    x += 1;
}

// while let（条件模式匹配循环）
while let Some(val) = stack.pop() {
    println!("{}", val);
}

// for - 最常用的循环
for i in 0..5 { }           // 0, 1, 2, 3, 4（左闭右开）
for i in 0..=5 { }          // 0, 1, 2, 3, 4, 5（两端闭合）
for item in &vec { }        // 不可变借用遍历
for item in &mut vec { }    // 可变借用遍历
for item in vec { }         // 消耗所有权遍历（之后 vec 不可用）
for (i, val) in vec.iter().enumerate() { }  // 带索引

// ==================== match（模式匹配，Rust 最强武器）====================
match value {
    1 => println!("one"),                 // 单值
    2 | 3 => println!("two or three"),    // 多值
    4..=9 => println!("four to nine"),    // 范围
    n if n < 0 => println!("negative"),   // 守卫条件
    n @ 10..=20 => println!("teen: {n}"), // 绑定变量
    _ => println!("other"),               // 通配符（必须穷举所有情况）
}

let result = match some_option {          // match 也是表达式
    Some(x) => x * 2,
    None => 0,
};

// ==================== if let / let else ====================
// if let - 只关心一种模式
if let Some(value) = some_option {
    println!("{value}");
}

// let else - 匹配失败时必须发散（return / break / panic）
let Some(value) = some_option else {
    return;   // 或 panic!("...")
};
// 此后 value 可直接使用
```

---

## 4. 所有权 & 借用 & 生命周期

```rust
// ==================== 所有权三原则 ====================
// 1. 每个值有且只有一个 owner
// 2. owner 离开作用域，值被 drop（释放）
// 3. 赋值 / 传参默认是 move（转移所有权）

let s1 = String::from("hello");
let s2 = s1;              // s1 被 move → s1 不再可用
let s3 = s2.clone();      // 深拷贝 → s2 仍可用

// 注意：实现了 Copy trait 的类型（i32, f64, bool, char, 元组(全Copy成员)）是复制语义
let a = 42;
let b = a;                // Copy → a 仍然可用 ✅

// ==================== 借用 ====================
fn len(s: &String) -> usize { s.len() }    // 不可变借用
fn push(s: &mut String) { s.push('!'); }   // 可变借用

let mut s = String::from("hello");
let r1 = &s;        // ✅ 可以有多个不可变借用
let r2 = &s;        // ✅
// let r3 = &mut s;  // ❌ 不可变借用存在时，不能同时可变借用
println!("{r1} {r2}");
// r1, r2 最后一次使用之后（NLL），就可以可变借用了
let r3 = &mut s;    // ✅ 现在可以了

// ==================== 生命周期（新手保命版）====================
// 核心理念：引用不能比它指向的数据活得更久

// 规则1：大多数情况编译器自动推断（生命周期省略规则），不需要你写
fn first_word(s: &str) -> &str { &s[..1] }  // 编译器自动处理

// 规则2：多个引用参数 + 引用返回值时，可能需要手动标注
fn longest<'a>(x: &'a str, y: &'a str) -> &'a str {
    if x.len() > y.len() { x } else { y }
}
// 含义：返回的引用，生命周期 ≤ x 和 y 中较短的那个

// 🛡️ 新手黄金法则：结构体中不要用引用，用 String / Vec<T> 代替！
```

---

## 5. 结构体 & 枚举 & 方法

```rust
// ==================== 结构体 (Struct) ====================
struct User {
    name: String,
    age: u32,
    active: bool,
}

// 实例化
let user = User {
    name: String::from("Alice"),
    age: 30,
    active: true,
};

// 字段简写（变量名与字段名相同时）
let name = String::from("Bob");
let user2 = User { name, age: 25, active: true };

// 结构体更新语法（从已有实例创建，类似JS展开运算符）
let user3 = User { age: 28, ..user2 };  // 注意：user2 中的 String 字段被 move 了

// 元组结构体
struct Point(f64, f64, f64);
let p = Point(1.0, 2.0, 3.0);
let x = p.0;

// 单元结构体（无字段，常用于标记）
struct Marker;

// ==================== 枚举 (Enum)  ====================
enum Direction {
    Up,
    Down,
    Left,
    Right,
}

// 枚举可以携带数据（这是 Rust 枚举的超能力 🦸）
enum Message {
    Quit,                       // 无数据
    Echo(String),               // 一个 String
    Move { x: i32, y: i32 },    // 匿名结构体
    Color(u8, u8, u8),          // 元组
}

// 最重要的两个内置枚举
enum Option<T> {
    Some(T),      // 有值
    None,         // 无值（代替 null）
}

enum Result<T, E> {
    Ok(T),        // 成功
    Err(E),       // 失败
}

// ==================== impl 方法块 ====================
struct Rect { width: f64, height: f64 }

impl Rect {
    // 关联函数（类似静态方法），不接收 self
    fn new(w: f64, h: f64) -> Self {        // Self = Rect
        Rect { width: w, height: h }
    }

    // 方法（不可变借用 self）
    fn area(&self) -> f64 {
        self.width * self.height
    }

    // 方法（可变借用 self）
    fn scale(&mut self, factor: f64) {
        self.width *= factor;
        self.height *= factor;
    }

    // 方法（消耗 self）
    fn into_square(self) -> Rect {
        let side = self.width.max(self.height);
        Rect { width: side, height: side }
    }
}

// 调用
let r = Rect::new(10.0, 20.0);    // 关联函数用 ::
let a = r.area();                  // 方法用 .
```

---

## 6. 常用集合

```rust
// ==================== Vec<T>（动态数组）====================
let mut v: Vec<i32> = Vec::new();
let v2 = vec![1, 2, 3];          // 宏快速创建

v.push(1);                        // 尾部追加
v.pop();                          // 尾部弹出 → Option<T>
v.len();                          // 长度
v.is_empty();                     // 是否为空
v[0];                             // 索引（越界 panic）
v.get(0);                         // 安全索引 → Option<&T>
v.contains(&1);                   // 是否包含
v.iter();                         // 不可变迭代器
v.iter_mut();                     // 可变迭代器
v.into_iter();                    // 消耗性迭代器

// ==================== HashMap<K, V> ====================
use std::collections::HashMap;

let mut map = HashMap::new();
map.insert("key", 42);
map.get("key");                   // → Option<&V>
map.contains_key("key");
map.remove("key");

// entry API（不存在时插入默认值）
map.entry("count").or_insert(0);
*map.entry("count").or_insert(0) += 1;  // 计数器模式

// 遍历
for (key, value) in &map {
    println!("{key}: {value}");
}

// ==================== HashSet<T> ====================
use std::collections::HashSet;
let mut set = HashSet::new();
set.insert(1);
set.contains(&1);                 // → bool
set.remove(&1);

// 集合运算
let a: HashSet<_> = [1, 2, 3].into();
let b: HashSet<_> = [2, 3, 4].into();
let union: HashSet<_> = a.union(&b).collect();
let inter: HashSet<_> = a.intersection(&b).collect();

// ==================== VecDeque<T>（双端队列）====================
use std::collections::VecDeque;
let mut dq = VecDeque::new();
dq.push_back(1);
dq.push_front(0);
dq.pop_front();
dq.pop_back();
```

---

## 7. 迭代器 & 链式调用

```rust
// Rust 的迭代器是惰性的（lazy），不调用消费方法不会执行

let nums = vec![1, 2, 3, 4, 5];

// 常用适配器（Adapter）- 返回新迭代器
nums.iter()
    .map(|x| x * 2)              // 映射
    .filter(|x| *x > 4)          // 过滤
    .enumerate()                  // 加索引 → (usize, &T)
    .skip(1)                      // 跳过前 n 个
    .take(3)                      // 只取前 n 个
    .zip(other.iter())            // 拉链配对
    .chain(other.iter())          // 串联
    .flatten()                    // 展平嵌套
    .peekable()                   // 允许 peek 下一个元素
    .rev()                        // 反转（需要双端迭代器）
    .cloned()                     // &T → T（需要 Clone）
    .copied();                    // &T → T（需要 Copy）

// 常用消费者（Consumer）- 产生最终结果
let v: Vec<_>  = nums.iter().map(|x| x * 2).collect();  // 收集成集合
let sum: i32   = nums.iter().sum();                       // 求和
let prod: i32  = nums.iter().product();                   // 求积
let count      = nums.iter().count();                     // 计数
let max        = nums.iter().max();                       // 最大值 → Option
let min        = nums.iter().min();                       // 最小值 → Option
let found      = nums.iter().find(|&&x| x == 3);         // 查找 → Option
let pos        = nums.iter().position(|&x| x == 3);      // 位置 → Option<usize>
let all        = nums.iter().all(|&x| x > 0);            // 全部满足？
let any        = nums.iter().any(|&x| x > 4);            // 任一满足？
let folded     = nums.iter().fold(0, |acc, x| acc + x);  // 折叠/归约

// for_each（副作用）
nums.iter().for_each(|x| println!("{x}"));
```

---

## 8. Trait（特征 / 接口）

```rust
// ==================== 定义 Trait ====================
trait Summary {
    fn summarize(&self) -> String;                       // 必须实现
    fn preview(&self) -> String {                        // 默认实现（可选覆盖）
        format!("{}...", &self.summarize()[..20])
    }
}

// ==================== 为类型实现 Trait ====================
struct Article { title: String, content: String }

impl Summary for Article {
    fn summarize(&self) -> String {
        format!("{}: {}", self.title, self.content)
    }
}

// ==================== Trait 作参数（3种写法）====================
fn notify1(item: &impl Summary) { }                     // 语法糖（最简洁）
fn notify2<T: Summary>(item: &T) { }                    // 泛型约束
fn notify3<T>(item: &T) where T: Summary { }            // where 子句（参数多时更清晰）

// 多 trait 约束
fn notify(item: &(impl Summary + Display)) { }
fn notify<T: Summary + Display>(item: &T) { }

// Trait 作返回值
fn make_summary() -> impl Summary { /* 返回某个实现了 Summary 的类型 */ }

// ==================== 常用 derive 宏（自动实现 Trait）====================
#[derive(Debug)]          // 允许 {:?} 格式化打印
#[derive(Clone)]          // 允许 .clone() 深拷贝
#[derive(Copy, Clone)]    // 复制语义（仅适用于栈上简单类型）
#[derive(PartialEq, Eq)]  // 允许 == 比较
#[derive(PartialOrd, Ord)]// 允许 < > 比较和排序
#[derive(Hash)]           // 允许作为 HashMap 的 key
#[derive(Default)]        // 允许 Type::default() 创建默认值
#[derive(serde::Serialize, serde::Deserialize)]  // JSON 序列化（需要 serde 依赖）

// 通常组合使用
#[derive(Debug, Clone, PartialEq)]
struct Point { x: f64, y: f64 }

// ==================== Trait Object（动态分发）====================
// 当需要在运行时处理不同类型时使用 dyn
let items: Vec<Box<dyn Summary>> = vec![
    Box::new(article),
    Box::new(tweet),
];
for item in &items {
    println!("{}", item.summarize());
}
```

---

## 9. 泛型

```rust
// ==================== 泛型函数 ====================
fn largest<T: PartialOrd>(list: &[T]) -> &T {
    let mut max = &list[0];
    for item in list {
        if item > max { max = item; }
    }
    max
}

// ==================== 泛型结构体 ====================
struct Point<T> {
    x: T,
    y: T,
}

struct Pair<T, U> {     // 多类型参数
    first: T,
    second: U,
}

impl<T> Point<T> {
    fn x(&self) -> &T { &self.x }
}

// 为特定类型实现方法
impl Point<f64> {
    fn distance(&self) -> f64 {
        (self.x.powi(2) + self.y.powi(2)).sqrt()
    }
}

// ==================== 泛型枚举 ====================
// Option<T> 和 Result<T, E> 就是泛型枚举的经典案例
enum MyResult<T, E> {
    Ok(T),
    Err(E),
}
```

---

## 10. 错误处理

```rust
// ==================== panic!（不可恢复错误）====================
panic!("crash and burn!");
unreachable!("should never reach here");
todo!("not implemented yet");        // 占位符，会 panic
unimplemented!("not supported");

// ==================== Result<T, E>（可恢复错误）====================
use std::fs;
use std::io;

fn read_file() -> Result<String, io::Error> {
    let content = fs::read_to_string("hello.txt")?;   // ? 操作符：出错则提前返回 Err
    Ok(content)
}

// ? 操作符展开等价于：
// let content = match fs::read_to_string("hello.txt") {
//     Ok(c) => c,
//     Err(e) => return Err(e.into()),
// };

// 处理 Result
match result {
    Ok(val) => println!("成功: {val}"),
    Err(e) => eprintln!("失败: {e}"),
}

result.unwrap();              // 成功取值，失败则 panic（仅用于原型/测试）
result.expect("读取失败");    // 同上，但可自定义 panic 信息
result.unwrap_or(default);    // 失败时返回默认值
result.unwrap_or_else(|e| {   // 失败时执行闭包
    eprintln!("{e}");
    default
});
result.is_ok();               // → bool
result.is_err();              // → bool
result.ok();                  // Result → Option（丢弃错误信息）
result.map(|v| v * 2);        // 对 Ok 值做变换
result.and_then(|v| other_fn(v)); // 链式调用

// ==================== Option<T>（可能为空）====================
let x: Option<i32> = Some(42);
let y: Option<i32> = None;

x.unwrap();                    // Some → 值, None → panic
x.unwrap_or(0);                // None 时返回 0
x.unwrap_or_default();         // None 时返回类型默认值
x.map(|v| v * 2);             // Some(42) → Some(84)
x.and_then(|v| if v > 0 { Some(v) } else { None });
x.filter(|v| *v > 0);
x.is_some();                   // → bool
x.is_none();                   // → bool

// ==================== 自定义错误（推荐用 thiserror 库）====================
use thiserror::Error;

#[derive(Error, Debug)]
enum AppError {
    #[error("IO error: {0}")]
    Io(#[from] io::Error),           // 自动实现 From<io::Error>

    #[error("Parse error: {0}")]
    Parse(#[from] std::num::ParseIntError),

    #[error("Not found: {name}")]
    NotFound { name: String },
}

// 简单场景用 anyhow 库
use anyhow::{Result, Context};
fn run() -> Result<()> {
    let content = fs::read_to_string("config.toml")
        .context("Failed to read config")?;     // 附加上下文信息
    Ok(())
}
```

---

## 11. 模块系统 & 可见性

```rust
// ==================== 模块组织 ====================
// 文件结构示例：
// src/
// ├── main.rs          （入口，声明模块）
// ├── lib.rs           （库入口）
// ├── config.rs         （config 模块）
// └── db/
//     ├── mod.rs        （db 模块入口）
//     └── connection.rs （db::connection 子模块）

// main.rs 或 lib.rs 中声明模块
mod config;              // 加载 src/config.rs
mod db;                  // 加载 src/db/mod.rs（或 src/db.rs）

// ==================== 模块内容 ====================
mod my_module {
    pub fn public_fn() {}        // pub → 外部可见
    fn private_fn() {}           // 默认私有
    pub struct User {
        pub name: String,        // 字段也需要单独 pub
        password: String,        // 这个字段外部不可访问
    }
    pub enum Status {            // enum 的变体只要 enum 是 pub 的，变体就全部公开
        Active,
        Inactive,
    }
}

// ==================== use 导入 ====================
use std::collections::HashMap;
use std::io::{self, Read, Write};          // 嵌套导入
use std::fmt::{self, Display, Formatter};
use crate::my_module::public_fn;           // crate 根路径
use super::sibling_module;                 // 上级模块
use my_module::User as MyUser;             // 别名

// 重新导出（在库中常用）
pub use crate::db::connection::Connection;
```

---

## 12. 智能指针

```rust
// ==================== Box<T>（堆分配）====================
let b = Box::new(5);               // 在堆上存储值
// 最常见用途：递归类型
enum List {
    Cons(i32, Box<List>),
    Nil,
}

// ==================== Rc<T>（引用计数，单线程共享所有权）====================
use std::rc::Rc;
let a = Rc::new(String::from("hello"));
let b = Rc::clone(&a);            // 引用计数 +1（不是深拷贝！）
println!("count = {}", Rc::strong_count(&a));  // → 2

// ==================== Arc<T>（原子引用计数，多线程共享所有权）====================
use std::sync::Arc;
let data = Arc::new(vec![1, 2, 3]);
let data_clone = Arc::clone(&data); // 线程安全的引用计数 +1

// ==================== RefCell<T>（运行时借用检查，内部可变性）====================
use std::cell::RefCell;
let cell = RefCell::new(5);
*cell.borrow_mut() += 1;          // 运行时检查（违反借用规则会 panic）
println!("{}", cell.borrow());     // 不可变借用

// ==================== 经典组合 ====================
// 单线程共享可变：Rc<RefCell<T>>
let shared = Rc::new(RefCell::new(vec![1, 2, 3]));
let clone = Rc::clone(&shared);
clone.borrow_mut().push(4);

// 多线程共享可变：Arc<Mutex<T>>
use std::sync::Mutex;
let shared = Arc::new(Mutex::new(0));
let clone = Arc::clone(&shared);
*clone.lock().unwrap() += 1;
```

---

## 13. 并发

```rust
use std::thread;
use std::sync::{Arc, Mutex, mpsc};

// ==================== 线程 ====================
let handle = thread::spawn(|| {
    println!("from thread");
    42
});
let result = handle.join().unwrap();   // 等待线程完成，获取返回值

// 传递数据到线程（需要 move）
let data = vec![1, 2, 3];
thread::spawn(move || {
    println!("{:?}", data);            // data 的所有权被 move 进线程
});

// ==================== 消息传递 (Channel) ====================
let (tx, rx) = mpsc::channel();        // 多生产者，单消费者
let tx2 = tx.clone();                  // 克隆发送端

thread::spawn(move || { tx.send("hello").unwrap(); });
thread::spawn(move || { tx2.send("world").unwrap(); });

for msg in rx {                        // 阻塞接收，直到所有发送端关闭
    println!("{msg}");
}

// ==================== 共享状态 ====================
let counter = Arc::new(Mutex::new(0));
let mut handles = vec![];

for _ in 0..10 {
    let c = Arc::clone(&counter);
    handles.push(thread::spawn(move || {
        *c.lock().unwrap() += 1;
    }));
}

for h in handles { h.join().unwrap(); }
println!("count = {}", *counter.lock().unwrap());

// ==================== async / await ====================
// 需要异步运行时（tokio 或 async-std）
// Cargo.toml: tokio = { version = "1", features = ["full"] }

#[tokio::main]
async fn main() {
    let result = fetch_data().await;

    // 并发执行多个异步任务
    let (a, b) = tokio::join!(
        async_task_1(),
        async_task_2(),
    );

    // spawn 异步任务
    let handle = tokio::spawn(async {
        // 后台任务
    });
    handle.await.unwrap();
}

async fn fetch_data() -> String {
    "data".to_string()
}
```

---

## 14. 模式匹配（进阶）

```rust
// Rust 能用模式匹配的地方非常多
// let, match, if let, while let, for, 函数参数 都支持

let (x, y, z) = (1, 2, 3);                  // 元组解构
let Point { x, y } = point;                 // 结构体解构
let [first, .., last] = [1, 2, 3, 4, 5];    // 数组解构

// 嵌套解构
match msg {
    Message::Move { x: 0, y } => println!("move vertically {y}"),
    Message::Color(r, g, b) => println!("rgb({r},{g},{b})"),
    _ => {}
}

// 解构引用
let v = vec![1, 2, 3];
for &item in v.iter() {      // &item 解构引用
    // item 是 i32，不是 &i32
}

// matches! 宏（快速判断是否匹配）
let is_letter = matches!('A', 'a'..='z' | 'A'..='Z');   // → true
```

---

## 15. 常用宏

```rust
// ==================== 输出 ====================
println!("Hello {}!", name);              // 标准输出（换行）
print!("no newline");                     // 标准输出（不换行）
eprintln!("Error: {}", msg);              // 标准错误
format!("Hello {name}");                  // 返回 String（不打印）

// 格式化
println!("{:?}", vec);            // Debug 格式
println!("{:#?}", struct_val);    // Debug 美化（缩进）
println!("{:.2}", 3.14159);       // 保留 2 位小数
println!("{:>10}", "right");      // 右对齐，宽度 10
println!("{:<10}", "left");       // 左对齐
println!("{:^10}", "center");     // 居中
println!("{:0>5}", 42);           // 前导零 → "00042"
println!("{:#b}", 10);            // 二进制 → "0b1010"
println!("{:#x}", 255);           // 十六进制 → "0xff"

// ==================== 断言（测试中常用）====================
assert!(condition);
assert_eq!(left, right);
assert_ne!(left, right);
debug_assert!(condition);         // 仅在 debug 模式生效

// ==================== 其他常用 ====================
vec![1, 2, 3];                    // 创建 Vec
todo!();                          // 占位符（编译通过但运行 panic）
dbg!(expression);                 // 调试打印（输出文件名+行号+表达式值）
include_str!("file.txt");        // 编译时嵌入文件内容为 &str
include_bytes!("image.png");     // 编译时嵌入文件内容为 &[u8]
cfg!(target_os = "windows");     // 条件编译判断
env!("CARGO_PKG_VERSION");       // 编译时读取环境变量
```

---

## 16. 测试

```rust
// ==================== 单元测试（写在同一文件中）====================
#[cfg(test)]
mod tests {
    use super::*;                  // 导入外部模块的所有内容

    #[test]
    fn test_add() {
        assert_eq!(add(2, 3), 5);
    }

    #[test]
    #[should_panic(expected = "overflow")]
    fn test_panic() {
        dangerous_fn();            // 期望 panic
    }

    #[test]
    fn test_result() -> Result<(), String> {
        if add(2, 3) == 5 {
            Ok(())
        } else {
            Err("math is broken".to_string())
        }
    }

    #[test]
    #[ignore]                      // 跳过该测试（cargo test -- --ignored 可运行）
    fn expensive_test() { }
}

// 运行命令
// cargo test                    运行所有测试
// cargo test test_add           运行名字包含 "test_add" 的测试
// cargo test -- --nocapture     显示 println 输出
// cargo test -- --ignored       运行被忽略的测试
```

---

## 17. Cargo 常用命令

```bash
cargo new my_project       # 创建新项目（二进制）
cargo new --lib my_lib     # 创建库项目
cargo build                # 编译（debug 模式）
cargo build --release      # 编译（release 模式，优化）
cargo run                  # 编译并运行
cargo run -- arg1 arg2     # 编译并运行，传递命令行参数
cargo check                # 仅检查语法（比 build 快得多）
cargo test                 # 运行测试
cargo clippy               # 代码质量检查（超有用的 linter）
cargo fmt                  # 自动格式化代码
cargo doc --open           # 生成文档并打开
cargo add serde            # 添加依赖（需要 cargo-edit）
cargo update               # 更新依赖
```

---

## 18. 类型转换速查

```rust
// ==================== 数值转换 ====================
let x: i32 = 42;
let y: i64 = x as i64;            // as 关键字（可能截断/溢出，需小心）
let z: f64 = x as f64;
let w: u8 = 256 as u8;            // ⚠️ 溢出！结果为 0

// 安全转换
let n: u8 = i32::try_from(256).unwrap_or(255);  // TryFrom trait

// ==================== 字符串转换 ====================
let s: String = 42.to_string();                  // 任何实现 Display 的类型
let n: i32 = "42".parse().unwrap();              // parse 需要目标类型
let n: i32 = "42".parse::<i32>().unwrap();       // 或者 turbofish 语法
let s: &str = &my_string;                        // String → &str（自动解引用）
let s: String = my_str.to_string();              // &str → String
let s: String = my_str.to_owned();               // &str → String（等价）

// ==================== From / Into ====================
let s = String::from("hello");                   // From trait
let s: String = "hello".into();                  // Into trait（From 的反向）

// 自定义 From
impl From<(f64, f64)> for Point {
    fn from((x, y): (f64, f64)) -> Self {
        Point { x, y }
    }
}
let p: Point = (1.0, 2.0).into();
```

---

## 📌 速记口诀

| 概念 | 口诀 |
|---|---|
| **所有权** | 值只有一个主人，赋值即转让 |
| **借用** | 共享读（`&`）或独占写（`&mut`），二选一 |
| **生命周期** | 引用不能比数据活得长 |
| **Option** | 用 `Some/None` 替代 `null` |
| **Result** | 用 `Ok/Err` 替代 `try-catch`，`?` 自动传播 |
| **match** | 必须穷举，`_` 兜底 |
| **trait** | 接口 + 默认实现，`derive` 自动生成 |
| **Clone vs Copy** | `Clone` 显式深拷贝，`Copy` 隐式栈拷贝 |
| **String vs &str** | `String` 是 owner（堆上），`&str` 是 view（借用） |
| **Vec vs &[T]** | `Vec` 是 owner（堆上），`&[T]` 是 view（借用） |

---
