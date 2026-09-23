Set-StrictMode -Version Latest

function Get-GuardianNetworkState {
    $adapter = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object Status -eq 'Up' | Select-Object -First 1)
    $name = if ($adapter.Count -gt 0) { [string]$adapter[0].Name } else { $null }

    $ip = @()
    if ($name) {
        $ip = @(Get-NetIPAddress -InterfaceAlias $name -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1)
    }

    $route = @()
    if ($name) {
        $route = @(Get-NetRoute -InterfaceAlias $name -AddressFamily IPv4 -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue | Sort-Object RouteMetric | Select-Object -First 1)
    }

    [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        Adapter = $name
        IPv4 = if ($ip.Count -gt 0) { [string]$ip[0].IPAddress } else { $null }
        Gateway = if ($route.Count -gt 0) { [string]$route[0].NextHop } else { $null }
        Available = [bool]($ip.Count -gt 0)
    }
}

Export-ModuleMember -Function Get-GuardianNetworkState