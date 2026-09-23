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

Export-ModuleMember -Function Invoke-FritzBoxProbe