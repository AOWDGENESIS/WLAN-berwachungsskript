param([string]$ConfigPath = '')
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
& powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'src\Guardian.Service\Guardian.Service.ps1') -ConfigPath $ConfigPath