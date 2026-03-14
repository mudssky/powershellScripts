function Get-InteractiveSelectionFzfInstallHint {
    [CmdletBinding()]
    param()

    if ($IsLinux) {
        return '请先安装 fzf，例如：sudo apt-get install -y fzf 或 sudo dnf install -y fzf'
    }

    if ($IsMacOS) {
        return '请先安装 fzf，例如：brew install fzf'
    }

    if ($IsWindows -or $env:OS -eq 'Windows_NT') {
        return '请先安装 fzf，例如：winget install junegunn.fzf 或 choco install fzf'
    }

    return '请先安装 fzf 并确保其在 PATH 中。'
}

function Test-InteractiveSelectionIsWindows {
    [CmdletBinding()]
    param()

    return ($IsWindows -or $env:OS -eq 'Windows_NT')
}

function Find-InteractiveSelectionExecutablePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }

    $pathValue = [Environment]::GetEnvironmentVariable('PATH', 'Process')
    if ([string]::IsNullOrWhiteSpace($pathValue)) {
        return $null
    }

    $extensions = @('')
    if (Test-InteractiveSelectionIsWindows) {
        $pathExtValue = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
        if ([string]::IsNullOrWhiteSpace($pathExtValue)) {
            $pathExtValue = '.COM;.EXE;.BAT;.CMD'
        }

        if ([string]::IsNullOrWhiteSpace([System.IO.Path]::GetExtension($Name))) {
            $extensions = @($pathExtValue.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries))
            if ($extensions.Count -eq 0) {
                $extensions = @('.COM', '.EXE', '.BAT', '.CMD')
            }
        }
    }

    foreach ($rawPath in $pathValue.Split([System.IO.Path]::PathSeparator, [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $searchPath = $rawPath.Trim().Trim('"')
        if ([string]::IsNullOrWhiteSpace($searchPath) -or -not [System.IO.Directory]::Exists($searchPath)) {
            continue
        }

        foreach ($extension in $extensions) {
            $candidateName = if ([string]::IsNullOrEmpty($extension)) {
                $Name
            }
            else {
                "$Name$extension"
            }

            $candidatePath = [System.IO.Path]::Combine($searchPath, $candidateName)
            if ([System.IO.File]::Exists($candidatePath)) {
                return [System.IO.Path]::GetFullPath($candidatePath)
            }
        }
    }

    return $null
}

function Test-InteractiveSelectionFzfAvailable {
    [CmdletBinding()]
    param()

    if (Test-Path Function:\fzf) {
        return $true
    }

    if (Test-Path Alias:\fzf) {
        return $true
    }

    return (-not [string]::IsNullOrWhiteSpace((Find-InteractiveSelectionExecutablePath -Name 'fzf')))
}

function Get-InteractiveSelectionDisplayText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Item,
        [string]$DisplayProperty,
        [scriptblock]$DisplayScriptBlock
    )

    if ($Item -is [string]) {
        return [string]$Item
    }

    if (-not [string]::IsNullOrWhiteSpace($DisplayProperty)) {
        $property = $Item.PSObject.Properties[$DisplayProperty]
        if ($null -eq $property) {
            throw ("候选项对象缺少显示属性: {0}" -f $DisplayProperty)
        }

        if ($null -eq $property.Value) {
            return ''
        }

        return [string]$property.Value
    }

    if ($null -ne $DisplayScriptBlock) {
        $displayParts = @($Item | ForEach-Object -Process $DisplayScriptBlock)
        if ($displayParts.Count -eq 0) {
            return ''
        }

        return (($displayParts | ForEach-Object { [string]$_ }) -join ' ')
    }

    throw '对象候选项必须显式提供 -DisplayProperty 或 -DisplayScriptBlock。'
}

function New-InteractiveSelectionEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,
        [string]$DisplayProperty,
        [scriptblock]$DisplayScriptBlock
    )

    $hasObjectItem = $false
    foreach ($item in $Items) {
        if ($item -isnot [string]) {
            $hasObjectItem = $true
            break
        }
    }

    if (
        $hasObjectItem -and
        [string]::IsNullOrWhiteSpace($DisplayProperty) -and
        $null -eq $DisplayScriptBlock
    ) {
        throw '对象候选项必须显式提供 -DisplayProperty 或 -DisplayScriptBlock。'
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    for ($index = 0; $index -lt $Items.Count; $index++) {
        $displayTextParams = @{
            Item = $Items[$index]
        }
        if (-not [string]::IsNullOrWhiteSpace($DisplayProperty)) {
            $displayTextParams.DisplayProperty = $DisplayProperty
        }
        if ($null -ne $DisplayScriptBlock) {
            $displayTextParams.DisplayScriptBlock = $DisplayScriptBlock
        }

        $displayText = Get-InteractiveSelectionDisplayText @displayTextParams

        # fzf 与文本列表都依赖单行展示，因此这里统一清洗换行和制表符。
        $normalizedDisplayText = ([string]$displayText) -replace "`r?`n", ' ' -replace "`t", '    '
        $entries.Add([PSCustomObject]@{
                Index       = $index
                Number      = ($index + 1)
                DisplayText = $normalizedDisplayText
                Item        = $Items[$index]
            }) | Out-Null
    }

    return $entries.ToArray()
}

