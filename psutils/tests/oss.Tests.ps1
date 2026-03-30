BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'oss.psm1'
    $script:ManifestPath = Join-Path $PSScriptRoot '..' 'psutils.psd1'
    Import-Module $script:ModulePath -Force
}

Describe 'psutils oss manifest exports' {
    It 'psutils manifest 显式导出 OSS 公共函数' {
        $manifest = Import-PowerShellDataFile $script:ManifestPath
        $expectedFunctions = @(
            'New-OssContext',
            'Test-OssObject',
            'Get-OssObjectInfo',
            'Get-OssObjectList',
            'Publish-OssObject',
            'Publish-OssDirectory'
        )

        foreach ($functionName in $expectedFunctions) {
            @($manifest.FunctionsToExport) | Should -Contain $functionName
        }
    }
}

Describe 'New-OssContext' {
    It '标准 endpoint 输入会自动补齐 bucket host 并归一化 region' {
        $context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'oss-cn-hangzhou' `
            -Host 'https://oss-cn-hangzhou.aliyuncs.com/' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'

        $context.Bucket | Should -Be 'examplebucket'
        $context.Region | Should -Be 'cn-hangzhou'
        $context.Host | Should -Be 'examplebucket.oss-cn-hangzhou.aliyuncs.com'
        $context.Scheme | Should -Be 'https'
    }

    It '显式自定义域名会被保留' {
        $context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -Host 'static.example.com' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'

        $context.Host | Should -Be 'static.example.com'
    }

    It '同时指定 Endpoint 和 Host 时抛错' {
        {
            New-OssContext `
                -Bucket 'examplebucket' `
                -Region 'cn-hangzhou' `
                -Endpoint 'https://oss-cn-hangzhou.aliyuncs.com' `
                -Host 'static.example.com' `
                -AccessKeyId 'test-ak' `
                -AccessKeySecret 'test-sk'
        } | Should -Throw
    }
}

Describe 'Oss V4 signing helpers' {
    It '能够按官方示例生成稳定的 V4 签名' {
        InModuleScope oss {
            $context = New-OssContext `
                -Bucket 'examplebucket' `
                -Region 'cn-hangzhou' `
                -Host 'examplebucket.oss-cn-hangzhou.aliyuncs.com' `
                -AccessKeyId 'LTAI****************' `
                -AccessKeySecret 'yourAccessKeySecret'

            $requestTime = [System.DateTimeOffset]::ParseExact(
                '20250411T064124Z',
                'yyyyMMddTHHmmssZ',
                [System.Globalization.CultureInfo]::InvariantCulture
            )

            $details = New-OssSignedRequestDetails `
                -Method 'PUT' `
                -Context $context `
                -ObjectKey 'exampleobject' `
                -Headers ([ordered]@{
                        'Content-Disposition' = 'attachment'
                        'Content-Length'      = '3'
                        'Content-MD5'         = 'ICy5YqxZB1uWSwcVLSNLcA=='
                        'Content-Type'        = 'text/plain'
                    }) `
                -AdditionalHeaders @('content-disposition', 'content-length') `
                -PayloadHash '6352ab6b14233af72836a02b08190a493089eb9a9df988c2923cda1073287cc5' `
                -RequestTime $requestTime

            $details.CanonicalUri | Should -Be '/examplebucket/exampleobject'
            $details.CanonicalRequest | Should -Match 'content-disposition:attachment'
            $details.StringToSign | Should -Match '20250411/cn-hangzhou/oss/aliyun_v4_request'
            $details.StringToSign.Split("`n")[-1] | Should -Be (Get-OssSha256Hex -Text $details.CanonicalRequest)
            $details.Signature | Should -Match '^[0-9a-f]{64}$'
            $details.AuthorizationHeader | Should -Match 'AdditionalHeaders=content-disposition;content-length'
        }
    }
}

