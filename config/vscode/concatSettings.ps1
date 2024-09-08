

function Get-JsoncInnerContent {
    [CmdletBinding()]
    param (
        [string]$Path,
        [string]$JsoncString   
    )

    if ($Path) {
        $JsoncString = Get-Content -Raw  $Path
    }
    # (?s) 的作用是开启.匹配所有字符的模式，后面.*?关闭贪婪模式，这样使得可以移除括号附近的空白字符
    $isMatch = $JsoncString -match '(?s)^[^{}]*{\s*(.*?)\s*}[^{}]*$'
    if ($isMatch) {
        $innerString = $matches[1]
        # 添加尾部逗号
        if (-not $innerString.EndsWith(',')) {
            $innerString += ',' 
        }
        return $innerString
    }
    else {
        throw "match failed: $Path,$JsoncString"
    }
    
}

$settingsList = [System.Collections.Generic.List[string]]::new()
Get-ChildItem -Recurse  -Filter *.jsonc   -Path $PSScriptRoot/settings | ForEach-Object {
    $jsoncString = Get-JsoncInnerContent -Path $_.FullName;
    $settingsList.Add($jsoncString)
}
$newSettings = ($settingsList -join "`n").TrimEnd(",")
"{$newSettings}" | Set-Content -Path $PSScriptRoot/settings.jsonc