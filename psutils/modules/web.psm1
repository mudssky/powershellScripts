
function Get-WebPageTitle {
    param([string]$Url)
    try {
        Write-Verbose "Fetching title from $Url..."
        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($Response.Content -match '<title>(.*?)</title>') {
            $Title = $matches[1].Trim()
            # Clean invalid filename chars
            return $Title -replace '[\\/:*?"<>|]', ''
        }
    }
    catch {
        Write-Verbose "Failed to fetch title: $_"
    }
    
    # Fallback to domain
    try {
        $Uri = [System.Uri]$Url
        return $Uri.Host
    }
    catch {
        return "WebShortcut"
    }
}

function Get-BrowserPath {
    param([string]$BrowserName)
    
    if ($IsWindows) {
        $Paths = @{
            'Chrome'  = @(
                "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
                "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
                "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
            )
            'Edge'    = @(
                "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
                "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
            )
            'Firefox' = @(
                "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
                "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe"
            )
        }
    }
    elseif ($IsLinux) {
        $Paths = @{
            'Chrome'  = @('/usr/bin/google-chrome', '/usr/bin/google-chrome-stable', '/usr/bin/chromium-browser')
            'Edge'    = @('/usr/bin/microsoft-edge', '/usr/bin/microsoft-edge-stable')
            'Firefox' = @('/usr/bin/firefox')
        }
    }
    elseif ($IsMacOS) {
        # macOS apps are directories, but executable is inside
        $Paths = @{
            'Chrome'  = @('/Applications/Google Chrome.app/Contents/MacOS/Google Chrome')
            'Edge'    = @('/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge')
            'Firefox' = @('/Applications/Firefox.app/Contents/MacOS/firefox')
        }
    }

    if ($Paths.ContainsKey($BrowserName)) {
        foreach ($Path in $Paths[$BrowserName]) {
            if (Test-Path $Path) { return $Path }
        }
    }
    
    return $null
}

