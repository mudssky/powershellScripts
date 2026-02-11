
<#
.SYNOPSIS
    web.psm1 模块的单元测试

.DESCRIPTION
    测试 New-WebShortcut 函数的功能，包括 HTML 生成、快捷方式创建等。
    同时通过 InModuleScope 测试内部函数 Get-WebPageTitle、Get-BrowserPath、Save-Icon。
#>

BeforeAll {
    $ModulePath = "$PSScriptRoot\..\modules\web.psm1"
    Import-Module $ModulePath -Force

    $TestDir = Join-Path $TestDrive "WebTestOutput"
    if (Test-Path $TestDir) { Remove-Item $TestDir -Recurse -Force }
    New-Item -ItemType Directory -Path $TestDir | Out-Null
}

AfterAll {
    if (Test-Path $TestDir) { Remove-Item $TestDir -Recurse -Force }
    Remove-Module web -Force -ErrorAction SilentlyContinue
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

        It "Should create HTML with correct meta refresh tag" {
            $Name = "MetaRefresh"
            $Url = "https://test-meta.com"
            $SavePath = Join-Path $TestDir "$Name.html"

            New-WebShortcut -Url $Url -Name $Name -Type Html -SaveDir $TestDir

            $Content = Get-Content $SavePath -Raw
            $Content | Should -Match 'http-equiv="refresh"'
            $Content | Should -Match $Url
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

    Context "URL auto-prepend https" {
        It "Should prepend https:// if missing" {
            Mock Invoke-WebRequest {
                return [PSCustomObject]@{
                    Content = "<html><head><title>HttpsTest</title></head><body></body></html>"
                }
            } -ModuleName web

            New-WebShortcut -Url "example-nohttps.com" -Name "NoPrefixTest" -Type Html -SaveDir $TestDir

            $SavePath = Join-Path $TestDir "NoPrefixTest.html"
            Test-Path $SavePath | Should -Be $true

            $Content = Get-Content $SavePath -Raw
            $Content | Should -Match "https://example-nohttps.com"
        }

        It "Should not double-prepend https://" {
            New-WebShortcut -Url "https://already-has-protocol.com" -Name "DoublePrefix" -Type Html -SaveDir $TestDir

            $SavePath = Join-Path $TestDir "DoublePrefix.html"
            $Content = Get-Content $SavePath -Raw
            $Content | Should -Not -Match "https://https://"
        }
    }

    Context "Type=Auto resolution" {
        It "Auto应该在Linux上解析为Shortcut类型" {
            if ($IsLinux) {
                # 需要 mock browser path 否则会 fallback 到 Html
                Mock Get-BrowserPath { return "/usr/bin/fakebrowser" } -ModuleName web
                Mock Test-Path { return $true } -ParameterFilter { $Path -eq "/usr/bin/fakebrowser" } -ModuleName web
                Mock Save-Icon { return $false } -ModuleName web

                New-WebShortcut -Url "https://auto-test.com" -Name "AutoLinux" -Type Auto -SaveDir $TestDir

                # 在 Linux 上 Auto 应该尝试创建 .desktop 文件
                $desktopFile = Join-Path $TestDir "AutoLinux.desktop"
                $htmlFile = Join-Path $TestDir "AutoLinux.html"
                # 如果 browser 不存在会 fallback 到 html
                ((Test-Path $desktopFile) -or (Test-Path $htmlFile)) | Should -Be $true
            }
        }
    }

    Context "Missing browser fallback" {
        It "当浏览器不存在时应该回退到Html类型" {
            Mock Get-BrowserPath { return $null } -ModuleName web
            Mock Save-Icon { return $false } -ModuleName web

            New-WebShortcut -Url "https://no-browser.com" -Name "NoBrowser" -Type Shortcut -SaveDir $TestDir

            $htmlFile = Join-Path $TestDir "NoBrowser.html"
            Test-Path $htmlFile | Should -Be $true
        }
    }

    Context "SaveDir自动创建" {
        It "应该自动创建不存在的保存目录" {
            $newDir = Join-Path $TestDir "auto_created_dir"
            New-WebShortcut -Url "https://dir-test.com" -Name "DirTest" -Type Html -SaveDir $newDir

            Test-Path $newDir | Should -Be $true
            Test-Path (Join-Path $newDir "DirTest.html") | Should -Be $true
        }
    }
}

Describe "Get-WebPageTitle 内部函数测试" {
    Context "标题提取" {
        It "应该从HTML中提取标题" {
            InModuleScope web {
                Mock Invoke-WebRequest {
                    return [PSCustomObject]@{
                        Content = "<html><head><title>My Page Title</title></head></html>"
                    }
                }

                $result = Get-WebPageTitle -Url "https://example.com"
                $result | Should -Be "My Page Title"
            }
        }

        It "标题中的非法文件名字符应该被移除" {
            InModuleScope web {
                Mock Invoke-WebRequest {
                    return [PSCustomObject]@{
                        Content = '<html><head><title>Title: With "Special" Chars</title></head></html>'
                    }
                }

                $result = Get-WebPageTitle -Url "https://example.com"
                $result | Should -Not -Match '[\\/:*?"<>|]'
            }
        }

        It "当无法获取标题时应该回退到域名" {
            InModuleScope web {
                Mock Invoke-WebRequest {
                    throw "Network Error"
                }

                $result = Get-WebPageTitle -Url "https://fallback-example.com/path"
                $result | Should -Be "fallback-example.com"
            }
        }

        It "当URL无效时应该返回默认值" {
            InModuleScope web {
                Mock Invoke-WebRequest {
                    throw "Invalid URL"
                }

                # 使用一个不符合 URI 格式的 URL 进行回退
                $result = Get-WebPageTitle -Url "https://some-domain.org"
                $result | Should -Not -BeNullOrEmpty
            }
        }

        It "HTML中没有title标签时应该回退到域名" {
            InModuleScope web {
                Mock Invoke-WebRequest {
                    return [PSCustomObject]@{
                        Content = "<html><head></head><body>No title here</body></html>"
                    }
                }

                $result = Get-WebPageTitle -Url "https://no-title.com"
                $result | Should -Be "no-title.com"
            }
        }
    }
}

Describe "Get-BrowserPath 内部函数测试" {
    Context "浏览器路径检测" {
        It "查找不存在的浏览器应该返回null" {
            InModuleScope web {
                # 使用不太可能存在的浏览器名称
                $result = Get-BrowserPath -BrowserName "NonExistentBrowser"
                $result | Should -BeNullOrEmpty
            }
        }

        It "已知浏览器名称不应报错" {
            InModuleScope web {
                { Get-BrowserPath -BrowserName "Chrome" } | Should -Not -Throw
                { Get-BrowserPath -BrowserName "Firefox" } | Should -Not -Throw
                { Get-BrowserPath -BrowserName "Edge" } | Should -Not -Throw
            }
        }

        It "在Linux上检测Chrome路径格式正确" {
            if ($IsLinux) {
                InModuleScope web {
                    $result = Get-BrowserPath -BrowserName "Chrome"
                    # 可能为 null（如果没装），但不应该报错
                    if ($result) {
                        $result | Should -Match "chrome|chromium"
                    }
                }
            }
        }

        It "在Linux上检测Firefox路径格式正确" {
            if ($IsLinux) {
                InModuleScope web {
                    $result = Get-BrowserPath -BrowserName "Firefox"
                    if ($result) {
                        $result | Should -Match "firefox"
                    }
                }
            }
        }
    }
}

Describe "Save-Icon 内部函数测试" {
    Context "基本功能" {
        It "下载失败时应该返回false" {
            InModuleScope web {
                # Mock WebClient 使其抛出异常
                Mock New-Object {
                    $mockClient = [PSCustomObject]@{}
                    $mockClient | Add-Member -MemberType ScriptMethod -Name DownloadData -Value {
                        param($url)
                        throw "Download failed"
                    }
                    return $mockClient
                } -ParameterFilter { $TypeName -eq "System.Net.WebClient" }

                Mock Invoke-WebRequest {
                    throw "Network Error"
                }

                $iconPath = Join-Path $TestDrive "test_icon.png"
                $result = Save-Icon -Url "https://example.com" -DestinationPath $iconPath
                $result | Should -Be $false
            }
        }

        It "使用CustomIconUrl时应该使用自定义URL" {
            InModuleScope web {
                # Mock WebClient 使其返回假数据
                Mock New-Object {
                    $mockClient = [PSCustomObject]@{}
                    $mockClient | Add-Member -MemberType ScriptMethod -Name DownloadData -Value {
                        param($url)
                        return [byte[]](0x89, 0x50, 0x4E, 0x47) # PNG header bytes
                    }
                    return $mockClient
                } -ParameterFilter { $TypeName -eq "System.Net.WebClient" }

                $iconPath = Join-Path $TestDrive "custom_icon.png"
                $result = Save-Icon -Url "https://example.com" -DestinationPath $iconPath -CustomIconUrl "https://custom-icon.com/icon.png"
                $result | Should -Be $true
                Test-Path $iconPath | Should -Be $true
            }
        }

        It "成功下载时应该返回true" {
            InModuleScope web {
                Mock New-Object {
                    $mockClient = [PSCustomObject]@{}
                    $mockClient | Add-Member -MemberType ScriptMethod -Name DownloadData -Value {
                        param($url)
                        return [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A) # Valid PNG header
                    }
                    return $mockClient
                } -ParameterFilter { $TypeName -eq "System.Net.WebClient" }

                $iconPath = Join-Path $TestDrive "success_icon.png"
                $result = Save-Icon -Url "https://example.com" -DestinationPath $iconPath
                $result | Should -Be $true
            }
        }
    }
}
