# 使用 NestedModules 方式导入子模块，无需手动导入
# 所有子模块已在 psutils.psd1 的 NestedModules 中配置
# PowerShell 会自动加载这些模块

# # 统一导出控制 - 明确指定所有要导出的函数
# Export-ModuleMember -Function @(
#     # env.psm1
#     'Get-Dotenv', 'Install-Dotenv', 'Import-EnvPath', 'Set-EnvPath', 'Add-EnvPath', 'Get-EnvParam', 'Remove-FromEnvPath',
    
#     # error.psm1
#     'Debug-CommandExecution',
    
#     # filesystem.psm1
#     'Get-Tree', 'Show-TreeItem', 'Get-ItemColor', 'Get-GitignoreRules', 'Test-GitignoreMatch', 'Build-TreeObject', 'Get-TreeObject', 'ConvertTo-TreeJson',
    
#     # font.psm1
#     'Test-Font', 'Install-Font', 'Uninstall-Font',
    
#     # functions.psm1
#     'Get-HistoryCommandRank', 'Get-ScriptFolder', 'Start-Ipython', 'Start-PSReadline', 'New-Shortcut', 'Set-Script', 'Update-Semver', 'Get-FormatLength', 'Get-NeedBinaryDigit', 'Get-ReversedMap',
    
#     # hardware.psm1
#     'Get-GpuInfo', 'Get-SystemMemoryInfo',
    
#     # help.psm1
#     'Get-Help',
    
#     # install.psm1
#     'Test-ModuleInstalled', 'Install-RequiredModule', 'Install-PackageManagerApps', 'Get-PackageInstallCommand',
    
#     # linux.psm1
#     'Set-SSHKeyAuth',
    
#     # network.psm1
#     'Test-PortOccupation', 'Get-PortProcess', 'Wait-ForURL',
    
#     # os.psm1
#     'Get-OperatingSystem', 'Test-Administrator',
    
#     # proxy.psm1
#     'Close-Proxy', 'Start-Proxy',
    
#     # pwsh.psm1
#     'Out-ModuleToFile',
    
#     # test.psm1
#     'Test-ModuleFunction',
    
#     # win.psm1
#     'Add-Startup', 'New-Shortcut'
# )


