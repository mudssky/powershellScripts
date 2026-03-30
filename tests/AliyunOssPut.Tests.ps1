Set-StrictMode -Version Latest

BeforeAll {
    $script:AliyunOssPutScriptPath = Join-Path $PSScriptRoot '..' 'scripts' 'pwsh' 'network' 'aliyun-oss-put.ps1'
    $script:OssModulePath = Join-Path $PSScriptRoot '..' 'psutils' 'modules' 'oss.psm1'
    $script:OriginalSkipMainFlag = [Environment]::GetEnvironmentVariable('PWSH_TEST_SKIP_ALIYUN_OSS_PUT_MAIN', 'Process')
    $env:PWSH_TEST_SKIP_ALIYUN_OSS_PUT_MAIN = '1'
    Import-Module $script:OssModulePath -Force

    . $script:AliyunOssPutScriptPath `
        -FilePath 'placeholder.txt' `
        -ObjectKey 'placeholder.txt' `
        -Bucket 'placeholder-bucket' `
        -Region 'cn-hangzhou' `
        -AccessKeyId 'test-ak' `
        -AccessKeySecret 'test-sk'
}

AfterAll {
    if ($null -eq $script:OriginalSkipMainFlag) {
        Remove-Item Env:\PWSH_TEST_SKIP_ALIYUN_OSS_PUT_MAIN -ErrorAction SilentlyContinue
    }
    else {
        $env:PWSH_TEST_SKIP_ALIYUN_OSS_PUT_MAIN = $script:OriginalSkipMainFlag
    }

    Remove-Module oss -Force -ErrorAction SilentlyContinue

    foreach ($functionName in @(
            'Import-AliyunOssPutDependencies',
            'Write-AliyunOssPutSummary',
            'Invoke-AliyunOssPutCommand'
        )) {
        Remove-Item -Path ("Function:\{0}" -f $functionName) -ErrorAction SilentlyContinue
    }
}

Describe 'Invoke-AliyunOssPutCommand helper routing' {
    BeforeEach {
        Mock Import-AliyunOssPutDependencies { }
        Mock Write-AliyunOssPutSummary { }
        Mock New-OssContext {
            $resolvedHost = if ($PSBoundParameters.ContainsKey('Host') -and -not [string]::IsNullOrWhiteSpace([string]$PSBoundParameters['Host'])) {
                [string]$PSBoundParameters['Host']
            }
            else {
                "$Bucket.oss-$Region.aliyuncs.com"
            }

            return [PSCustomObject]@{
                Bucket = $Bucket
                Region = $Region
                Host   = $resolvedHost
            }
        }
        Mock Publish-OssObject { throw '当前测试应覆盖该 mock。' }
        Mock Publish-OssDirectory { throw '当前测试应覆盖该 mock。' }
    }

    It '单文件参数集会路由到 Publish-OssObject' {
        Mock Publish-OssObject {
            return [PSCustomObject]@{
                ObjectKey  = $ObjectKey
                RequestId  = 'req-file'
                StatusCode = 200
            }
        }

        $result = Invoke-AliyunOssPutCommand `
            -FilePath (Join-Path $TestDrive 'demo.txt') `
            -ObjectKey 'assets/demo.txt' `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk' `
            -Host 'static.example.com'

        $result.ObjectKey | Should -Be 'assets/demo.txt'
        Should -Invoke Publish-OssObject -Times 1 -Exactly
        Should -Invoke Publish-OssDirectory -Times 0 -Exactly
    }

    It '目录参数集会路由到 Publish-OssDirectory' {
        Mock Publish-OssDirectory {
            return [PSCustomObject]@{
                Prefix       = $Prefix
                UploadedCount = 2
                FileCount     = 2
            }
        }

        $directoryPath = Join-Path $TestDrive 'assets'
        New-Item -ItemType Directory -Path $directoryPath -Force | Out-Null

        $result = Invoke-AliyunOssPutCommand `
            -DirectoryPath $directoryPath `
            -Prefix 'site-assets' `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'

        $result.Prefix | Should -Be 'site-assets'
        Should -Invoke Publish-OssDirectory -Times 1 -Exactly
        Should -Invoke Publish-OssObject -Times 0 -Exactly
    }
}

Describe 'aliyun-oss-put.ps1 script smoke path' {
    It '直接执行脚本并传入 WhatIf 时不会触发真实网络上传' {
        $filePath = Join-Path $TestDrive 'smoke.txt'
        Set-Content -Path $filePath -Value 'preview' -Encoding utf8

        {
            & $script:AliyunOssPutScriptPath `
                -FilePath $filePath `
                -ObjectKey 'smoke.txt' `
                -Bucket 'examplebucket' `
                -Region 'cn-hangzhou' `
                -AccessKeyId 'test-ak' `
                -AccessKeySecret 'test-sk' `
                -WhatIf
        } | Should -Not -Throw
    }
}
