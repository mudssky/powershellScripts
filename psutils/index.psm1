#requires -Version 7.4

$manifestPath = Join-Path $PSScriptRoot 'psutils.psd1'
Write-Warning 'psutils/index.psm1 已弃用，请改为导入 psutils.psd1 或 psutils 目录。'

# 兼容入口必须把规范模块导入调用方会话，否则 shim 返回后公共命令不可见。
Import-Module $manifestPath -Force -Global
