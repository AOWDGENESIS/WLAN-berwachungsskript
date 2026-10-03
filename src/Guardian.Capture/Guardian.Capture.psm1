Set-StrictMode -Version Latest

function Get-CapturePolicy {
    param([object]$Config)

    [pscustomobject]@{
        Enabled = [bool]$Config.captureEnabled
        Mode = if ($Config.captureEnabled) { 'INCIDENT_ONLY' } else { 'DISABLED' }
        RequiresExplicitOptIn = $true
    }
}

Export-ModuleMember -Function Get-CapturePolicy