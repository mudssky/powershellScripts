
<#
.SYNOPSIS
    web.psm1 模块的单元测试

.DESCRIPTION
    测试 New-WebShortcut 函数的功能，包括 HTML 生成、快捷方式创建等。
#>

BeforeAll {
    $ModulePath = "$PSScriptRoot\..\modules\web.psm1"
    Import-Module $ModulePath -Force
    
    $TestDir = Join-Path $PSScriptRoot "TestOutput"
    if (Test-Path $TestDir) { Remove-Item $TestDir -Recurse -Force }
    New-Item -ItemType Directory -Path $TestDir | Out-Null
}

AfterAll {
    if (Test-Path $TestDir) { Remove-Item $TestDir -Recurse -Force }
}

Describe "New-WebShortcut Tests" {
    
    Context "HTML Shortcut Creation" {
        It "Should create an HTML file with correct content" {
            $Name = "TestHtml"
            $Url = "https://example.com"
            $SavePath = Join-Path $TestDir "$Name.html"
            
            New-WebShortcut -Url $Url -Name $Name -Type Html -SaveDir $TestDir
            
            Test-Path $SavePath | Should -Be $true
            
            $Content = Get-Content $SavePath -Raw
            $Content | Should -Match "Redirecting..."
            $Content | Should -Match "You are being redirected to"
            $Content | Should -Match $Url
            $Content | Should -Match "window.location.href"
        }
    }

    Context "Name Resolution" {
        It "Should auto-resolve name from URL when Name is missing" {
            # Mock Invoke-WebRequest to return a fake title
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    Content = "<html><head><title>AutoResolvedTitle</title></head><body></body></html>"
                }
            } -ModuleName web

            $Url = "https://autoresolve.com"
            $ExpectedFile = Join-Path $TestDir "AutoResolvedTitle.html"
            
            # Use Type Html to avoid OS specific shortcut creation issues during this test
            New-WebShortcut -Url $Url -Type Html -SaveDir $TestDir
            
            Test-Path $ExpectedFile | Should -Be $true
        }

        It "Should fallback to domain if title fetch fails" {
            Mock Invoke-WebRequest {
                throw "Network Error"
            } -ModuleName web

            $Url = "https://fallback-domain.com/some/path"
            $ExpectedFile = Join-Path $TestDir "fallback-domain.com.html"
            
            New-WebShortcut -Url $Url -Type Html -SaveDir $TestDir
            
            Test-Path $ExpectedFile | Should -Be $true
        }
    }

    if ($IsWindows) {
        Context "Windows Shortcut Creation" {
            It "Should create a .lnk file on Windows" {
                $Name = "WinShortcut"
                $Url = "https://windows.com"
                $SavePath = Join-Path $TestDir "$Name.lnk"
                
                # Mock Save-Icon to avoid network call, but it's internal.
                # We can mock New-Object System.Net.WebClient? 
                # Or just let it fail (it will warn) and continue.
                
                Mock Save-Icon { return $false } -ModuleName web

                New-WebShortcut -Url $Url -Name $Name -Type Shortcut -SaveDir $TestDir
                
                Test-Path $SavePath | Should -Be $true
                
                $WshShell = New-Object -ComObject WScript.Shell
                $Shortcut = $WshShell.CreateShortcut($SavePath)
                $Shortcut.TargetPath | Should -Match "chrome.exe" # Default is Chrome
                $Shortcut.Arguments | Should -Match $Url
            }
        }
    }
}
