#
# psutils 模块清单文件
#
# 作者: mudssky
# 创建日期: 2024/1/19
# 更新日期: 2025/7/25
# 描述: PowerShell 实用工具函数集合模块
#

@{

    # 与此清单关联的脚本模块或二进制模块文件
    # RootModule           = 'index.psm1'
    # 不需要执行代码，通过psd1可以导入模块，所以不需要指定RootModule
    # 如果指定，则会执行这个模块的代码
    RootModule           = ''

    # 此模块的版本号
    ModuleVersion        = '1.0.0'

    # 支持的 PowerShell 版本
    CompatiblePSEditions = @('Desktop', 'Core')

    # 用于唯一标识此模块的 ID
    GUID                 = 'd1108e87-11b1-42f6-899b-2f1bfbb1d399'

    # 此模块的作者
    Author               = 'mudssky'

    # 此模块的公司或供应商
    CompanyName          = 'mudssky'

    # 此模块的版权声明
    Copyright            = '(c) 2024-2025 mudssky. All rights reserved.'

    # 此模块提供的功能说明
    Description          = 'PowerShell 实用工具函数集合，包含环境管理、文件系统操作、网络工具、系统信息获取等功能模块'

    # 此模块所需的 PowerShell 引擎最低版本
    PowerShellVersion    = '5.1'

    # 此模块所需的 PowerShell 主机名称
    # PowerShellHostName = ''

    # 此模块所需的 PowerShell 主机最低版本
    # PowerShellHostVersion = ''

    # 此模块所需的 Microsoft .NET Framework 最低版本（仅适用于 PowerShell Desktop 版本）
    # DotNetFrameworkVersion = ''

    # 此模块所需的公共语言运行时 (CLR) 最低版本（仅适用于 PowerShell Desktop 版本）
    # ClrVersion = ''

    # 此模块所需的处理器架构 (None, X86, Amd64)
    # ProcessorArchitecture = ''

    # 在导入此模块之前必须导入到全局环境中的模块
    # RequiredModules = @()

    # 在导入此模块之前必须加载的程序集
    # RequiredAssemblies = @()

    # 在导入此模块之前在调用方环境中运行的脚本文件 (.ps1)
    # ScriptsToProcess = @()

    # 导入此模块时要加载的类型文件 (.ps1xml)
    # TypesToProcess = @()

    # 导入此模块时要加载的格式文件 (.ps1xml)
    # FormatsToProcess = @()

    # 要作为 RootModule/ModuleToProcess 中指定模块的嵌套模块导入的模块
    NestedModules        = @(
        'modules\cache.psm1',
        'modules\env.psm1',
        'modules\error.psm1',
        'modules\filesystem.psm1',
        'modules\font.psm1',
        'modules\functions.psm1',
        'modules\hardware.psm1',
        'modules\help.psm1',
        'modules\install.psm1',
        'modules\linux.psm1',
        'modules\network.psm1',
        'modules\os.psm1',
        'modules\proxy.psm1',
        'modules\pwsh.psm1',
        'modules\git.psm1',
        'modules\string.psm1',
        'modules\test.psm1',
        'modules\win.psm1',
        'modules\wrapper.psm1'
    )

    # 要从此模块导出的函数，为获得最佳性能，请不要使用通配符，如果没有要导出的函数，请使用空数组
    FunctionsToExport    = @(
        # 缓存管理模块 (cache.psm1)
        'Invoke-WithCache', 'Clear-ExpiredCache', 'Get-CacheStats', 'Invoke-WithFileCache',
        # 环境管理模块 (env.psm1)
        'Get-Dotenv', 'Install-Dotenv', 'Import-EnvPath', 'Set-EnvPath', 'Add-EnvPath', 'Get-EnvParam', 'Remove-FromEnvPath', 'Sync-PathFromBash'
        # 错误处理模块 (error.psm1)
        'Debug-CommandExecution',
        # 文件系统模块 (filesystem.psm1)
        'Get-Tree', 'Show-TreeItem', 'Get-ItemColor', 'Get-GitignoreRules', 'Test-GitignoreMatch', 'Build-TreeObject', 'Get-TreeObject', 'ConvertTo-TreeJson',
        # 字体管理模块 (font.psm1)
        'Test-Font', 'Install-Font', 'Uninstall-Font',
        # 通用函数模块 (functions.psm1)
        'Get-HistoryCommandRank', 'Get-ScriptFolder', 'Start-Ipython', 'Start-PSReadline', 'New-Shortcut', 'Set-Script', 'Update-Semver', 'Get-FormatLength', 'Get-NeedBinaryDigit', 'Get-ReversedMap',
        # 硬件信息模块 (hardware.psm1)
        'Get-GpuInfo', 'Get-SystemMemoryInfo',
        # 帮助搜索模块 (help.psm1)
        'Search-ModuleHelp', 'Find-PSUtilsFunction', 'Get-FunctionHelp', 'Test-HelpSearchPerformance', 'Convert-HelpBlock',
        # 安装管理模块 (install.psm1)
        'Test-ModuleInstalled', 'Install-RequiredModule', 'Install-PackageManagerApps', 'Get-PackageInstallCommand',
        # Linux 系统模块 (linux.psm1)
        'Set-SSHKeyAuth',
        # 网络工具模块 (network.psm1)
        'Test-PortOccupation', 'Get-PortProcess', 'Wait-ForURL',
        # 操作系统模块 (os.psm1)
        'Get-OperatingSystem', 'Test-Administrator',
        # 代理管理模块 (proxy.psm1)
        'Close-Proxy', 'Start-Proxy',
        # PowerShell 工具模块 (pwsh.psm1)
        'Out-ModuleToFile',
        # 字符串处理模块 (string.psm1)
        'Get-LineBreak', 'Convert-JsoncToJson',
        # 测试工具模块 (test.psm1)
        'Test-ModuleFunction', 'Test-EXEProgram', 'Test-ArrayNotNull', 'Test-PathHasExe', 'Test-MacOSCaskApp', 'Test-HomebrewFormula', 'Test-ApplicationInstalled', 'Test-MacOSApplicationInstalled', 'Clear-EXEProgramCache',
        # Windows 系统模块 (win.psm1)
        'Add-Startup', 'New-Shortcut',
        # 包装器模块 (wrapper.psm1)
        'Set-CustomAlias', 'Get-CustomAlias',
        # Git 工具模块 (git.psm1)
        'Get-GitIgnorePatterns', 'New-7ZipExcludeArgs'
    )

    # 要从此模块导出的 Cmdlet，为获得最佳性能，请不要使用通配符，如果没有要导出的 Cmdlet，请使用空数组
    CmdletsToExport      = @()

    # 要从此模块导出的变量
    VariablesToExport    = @()

    # 要从此模块导出的别名，为获得最佳性能，请不要使用通配符，如果没有要导出的别名，请使用空数组
    AliasesToExport      = @()

    # 要从此模块导出的 DSC 资源
    # DscResourcesToExport = @()

    # 与此模块一起打包的所有模块的列表
    # ModuleList = @()

    # 与此模块一起打包的所有文件的列表
    # FileList = @()

    # 要传递给 RootModule/ModuleToProcess 中指定模块的私有数据。这还可能包含 PowerShell 使用的其他模块元数据的 PSData 哈希表
    PrivateData          = @{

        PSData = @{

            # 应用于此模块的标记。这些有助于在在线库中发现模块
            Tags                     = @('PowerShell', 'Utility', 'Tools', 'Environment', 'FileSystem', 'Network', 'System', 'Helper')

            # 此模块许可证的 URL
            # LicenseUri = ''

            # 此项目主网站的 URL
            # ProjectUri = ''

            # 表示此模块的图标的 URL
            # IconUri = ''

            # 此模块的发行说明
            ReleaseNotes             = @'
版本 1.0.0 (2025/7/25)
- 完善模块清单配置文件
- 采用中文注释提高可读性
- 统一子模块导出：所有子模块都明确指定导出函数名
- 增强主模块控制：在 index.psm1 中添加统一的导出控制
- 添加模块元数据：完善 Tags、ProjectUri、LicenseUri 等信息
- 明确指定导出函数列表，移除通配符导出
- 移除重复的 NestedModules 配置
- 更新模块版本和元数据信息
- 添加模块标签和分类
- 支持 PowerShell 5.1+ 和 Core 版本
'@

            # 此模块的预发布字符串
            # Prerelease = ''

            # 指示模块是否需要用户明确接受安装/更新/保存的标志
            RequireLicenseAcceptance = $false

            # 此模块的外部依赖模块
            # ExternalModuleDependencies = @()

        } # PSData 哈希表结束

    } # PrivateData 哈希表结束

    # 此模块的 HelpInfo URI
    # HelpInfoURI = ''

    # 从此模块导出的命令的默认前缀。使用 Import-Module -Prefix 覆盖默认前缀
    # DefaultCommandPrefix = ''

}

