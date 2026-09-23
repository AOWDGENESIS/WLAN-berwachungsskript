Set-StrictMode -Version Latest

function Get-GuardianDevices {
    param([string]$OutputPath = '')

    $route = @(Get-NetRoute -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Where-Object { $_.NextHop -ne '0.0.0.0' } | Sort-Object RouteMetric | Select-Object -First 1)
    if ($route.Count -eq 0) {
        return @()
    }

    $list = @(Get-NetNeighbor -AddressFamily IPv4 -InterfaceIndex $route[0].InterfaceIndex -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -and $_.LinkLayerAddress -and $_.IPAddress -ne $route[0].NextHop } |
        ForEach-Object {
            [pscustomobject]@{
                DeviceId = ('mac:' + ([string]$_.LinkLayerAddress).ToLowerInvariant())
                MAC = [string]$_.LinkLayerAddress
                IPv4 = [string]$_.IPAddress
                Hostname = 'unknown'
                Model = 'unknown'
                DeviceType = 'unknown'
                Status = [string]$_.State
                TrustState = 'unknown'
                Confidence = 0
                Source = 'windows_neighbor_table'
                ObservedAt = (Get-Date).ToUniversalTime().ToString('o')
            }
        })

    if ($OutputPath) {
        $list | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding utf8
    }

    return $list
}

Export-ModuleMember -Function Get-GuardianDevices
