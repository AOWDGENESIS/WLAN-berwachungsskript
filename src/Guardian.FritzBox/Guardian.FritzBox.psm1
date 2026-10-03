Set-StrictMode -Version Latest

function Invoke-FritzBoxProbe {
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [int]$TimeoutSeconds = 5
    )

    try {
        $response = Invoke-WebRequest -Uri $BaseUrl -Method Head -TimeoutSec $TimeoutSeconds -UseBasicParsing -ErrorAction Stop
        [pscustomobject]@{
            Reachable = $true
            StatusCode = [int]$response.StatusCode
            Source = 'http_probe'
            ObservedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
    catch {
        [pscustomobject]@{
            Reachable = $false
            StatusCode = $null
            Source = 'http_probe'
            Error = $_.Exception.Message
            ObservedAt = (Get-Date).ToUniversalTime().ToString('o')
        }
    }
}

function Get-FritzBoxPolicy {
    param([object]$Config)

    # tr069Enabled war bis hierhin ein toter Schluessel: in der Beispielconfig
    # vorhanden, im Code nirgends gelesen. Die Policy macht ihn verbindlich und
    # haelt die Vorgabe aus SECURITY.md fest, dass keine Anmeldedaten im
    # Repository liegen.
    [pscustomobject]@{
        Enabled = [bool]$Config.tr069Enabled
        Mode = if ($Config.tr069Enabled) { 'TR064_EXPLICIT_OPT_IN' } else { 'DISABLED' }
        RequiresExplicitOptIn = $true
        CredentialsInRepository = $false
    }
}

Export-ModuleMember -Function Invoke-FritzBoxProbe, Get-FritzBoxPolicy