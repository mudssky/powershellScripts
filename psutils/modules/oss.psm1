Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-OssUtf8Bytes {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    return [System.Text.Encoding]::UTF8.GetBytes($Text)
}

function ConvertTo-OssHexString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$Bytes
    )

    return ([System.BitConverter]::ToString($Bytes)).Replace('-', '').ToLowerInvariant()
}

function Get-OssSha256Hex {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $sha256.ComputeHash((ConvertTo-OssUtf8Bytes -Text $Text))
        return ConvertTo-OssHexString -Bytes $hashBytes
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-OssHmacSha256Bytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [byte[]]$KeyBytes,
        [AllowEmptyString()]
        [string]$MessageText
    )

    $hmac = [System.Security.Cryptography.HMACSHA256]::new($KeyBytes)
    try {
        return $hmac.ComputeHash((ConvertTo-OssUtf8Bytes -Text $MessageText))
    }
    finally {
        $hmac.Dispose()
    }
}

function Get-OssContentMd5Base64 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $stream = [System.IO.File]::OpenRead($FilePath)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try {
        $hashBytes = $md5.ComputeHash($stream)
        return [System.Convert]::ToBase64String($hashBytes)
    }
    finally {
        $md5.Dispose()
        $stream.Dispose()
    }
}

function ConvertTo-OssIso8601Timestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.DateTimeOffset]$Timestamp
    )

    return $Timestamp.ToUniversalTime().ToString('yyyyMMddTHHmmssZ', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-OssRfc1123Timestamp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.DateTimeOffset]$Timestamp
    )

    return $Timestamp.ToUniversalTime().ToString('r', [System.Globalization.CultureInfo]::InvariantCulture)
}

function Normalize-OssHeaderValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return ''
    }

    return ([string]$Value).Trim() -replace '\s+', ' '
}

function Remove-OssUriDecorators {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $trimmedValue = $Value.Trim()
    $trimmedValue = $trimmedValue -replace '^https?://', ''
    $trimmedValue = $trimmedValue.TrimEnd('/')
    return $trimmedValue
}

function Resolve-OssNormalizedRegion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Region
    )

    $trimmedRegion = $Region.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedRegion)) {
        throw 'Region 不能为空。'
    }

    if ($trimmedRegion.StartsWith('oss-', [System.StringComparison]::OrdinalIgnoreCase)) {
        $trimmedRegion = $trimmedRegion.Substring(4)
    }

    return $trimmedRegion
}

function Test-OssStandardEndpointHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Host
    )

    return ($Host -match '^oss-[^.]+\.aliyuncs\.com(?:\.cn)?$')
}

function Resolve-OssHost {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Bucket,
        [Parameter(Mandatory)]
        [string]$Region,
        [string]$Endpoint,
        [string]$Host
    )

    if (-not [string]::IsNullOrWhiteSpace($Endpoint) -and -not [string]::IsNullOrWhiteSpace($Host)) {
        throw 'Endpoint 和 Host 不能同时指定。'
    }

    $rawHost = if (-not [string]::IsNullOrWhiteSpace($Host)) {
        $Host
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Endpoint)) {
        $Endpoint
    }
    else {
        "oss-$Region.aliyuncs.com"
    }

    $normalizedHost = Remove-OssUriDecorators -Value $rawHost
    if ([string]::IsNullOrWhiteSpace($normalizedHost)) {
        throw 'Host 归一化后不能为空。'
    }

    if ($normalizedHost.Contains('/')) {
        throw 'Host 或 Endpoint 不能包含路径段。'
    }

    if (Test-OssStandardEndpointHost -Host $normalizedHost) {
        return "$Bucket.$normalizedHost"
    }

    return $normalizedHost
}

function Resolve-OssObjectKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ObjectKey
    )

    $normalizedObjectKey = $ObjectKey.Trim().TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($normalizedObjectKey)) {
        throw 'ObjectKey 不能为空。'
    }

    return $normalizedObjectKey
}

function Join-OssKeySegments {
    [CmdletBinding()]
    param(
        [string[]]$Segments
    )

    $normalizedSegments = @(
        $Segments |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object {
                $_.Trim().Trim('/') -replace '\\', '/'
            } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    return ($normalizedSegments -join '/')
}

function ConvertTo-OssEncodedPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $pathSegments = $Path -split '/'
    $encodedSegments = foreach ($segment in $pathSegments) {
        [System.Uri]::EscapeDataString($segment)
    }

    return ($encodedSegments -join '/')
}

function Get-OssCanonicalUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [string]$ObjectKey
    )

    if ([string]::IsNullOrWhiteSpace($ObjectKey)) {
        return "/$($Context.Bucket)/"
    }

    $normalizedObjectKey = Resolve-OssObjectKey -ObjectKey $ObjectKey
    return "/$($Context.Bucket)/$(ConvertTo-OssEncodedPath -Path $normalizedObjectKey)"
}

function ConvertTo-OssQueryComponent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    return [System.Uri]::EscapeDataString($Value)
}

function Get-OssCanonicalQueryString {
    [CmdletBinding()]
    param(
        [hashtable]$QueryParameters
    )

    if ($null -eq $QueryParameters -or $QueryParameters.Count -eq 0) {
        return ''
    }

    $pairs = foreach ($entry in $QueryParameters.GetEnumerator()) {
        $encodedName = ConvertTo-OssQueryComponent -Value ([string]$entry.Key)
        if ($null -eq $entry.Value) {
            [PSCustomObject]@{
                SortKey = $encodedName
                Text    = $encodedName
            }
            continue
        }

        $encodedValue = ConvertTo-OssQueryComponent -Value ([string]$entry.Value)
        [PSCustomObject]@{
            SortKey = $encodedName
            Text    = "$encodedName=$encodedValue"
        }
    }

    return (($pairs | Sort-Object SortKey, Text | ForEach-Object { $_.Text }) -join '&')
}