function Save-Icon {
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$CustomIconUrl
    )
    
    try {
        if (-not $CustomIconUrl) {
            $Uri = [System.Uri]$Url
            $Domain = $Uri.Host
            # size=128 for high res
            $DownloadUrl = "https://www.google.com/s2/favicons?sz=128&domain_url=$Domain"
        }
        else {
            $DownloadUrl = $CustomIconUrl
        }

        Write-Verbose "Downloading icon from $DownloadUrl..."
        
        $WebClient = New-Object System.Net.WebClient
        try {
            $Bytes = $WebClient.DownloadData($DownloadUrl)
        }
        catch {
            # Only try fallback if we were using the default Google service
            if ([string]::IsNullOrEmpty($CustomIconUrl)) {
                Write-Verbose "Google favicon service failed: $_. Trying direct favicon.ico..."
                $Uri = [System.Uri]$Url
                $FallbackUrl = "$($Uri.Scheme)://$($Uri.Host)/favicon.ico"
                try {
                    Write-Verbose "Downloading fallback icon from $FallbackUrl..."
                    $Bytes = $WebClient.DownloadData($FallbackUrl)
                }
                catch {
                    Write-Verbose "Fallback to favicon.ico failed: $_. Trying to parse HTML for icon link..."
                    try {
                        # Try to fetch HTML and parse <link rel="icon">
                        $Response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
                        $Html = $Response.Content
                        $IconHref = $null
                        
                        # Find all link tags, then check attributes
                        $LinkTags = [regex]::Matches($Html, '(?i)<link\s+[^>]+>')
                        foreach ($Tag in $LinkTags) {
                            $TagStr = $Tag.Value
                            if ($TagStr -match '(?i)rel=["''](?:shortcut\s+)?icon["'']') {
                                if ($TagStr -match '(?i)href=["'']([^"'']+)["'']') {
                                    $IconHref = $matches[1]
                                    break
                                }
                            }
                        }

                        if ($IconHref) {
                            # Handle relative URLs
                            if ($IconHref -notmatch '^https?://') {
                                $BaseUri = [System.Uri]$Url
                                if ($IconHref.StartsWith('//')) {
                                    $IconHref = "$($BaseUri.Scheme):$IconHref"
                                }
                                else {
                                    $IconHref = [System.Uri]::new($BaseUri, $IconHref).AbsoluteUri
                                }
                            }
                            
                            Write-Verbose "Found icon in HTML: $IconHref"
                            $Bytes = $WebClient.DownloadData($IconHref)
                        }
                        else {
                            throw "No icon link found in HTML."
                        }
                    }
                    catch {
                        Write-Verbose "HTML parsing fallback failed: $_"
                        Write-Warning "Could not download icon (Google service, favicon.ico, and HTML parsing failed). Shortcut will be created without custom icon."
                        return $false
                    }
                }
            }
            else {
                throw $_
            }
        }
        
        # Check if we need conversion (Windows LNK needs .ico)
        if ($IsWindows -and $DestinationPath.EndsWith('.ico')) {
            $ConversionSuccess = $false
            
            # Try ffmpeg first
            if (Get-Command ffmpeg -ErrorAction SilentlyContinue) {
                try {
                    Write-Verbose "Using ffmpeg for icon conversion..."
                    # Create temp file with .png extension to help ffmpeg (Google favicons are often png)
                    $TempFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString() + ".png")
                    [System.IO.File]::WriteAllBytes($TempFile, $Bytes)
                    
                    # -y: overwrite
                    $FfmpegArgs = "-i `"$TempFile`" -y `"$DestinationPath`""
                    Write-Verbose "Executing: ffmpeg $FfmpegArgs"
                    
                    $Process = Start-Process -FilePath "ffmpeg" -ArgumentList $FfmpegArgs -NoNewWindow -PassThru -Wait
                    
                    if ($Process.ExitCode -eq 0) {
                        $ConversionSuccess = $true
                        Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
                    }
                    else {
                        Write-Warning "ffmpeg exited with code $($Process.ExitCode). Falling back to System.Drawing."
                        Remove-Item $TempFile -Force -ErrorAction SilentlyContinue
                    }
                }
                catch {
                    Write-Warning "ffmpeg failed: $_. Falling back to System.Drawing."
                }
            }
            
            if (-not $ConversionSuccess) {
                try {
                    Add-Type -AssemblyName System.Drawing
                    
                    # Define DestroyIcon if not already defined
                    if (-not ([System.Management.Automation.PSTypeName]'PSUtils.Web.NativeMethods').Type) {
                        $Source = @"
using System;
using System.Runtime.InteropServices;
namespace PSUtils.Web {
    public class NativeMethods {
        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern bool DestroyIcon(IntPtr handle);
    }
}
"@
                        Add-Type -TypeDefinition $Source -Language CSharp
                    }

                    $Stream = New-Object System.IO.MemoryStream(, $Bytes)
                    $Bitmap = [System.Drawing.Bitmap]::FromStream($Stream)
                    
                    $FileStream = [System.IO.File]::Open($DestinationPath, "OpenOrCreate")
                    $IconHandle = $Bitmap.GetHicon()
                    $Icon = [System.Drawing.Icon]::FromHandle($IconHandle)
                    $Icon.Save($FileStream)
                    $FileStream.Close()
                    
                    # Cleanup
                    [PSUtils.Web.NativeMethods]::DestroyIcon($IconHandle) | Out-Null
                    $Icon.Dispose()
                    $Bitmap.Dispose()
                    $Stream.Dispose()
                }
                catch {
                    Write-Warning "ICO conversion failed, saving as raw file. ($($_.Exception.Message))"
                    [System.IO.File]::WriteAllBytes($DestinationPath, $Bytes)
                }
            }
        }
        else {
            # Just save bytes (png/jpg/ico)
            [System.IO.File]::WriteAllBytes($DestinationPath, $Bytes)
        }
        
        return $true
    }
    catch {
        Write-Warning "Icon download failed: $_"
        return $false
    }
}

<#
.SYNOPSIS
    创建一个指向特定 URL 的 Web 快捷方式或 HTML 重定向文件。

.DESCRIPTION
    此函数用于创建一个桌面快捷方式，用于打开指定的 URL。
    支持创建指向特定浏览器的本机快捷方式（Windows 上的 .lnk，Linux 上的 .desktop）。
    也支持创建一个跨平台的 .html 文件，该文件会自动重定向到目标 URL。
    
    功能特点：
    - 如果未提供名称，则自动获取页面标题。
    - 下载并处理 favicon/icon。
    - 支持多种浏览器（Chrome、Edge、Firefox）。
    - 跨平台 HTML 回退支持。

