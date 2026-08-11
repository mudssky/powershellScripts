Set-StrictMode -Version Latest

<##
.SYNOPSIS
    计算 browser-debug Native Completion 候选。
.PARAMETER Line
    完整命令行文本。
.PARAMETER Position
    光标位置。
.PARAMETER RegistryPath
    可选注册表路径，仅用于只读名称补全。
.OUTPUTS
    System.String[]
    返回候选字符串。
#>
function Get-BrowserDebugCompletionCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Line, [Parameter(Mandatory)][int]$Position, [string]$RegistryPath)
    try {
        $prefixLine = $Line.Substring(0, [Math]::Min($Position, $Line.Length))
        $endsWithSpace = $prefixLine -match '\s$'
        [object[]]$tokens = @([regex]::Matches($prefixLine, '"[^"]*"|\S+') | ForEach-Object { $_.Value.Trim('"') })
        if ($tokens.Count -gt 0) { [object[]]$tokens = @($tokens | Select-Object -Skip 1) }
        $current = if ($endsWithSpace -or $tokens.Count -eq 0) { '' } else { $tokens[-1] }
        [object[]]$committed = @()
        if ($endsWithSpace) { $committed = @($tokens) }
        elseif ($tokens.Count -gt 1) { $committed = @($tokens | Select-Object -SkipLast 1) }
        $schema = Get-BrowserDebugCommandSchema
        $candidates = @()
        if ($committed.Count -eq 0) { $candidates = @('profile', 'ssh', 'completion', 'help') }
        elseif ($committed[0] -eq 'completion') { $candidates = @('powershell') }
        elseif ($committed[0] -in 'profile', 'ssh') {
            $resource = $committed[0]
            if ($committed.Count -eq 1) { $candidates = @($schema[$resource]['Actions'].Keys) }
            else {
                $action = $committed[1]
                if (-not $schema[$resource]['Actions'].Contains($action)) { return @() }
                $actionSchema = $schema[$resource]['Actions'][$action]
                $previous = if ($committed.Count -gt 0) { $committed[-1] } else { $null }
                if ($actionSchema.Enums.Contains($previous)) { $candidates = @($actionSchema.Enums[$previous]) }
                elseif ($committed.Count -eq 2 -and $action -notin 'list') {
                    if ($action -in 'create') { $candidates = @() }
                    else {
                        $resolvedPath = Resolve-BrowserDebugRegistryPath -RegistryPath $RegistryPath
                        $registry = Read-BrowserDebugRegistry -RegistryPath $resolvedPath
                        $candidates = if ($resource -eq 'profile') { @($registry.profiles.name) } else { @($registry.sshConfigurations.name) }
                    }
                }
                else { $candidates = @($actionSchema.Options) + @('--help') }
            }
        }
        return @($candidates | Where-Object { $_ -like "$current*" } | Sort-Object -Unique)
    }
    catch { return @() }
}

<##
.SYNOPSIS
    幂等注册 browser-debug 别名和 Native Completer。
.PARAMETER CommandPath
    browser-debug.ps1 入口路径。
.OUTPUTS
    None
    仅修改当前 PowerShell 会话的别名和补全注册。
#>
function Register-BrowserDebugCompletion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$CommandPath)
    Set-Alias -Name browser-debug -Value $CommandPath -Scope Global -Force
    $registrationMarker = Get-Variable -Name __BrowserDebugCompletionRegistered -Scope Global -ErrorAction SilentlyContinue
    $registeredPath = Get-Variable -Name __BrowserDebugCompletionCommandPath -Scope Global -ErrorAction SilentlyContinue
    if ($registrationMarker -and [bool]$registrationMarker.Value -and $registeredPath -and [string]$registeredPath.Value -eq $CommandPath) { return }
    $completionCommandPath = $CommandPath
    $pwshPath = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    Register-ArgumentCompleter -Native -CommandName browser-debug, browser-debug.ps1 -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        try {
            # 公开入口会调用 exit 映射 CLI 退出码，必须放在子进程中，不能终止当前交互式会话。
            & $pwshPath -NoLogo -NoProfile -File $completionCommandPath __complete --line $commandAst.ToString() --position $cursorPosition 2>$null
        }
        catch { @() }
    }.GetNewClosure()
    $Global:__BrowserDebugCompletionRegistered = $true
    $Global:__BrowserDebugCompletionCommandPath = $CommandPath
}
