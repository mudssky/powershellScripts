# PowerShell 脚本项目规则

我们的默认终端是pwsh（powershell 7+），执行较长的命令创建一个ps1脚本来执行。因为长命令有很多引号，容易出错导致命令不执行
短命令可以使用pwsh -Command来执行，不要用powershell来执行，因为可能调用的是windows默认的powershell，而不是powershell 7+

## 代码风格规范

### 命名约定

- **函数名**: 使用 Pascal 命名法（如 `Install-RequiredModule`、`Test-ModuleInstalled`）
- **参数名**: 使用 Pascal 命名法（如 `$ModuleName`、`$PackageManager`）
- **变量名**: 使用 camelCase 命名法（如 `$appName`、`$cliName`、`$configPath`）
- **常量**: 使用全大写加下划线（如 `$SCRIPT_ROOT`）

### 代码格式

- **缩进**: 使用 4 个空格进行缩进，不使用制表符
- **大括号**: 开括号与控制语句在同一行，闭括号独占一行
- **运算符**: 运算符前后添加空格（如 `$a -eq $b`）
- **参数**: 长参数列表时每个参数独占一行并适当缩进

### 注释规范

- **函数注释**: 必须使用完整的 PowerShell Help 注释格式，包含：
  - `.SYNOPSIS`: 简短描述
  - `.DESCRIPTION`: 详细描述
  - `.PARAMETER`: 每个参数的说明
  - `.EXAMPLE`: 使用示例
  - `.OUTPUTS`: 返回值说明（如适用）
  - `.NOTES`: 额外说明（如适用）
- **行内注释**: 使用中文进行注释，简洁明了
- **代码块注释**: 对复杂逻辑进行分段注释说明

### 错误处理

- 使用 `try-catch` 块处理可能的异常
- 使用 `Write-Warning` 输出警告信息
- 使用 `Write-Error` 输出错误信息
- 使用 `Write-Verbose` 输出详细信息
- 使用 `Write-Host` 配合颜色输出用户友好的状态信息

### 参数验证

- 使用 `[CmdletBinding()]` 启用高级函数特性
- 使用 `[Parameter()]` 属性定义参数特性
- 必需参数使用 `Mandatory = $true`
- 使用参数集 `ParameterSetName` 处理互斥参数
- 支持 `SupportsShouldProcess` 用于需要确认的操作

## 模块结构规范

### 文件组织

- 主模块文件: `index.psm1`
- 子模块目录: `modules/`
- 模块清单: `*.psd1`
- 测试文件: `tests/` 目录下的 `*.Tests.ps1`

### 模块导出

- 在模块末尾使用 `Export-ModuleMember -Function *` 导出所有函数
- 或明确指定要导出的函数名

### 依赖管理

- 检查模块是否已安装后再导入
- 使用 `Install-Module` 安装缺失的依赖
- 优先使用 `CurrentUser` 作用域安装模块

## 功能实现规范

### 跨平台兼容性

- 支持 Windows、macOS 和 Linux 系统
- 使用条件判断处理平台特定的逻辑
- 路径处理使用 PowerShell 内置的路径操作函数

### 包管理器支持

- 支持多种包管理器：choco、scoop、winget、cargo、homebrew、apt
- 使用 switch 语句处理不同包管理器的命令格式
- 提供统一的配置文件格式

### 配置文件格式

- 使用 JSON 格式存储配置
- 支持嵌套结构组织不同类型的配置
- 提供默认值和可选字段
- 包含详细的字段说明和示例

## 测试规范

### 测试文件命名

- 测试文件以 `.Tests.ps1` 结尾
- 测试文件名与被测试模块名对应

### 测试框架

- 使用 Pester 框架进行单元测试
- 测试覆盖主要功能和边界情况

### 空值检查

#### **1. 检查一个变量是否就是 `null`**

**做法：** 把 `$null` 放在左边比较。

```powershell
if ($null -eq $myVar) { ... }
```

**场景：** 只关心变量是不是 `null`，不关心它是不是空字符串或空数组。

#### **2. 检查一个字符串是否“没有内容”**

**做法：** 使用 `[string]::IsNullOrWhiteSpace()`。

```powershell
if ([string]::IsNullOrWhiteSpace($myString)) { ... }
```

**场景：** 需要判断字符串是 `null`、空 (`""`) 还是只有空格。

---

#### **3. 检查一个数组或哈希表是否为空**

**做法：** 检查 `.Count` 属性是否为 `0`。

```powershell
if ($myArray.Count -eq 0) { ... }
```

**场景：** 确定一个集合里没有任何元素。**切勿**用 `if (-not $myArray)`，因为空数组在布尔判断中是 `true`。

---

#### **4. 检查一个变量是 `null` 或空数组**

**做法：** 使用 `@()` 强制转换为数组再检查 `.Count`。

```powershell
if (@($myVar).Count -eq 0) { ... }
```

**场景：** 函数可能返回 `null` 或一个空数组，你希望两种情况都当成“空”来处理。

---

### **Pester 测试中的规则 (`.Tests.ps1`)**

| 检查目标                  | Pester 断言                                |
| :------------------------ | :----------------------------------------- |
| **是 `$null`**            | `($variable) | Should -Be $null`         |
| **不是 `$null`**          | `($variable) | Should -Not -Be $null`     |
| **是空数组/空字符串**     | `$variable | Should -BeEmpty`             |
| **是 `$null` 或空**       | `($variable) | Should -BeNullOrEmpty`     |

**为什么要有括号？** 防止当变量是空数组时，PowerShell 管道“吞掉”它，导致 `Should` 命令收不到任何东西而报错。括号能确保数组对象本身被传递。

## 文档规范

### README 文档

- 提供清晰的项目描述和使用说明
- 包含安装和配置步骤
- 提供使用示例

### 代码示例

- 在函数注释中提供实际可运行的示例
- 示例应覆盖常见使用场景
- 使用中文注释说明示例的用途

## 安全规范

### 权限控制

- 避免使用管理员权限执行非必要操作
- 优先使用用户级别的安装和配置
- 对敏感操作提供确认机制

### 输入验证

- 验证文件路径的有效性
- 检查配置文件的格式和内容
- 对用户输入进行适当的清理和验证
