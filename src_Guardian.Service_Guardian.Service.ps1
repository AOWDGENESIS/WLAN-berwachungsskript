param([string]$ConfigPath = '')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $ConfigPath) {
    $ConfigPath = Join-Path $root 'config\guardian.example.json'
}

Import-Module (Join-Path $root 'src\Guardian.Core\Guardian.Core.psm1') -Force
Import-Module (Join-Path $root 'src\Guardian.Network\Guardian.Network.psm1') -Force
Import-Module (Join-Path $root 'src\Guardian.Devices\Guardian.Devices.psm1') -Force
Import-Module (Join-Path $root 'src\Guardian.Evidence\Guardian.Evidence.psm1') -Force

$config = Read-GuardianConfig $ConfigPath
$log = $config.logDirectory
if (-not [System.IO.Path]::IsPathRooted($log)) {
    $log = Join-Path $root $log
}
New-Item -ItemType Directory -Path $log -Force | Out-Null

$context = [pscustomobject]@{ State = New-GuardianState }
Set-GuardianState -Context $context -State 'INITIALIZING' -Reason 'service startup' | Out-Null

while ($true) {
    $network = Get-GuardianNetworkState
    $state = if ($network.Available) { 'RUNNING' } else { 'NETWORK_UNAVAILABLE' }
    Set-GuardianState -Context $context -State $state -Reason 'network poll' | Out-Null

    $event = [pscustomobject]@{
        EventType = 'NETWORK_STATE'
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        GuardianState = $context.State.State
        Network = $network
    }

    Write-GuardianEvidence -Path (Join-Path $log 'guardian-events.jsonl') -Event $event | Out-Null
    Start-Sleep -Seconds ([int]$config.intervalSeconds)
}