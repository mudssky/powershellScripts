#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Claude Code Agent Skill Manager (CSM)
    管理本地开发 Skill (skills-dev) 与全局配置 (.claude/skills) 的同步、打包与监控。

.DESCRIPTION
    此脚本提供了一个交互式菜单，用于：
    1. 查看 Skill 状态 (已安装/未安装)
    2. 安装/更新 Skill (Copy 模式)
    3. 开启 Watch 模式 (实时同步)
    4. 打包 Skill (Zip 导出)
    5. 搜索 Skill

.NOTES
    Author: Trae AI
    Date: 2026-01-09
    Requires: PowerShell 7+
#>

# -----------------------------------------------------------------------------
# Entry Point Parameters
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet("Install", "Uninstall", "Watch", "Export", "List")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$SkillName
)

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
$Script:RootPath = $PSScriptRoot
$Script:SourceDir = Join-Path $Script:RootPath "skills-dev"
$Script:GlobalClaudeDir = Join-Path $Script:RootPath ".claude"
$Script:TargetDir = Join-Path $Script:GlobalClaudeDir "skills"
$Script:DistDir = Join-Path $Script:RootPath "dist"

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------

function Write-Color {
    param(
        [string]$Text,
        [ConsoleColor]$Color = "White",
        [switch]$NoNewLine
    )
    Write-Host $Text -ForegroundColor $Color -NoNewline:$NoNewLine
}