.PARAMETER Url
    要打开的 URL。必须参数。

.PARAMETER Name
    快捷方式的名称。可选。如果省略，将尝试获取页面标题。

.PARAMETER Browser
    用于快捷方式的浏览器。默认为 'Chrome'。
    选项：Chrome, Edge, Firefox, Default (系统默认 - 仅适用于 HTML/Open)。

.PARAMETER Type
    要创建的快捷方式类型。
    'Auto': Windows 上创建 .lnk，Linux 上创建 .desktop，macOS 或其他失败时创建 .html。
    'Shortcut': 强制创建本机快捷方式 (.lnk/.desktop)。
    'Html': 创建 HTML 重定向文件。

.PARAMETER IconUrl
    自定义图标 URL。如果省略，将尝试从 Google 服务获取 favicon。

.PARAMETER SaveDir
    保存快捷方式的目录。默认为桌面。

.EXAMPLE
    New-WebShortcut -Url "https://www.bilibili.com"
    在桌面上为 Bilibili 创建一个 Chrome 快捷方式。

.EXAMPLE
    New-WebShortcut -Url "https://github.com" -Browser Firefox
    为 GitHub 创建一个 Firefox 快捷方式。

.EXAMPLE
    New-WebShortcut -Url "https://google.com" -Type Html
    创建一个 HTML 重定向文件。