function Get-OssSigningScope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$ShortDate
    )

    return "$ShortDate/$($Context.Region)/oss/aliyun_v4_request"
}

function Get-OssSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$ShortDate,
        [Parameter(Mandatory)]
        [string]$StringToSign
    )

    $kDate = Get-OssHmacSha256Bytes -KeyBytes (ConvertTo-OssUtf8Bytes -Text ("aliyun_v4" + $Context.AccessKeySecret)) -MessageText $ShortDate
    $kRegion = Get-OssHmacSha256Bytes -KeyBytes $kDate -MessageText $Context.Region
    $kService = Get-OssHmacSha256Bytes -KeyBytes $kRegion -MessageText 'oss'
    $kSigning = Get-OssHmacSha256Bytes -KeyBytes $kService -MessageText 'aliyun_v4_request'
    $signatureBytes = Get-OssHmacSha256Bytes -KeyBytes $kSigning -MessageText $StringToSign

    return ConvertTo-OssHexString -Bytes $signatureBytes
}

function Get-OssSignedHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Headers,
        [string[]]$AdditionalHeaders
    )

    $normalizedAdditionalHeaders = @(
        $AdditionalHeaders |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() }
    )

    $signedHeaderNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($entry in $Headers.GetEnumerator()) {
        $headerName = ([string]$entry.Key).Trim().ToLowerInvariant()
        if ($headerName.StartsWith('x-oss-', [System.StringComparison]::Ordinal)) {
            $null = $signedHeaderNames.Add($headerName)
            continue
        }

        if ($headerName -in @('content-type', 'content-md5')) {
            $null = $signedHeaderNames.Add($headerName)
            continue
        }

        if ($normalizedAdditionalHeaders -contains $headerName) {
            $null = $signedHeaderNames.Add($headerName)
        }
    }

    return @($signedHeaderNames | Sort-Object)
}

function Get-OssCanonicalHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Headers,
        [string[]]$AdditionalHeaders
    )

    $lines = foreach ($headerName in (Get-OssSignedHeaders -Headers $Headers -AdditionalHeaders $AdditionalHeaders)) {
        $matchingEntry = $Headers.GetEnumerator() | Where-Object { $_.Key -ieq $headerName } | Select-Object -First 1
        if ($null -eq $matchingEntry) {
            continue
        }

        '{0}:{1}' -f $headerName, (Normalize-OssHeaderValue -Value $matchingEntry.Value)
    }

    if ($lines.Count -eq 0) {
        return ''
    }

    return (($lines -join "`n") + "`n")
}

function Get-OssAdditionalHeadersValue {
    [CmdletBinding()]
    param(
        [string[]]$AdditionalHeaders
    )

    $normalizedHeaders = @(
        $AdditionalHeaders |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().ToLowerInvariant() } |
            Sort-Object -Unique
    )

    return ($normalizedHeaders -join ';')
}