function ConvertFrom-InteractiveSelectionTextInput {
    [CmdletBinding()]
    param(
        [string]$Text,
        [int]$MaxNumber,
        [switch]$AllowMultiple
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return [PSCustomObject]@{
            IsCanceled   = $true
            IsValid      = $false
            SelectedRows = @()
            ErrorMessage = $null
        }
    }

    if (-not $AllowMultiple -and $Text.Contains(',')) {
        return [PSCustomObject]@{
            IsCanceled   = $false
            IsValid      = $false
            SelectedRows = @()
            ErrorMessage = '当前为单选模式，请只输入一个编号。'
        }
    }

    $segments = if ($AllowMultiple) {
        $Text.Split(',', [System.StringSplitOptions]::None)
    }
    else {
        @($Text)
    }

    $selectedRows = New-Object 'System.Collections.Generic.List[int]'
    $seenRows = New-Object 'System.Collections.Generic.HashSet[int]'

    foreach ($segment in $segments) {
        $trimmedSegment = $segment.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedSegment)) {
            return [PSCustomObject]@{
                IsCanceled   = $false
                IsValid      = $false
                SelectedRows = @()
                ErrorMessage = '输入中包含空编号，请重新输入。'
            }
        }

        $parsedNumber = 0
        if (-not [int]::TryParse($trimmedSegment, [ref]$parsedNumber)) {
            return [PSCustomObject]@{
                IsCanceled   = $false
                IsValid      = $false
                SelectedRows = @()
                ErrorMessage = ("无法解析编号: {0}" -f $trimmedSegment)
            }
        }

        if ($parsedNumber -lt 1 -or $parsedNumber -gt $MaxNumber) {
            return [PSCustomObject]@{
                IsCanceled   = $false
                IsValid      = $false
                SelectedRows = @()
                ErrorMessage = ("编号超出范围，请输入 1 到 {0} 之间的值。" -f $MaxNumber)
            }
        }

        $zeroBasedIndex = $parsedNumber - 1
        # 使用 HashSet 去重，同时保留用户首次输入的顺序。
        if ($seenRows.Add($zeroBasedIndex)) {
            $selectedRows.Add($zeroBasedIndex) | Out-Null
        }
    }

    return [PSCustomObject]@{
        IsCanceled   = $false
        IsValid      = $true
        SelectedRows = $selectedRows.ToArray()
        ErrorMessage = $null
    }
}

function Invoke-InteractiveSelectionByText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [string]$Prompt,
        [string]$Header,
        [switch]$AllowMultiple
    )

    if (-not [string]::IsNullOrWhiteSpace($Header)) {
        Write-Host $Header -ForegroundColor Cyan
    }

    do {
        foreach ($entry in $Entries) {
            Write-Host ("[{0}] {1}" -f $entry.Number, $entry.DisplayText)
        }

        if ($AllowMultiple) {
            Write-Host '请输入逗号分隔的编号，直接回车可取消。' -ForegroundColor DarkGray
        }
        else {
            Write-Host '请输入一个编号，直接回车可取消。' -ForegroundColor DarkGray
        }

        $rawInput = Read-Host $Prompt
        $parsedInput = ConvertFrom-InteractiveSelectionTextInput `
            -Text $rawInput `
            -MaxNumber $Entries.Count `
            -AllowMultiple:$AllowMultiple

        if ($parsedInput.IsCanceled) {
            return @()
        }

        if ($parsedInput.IsValid) {
            return @($parsedInput.SelectedRows)
        }

        Write-Warning $parsedInput.ErrorMessage
        Write-Host ''
    }
    while ($true)
}

function Invoke-InteractiveSelectionByFzf {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Entries,
        [string]$Prompt,
        [string]$Header,
        [switch]$AllowMultiple
    )

    $rows = foreach ($entry in $Entries) {
        "{0}`t{1}" -f $entry.Index, $entry.DisplayText
    }

    $fzfArgs = @(
        '--layout=reverse',
        '--height=80%',
        '--border',
        '--delimiter', "`t",
        '--with-nth', '2'
    )

    if ($AllowMultiple) {
        $fzfArgs += '--multi'
    }

    if (-not [string]::IsNullOrWhiteSpace($Prompt)) {
        $fzfArgs += @('--prompt', $Prompt)
    }

    $headerParts = New-Object 'System.Collections.Generic.List[string]'
    if (-not [string]::IsNullOrWhiteSpace($Header)) {
        $headerParts.Add($Header) | Out-Null
    }

    if ($AllowMultiple) {
        $headerParts.Add('Tab 多选, Enter 确认, Esc 取消') | Out-Null
    }
    else {
        $headerParts.Add('Enter 确认, Esc 取消') | Out-Null
    }

    if ($headerParts.Count -gt 0) {
        $fzfArgs += @('--header', ($headerParts -join ' | '))
    }

    $selectedRows = @($rows | & fzf @fzfArgs)
    $fzfExitCode = $LASTEXITCODE

    if ($fzfExitCode -eq 130 -or ($fzfExitCode -eq 1 -and $selectedRows.Count -eq 0)) {
        return @()
    }

    if ($fzfExitCode -ne 0) {
        throw ("fzf 执行失败，exit code: {0}" -f $fzfExitCode)
    }

    if ($selectedRows.Count -eq 0) {
        return @()
    }

    $selectedIndexes = New-Object 'System.Collections.Generic.List[int]'
    $seenIndexes = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($row in $selectedRows) {
        $parts = $row -split "`t", 2
        if ($parts.Count -eq 0) {
            continue
        }

        $parsedIndex = 0
        if (-not [int]::TryParse($parts[0], [ref]$parsedIndex)) {
            continue
        }

        if ($seenIndexes.Add($parsedIndex)) {
            $selectedIndexes.Add($parsedIndex) | Out-Null
        }
    }

    return $selectedIndexes.ToArray()
}