Describe 'Test-OssObject and Get-OssObjectInfo' {
    BeforeEach {
        $script:Context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -Host 'examplebucket.oss-cn-hangzhou.aliyuncs.com' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'
    }

    It 'Test-OssObject 在 200 时返回 true' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{ 'x-oss-request-id' = 'req-200' }
                Body                = ''
                IsSuccessStatusCode = $true
            }
        }

        $result = Test-OssObject -Context $script:Context -ObjectKey 'demo.txt'
        $result | Should -Be $true
    }

    It 'Test-OssObject 在 404 时返回 false' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 404
                ReasonPhrase        = 'Not Found'
                Headers             = @{ 'x-oss-request-id' = 'req-404' }
                Body                = '<Error><Code>NoSuchKey</Code><Message>missing</Message></Error>'
                IsSuccessStatusCode = $false
            }
        }

        $result = Test-OssObject -Context $script:Context -ObjectKey 'missing.txt'
        $result | Should -Be $false
    }

    It 'Get-OssObjectInfo 会提取基础响应头和用户元数据' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{
                    'etag'             = '"etag-value"'
                    'content-length'   = '42'
                    'content-type'     = 'text/plain'
                    'last-modified'    = 'Wed, 02 Apr 2025 16:57:01 GMT'
                    'x-oss-request-id' = 'req-200'
                    'x-oss-version-id' = 'vid-001'
                    'x-oss-meta-owner' = 'mudssky'
                }
                Body                = ''
                IsSuccessStatusCode = $true
            }
        }

        $result = Get-OssObjectInfo -Context $script:Context -ObjectKey 'demo.txt'

        $result.ObjectKey | Should -Be 'demo.txt'
        $result.ETag | Should -Be 'etag-value'
        $result.ContentLength | Should -Be 42
        $result.ContentType | Should -Be 'text/plain'
        $result.RequestId | Should -Be 'req-200'
        $result.VersionId | Should -Be 'vid-001'
        $result.Metadata.owner | Should -Be 'mudssky'
    }
}

Describe 'Get-OssObjectList' {
    BeforeEach {
        $script:Context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -Host 'examplebucket.oss-cn-hangzhou.aliyuncs.com' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'
    }

    It '会解析对象列表、公共前缀与分页令牌' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{ 'x-oss-request-id' = 'req-list' }
                Body                = @'
<ListBucketResult>
  <Name>examplebucket</Name>
  <Prefix>assets%2F</Prefix>
  <Delimiter>%2F</Delimiter>
  <MaxKeys>100</MaxKeys>
  <IsTruncated>true</IsTruncated>
  <NextContinuationToken>next-token</NextContinuationToken>
  <Contents>
    <Key>assets%2Flogo.png</Key>
    <ETag>"etag-1"</ETag>
    <Size>12</Size>
    <LastModified>2025-04-02T16:57:01.000Z</LastModified>
    <StorageClass>Standard</StorageClass>
  </Contents>
  <CommonPrefixes>
    <Prefix>assets%2Ficons%2F</Prefix>
  </CommonPrefixes>
</ListBucketResult>
'@
                IsSuccessStatusCode = $true
            }
        }

        $result = Get-OssObjectList -Context $script:Context -Prefix 'assets/' -Delimiter '/' -MaxKeys 100

        $result.RequestId | Should -Be 'req-list'
        $result.IsTruncated | Should -Be $true
        $result.NextContinuationToken | Should -Be 'next-token'
        $result.Items.Count | Should -Be 1
        $result.Items[0].Key | Should -Be 'assets/logo.png'
        $result.CommonPrefixes | Should -Contain 'assets/icons/'
    }
}