function New-OssSignedRequestDetails {
    <#
    .SYNOPSIS
        生成单个 OSS 请求的签名与请求头细节。

    .DESCRIPTION
        此函数统一构造对象级或 bucket 级 OSS 请求所需的 canonical request、
        string-to-sign、Authorization 头和最终请求 URL。
        设计意图：
        - 把签名逻辑与真实网络发送分离，便于在 Pester 中稳定断言。
        - 让 HEAD / GET / PUT 复用同一套签名流程，减少重复实现。

    .PARAMETER Method
        请求方法，例如 GET、HEAD、PUT。

    .PARAMETER Context
        由 `New-OssContext` 返回的配置对象。

    .PARAMETER ObjectKey
        对象键。若为空，则表示 bucket 级操作。

    .PARAMETER Headers
        参与请求的原始头集合。函数会自动补齐 `x-oss-*` 和 `Authorization`。

    .PARAMETER QueryParameters
        查询参数哈希表。

    .PARAMETER AdditionalHeaders
        需要写入 `Authorization` 的 AdditionalHeaders 头名列表。

    .PARAMETER RequestTime
        用于签名的请求时间，默认使用当前 UTC 时间。

    .OUTPUTS
        PSCustomObject
        返回请求 URL、规范化字符串、签名和最终请求头。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'HEAD', 'PUT')]
        [string]$Method,
        [Parameter(Mandatory)]
        [psobject]$Context,
        [string]$ObjectKey,
        [hashtable]$Headers,
        [hashtable]$QueryParameters,
        [string[]]$AdditionalHeaders,
        [string]$PayloadHash = 'UNSIGNED-PAYLOAD',
        [System.DateTimeOffset]$RequestTime = [System.DateTimeOffset]::UtcNow
    )

    $requestHeaders = @{}
    if ($Headers) {
        foreach ($entry in $Headers.GetEnumerator()) {
            $requestHeaders[([string]$entry.Key)] = [string]$entry.Value
        }
    }

    $iso8601Timestamp = ConvertTo-OssIso8601Timestamp -Timestamp $RequestTime
    $rfc1123Timestamp = ConvertTo-OssRfc1123Timestamp -Timestamp $RequestTime
    $shortDate = $iso8601Timestamp.Substring(0, 8)
    $requestHeaders['x-oss-content-sha256'] = $payloadHash
    $requestHeaders['x-oss-date'] = $iso8601Timestamp

    if (-not [string]::IsNullOrWhiteSpace($Context.SecurityToken)) {
        $requestHeaders['x-oss-security-token'] = $Context.SecurityToken
    }

    $canonicalUri = Get-OssCanonicalUri -Context $Context -ObjectKey $ObjectKey
    $canonicalQueryString = Get-OssCanonicalQueryString -QueryParameters $QueryParameters
    $canonicalHeaders = Get-OssCanonicalHeaders -Headers $requestHeaders -AdditionalHeaders $AdditionalHeaders
    $additionalHeadersValue = Get-OssAdditionalHeadersValue -AdditionalHeaders $AdditionalHeaders
    $canonicalRequest = @(
        $Method
        $canonicalUri
        $canonicalQueryString
        $canonicalHeaders.TrimEnd("`n")
        ''
        $additionalHeadersValue
        $payloadHash
    ) -join "`n"

    $signingScope = Get-OssSigningScope -Context $Context -ShortDate $shortDate
    $stringToSign = @(
        'OSS4-HMAC-SHA256'
        $iso8601Timestamp
        $signingScope
        (Get-OssSha256Hex -Text $canonicalRequest)
    ) -join "`n"

    $signature = Get-OssSignature -Context $Context -ShortDate $shortDate -StringToSign $stringToSign
    $authorizationHeader = 'OSS4-HMAC-SHA256 Credential={0}/{1},AdditionalHeaders={2},Signature={3}' -f `
        $Context.AccessKeyId, `
        $signingScope, `
        $additionalHeadersValue, `
        $signature

    $requestHeaders['Authorization'] = $authorizationHeader
    $requestHeaders['Date'] = $rfc1123Timestamp

    $requestPath = if ([string]::IsNullOrWhiteSpace($ObjectKey)) {
        '/'
    }
    else {
        "/$(ConvertTo-OssEncodedPath -Path (Resolve-OssObjectKey -ObjectKey $ObjectKey))"
    }

    $requestUriText = '{0}://{1}{2}' -f $Context.Scheme, $Context.Host, $requestPath
    if (-not [string]::IsNullOrWhiteSpace($canonicalQueryString)) {
        $requestUriText = '{0}?{1}' -f $requestUriText, $canonicalQueryString
    }

    return [PSCustomObject]@{
        Method               = $Method
        RequestUri           = $requestUriText
        Headers              = $requestHeaders
        CanonicalUri         = $canonicalUri
        CanonicalQueryString = $canonicalQueryString
        CanonicalRequest     = $canonicalRequest
        StringToSign         = $stringToSign
        SigningScope         = $signingScope
        Signature            = $signature
        AuthorizationHeader  = $authorizationHeader
        Iso8601Timestamp     = $iso8601Timestamp
        Rfc1123Timestamp     = $rfc1123Timestamp
        PayloadHash          = $payloadHash
    }
}

function Get-OssHeaderValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Headers,
        [Parameter(Mandatory)]
        [string]$Name
    )

    foreach ($entry in $Headers.GetEnumerator()) {
        if ($entry.Key -ieq $Name) {
            return [string]$entry.Value
        }
    }

    return $null
}

function Get-OssMetadataFromHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    $metadata = @{}
    foreach ($entry in $Headers.GetEnumerator()) {
        if ($entry.Key -ilike 'x-oss-meta-*') {
            $metadataKey = ([string]$entry.Key).Substring('x-oss-meta-'.Length)
            $metadata[$metadataKey] = [string]$entry.Value
        }
    }

    return $metadata
}

function ConvertFrom-OssEncodedText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    return [System.Uri]::UnescapeDataString($Value)
}

function ConvertFrom-OssErrorBody {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Body
    )

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return $null
    }

    try {
        $xmlDocument = [xml]$Body
    }
    catch {
        return $null
    }

    if ($null -eq $xmlDocument.Error) {
        return $null
    }

    return [PSCustomObject]@{
        Code      = [string]$xmlDocument.Error.Code
        Message   = [string]$xmlDocument.Error.Message
        RequestId = [string]$xmlDocument.Error.RequestId
        HostId    = [string]$xmlDocument.Error.HostId
    }
}

function Throw-OssRequestFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Operation,
        [Parameter(Mandatory)]
        [psobject]$Response,
        [string]$ObjectKey
    )

    $errorPayload = ConvertFrom-OssErrorBody -Body $Response.Body
    $requestId = Get-OssHeaderValue -Headers $Response.Headers -Name 'x-oss-request-id'
    if ($null -eq $requestId -and $null -ne $errorPayload -and -not [string]::IsNullOrWhiteSpace($errorPayload.RequestId)) {
        $requestId = $errorPayload.RequestId
    }

    $messageSegments = @(
        ('{0} 失败' -f $Operation)
        ('HTTP {0}' -f $Response.StatusCode)
    )

    if (-not [string]::IsNullOrWhiteSpace($ObjectKey)) {
        $messageSegments += ('对象: {0}' -f $ObjectKey)
    }

    if ($null -ne $errorPayload -and -not [string]::IsNullOrWhiteSpace($errorPayload.Code)) {
        $messageSegments += ('OSS Code: {0}' -f $errorPayload.Code)
    }

    if ($null -ne $errorPayload -and -not [string]::IsNullOrWhiteSpace($errorPayload.Message)) {
        $messageSegments += ('消息: {0}' -f $errorPayload.Message)
    }

    if (-not [string]::IsNullOrWhiteSpace($requestId)) {
        $messageSegments += ('RequestId: {0}' -f $requestId)
    }

    throw ($messageSegments -join ' | ')
}

