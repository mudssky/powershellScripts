编写跨平台（Windows, Linux, macOS）且可直接执行的 PowerShell (pwsh) 脚本，需要关注**解释器声明**、**文件编码**、**路径处理**以及**平台差异兼容**。

以下是实现这一目标的最佳实践指南。

---

### 1. 核心基础 (The Essentials)

#### A. 添加 Shebang 行 (Unix-like 系统必需)

为了让 Linux 和 macOS 知道使用哪个解释器来运行该文件，脚本的**第一行**必须是 Shebang。Windows 会忽略这一行（视作注释），所以是安全的。

```powershell
#!/usr/bin/env pwsh
```

* **注意**：使用 `/usr/bin/env` 比硬编码 `/usr/bin/pwsh` 更好，因为它会自动在系统的 `PATH` 环境变量中查找 `pwsh`，兼容性更强。

#### B. 文件编码：UTF-8 (无 BOM)

这是最关键的一点。

* **Windows PowerShell (旧版)** 喜欢带 BOM 的 UTF-8。
* **Linux/macOS** 的 Shebang 机制如果遇到 BOM 标记（文件开头的不可见字节），会报错 `exec format error` 或找不到命令。
* **最佳实践**：始终将文件保存为 **UTF-8 (No BOM)** 格式。VS Code 默认即为此格式。

#### C. 换行符 (Line Endings)

尽量使用 **LF (\n)** 而不是 Windows 的 CRLF (\r\n)。虽然现代 PowerShell 能够处理 CRLF，但在某些严格的 Linux 环境下，Shebang 行如果以 `\r` 结尾可能会导致解释器解析失败。

---

### 2. 代码编写规范 (Coding Standards)

#### A. 路径处理 (Path Handling)

不要硬编码路径分隔符（`\` 或 `/`）。Windows 使用反斜杠，Unix 使用正斜杠。

* **错误做法**: `$path = "C:\Temp\file.txt"` 或 `$path = "/tmp/file.txt"`
* **最佳实践**:
    1. 使用 `Join-Path` 拼接路径。
    2. 利用内置变量 `$PSScriptRoot` 获取当前脚本所在目录。
    3. PowerShell Core 在 Windows 上也能识别 `/`，但在与原生 Windows 命令交互时可能出问题。

```powershell
# 跨平台路径拼接
$ConfigPath = Join-Path $PSScriptRoot "config" "settings.json"
```

#### B. 避免使用别名 (Aliases)

在 Windows 上，`curl` 是 `Invoke-WebRequest` 的别名，`ls` 是 `Get-ChildItem` 的别名。但在 Linux 上，`curl` 和 `ls` 是系统原生的二进制程序。
混用会导致脚本在不同平台上行为不一致。

* **最佳实践**: 始终使用完整的 Cmdlet 名称。
  * 用 `Get-ChildItem` 代替 `ls` 或 `dir`。
  * 用 `Invoke-RestMethod` 代替 `curl`。
  * 用 `Select-String` 代替 `grep`。

#### C. 平台检测 (Platform Checks)

如果必须针对不同系统执行不同逻辑，请使用内置的布尔变量：

```powershell
if ($IsLinux) {
    Write-Host "Running on Linux"
}
elseif ($IsMacOS) {
    Write-Host "Running on macOS"
}
elseif ($IsWindows) {
    Write-Host "Running on Windows"
}
```

#### D. 环境变量

不同系统的环境变量不同（例如 Windows 的 `$env:USERPROFILE` vs Linux 的 `$env:HOME`）。

* **最佳实践**: 使用 .NET 跨平台方法或 PowerShell 抽象变量。
  * 主目录: `[System.Environment]::GetFolderPath('UserProfile')` 或 `$HOME` (PS Core 通用)。
  * 临时目录: `[System.IO.Path]::GetTempPath()`.

---

### 3. 完整脚本模版 (Template)

将以下内容保存为 `myscript.ps1`，并确保编码为 UTF-8 (No BOM)。

```powershell
#!/usr/bin/env pwsh

<#
.SYNOPSIS
    跨平台 PowerShell 脚本模版。
.DESCRIPTION
    演示如何编写在 Windows, Linux 和 macOS 上都能直接运行的脚本。
#>

[CmdletBinding()]
param(
    [string]$Name = "World"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Main {
    Write-Host "Hello, $Name!" -ForegroundColor Green

    # 1. 平台检测
    if ($IsWindows) {
        Write-Host "OS: Windows"
    } elseif ($IsLinux) {
        Write-Host "OS: Linux"
    } elseif ($IsMacOS) {
        Write-Host "OS: macOS"
    }

    # 2. 跨平台路径处理
    $LogFile = Join-Path $PSScriptRoot "script.log"
    Write-Host "Log path: $LogFile"

    # 3. 模拟跨平台操作
    try {
        # 使用原生 Cmdlet 而非别名 (如 date, ls)
        $Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        "Script run at $Date" | Out-File -FilePath $LogFile -Encoding utf8 -Append
    }
    catch {
        Write-Error "An error occurred: $_"
        exit 1
    }
}

# 执行主函数
Main
```

---

### 4. 赋予执行权限 (Execution Permissions)

为了让脚本像二进制程序一样运行（即可“直接执行”），你需要设置权限。

#### 在 Linux / macOS 上

必须赋予脚本执行权限 (`x` bit)。

```bash
chmod +x myscript.ps1
```

现在你可以这样运行：

```bash
./myscript.ps1
```

#### 在 Windows 上

Windows 不通过文件权限位来判断可执行性，而是通过文件扩展名关联。

1. **直接运行**: 通常需要输入 `.\myscript.ps1`。
2. **双击运行**: 默认情况下，双击 `.ps1` 会用记事本打开。如果你想双击运行，通常建议创建一个同名的 `.cmd` 或 `.bat` 包装器，或者修改注册表（不推荐用于分发）。

**Windows 包装器技巧 (可选)**：
如果你希望在 Windows cmd 中也能像 Linux 那样直接输入 `myscript` (不带扩展名) 运行，可以创建一个同名的 `myscript.cmd` 文件：

```batch
@echo off
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0myscript.ps1" %*
```

### 5. 总结清单 (Checklist)

1. [ ] **第一行**: `#!/usr/bin/env pwsh`
2. [ ] **编码**: UTF-8 without BOM
3. [ ] **换行符**: LF (推荐)
4. [ ] **路径**: 使用 `Join-Path` 和 `$PSScriptRoot`
5. [ ] **命令**: 拒绝别名，使用完整 Cmdlet (`Get-ChildItem` vs `ls`)
6. [ ] **权限**: Linux/Mac 下执行 `chmod +x script.ps1`