Describe 'Publish-OssObject' {
    BeforeEach {
        $script:Context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -Host 'examplebucket.oss-cn-hangzhou.aliyuncs.com' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'
    }

    It '本地文件不存在时直接失败' {
        {
            Publish-OssObject -Context $script:Context -FilePath (Join-Path $TestDrive 'missing.txt') -ObjectKey 'missing.txt'
        } | Should -Throw
    }

    It '默认检测到远端对象已存在时失败且不发送 PUT' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{ 'x-oss-request-id' = 'req-head' }
                Body                = ''
                IsSuccessStatusCode = $true
            }
        } -ParameterFilter { $RequestPlan.Method -eq 'HEAD' }

        Mock -ModuleName oss Invoke-OssHttpRequest { throw '不应进入 PUT' } -ParameterFilter { $RequestPlan.Method -eq 'PUT' }

        $filePath = Join-Path $TestDrive 'demo.txt'
        Set-Content -Path $filePath -Value 'demo' -Encoding utf8

        {
            Publish-OssObject -Context $script:Context -FilePath $filePath -ObjectKey 'demo.txt'
        } | Should -Throw '*已存在*'

        Should -Invoke Invoke-OssHttpRequest -ModuleName oss -Times 1 -ParameterFilter { $RequestPlan.Method -eq 'HEAD' }
        Should -Invoke Invoke-OssHttpRequest -ModuleName oss -Times 0 -ParameterFilter { $RequestPlan.Method -eq 'PUT' }
    }

    It '默认上传会执行 HEAD 预检查并携带 forbid-overwrite 头' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            return [PSCustomObject]@{
                StatusCode          = 404
                ReasonPhrase        = 'Not Found'
                Headers             = @{ 'x-oss-request-id' = 'req-head-miss' }
                Body                = '<Error><Code>NoSuchKey</Code></Error>'
                IsSuccessStatusCode = $false
            }
        } -ParameterFilter { $RequestPlan.Method -eq 'HEAD' }

        Mock -ModuleName oss Invoke-OssHttpRequest {
            $RequestPlan.Headers['x-oss-forbid-overwrite'] | Should -Be 'true'

            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{
                    'etag'             = '"etag-put"'
                    'x-oss-request-id' = 'req-put'
                }
                Body                = ''
                IsSuccessStatusCode = $true
            }
        } -ParameterFilter { $RequestPlan.Method -eq 'PUT' }

        $filePath = Join-Path $TestDrive 'demo.txt'
        Set-Content -Path $filePath -Value 'demo' -Encoding utf8

        $result = Publish-OssObject -Context $script:Context -FilePath $filePath -ObjectKey 'demo.txt'

        $result.ObjectKey | Should -Be 'demo.txt'
        $result.RequestId | Should -Be 'req-put'
        $result.ETag | Should -Be 'etag-put'
    }

    It 'Force 上传会跳过 HEAD 检查且不附带 forbid-overwrite 头' {
        Mock -ModuleName oss Invoke-OssHttpRequest {
            $RequestPlan.Headers.ContainsKey('x-oss-forbid-overwrite') | Should -Be $false

            return [PSCustomObject]@{
                StatusCode          = 200
                ReasonPhrase        = 'OK'
                Headers             = @{
                    'etag'             = '"etag-force"'
                    'x-oss-request-id' = 'req-force'
                }
                Body                = ''
                IsSuccessStatusCode = $true
            }
        } -ParameterFilter { $RequestPlan.Method -eq 'PUT' }

        $filePath = Join-Path $TestDrive 'force.txt'
        Set-Content -Path $filePath -Value 'force' -Encoding utf8

        $result = Publish-OssObject -Context $script:Context -FilePath $filePath -ObjectKey 'force.txt' -Force

        $result.RequestId | Should -Be 'req-force'
        Should -Invoke Invoke-OssHttpRequest -ModuleName oss -Times 0 -ParameterFilter { $RequestPlan.Method -eq 'HEAD' }
        Should -Invoke Invoke-OssHttpRequest -ModuleName oss -Times 1 -ParameterFilter { $RequestPlan.Method -eq 'PUT' }
    }

    It 'WhatIf 下不会发送网络请求' {
        Mock -ModuleName oss Invoke-OssHttpRequest { throw 'WhatIf 不应发请求' }

        $filePath = Join-Path $TestDrive 'preview.txt'
        Set-Content -Path $filePath -Value 'preview' -Encoding utf8

        Publish-OssObject -Context $script:Context -FilePath $filePath -ObjectKey 'preview.txt' -WhatIf

        Should -Invoke Invoke-OssHttpRequest -ModuleName oss -Times 0
    }
}

Describe 'Publish-OssDirectory' {
    BeforeEach {
        $script:Context = New-OssContext `
            -Bucket 'examplebucket' `
            -Region 'cn-hangzhou' `
            -Host 'examplebucket.oss-cn-hangzhou.aliyuncs.com' `
            -AccessKeyId 'test-ak' `
            -AccessKeySecret 'test-sk'
    }

    It '会将本地相对路径映射到指定 OSS 前缀' {
        $rootPath = Join-Path $TestDrive 'assets'
        $nestedPath = Join-Path $rootPath 'icons'
        New-Item -ItemType Directory -Path $nestedPath -Force | Out-Null
        Set-Content -Path (Join-Path $rootPath 'logo.png') -Value 'logo' -Encoding utf8
        Set-Content -Path (Join-Path $nestedPath 'menu.svg') -Value 'menu' -Encoding utf8

        $script:ObservedObjectKeys = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName oss Publish-OssObject {
            $script:ObservedObjectKeys.Add($ObjectKey) | Out-Null

            return [PSCustomObject]@{
                ObjectKey  = $ObjectKey
                RequestId  = 'req-dir'
                LocalPath  = $FilePath
                StatusCode = 200
            }
        }

        $result = Publish-OssDirectory -Context $script:Context -DirectoryPath $rootPath -Prefix 'site-assets'

        $result.FileCount | Should -Be 2
        $result.Results.Count | Should -Be 2
        $script:ObservedObjectKeys | Should -Contain 'site-assets/logo.png'
        $script:ObservedObjectKeys | Should -Contain 'site-assets/icons/menu.svg'
    }
}
