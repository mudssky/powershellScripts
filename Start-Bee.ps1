
function Start-Bee {
    [CmdletBinding(supportsShouldProcess)]
    param()
    1..3 | ForEach-Object {
        $frequency = Get-Random -Minimum 400 -Maximum 10000
        $duration = Get-Random -Minimum 1000 -Maximum 4000
        [Console]::Beep($frequency, $duration)
    }
    # $host.ui.RawUI.WindowTitle=Get-Location
}
Start-Beert-Bee.ps1
执行脚本发出3次随机蜂鸣声

.EXAMPLE
Start-Bee
直接调用函数发出蜂鸣声

.NOTES
使用Console.Beep方法发出系统蜂鸣声
需要系统支持蜂鸣器功能
每次执行会产生不同的声音效果
#>

function Start-Bee {
    [CmdletBinding(supportsShouldProcess)]
    param()
    1..3 | ForEach-Object {
        $frequency = Get-Random -Minimum 400 -Maximum 10000
        $duration = Get-Random -Minimum 1000 -Maximum 4000
        [Console]::Beep($frequency, $duration)
    }
    # $host.ui.RawUI.WindowTitle=Get-Location
}
Start-Bee