#>
function New-WebShortcut {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Url,

        [Parameter(Position = 1)]
        [string]$Name,

        [Parameter()]
        [ValidateSet('Chrome', 'Edge', 'Firefox', 'Default')]
        [string]$Browser = 'Chrome',

        [Parameter()]
        [ValidateSet('Auto', 'Shortcut', 'Html')]
        [string]$Type = 'Auto',

        [Parameter()]
        [string]$IconUrl,

        [Parameter()]
        [string]$SaveDir = "$([Environment]::GetFolderPath('Desktop'))"
    )

    # 0. Check Clipboard if Url is empty
    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-Verbose "Url not provided, checking clipboard..."
        try {
            $ClipboardContent = Get-Clipboard | Select-Object -First 1
            if (-not [string]::IsNullOrWhiteSpace($ClipboardContent)) {
                $ClipboardContent = $ClipboardContent.Trim()
                $UriResult = $null
                # Basic validation for common schemes
                if ([System.Uri]::TryCreate($ClipboardContent, [System.UriKind]::Absolute, [ref]$UriResult) -and 
                    ($UriResult.Scheme -match '^https?$')) {
                    $Url = $ClipboardContent
                    Write-Host "Using URL from clipboard: $Url" -ForegroundColor Cyan
                }
                else {
                    Write-Verbose "Clipboard content '$ClipboardContent' is not a valid HTTP/HTTPS URL."
                }
            }
        }
        catch {
            Write-Verbose "Failed to get clipboard content: $_"
        }
        
        if ([string]::IsNullOrWhiteSpace($Url)) {
            throw "URL parameter is missing and no valid URL found in clipboard."
        }
    }

    # 0.1 Ensure URL has protocol
    if ($Url -notmatch '^http(s)?://') {
        $Url = "https://$Url"
    }

    # 1. Determine Name
    if ([string]::IsNullOrWhiteSpace($Name)) {
        Write-Verbose "Resolving name..."
        $Name = Get-WebPageTitle -Url $Url
        Write-Verbose "Resolved Name: $Name"
    }

    # 2. Determine Shortcut Type
    if ($Type -eq 'Auto') {
        if ($IsWindows) { $Type = 'Shortcut' }
        elseif ($IsLinux) { $Type = 'Shortcut' }
        else { 
            Write-Warning "Native shortcuts not fully supported on this platform (macOS/Other). Falling back to HTML."
            $Type = 'Html' 
        } 
    }

    # 3. Prepare Paths
    if (-not (Test-Path $SaveDir)) {
        New-Item -ItemType Directory -Path $SaveDir -Force | Out-Null
    }

    $IconDir = Join-Path $SaveDir "Icons"
    if (-not (Test-Path $IconDir)) { New-Item -ItemType Directory -Path $IconDir -Force | Out-Null }

    # 4. Process Icon (needed for Shortcuts)
    $IconPath = $null
    if ($Type -eq 'Shortcut') {
        $IconExt = if ($IsWindows) { ".ico" } else { ".png" }
        $IconPath = Join-Path $IconDir "$Name$IconExt"
        
        $IconSaved = Save-Icon -Url $Url -DestinationPath $IconPath -CustomIconUrl $IconUrl
        if (-not $IconSaved) {
            $IconPath = $null # Fallback to browser icon
        }
    }

    # 5. Create Output
    try {
        if ($Type -eq 'Shortcut') {
            $BrowserExe = Get-BrowserPath -BrowserName $Browser
            
            if (-not $BrowserExe) {
                Write-Warning "Browser '$Browser' not found. Falling back to HTML shortcut."
                $Type = 'Html'
            }
            else {
                if ($IsWindows) {
                    $WshShell = New-Object -ComObject WScript.Shell
                    $ShortcutFile = Join-Path $SaveDir "$Name.lnk"
                    $Shortcut = $WshShell.CreateShortcut($ShortcutFile)
                    $Shortcut.TargetPath = $BrowserExe
                    $Shortcut.Arguments = "$Url"
                    if ($IconPath) { $Shortcut.IconLocation = $IconPath }
                    $Shortcut.Description = "Created by PowerShell"
                    $Shortcut.Save()
                    Write-Verbose "Shortcut created: $ShortcutFile"
                }
                elseif ($IsLinux) {
                    $DesktopFile = Join-Path $SaveDir "$Name.desktop"
                    $Content = @"
[Desktop Entry]
Version=1.0
Type=Application
Name=$Name
Comment=Open $Url in $Browser
Exec="$BrowserExe" "$Url"
Icon=$($IconPath -replace '\\', '/')
Terminal=false
StartupNotify=true
Categories=Network;WebBrowser;
"@
                    Set-Content -Path $DesktopFile -Value $Content -Encoding UTF8
                    chmod +x $DesktopFile
                    Write-Verbose "Desktop entry created: $DesktopFile"
                }
                else {
                    Write-Warning "Native shortcuts not fully supported on this platform. Falling back to HTML."
                    $Type = 'Html'
                }
            }
        }

        if ($Type -eq 'Html') {
            $HtmlFile = Join-Path $SaveDir "$Name.html"
            $HtmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="0; url=$Url" />
    <title>$Name</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
            background-color: #f0f2f5;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            color: #333;
        }
        .container {
            text-align: center;
            background: white;
            padding: 2rem;
            border-radius: 8px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            max-width: 400px;
            width: 90%;
        }
        h1 {
            font-size: 1.2rem;
            margin-bottom: 1rem;
            color: #1a73e8;
        }
        p {
            margin-bottom: 1.5rem;
            color: #5f6368;
        }
        a {
            color: #1a73e8;
            text-decoration: none;
            font-weight: 500;
        }
        a:hover {
            text-decoration: underline;
        }
        .loader {
            border: 3px solid #f3f3f3;
            border-top: 3px solid #1a73e8;
            border-radius: 50%;
            width: 24px;
            height: 24px;
            animation: spin 1s linear infinite;
            margin: 0 auto 1rem;
        }
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="loader"></div>
        <h1>Redirecting...</h1>
        <p>You are being redirected to<br><strong>$Name</strong></p>
        <p><small>If you are not redirected automatically, <a href="$Url">click here</a>.</small></p>
    </div>
    <script>
        setTimeout(function() {
            window.location.href = "$Url";
        }, 500); // Small delay to show UI if instant redirect fails
    </script>
</body>
</html>
"@
            try {
                [System.IO.File]::WriteAllText($HtmlFile, $HtmlContent, [System.Text.Encoding]::UTF8)
                Write-Verbose "HTML shortcut created: $HtmlFile"
            }
            catch {
                Write-Error "Failed to write HTML file: $_"
                throw
            }
        }
    }
    catch {
        Write-Error "Failed to create shortcut: $_"
        throw
    }
}