function Write-Info { param([string]$Msg) Write-Host "[INFO] $Msg" -ForegroundColor Cyan }
function Write-Success { param([string]$Msg) Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn { param([string]$Msg) Write-Host "[WARN] $Msg" -ForegroundColor Yellow }
function Write-ErrorMsg { param([string]$Msg) Write-Host "[ERROR] $Msg" -ForegroundColor Red }

function Get-InteractiveChoice {
    param(
        [string]$Title,
        [Array]$Options, # Array of [PSCustomObject] with Label and Value
        [string]$Placeholder = "Type to filter..."
    )

    $SelectedIndex = 0
    $Filter = ""
    $CursorTop = [Console]::CursorTop
    $LastDisplayCount = 0

    while ($true) {
        # Filter options
        $FilteredOptions = if ([string]::IsNullOrWhiteSpace($Filter)) {
            $Options
        }
        else {
            $Options | Where-Object { $_.Label -match [regex]::Escape($Filter) }
        }

        # Reset index if out of bounds
        if ($SelectedIndex -ge $FilteredOptions.Count) { $SelectedIndex = [Math]::Max(0, $FilteredOptions.Count - 1) }

        # Render Logic with Safety Check
        try {
            $BufferHeight = [Console]::BufferHeight
            # 如果预计渲染范围超出缓冲区，先清屏
            if ($CursorTop + 12 -ge $BufferHeight) {
                Clear-Host
                $CursorTop = 0
            }
            [Console]::SetCursorPosition(0, $CursorTop)
        }
        catch {
            Clear-Host
            $CursorTop = 0
        }

        Write-Color "$Title" "Yellow"
        Write-Color "  (Filter: " "Gray" -NoNewLine
        Write-Color "$Filter" "Cyan" -NoNewLine
        Write-Color "_)    " "Gray" # 额外的空格清除旧字符
        
        $DisplayCount = 10
        for ($i = 0; $i -lt $DisplayCount; $i++) {
            $TargetLine = $CursorTop + 2 + $i
            if ($TargetLine -ge [Console]::BufferHeight) { break }
            
            [Console]::SetCursorPosition(0, $TargetLine)
            if ($i -lt $FilteredOptions.Count) {
                $Opt = $FilteredOptions[$i]
                if ($i -eq $SelectedIndex) {
                    Write-Color "> " "Cyan" -NoNewLine
                    Write-Color "$($Opt.Label.PadRight([Console]::WindowWidth - 5))" "White"
                }
                else {
                    Write-Color "  $($Opt.Label.PadRight([Console]::WindowWidth - 5))" "Gray"
                }
            }
            else {
                Write-Host (" " * ([Console]::WindowWidth - 1)) # Clear line
            }
        }

        # Handle input
        $Key = [Console]::ReadKey($true)
        switch ($Key.Key) {
            "UpArrow" { $SelectedIndex = ($SelectedIndex - 1 + $FilteredOptions.Count) % [Math]::Max(1, $FilteredOptions.Count) }
            "DownArrow" { $SelectedIndex = ($SelectedIndex + 1) % [Math]::Max(1, $FilteredOptions.Count) }
            "Enter" {
                if ($FilteredOptions.Count -gt 0) {
                    [Console]::SetCursorPosition(0, [Math]::Min($CursorTop + $DisplayCount + 2, [Console]::BufferHeight - 1))
                    return $FilteredOptions[$SelectedIndex].Value
                }
            }
            "Backspace" {
                if ($Filter.Length -gt 0) { $Filter = $Filter.Substring(0, $Filter.Length - 1) }
            }
            "Escape" { return $null }
            default {
                if ($Key.KeyChar -match '[\w\s\-\.]') { $Filter += $Key.KeyChar }
            }
        }
    }
}

function Ensure-Directories {
    if (-not (Test-Path $Script:SourceDir)) {
        New-Item -ItemType Directory -Path $Script:SourceDir | Out-Null
    }
    # 检查 .claude 是否存在 (可能是软链接)
    if (-not (Test-Path $Script:GlobalClaudeDir)) {
        Write-ErrorMsg "未找到 .claude 目录。请确保它已正确链接到全局配置。"
        exit 1
    }
    if (-not (Test-Path $Script:TargetDir)) {
        New-Item -ItemType Directory -Path $Script:TargetDir | Out-Null
    }
    if (-not (Test-Path $Script:DistDir)) {
        New-Item -ItemType Directory -Path $Script:DistDir | Out-Null
    }
}

function Get-SkillMetadata {
    param([string]$Path)
    $SkillFile = Join-Path $Path "SKILL.md"
    $Meta = @{
        Name        = (Split-Path $Path -Leaf)
        Description = "No description"
        Version     = "Unknown"
    }

    if (Test-Path $SkillFile) {
        # 简单解析 YAML Frontmatter
        $Content = Get-Content $SkillFile -Raw
        if ($Content -match '(?ms)^---\s*(.*?)\s*---') {
            $Yaml = $matches[1]
            if ($Yaml -match 'description:\s*(.*)') { $Meta.Description = $matches[1].Trim(" `t`n`r") }
            if ($Yaml -match 'version:\s*(.*)') { $Meta.Version = $matches[1].Trim(" `t`n`r") }
        }
    }
    return $Meta
}

function Select-SkillInteractive {
    param([string]$Title = "Select a skill")
    $Skills = Get-Skills
    if ($Skills.Count -eq 0) {
        Write-Warn "No skills found."
        return $null
    }

    $Options = $Skills | ForEach-Object {
        [PSCustomObject]@{
            Label = "$($_.Name.PadRight(20)) [$($_.Version.PadRight(8))] - $($_.Description)"
            Value = $_.Name
        }
    }

    return Get-InteractiveChoice -Title $Title -Options $Options
}

function Main-Loop {
    Ensure-Directories
    
    while ($true) {
        Show-Header
        
        $MainMenu = @(
            [PSCustomObject]@{ Label = "Install/Update Skill"; Value = "i" }
            [PSCustomObject]@{ Label = "Uninstall Skill"; Value = "u" }
            [PSCustomObject]@{ Label = "Watch Skill (Dev Mode)"; Value = "w" }
            [PSCustomObject]@{ Label = "Export/Zip Skill"; Value = "e" }
            [PSCustomObject]@{ Label = "Quit"; Value = "q" }
        )

        $Choice = Get-InteractiveChoice -Title "Main Menu" -Options $MainMenu
        
        switch ($Choice) {
            "q" { exit }
            "i" { 
                $Name = Select-SkillInteractive -Title "Select skill to INSTALL/UPDATE"
                if ($Name) { Install-Skill -Name $Name; Pause }
            }
            "u" {
                $Name = Select-SkillInteractive -Title "Select skill to UNINSTALL"
                if ($Name) { Uninstall-Skill -Name $Name; Pause }
            }
            "w" {
                $Name = Select-SkillInteractive -Title "Select skill to WATCH"
                if ($Name) { Start-Watch -Name $Name }
            }
            "e" {
                $Name = Select-SkillInteractive -Title "Select skill to EXPORT"
                if ($Name) { Export-Skill -Name $Name; Pause }
            }
            default { continue }
        }
    }
}

function Get-Skills {
    param([string]$Filter = "")
    
    $SourceSkills = Get-ChildItem -Path $Script:SourceDir -Directory
    $TargetSkills = Get-ChildItem -Path $Script:TargetDir -Directory

    $AllSkills = @{}

    foreach ($Item in $SourceSkills) {
        $Name = $Item.Name
        $AllSkills[$Name] = @{
            Name       = $Name
            SourcePath = $Item.FullName
            Installed  = $false
            Orphaned   = $false
        }
    }

    foreach ($Item in $TargetSkills) {
        $Name = $Item.Name
        if ($AllSkills.ContainsKey($Name)) {
            $AllSkills[$Name].Installed = $true
            $AllSkills[$Name].TargetPath = $Item.FullName
        }
        else {
            # Orphaned skills (only in global)
            $AllSkills[$Name] = @{
                Name       = $Name
                TargetPath = $Item.FullName
                SourcePath = $null
                Installed  = $true
                Orphaned   = $true
            }
        }
    }

    # Add Metadata and Apply Filter
    $Result = @()
    foreach ($Key in $AllSkills.Keys) {
        $Skill = $AllSkills[$Key]
        $PathToRead = if ($Skill.SourcePath) { $Skill.SourcePath } else { $Skill.TargetPath }
        $Meta = Get-SkillMetadata -Path $PathToRead
        
        $Skill.Description = $Meta.Description
        $Skill.Version = $Meta.Version

        # Filter Logic
        if ($Filter -ne "") {
            if ($Skill.Name -notmatch $Filter -and $Skill.Description -notmatch $Filter) {
                continue
            }
        }
        $Result += [PSCustomObject]$Skill
    }

    return $Result | Sort-Object Name
}

function Install-Skill {
    param([string]$Name)
    $Source = Join-Path $Script:SourceDir $Name
    $Target = Join-Path $Script:TargetDir $Name

    if (-not (Test-Path $Source)) {
        Write-ErrorMsg "Skill source not found: $Name"
        return
    }

    Write-Info "Installing $Name..."
    Copy-Item -Path $Source -Destination $Script:TargetDir -Recurse -Force
    Write-Success "Installed $Name to $Target"
}

function Uninstall-Skill {
    param([string]$Name)
    $Target = Join-Path $Script:TargetDir $Name
    if (Test-Path $Target) {
        Remove-Item -Path $Target -Recurse -Force
        Write-Success "Uninstalled $Name"
    }
    else {
        Write-Warn "$Name is not installed."
    }
}

function Export-Skill {
    param([string]$Name)
    $Source = Join-Path $Script:SourceDir $Name
    $ZipPath = Join-Path $Script:DistDir "$Name.zip"

    if (-not (Test-Path $Source)) {
        Write-ErrorMsg "Skill source not found: $Name"
        return
    }

    if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
    
    Compress-Archive -Path "$Source\*" -DestinationPath $ZipPath
    Write-Success "Exported to $ZipPath"
}

function Start-Watch {
    param([string]$Name)
    $Source = Join-Path $Script:SourceDir $Name
    $Target = Join-Path $Script:TargetDir $Name

    if (-not (Test-Path $Source)) {
        Write-ErrorMsg "Skill not found: $Name"
        return
    }

    # 初次同步
    Install-Skill -Name $Name

    Write-Info "Starting watch mode for [$Name]. Press Ctrl+C to stop."
    Write-Info "Watching: $Source"
    
    # Check for watchexec
    if (Get-Command "watchexec" -ErrorAction SilentlyContinue) {
        Write-Info "Using 'watchexec' for file monitoring..."
        # watchexec -w source -r "cp -r source target"
        $Cmd = "Copy-Item -Path '$Source' -Destination '$Script:TargetDir' -Recurse -Force; Write-Host '[Sync] Updated $Name' -ForegroundColor Green"
        # Escape quotes for shell
        $Cmd = $Cmd -replace '"', '\"'
        watchexec -w $Source --debounce 500ms -- pwsh -c "$Cmd"
    }
    else {
        Write-Info "Using PowerShell FileSystemWatcher..."
        $Watcher = New-Object System.IO.FileSystemWatcher
        $Watcher.Path = $Source
        $Watcher.IncludeSubdirectories = $true
        $Watcher.EnableRaisingEvents = $true

        $Action = {
            $Path = $Event.SourceEventArgs.FullPath
            $ChangeType = $Event.SourceEventArgs.ChangeType
            Write-Host "[Sync] $ChangeType : $Path" -ForegroundColor Cyan
            # 简单粗暴：全量覆盖
            Start-Sleep -Milliseconds 100
            Copy-Item -Path $Source -Destination $Script:TargetDir -Recurse -Force
            Write-Host "[Sync] Completed." -ForegroundColor Green
        }

        Register-ObjectEvent $Watcher "Changed" -Action $Action | Out-Null
        Register-ObjectEvent $Watcher "Created" -Action $Action | Out-Null
        Register-ObjectEvent $Watcher "Deleted" -Action $Action | Out-Null
        Register-ObjectEvent $Watcher "Renamed" -Action $Action | Out-Null

        try {
            while ($true) { Start-Sleep -Seconds 1 }
        }
        finally {
            Unregister-Event -SourceIdentifier $Watcher.Container.Name -ErrorAction SilentlyContinue
            $Watcher.Dispose()
        }
    }
}

# -----------------------------------------------------------------------------
# UI Functions
# -----------------------------------------------------------------------------

function Show-Header {
    Clear-Host
    Write-Color "============================================================" "Cyan"
    Write-Color "   Claude Skill Manager (CSM) - v1.0" "Cyan"
    Write-Color "   Source: $Script:SourceDir" "Gray"
    Write-Color "   Target: $Script:TargetDir" "Gray"
    Write-Color "============================================================" "Cyan"
    Write-Host ""
}

function Format-SkillTable {
    param($Skills)
    $Skills | Format-Table @{Label = "Status"; Expression = {
            if ($_.Orphaned) { "Orphaned" } 
            elseif ($_.Installed) { "Installed" } 
            else { "-" }
        }
    }, Name, Version, Description -AutoSize
}

# -----------------------------------------------------------------------------
# Logic Dispatch
# -----------------------------------------------------------------------------

if ($Action) {
    Ensure-Directories
    switch ($Action) {
        "Install" { 
            if (-not $SkillName) { Write-Error "SkillName is required for Install"; exit 1 }
            Install-Skill -Name $SkillName 
        }
        "Uninstall" { 
            if (-not $SkillName) { Write-Error "SkillName is required for Uninstall"; exit 1 }
            Uninstall-Skill -Name $SkillName 
        }
        "Watch" { 
            if (-not $SkillName) { Write-Error "SkillName is required for Watch"; exit 1 }
            Start-Watch -Name $SkillName 
        }
        "Export" { 
            if (-not $SkillName) { Write-Error "SkillName is required for Export"; exit 1 }
            Export-Skill -Name $SkillName 
        }
        "List" {
            $Skills = Get-Skills
            Format-SkillTable -Skills $Skills
        }
    }
}
else {
    Main-Loop
}
