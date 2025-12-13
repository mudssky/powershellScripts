#!/usr/bin/env pwsh

<#
.SYNOPSIS
    发出3次随机蜂鸣声
.DESCRIPTION
    使用 Console.Beep 以随机频率和时长蜂鸣 3 次。
.EXAMPLE
    .\Start-Bee.ps1
    直接运行脚本发出蜂鸣声
.EXAMPLE
    Start-Bee
    导入后调用函数发出蜂鸣声
.NOTES
    需要系统支持蜂鸣器功能
#>

function Start-Bee {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'
    1..3 | ForEach-Object {
        $frequency = Get-Random -Minimum 400 -Maximum 10000
        $duration = Get-Random -Minimum 1000 -Maximum 4000
        if ($PSCmdlet.ShouldProcess("Bee", "Beep ${frequency}Hz for ${duration}ms")) {
            [Console]::Beep($frequency, $duration)
        }
    }
}

Start-Bee