function New-OssHttpClient {
    [CmdletBinding()]
    param()

    if ($null -eq $script:OssHttpClient) {
        $handler = [System.Net.Http.HttpClientHandler]::new()
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        $script:OssHttpClient = [System.Net.Http.HttpClient]::new($handler, $true)
        $script:OssHttpClient.Timeout = [System.TimeSpan]::FromMinutes(10)
    }

    return $script:OssHttpClient
}

function Set-OssHttpContentHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.Http.HttpContent]$Content,
        [Parameter(Mandatory)]
        [hashtable]$Headers
    )

    foreach ($entry in $Headers.GetEnumerator()) {
        $headerName = ([string]$entry.Key).ToLowerInvariant()
        $headerValue = [string]$entry.Value
        switch ($headerName) {
            'content-length' {
                $Content.Headers.ContentLength = [long]$headerValue
                continue
            }
            'content-md5' {
                $Content.Headers.ContentMD5 = [System.Convert]::FromBase64String($headerValue)
                continue
            }
            'content-type' {
                $null = $Content.Headers.TryAddWithoutValidation('Content-Type', $headerValue)
                continue
            }
        }
    }
}

function ConvertFrom-OssHttpResponse {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Net.Http.HttpResponseMessage]$Response,
        [string]$Body
    )

    $headers = @{}
    foreach ($header in $Response.Headers) {
        $headers[$header.Key.ToLowerInvariant()] = ($header.Value -join ',')
    }
    foreach ($header in $Response.Content.Headers) {
        $headers[$header.Key.ToLowerInvariant()] = ($header.Value -join ',')
    }

    return [PSCustomObject]@{
        StatusCode          = [int]$Response.StatusCode
        ReasonPhrase        = [string]$Response.ReasonPhrase
        Headers             = $headers
        Body                = $Body
        IsSuccessStatusCode = [bool]$Response.IsSuccessStatusCode
    }
}

function Invoke-OssHttpRequest {
    <#
    .SYNOPSIS
        发送经过签名的 OSS HTTP 请求。

    .DESCRIPTION
        此函数是模块内部的网络发送 seam。公共函数负责生成 `RequestPlan`，
        这里再把 plan 映射到真实的 `HttpRequestMessage`，便于测试时通过 Mock
        拦截传输层而不必依赖真实网络环境。

    .PARAMETER RequestPlan
        由 `New-OssSignedRequestDetails` 返回的请求计划对象。

    .PARAMETER FilePath
        可选的本地文件路径。若提供，则以流式方式作为请求体上传。

    .OUTPUTS
        PSCustomObject
        返回状态码、响应头和响应体的归一化结果对象。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$RequestPlan,
        [string]$FilePath
    )

    $httpClient = New-OssHttpClient
    $requestMessage = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($RequestPlan.Method), $RequestPlan.RequestUri)
    $stream = $null

    try {
        foreach ($entry in $RequestPlan.Headers.GetEnumerator()) {
            $headerName = ([string]$entry.Key).ToLowerInvariant()
            if ($headerName -in @('content-length', 'content-md5', 'content-type')) {
                continue
            }

            $null = $requestMessage.Headers.TryAddWithoutValidation($entry.Key, [string]$entry.Value)
        }

        if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
            $stream = [System.IO.File]::OpenRead($FilePath)
            $requestMessage.Content = [System.Net.Http.StreamContent]::new($stream)
            Set-OssHttpContentHeaders -Content $requestMessage.Content -Headers $RequestPlan.Headers
        }

        $response = $httpClient.SendAsync($requestMessage, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        try {
            $body = if ($requestPlan.Method -eq 'HEAD') {
                ''
            }
            else {
                $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }

            return ConvertFrom-OssHttpResponse -Response $response -Body $body
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }

        $requestMessage.Dispose()
    }
}

function Resolve-OssContentType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [string]$ContentType
    )

    if (-not [string]::IsNullOrWhiteSpace($ContentType)) {
        return $ContentType
    }

    $extension = ([System.IO.Path]::GetExtension($FilePath) ?? '').ToLowerInvariant()
    $contentTypeMap = @{
        '.txt'  = 'text/plain'
        '.json' = 'application/json'
        '.html' = 'text/html'
        '.htm'  = 'text/html'
        '.css'  = 'text/css'
        '.js'   = 'application/javascript'
        '.xml'  = 'application/xml'
        '.svg'  = 'image/svg+xml'
        '.png'  = 'image/png'
        '.jpg'  = 'image/jpeg'
        '.jpeg' = 'image/jpeg'
        '.webp' = 'image/webp'
        '.pdf'  = 'application/pdf'
    }

    if ($contentTypeMap.ContainsKey($extension)) {
        return $contentTypeMap[$extension]
    }

    return 'application/octet-stream'
}

function ConvertTo-OssMetadataHeaders {
    [CmdletBinding()]
    param(
        [hashtable]$Metadata
    )

    $headers = @{}
    if ($null -eq $Metadata) {
        return $headers
    }

    foreach ($entry in $Metadata.GetEnumerator()) {
        $metadataKey = ([string]$entry.Key).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($metadataKey)) {
            throw 'Metadata 键不能为空。'
        }

        if ($metadataKey -notmatch '^[a-z0-9-]+$') {
            throw "Metadata 键 '$metadataKey' 仅支持小写字母、数字和连字符。"
        }

        $headers["x-oss-meta-$metadataKey"] = [string]$entry.Value
    }

    return $headers
}