<#
.SYNOPSIS
    从候选项列表中执行交互选择，并返回原始项本身。

.DESCRIPTION
    优先使用 `fzf` 提供交互选择体验；当环境中未安装 `fzf` 时，自动降级到文本编号选择。
    函数支持字符串列表与对象列表输入。对象列表必须显式提供显示逻辑，以避免公共模块
    隐式猜测领域字段。默认单选，启用 `-AllowMultiple` 后返回原始项数组。

.PARAMETER Items
    要选择的候选项列表。可以是字符串数组，也可以是对象数组。

.PARAMETER DisplayProperty
    对象候选项的显示属性名。仅对象输入需要指定，且不能与 `DisplayScriptBlock` 同时使用。

.PARAMETER DisplayScriptBlock
    对象候选项的显示脚本块。脚本块中的 `$_` 表示当前候选项。

.PARAMETER AllowMultiple
    启用多选模式。多选模式下返回原始项数组；取消时返回空数组。

.PARAMETER Prompt
    交互提示文案，同时用于 `fzf` 的 prompt 与文本降级的输入提示。

.PARAMETER Header
    展示在选择器顶部或文本列表前的说明文案。

.OUTPUTS
    单选时返回单个原始项或 `$null`；多选时返回原始项数组。

.EXAMPLE
    Select-InteractiveItem -Items @('alpha', 'beta')

.EXAMPLE
    Select-InteractiveItem -Items $catalog -DisplayProperty Name -Prompt 'Benchmark > '

.EXAMPLE
    Select-InteractiveItem -Items $items -DisplayScriptBlock { "{0} ({1})" -f $_.Name, $_.Path } -AllowMultiple
#>
function Select-InteractiveItem {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Items,
        [string]$DisplayProperty,
        [scriptblock]$DisplayScriptBlock,
        [switch]$AllowMultiple,
        [string]$Prompt = 'Select > ',
        [string]$Header
    )

    if (-not [string]::IsNullOrWhiteSpace($DisplayProperty) -and $null -ne $DisplayScriptBlock) {
        throw '-DisplayProperty 与 -DisplayScriptBlock 不能同时指定。'
    }

    $normalizedItems = @($Items)
    if ($normalizedItems.Count -eq 0) {
        if ($AllowMultiple) {
            return @()
        }

        return $null
    }

    $entryParams = @{
        Items = $normalizedItems
    }
    if (-not [string]::IsNullOrWhiteSpace($DisplayProperty)) {
        $entryParams.DisplayProperty = $DisplayProperty
    }
    if ($null -ne $DisplayScriptBlock) {
        $entryParams.DisplayScriptBlock = $DisplayScriptBlock
    }

    $entries = New-InteractiveSelectionEntries @entryParams

    $selectedIndexes = if (Test-InteractiveSelectionFzfAvailable) {
        Invoke-InteractiveSelectionByFzf `
            -Entries $entries `
            -Prompt $Prompt `
            -Header $Header `
            -AllowMultiple:$AllowMultiple
    }
    else {
        Write-Verbose ("未检测到 fzf，自动降级到文本编号选择。{0}" -f (Get-InteractiveSelectionFzfInstallHint))
        Invoke-InteractiveSelectionByText `
            -Entries $entries `
            -Prompt $Prompt `
            -Header $Header `
            -AllowMultiple:$AllowMultiple
    }

    $selectedItems = foreach ($selectedIndex in @($selectedIndexes)) {
        $entries[$selectedIndex].Item
    }

    if ($AllowMultiple) {
        return @($selectedItems)
    }

    if (@($selectedItems).Count -eq 0) {
        return $null
    }

    return @($selectedItems)[0]
}

Export-ModuleMember -Function Select-InteractiveItem
