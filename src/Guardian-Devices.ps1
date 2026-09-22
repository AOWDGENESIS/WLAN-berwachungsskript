param(
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot "artifacts\guardian-devices.json"
}

if (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
    $OutputPath = Join-Path $projectRoot $OutputPath.TrimStart(".\")
}

$outputDirectory = Split-Path -Parent $OutputPath

if (-not (Test-Path $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$defaultRoute = $null

if (Get-Command Get-NetRoute -ErrorAction SilentlyContinue) {
    $routes = @(
        Get-NetRoute `
            -AddressFamily IPv4 `
            -DestinationPrefix "0.0.0.0/0" `
            -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric
    )

    foreach ($route in $routes) {
        if ([string]$route.NextHop -ne "0.0.0.0") {
            $defaultRoute = $route
            break
        }
    }
}

$gateway = $null
$interfaceIndex = $null

if ($null -ne $defaultRoute) {
    $gateway = [string]$defaultRoute.NextHop
    $interfaceIndex = [int]$defaultRoute.InterfaceIndex
}

if ($null -eq $interfaceIndex) {
    throw "FAIL: No active IPv4 default route found."
}

$interfaceAddresses = @(
    Get-NetIPAddress `
        -AddressFamily IPv4 `
        -InterfaceIndex $interfaceIndex `
        -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne "127.0.0.1"
    }
)

$localAddress = $null
$prefixLength = $null

foreach ($address in $interfaceAddresses) {
    if (-not [string]::IsNullOrWhiteSpace([string]$address.IPAddress)) {
        $localAddress = [string]$address.IPAddress
        $prefixLength = [int]$address.PrefixLength
        break
    }
}

if ([string]::IsNullOrWhiteSpace($localAddress)) {
    throw "FAIL: No IPv4 address found on the active interface."
}

function Convert-IPv4ToUInt32 {
    param(
        [string]$IPAddress
    )

    $bytes = ([System.Net.IPAddress]::Parse($IPAddress)).GetAddressBytes()

    return (
        ([uint32]$bytes[0] -shl 24) -bor
        ([uint32]$bytes[1] -shl 16) -bor
        ([uint32]$bytes[2] -shl 8) -bor
        ([uint32]$bytes[3])
    )
}

function Convert-UInt32ToIPv4 {
    param(
        [uint32]$Value
    )

    $bytes = @(
        [byte](($Value -shr 24) -band 255)
        [byte](($Value -shr 16) -band 255)
        [byte](($Value -shr 8) -band 255)
        [byte]($Value -band 255)
    )

    return [System.Net.IPAddress]::new($bytes).ToString()
}

$localUInt = Convert-IPv4ToUInt32 $localAddress

if ($prefixLength -eq 0) {
    $maskUInt = [uint32]0
}

if ($prefixLength -gt 0) {
    $maskUInt = [uint32]([uint64]0xFFFFFFFF -shl (32 - $prefixLength))
}

$networkUInt = $localUInt -band $maskUInt
$broadcastUInt = $networkUInt -bor ([uint32]([uint64]0xFFFFFFFF -bxor $maskUInt))

$networkAddress = Convert-UInt32ToIPv4 $networkUInt
$broadcastAddress = Convert-UInt32ToIPv4 $broadcastUInt

$devices = @()

if (Get-Command Get-NetNeighbor -ErrorAction SilentlyContinue) {
    $neighbors = @(
        Get-NetNeighbor `
            -AddressFamily IPv4 `
            -InterfaceIndex $interfaceIndex `
            -ErrorAction SilentlyContinue
    )

    foreach ($neighbor in $neighbors) {
        $ip = [string]$neighbor.IPAddress
        $mac = [string]$neighbor.LinkLayerAddress

        if ([string]::IsNullOrWhiteSpace($ip)) {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($mac)) {
            continue
        }

        if ($ip -eq $localAddress) {
            continue
        }

        if ($ip -eq $gateway) {
            $role = "gateway"
        }

        if ($ip -eq $broadcastAddress) {
            continue
        }

        $parsed = $null

        if (-not [System.Net.IPAddress]::TryParse($ip, [ref]$parsed)) {
            continue
        }

        if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
            continue
        }

        $ipUInt = Convert-IPv4ToUInt32 $ip

        if (($ipUInt -band $maskUInt) -ne $networkUInt) {
            continue
        }

        $firstOctet = [int]$ip.Split(".")[0]

        if (($firstOctet -ge 224) -and ($firstOctet -le 239)) {
            continue
        }

        if ($ip -eq "255.255.255.255") {
            continue
        }

        if ([string]::IsNullOrWhiteSpace($role)) {
            $role = "device"
        }

        $devices += [PSCustomObject]@{
            timestamp = (Get-Date).ToUniversalTime().ToString("o")
            ip = $ip
            mac = $mac
            state = [string]$neighbor.State
            interfaceIndex = $interfaceIndex
            role = $role
            source = "windows_neighbor_table"
        }

        $role = $null
    }
}

$devices = @(
    $devices |
        Sort-Object ip, mac |
        Group-Object ip, mac |
        ForEach-Object {
            $_.Group[0]
        }
)

$result = [PSCustomObject]@{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    deviceCount = $devices.Count
    localAddress = $localAddress
    prefixLength = $prefixLength
    network = $networkAddress
    broadcast = $broadcastAddress
    gateway = $gateway
    interfaceIndex = $interfaceIndex
    discoveryMethod = "windows_neighbor_table"
    activeScan = $false
    devices = $devices
}

$json = $result | ConvertTo-Json -Depth 5

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $json, $utf8NoBom)

$result | ConvertTo-Json -Depth 5