function ConvertTo-OssTagHeaderValue {
    [CmdletBinding()]
    param(
        [hashtable]$Tags
    )

    if ($null -eq $Tags -or $Tags.Count -eq 0) {
        return $null
    }

    $segments = foreach ($entry in ($Tags.GetEnumerator() | Sort-Object Key)) {
        $tagKey = ([string]$entry.Key).Trim()
        if ([string]::IsNullOrWhiteSpace($tagKey)) {
            throw 'Tag 键不能为空。'
        }

        $tagValue = if ($null -eq $entry.Value) { '' } else { [string]$entry.Value }
        '{0}={1}' -f `
            (ConvertTo-OssQueryComponent -Value $tagKey), `
            (ConvertTo-OssQueryComponent -Value $tagValue)
    }

    return ($segments -join '&')
}

function Get-OssFileLength {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    return ([System.IO.FileInfo]::new($FilePath)).Length
}

function Assert-OssUploadableFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "本地文件不存在: $FilePath"
    }

    $fileLength = Get-OssFileLength -FilePath $FilePath
    $singlePutObjectLimit = 5GB
    if ($fileLength -gt $singlePutObjectLimit) {
        throw "文件超过 OSS PutObject 单次上传 5GB 上限: $FilePath"
    }
}

function Get-OssRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,
        [Parameter(Mandatory)]
        [string]$ChildPath
    )

    $resolvedRootPath = [System.IO.Path]::GetFullPath($RootPath)
    $resolvedChildPath = [System.IO.Path]::GetFullPath($ChildPath)
    $separator = [System.IO.Path]::DirectorySeparatorChar

    if (-not $resolvedRootPath.EndsWith([string]$separator)) {
        $resolvedRootPath = '{0}{1}' -f $resolvedRootPath, $separator
    }

    if (-not $resolvedChildPath.StartsWith($resolvedRootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "无法计算相对路径: $ChildPath"
    }

    return $resolvedChildPath.Substring($resolvedRootPath.Length) -replace '\\', '/'
}

function New-OssContext {
    <#
    .SYNOPSIS
        创建可复用的 OSS 配置上下文对象。

    .DESCRIPTION
        此函数将 bucket、region、鉴权信息与目标 host/endpoint 归一化为一个对象，
        供其他 `Oss` 公共函数重复使用。
        设计意图：
        - 统一处理 region 与 host 的规范化，避免每个 API 重复做输入校验。
        - 让脚本入口和模块调用都以同一种配置对象为核心交互模型。

    .PARAMETER Bucket
        目标 OSS bucket 名称。

    .PARAMETER Region
        OSS 区域标识，支持输入 `cn-hangzhou` 或 `oss-cn-hangzhou`。

    .PARAMETER AccessKeyId
        阿里云 AccessKeyId。

    .PARAMETER AccessKeySecret
        阿里云 AccessKeySecret。

    .PARAMETER SecurityToken
        可选 STS 临时凭证 Token。

    .PARAMETER Endpoint
        可选 endpoint 或自定义域名，不能与 Host 同时指定。

    .PARAMETER Host
        可选实际请求 host，不能与 Endpoint 同时指定。

    .PARAMETER Scheme
        请求协议，默认为 `https`。

    .OUTPUTS
        PSCustomObject
        返回规范化后的上下文对象。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Bucket,
        [Parameter(Mandatory)]
        [string]$Region,
        [Parameter(Mandatory)]
        [string]$AccessKeyId,
        [Parameter(Mandatory)]
        [string]$AccessKeySecret,
        [string]$SecurityToken,
        [string]$Endpoint,
        [string]$Host,
        [ValidateSet('https', 'http')]
        [string]$Scheme = 'https'
    )

    $normalizedBucket = $Bucket.Trim()
    if ([string]::IsNullOrWhiteSpace($normalizedBucket)) {
        throw 'Bucket 不能为空。'
    }

    if ([string]::IsNullOrWhiteSpace($AccessKeyId)) {
        throw 'AccessKeyId 不能为空。'
    }

    if ([string]::IsNullOrWhiteSpace($AccessKeySecret)) {
        throw 'AccessKeySecret 不能为空。'
    }

    $normalizedRegion = Resolve-OssNormalizedRegion -Region $Region
    $normalizedHost = Resolve-OssHost -Bucket $normalizedBucket -Region $normalizedRegion -Endpoint $Endpoint -Host $Host

    return [PSCustomObject]@{
        Bucket           = $normalizedBucket
        Region           = $normalizedRegion
        Host             = $normalizedHost
        Scheme           = $Scheme
        AccessKeyId      = $AccessKeyId
        AccessKeySecret  = $AccessKeySecret
        SecurityToken    = $SecurityToken
        ExplicitEndpoint = if (-not [string]::IsNullOrWhiteSpace($Endpoint)) { Remove-OssUriDecorators -Value $Endpoint } else { $null }
    }
}

