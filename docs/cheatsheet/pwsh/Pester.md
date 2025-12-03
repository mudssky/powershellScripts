## Pester 测试框架速查表 (Cheatsheet)

Pester 是 PowerShell 的标准测试框架，用于单元测试、集成测试、基础设施测试等。

### 1. 基本结构

一个 Pester 测试文件通常由 `Describe`、`Context` 和 `It` 块组成，形成一个清晰的层次结构。

```powershell
# 文件名通常以 .Tests.ps1 结尾，例如 MyFunction.Tests.ps1

# . '.\MyFunction.ps1' # 使用点采购（Dot-sourcing）加载你的函数文件

Describe '描述一个功能或模块 (例如 Get-Greeting 函数)' {
    Context '描述一个特定的场景 (例如 当提供名字时)' {
        It '描述一个具体的测试用例 (例如 应该返回正确的问候语)' {
            # 测试代码在这里
            $result = Get-Greeting -Name 'World'
            $result | Should -Be 'Hello, World!'
        }
    }

    Context '描述另一个场景 (例如 当不提供名字时)' {
        It '应该抛出错误' {
            { Get-Greeting } | Should -Throw
        }
    }
}
```

- **`Describe`**: 最高层级的组织块。
- **`Context`**: `Describe` 的子块，用于描述特定场景。
- **`It`**: 最小的测试单元，代表一个独立的测试用例。

### 2. 运行测试

使用 `Invoke-Pester` 命令来执行测试。

```powershell
# 运行当前目录及子目录下的所有 *.Tests.ps1 文件
Invoke-Pester

# 运行指定路径下的测试
Invoke-Pester -Path 'C:\Path\To\MyFunction.Tests.ps1'

# 显示详细的输出
Invoke-Pester -Output Detailed
```

### 3. 断言 (Assertions)

断言使用 `Should` 命令来验证结果是否符合预期。

| 断言 (`Should -Operator`) | 描述 | 示例 |
| ------------------------- | ---------------------------------------------------- | ----------------------------------------------------------------- |
| `-Be` | 值相等 (不区分大小写) | `$result | Should -Be 'hello'` |
| `-BeExactly` | 值和类型都完全相等 | `$result | Should -BeExactly 'hello'` |
| `-BeLike` | 字符串模糊匹配 (使用通配符 `*` `?`) | `$result | Should -BeLike 'Hello*'` |
| `-Match` | 正则表达式匹配 | `$result | Should -Match '^Hello'` |
| `-Contain` | 集合包含某个元素 | `(1, 2, 3) | Should -Contain 2` |
| `-HaveCount` | 集合/数组的元素数量 | `(1, 2, 3) | Should -HaveCount 3` |
| `-BeNullOrEmpty` | 变量为 `$null` 或空字符串/集合 | `$null | Should -BeNullOrEmpty` |
| `-BeTrue` / `-BeFalse` | 值为 `$true` 或 `$false` | `(1 -eq 1) | Should -BeTrue` |
| `-Throw` | 脚本块抛出异常 | `{ 1/0 } | Should -Throw` |
| `-Exist` | 文件或文件夹存在 | `Get-Item './file.txt' | Should -Exist` |
| `-BeOfType <Type>` | 对象的类型 | `'hello' | Should -BeOfType ([string])` |

**否定断言**: 在操作符前添加 `-Not` (`$result | Should -Not -Be 'world'`)。

### 4. 安装与拆卸 (Setup & Teardown)

用于在测试运行前后准备环境和进行清理。

| 命令 | 执行时机 | 作用域 |
| :----------- | :---------------------------------- | :------------------- |
| `BeforeAll` | 在 `Describe` 块中的所有测试开始前运行一次 | `Describe` |
| `AfterAll` | 在 `Describe` 块中的所有测试结束后运行一次 | `Describe` |
| `BeforeEach` | 在**每个** `It` 块运行之前都运行一次 | `Describe` 或 `Context` |
| `AfterEach` | 在**每个** `It` 块运行之后都运行一次 | `Describe` 或 `Context` |

### 5. 跳过测试 (Skipping Tests)

使用 `-Skip` 参数可以跳过单个测试 (`It`) 或一组测试 (`Describe`/`Context`)。

**基本用法**:
直接在 `It`, `Context` 或 `Describe` 后面添加 `-Skip`。

```powershell
It '这个测试将被跳过', -Skip {
    # 这里的代码将不会被执行
    1 | Should -Be 2
}
```

**条件性跳过**:
`-Skip` 参数可以接受一个表达式。如果表达式的结果为 `$true`，则测试被跳过。这对于环境相关的测试非常有用。

```powershell
Describe 'Windows 特有的测试' -Skip:(-not $IsWindows) {
    It '应该能读取注册表' {
        # ...
    }
}

It '仅在 CI 环境中运行', -Skip:(-not $env:CI) {
    # ...
}
```

### 6. 标签 (Tagging)

为测试用例打上标签，方便分类和选择性执行。

```powershell
It 'is a fast unit test', -Tag 'Unit', 'Fast' {
    # ...
}

It 'is a slow integration test', -Tag 'Integration', 'Slow' {
    # ...
}
```

**运行带标签的测试**:

```powershell
# 只运行 "Unit" 标签的测试
Invoke-Pester -Tag 'Unit'

# 运行 "Integration" 但排除 "Slow" 标签的测试
Invoke-Pester -Tag 'Integration' -ExcludeTag 'Slow'
```

### 7. 模拟 (Mocking)

Mocking 用于隔离被测试的代码，通过替换其依赖项（如其他函数、Cmdlet）。

**基本 Mock**:

```powershell
# 替换 Get-Date 命令，使其总是返回一个固定的日期
Mock Get-Date { return [datetime]'2023-01-01' }

It 'Should use the mocked date' {
    $today = Get-Date -Format 'yyyy-MM-dd'
    $today | Should -Be '2023-01-01'
}
```

**验证 Mock 是否被调用**:

```powershell
Describe 'My-Function which calls Get-ChildItem' {
    It 'Should call Get-ChildItem exactly once' {
        # 模拟 Get-ChildItem 并标记为可验证
        Mock Get-ChildItem { return @() } -Verifiable

        # 调用你的函数
        My-Function

        # 验证 Mock 被调用的情况
        Assert-Verifiable -Mock 'Get-ChildItem' -Times 1
    }
}
```

- **`Mock`**: 定义一个模拟。
- **`-Verifiable`**: 标记一个 Mock，以便之后用 `Assert-Verifiable` 进行验证。
- **`Assert-Verifiable`**: 验证一个可验证的 Mock 是否被按预期调用。

### 8. 代码覆盖率 (Code Coverage)

测量你的测试覆盖了多少源代码。

```powershell
# 1. 创建 Pester 配置对象
$pesterConfig = [PesterConfiguration]::Default
$pesterConfig.CodeCoverage.Enabled = $true
# 指定要分析覆盖率的源文件路径
$pesterConfig.CodeCoverage.Path = '.\MyFunction.ps1'

# 2. 使用此配置运行 Pester
Invoke-Pester -Configuration $pesterConfig
```

输出会显示类似 `[+] C:\Path\MyFunction.ps1 85.71% (6/7) covered` 的覆盖率报告。
