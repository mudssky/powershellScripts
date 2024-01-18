
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