function Test-OssObject {
    <#
    .SYNOPSIS
        检查指定 OSS 对象是否存在。

    .DESCRIPTION
        通过 `HEAD` 请求检查对象存在性。设计上仅把 `404 NoSuchKey`
        归一化为 `$false`，其他错误继续抛出，以免把权限错误误判成“对象不存在”。

    .PARAMETER Context
        由 `New-OssContext` 返回的上下文对象。

    .PARAMETER ObjectKey
        要检查的对象键。

    .OUTPUTS
        System.Boolean
        对象存在时返回 `$true`，不存在时返回 `$false`。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$ObjectKey
    )

    $normalizedObjectKey = Resolve-OssObjectKey -ObjectKey $ObjectKey
    $requestPlan = New-OssSignedRequestDetails -Method 'HEAD' -Context $Context -ObjectKey $normalizedObjectKey
    $response = Invoke-OssHttpRequest -RequestPlan $requestPlan

    if ($response.StatusCode -eq 404) {
        return $false
    }

    if (-not $response.IsSuccessStatusCode) {
        Throw-OssRequestFailure -Operation '检查 OSS 对象是否存在' -Response $response -ObjectKey $normalizedObjectKey
    }

    return $true
}

function Get-OssObjectInfo {
    <#
    .SYNOPSIS
        读取指定 OSS 对象的元信息。

    .DESCRIPTION
        此函数通过 `HEAD` 请求返回对象的核心头信息与用户元数据，
        包括 `ETag`、`Content-Length`、`Content-Type`、`Last-Modified` 和 `x-oss-meta-*`。

    .PARAMETER Context
        由 `New-OssContext` 返回的上下文对象。

    .PARAMETER ObjectKey
        要读取的对象键。

    .OUTPUTS
        PSCustomObject
        返回对象基础信息和用户元数据。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$ObjectKey
    )

    $normalizedObjectKey = Resolve-OssObjectKey -ObjectKey $ObjectKey
    $requestPlan = New-OssSignedRequestDetails -Method 'HEAD' -Context $Context -ObjectKey $normalizedObjectKey
    $response = Invoke-OssHttpRequest -RequestPlan $requestPlan

    if (-not $response.IsSuccessStatusCode) {
        Throw-OssRequestFailure -Operation '读取 OSS 对象元信息' -Response $response -ObjectKey $normalizedObjectKey
    }

    $etagValue = Get-OssHeaderValue -Headers $response.Headers -Name 'etag'
    $lastModifiedValue = Get-OssHeaderValue -Headers $response.Headers -Name 'last-modified'

    return [PSCustomObject]@{
        Bucket        = $Context.Bucket
        ObjectKey     = $normalizedObjectKey
        ETag          = if ([string]::IsNullOrWhiteSpace($etagValue)) { $null } else { $etagValue.Trim('"') }
        ContentLength = [long](Get-OssHeaderValue -Headers $response.Headers -Name 'content-length')
        ContentType   = Get-OssHeaderValue -Headers $response.Headers -Name 'content-type'
        LastModified  = if ([string]::IsNullOrWhiteSpace($lastModifiedValue)) { $null } else { [System.DateTimeOffset]::Parse($lastModifiedValue, [System.Globalization.CultureInfo]::InvariantCulture) }
        RequestId     = Get-OssHeaderValue -Headers $response.Headers -Name 'x-oss-request-id'
        VersionId     = Get-OssHeaderValue -Headers $response.Headers -Name 'x-oss-version-id'
        Metadata      = Get-OssMetadataFromHeaders -Headers $response.Headers
        Headers       = $response.Headers
    }
}

function Get-OssObjectList {
    <#
    .SYNOPSIS
        列举指定 prefix 下的 OSS 对象。

    .DESCRIPTION
        使用 `ListObjectsV2` 对 bucket 进行轻量列举，返回对象列表、
        公共前缀与分页令牌，适合脚本在上传前后做基本检查。

    .PARAMETER Context
        由 `New-OssContext` 返回的上下文对象。

    .PARAMETER Prefix
        可选对象前缀。

    .PARAMETER Delimiter
        可选分隔符，常用于模拟目录层级。

    .PARAMETER MaxKeys
        单次返回的最大对象数，默认 1000。

    .PARAMETER ContinuationToken
        分页 continuation token。

    .OUTPUTS
        PSCustomObject
        返回对象项、公共前缀、分页信息与请求标识。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [string]$Prefix,
        [string]$Delimiter,
        [ValidateRange(1, 1000)]
        [int]$MaxKeys = 1000,
        [string]$ContinuationToken
    )

    $queryParameters = [ordered]@{
        'encoding-type' = 'url'
        'list-type'     = '2'
        'max-keys'      = [string]$MaxKeys
    }

    if (-not [string]::IsNullOrWhiteSpace($Prefix)) {
        $queryParameters['prefix'] = $Prefix
    }
    if (-not [string]::IsNullOrWhiteSpace($Delimiter)) {
        $queryParameters['delimiter'] = $Delimiter
    }
    if (-not [string]::IsNullOrWhiteSpace($ContinuationToken)) {
        $queryParameters['continuation-token'] = $ContinuationToken
    }

    $requestPlan = New-OssSignedRequestDetails -Method 'GET' -Context $Context -QueryParameters $queryParameters
    $response = Invoke-OssHttpRequest -RequestPlan $requestPlan

    if (-not $response.IsSuccessStatusCode) {
        Throw-OssRequestFailure -Operation '列举 OSS 对象' -Response $response
    }

    try {
        $xmlDocument = [xml]$response.Body
    }
    catch {
        throw "解析 OSS 对象列表响应失败: $($_.Exception.Message)"
    }

    $contents = @(
        $xmlDocument.ListBucketResult.Contents |
            ForEach-Object {
                [PSCustomObject]@{
                    Key          = ConvertFrom-OssEncodedText -Value ([string]$_.Key)
                    ETag         = ([string]$_.ETag).Trim('"')
                    Size         = [long]$_.Size
                    LastModified = [System.DateTimeOffset]::Parse(([string]$_.LastModified), [System.Globalization.CultureInfo]::InvariantCulture)
                    StorageClass = [string]$_.StorageClass
                }
            }
    )

    $commonPrefixes = @(
        $xmlDocument.ListBucketResult.CommonPrefixes |
            ForEach-Object {
                ConvertFrom-OssEncodedText -Value ([string]$_.Prefix)
            }
    )

    return [PSCustomObject]@{
        Bucket                = $Context.Bucket
        Prefix                = ConvertFrom-OssEncodedText -Value ([string]$xmlDocument.ListBucketResult.Prefix)
        Delimiter             = ConvertFrom-OssEncodedText -Value ([string]$xmlDocument.ListBucketResult.Delimiter)
        MaxKeys               = [int]$xmlDocument.ListBucketResult.MaxKeys
        IsTruncated           = [System.Convert]::ToBoolean([string]$xmlDocument.ListBucketResult.IsTruncated)
        NextContinuationToken = [string]$xmlDocument.ListBucketResult.NextContinuationToken
        RequestId             = Get-OssHeaderValue -Headers $response.Headers -Name 'x-oss-request-id'
        Items                 = $contents
        CommonPrefixes        = $commonPrefixes
    }
}

