Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 通过 dot-source 复用 source-first 配置实现，确保模块导出与 bundle 构建共享同一份源码。
$sourceRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' 'src' 'config'))
foreach ($relativePath in @(
        'convert.ps1'
        'discovery.ps1'
        'reader.ps1'
        'resolver.ps1'
        'scoped-environment.ps1'
    )) {
    . (Join-Path $sourceRoot $relativePath)
}

Export-ModuleMember -Function @(
    'Resolve-ConfigSources'
    'Invoke-WithScopedEnvironment'
)