function Publish-OssObject {
    <#
    .SYNOPSIS
        上传单个本地文件到 OSS。

    .DESCRIPTION
        该函数负责单文件上传，并默认采用“先检查是否已存在，再禁止覆盖上传”的安全策略。
        设计意图：
        - 默认避免误覆盖已有对象。
        - 把上传结果整理成可复用对象，供脚本和其他模块直接消费。

    .PARAMETER Context
        由 `New-OssContext` 返回的上下文对象。

    .PARAMETER FilePath
        本地文件路径。

    .PARAMETER ObjectKey
        目标 OSS 对象键。

    .PARAMETER ContentType
        可选内容类型。不指定时按扩展名做轻量推断，推断失败回退为 `application/octet-stream`。

    .PARAMETER Metadata
        可选对象元数据哈希表，会映射为 `x-oss-meta-*` 请求头。

    .PARAMETER Tags
        可选对象标签哈希表，会映射为 `x-oss-tagging` 请求头。

    .PARAMETER StorageClass
        可选存储类型。

    .PARAMETER ObjectAcl
        可选对象 ACL。

    .PARAMETER Force
        显式允许覆盖远端已有对象。未指定时，函数会先检查对象是否存在并附加禁止覆盖头。

    .OUTPUTS
        PSCustomObject
        返回上传结果对象，包括对象键、请求标识、ETag 与版本标识等信息。
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$ObjectKey,
        [string]$ContentType,
        [hashtable]$Metadata,
        [hashtable]$Tags,
        [ValidateSet('Standard', 'IA', 'Archive', 'ColdArchive', 'DeepColdArchive')]
        [string]$StorageClass,
        [ValidateSet('default', 'private', 'public-read', 'public-read-write')]
        [string]$ObjectAcl,
        [switch]$Force
    )

    Assert-OssUploadableFile -FilePath $FilePath

    $resolvedFilePath = [System.IO.Path]::GetFullPath($FilePath)
    $normalizedObjectKey = Resolve-OssObjectKey -ObjectKey $ObjectKey
    $resolvedContentType = Resolve-OssContentType -FilePath $resolvedFilePath -ContentType $ContentType
    $fileLength = Get-OssFileLength -FilePath $resolvedFilePath

    if (-not $PSCmdlet.ShouldProcess("$($Context.Bucket)/$normalizedObjectKey", "上传本地文件 $resolvedFilePath")) {
        return $null
    }

    if (-not $Force.IsPresent -and (Test-OssObject -Context $Context -ObjectKey $normalizedObjectKey)) {
        throw "OSS 对象已存在: $normalizedObjectKey。若确认需要覆盖，请显式传入 -Force。"
    }

    $requestHeaders = [ordered]@{
        'Content-Length' = [string]$fileLength
        'Content-MD5'    = Get-OssContentMd5Base64 -FilePath $resolvedFilePath
        'Content-Type'   = $resolvedContentType
    }

    if (-not $Force.IsPresent) {
        $requestHeaders['x-oss-forbid-overwrite'] = 'true'
    }
    if (-not [string]::IsNullOrWhiteSpace($StorageClass)) {
        $requestHeaders['x-oss-storage-class'] = $StorageClass
    }
    if (-not [string]::IsNullOrWhiteSpace($ObjectAcl)) {
        $requestHeaders['x-oss-object-acl'] = $ObjectAcl
    }

    foreach ($entry in (ConvertTo-OssMetadataHeaders -Metadata $Metadata).GetEnumerator()) {
        $requestHeaders[$entry.Key] = $entry.Value
    }

    $tagHeaderValue = ConvertTo-OssTagHeaderValue -Tags $Tags
    if (-not [string]::IsNullOrWhiteSpace($tagHeaderValue)) {
        $requestHeaders['x-oss-tagging'] = $tagHeaderValue
    }

    $requestPlan = New-OssSignedRequestDetails `
        -Method 'PUT' `
        -Context $Context `
        -ObjectKey $normalizedObjectKey `
        -Headers $requestHeaders `
        -AdditionalHeaders @('content-length')

    $response = Invoke-OssHttpRequest -RequestPlan $requestPlan -FilePath $resolvedFilePath
    if (-not $response.IsSuccessStatusCode) {
        Throw-OssRequestFailure -Operation '上传 OSS 对象' -Response $response -ObjectKey $normalizedObjectKey
    }

    $etagValue = Get-OssHeaderValue -Headers $response.Headers -Name 'etag'

    return [PSCustomObject]@{
        Bucket        = $Context.Bucket
        ObjectKey     = $normalizedObjectKey
        LocalPath     = $resolvedFilePath
        ContentType   = $resolvedContentType
        ContentLength = $fileLength
        ETag          = if ([string]::IsNullOrWhiteSpace($etagValue)) { $null } else { $etagValue.Trim('"') }
        RequestId     = Get-OssHeaderValue -Headers $response.Headers -Name 'x-oss-request-id'
        VersionId     = Get-OssHeaderValue -Headers $response.Headers -Name 'x-oss-version-id'
        Host          = $Context.Host
        StatusCode    = $response.StatusCode
        Forced        = [bool]$Force.IsPresent
    }
}

function Publish-OssDirectory {
    <#
    .SYNOPSIS
        递归上传本地目录到指定 OSS 前缀。

    .DESCRIPTION
        该函数会遍历本地目录中的所有文件，并将它们的相对路径映射到指定 OSS 前缀。
        首版只负责“把本地文件追加上传到前缀”，不会删除远端多余对象。

    .PARAMETER Context
        由 `New-OssContext` 返回的上下文对象。

    .PARAMETER DirectoryPath
        本地目录路径。

    .PARAMETER Prefix
        远端对象前缀。若为空，则直接使用本地相对路径作为对象键。

    .PARAMETER ContentType
        可选统一内容类型。若不指定，则对每个文件单独做轻量推断。

    .PARAMETER Metadata
        可选对象元数据哈希表，将应用到所有上传对象。

    .PARAMETER Tags
        可选对象标签哈希表，将应用到所有上传对象。

    .PARAMETER StorageClass
        可选存储类型。

    .PARAMETER ObjectAcl
        可选对象 ACL。

    .PARAMETER Force
        显式允许覆盖远端已有对象。

    .OUTPUTS
        PSCustomObject
        返回目录上传汇总结果与逐文件上传结果。
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [psobject]$Context,
        [Parameter(Mandatory)]
        [string]$DirectoryPath,
        [string]$Prefix,
        [string]$ContentType,
        [hashtable]$Metadata,
        [hashtable]$Tags,
        [ValidateSet('Standard', 'IA', 'Archive', 'ColdArchive', 'DeepColdArchive')]
        [string]$StorageClass,
        [ValidateSet('default', 'private', 'public-read', 'public-read-write')]
        [string]$ObjectAcl,
        [switch]$Force
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath -PathType Container)) {
        throw "本地目录不存在: $DirectoryPath"
    }

    $resolvedDirectoryPath = [System.IO.Path]::GetFullPath($DirectoryPath)
    $files = @(Get-ChildItem -LiteralPath $resolvedDirectoryPath -File -Recurse | Sort-Object FullName)
    $results = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in $files) {
        $relativePath = Get-OssRelativePath -RootPath $resolvedDirectoryPath -ChildPath $file.FullName
        $objectKey = Join-OssKeySegments -Segments @($Prefix, $relativePath)

        try {
            $publishObjectParameters = @{
                Context   = $Context
                FilePath  = $file.FullName
                ObjectKey = $objectKey
                Force     = $Force.IsPresent
                WhatIf    = $WhatIfPreference
            }

            if (-not [string]::IsNullOrWhiteSpace($ContentType)) {
                $publishObjectParameters.ContentType = $ContentType
            }
            if ($null -ne $Metadata) {
                $publishObjectParameters.Metadata = $Metadata
            }
            if ($null -ne $Tags) {
                $publishObjectParameters.Tags = $Tags
            }
            if (-not [string]::IsNullOrWhiteSpace($StorageClass)) {
                $publishObjectParameters.StorageClass = $StorageClass
            }
            if (-not [string]::IsNullOrWhiteSpace($ObjectAcl)) {
                $publishObjectParameters.ObjectAcl = $ObjectAcl
            }

            $result = Publish-OssObject @publishObjectParameters

            if ($null -ne $result) {
                $results.Add($result) | Out-Null
            }
        }
        catch {
            $exception = [System.InvalidOperationException]::new(
                "目录上传在对象 '$objectKey' 处失败: $($_.Exception.Message)",
                $_.Exception
            )
            $exception.Data['CompletedResults'] = @($results.ToArray())
            $exception.Data['FailedObjectKey'] = $objectKey
            $exception.Data['FailedLocalPath'] = $file.FullName
            throw $exception
        }
    }

    return [PSCustomObject]@{
        Bucket        = $Context.Bucket
        Prefix        = if ([string]::IsNullOrWhiteSpace($Prefix)) { '' } else { Join-OssKeySegments -Segments @($Prefix) }
        FileCount     = $files.Count
        UploadedCount = $results.Count
        Results       = @($results.ToArray())
    }
}

Export-ModuleMember -Function @(
    'New-OssContext',
    'Test-OssObject',
    'Get-OssObjectInfo',
    'Get-OssObjectList',
    'Publish-OssObject',
    'Publish-OssDirectory'
)
