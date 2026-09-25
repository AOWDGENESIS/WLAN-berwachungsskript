param(
    [switch]$Once,
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $scriptRoot) "config\guardian.example.json"
} elseif (-not [System.IO.Path]::IsPathRooted($ConfigPath)) {
    $ConfigPath = Join-Path (Split-Path -Parent $scriptRoot) $ConfigPath
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Configuration not found: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if ($null -eq $config.intervalSeconds -or [int]$config.intervalSeconds -lt 1) {
    throw "Configuration intervalSeconds must be greater than zero."
}
if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) {
    throw "Configuration logDirectory is required."
}

$logDirectory = [string]$config.logDirectory
if (-not [System.IO.Path]::IsPathRooted($logDirectory)) {
    $logDirectory = Join-Path (Split-Path -Parent $scriptRoot) $logDirectory
}

New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null

$logFile = Join-Path $logDirectory "guardian-events.jsonl"
$stateFile = Join-Path $logDirectory "guardian-chain.json"

function Get-WlanState {
    $ssid = $null
    $adapter = $null
    $ipv4 = $null
    $gateway = $null
    $dnsOk = $false
    $internetOk = $false

    $wlanText = netsh wlan show interfaces 2>$null
    if ($wlanText) {
        $ssidLine = $wlanText | Select-String "^\s*SSID\s*:"
        if ($ssidLine) {
            $ssid = ($ssidLine.Line -split ":",2)[1].Trim()
        }
    }

    $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.Status -eq "Up" }

    if ($adapters) {
        $adapter = ($adapters | Select-Object -First 1).Name
    }

    if ($adapter) {
        $ip = Get-NetIPAddress -InterfaceAlias $adapter -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress -notlike "169.254.*" } |
            Select-Object -First 1

        if ($ip) {
            $ipv4 = $ip.IPAddress
        }

        $route = Get-NetRoute -InterfaceAlias $adapter -AddressFamily IPv4 -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
            Sort-Object RouteMetric |
            Select-Object -First 1

        if ($route) {
            $gateway = $route.NextHop
        }
    }

    if ($config.dnsName) {
        try {
            Resolve-DnsName -Name $config.dnsName -Type A -ErrorAction Stop | Out-Null
            $dnsOk = $true
        }
        catch {
            $dnsOk = $false
        }
    }

    if ($config.testHost) {
        try {
            $internetOk = Test-Connection -ComputerName $config.testHost -Count 1 -Quiet -ErrorAction Stop
        }
        catch {
            $internetOk = $false
        }
    }

    $status = "OFFLINE"
    if ($internetOk -and $ipv4) {
        $status = "ONLINE"
    }
    if ($ipv4 -and -not $internetOk) {
        $status = "LOCAL_ONLY"
    }

    [ordered]@{
        timestamp = (Get-Date).ToUniversalTime().ToString("o")
        status = $status
        ssid = $ssid
        adapter = $adapter
        ipv4 = $ipv4
        gateway = $gateway
        dnsOk = $dnsOk
        internetOk = $internetOk
    }
}

function Get-Sha256 {
    param([string]$Text)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace("-","").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Write-GuardianEvent {
    param([object]$Event)

    $json = $Event | ConvertTo-Json -Compress -Depth 8
    $previous = ""

    if (Test-Path $stateFile) {
        try {
            $state = Get-Content $stateFile -Raw | ConvertFrom-Json
            if ($state.hash) {
                $previous = [string]$state.hash
            }
        }
        catch {
            $previous = ""
        }
    }

    $chainInput = $previous + $json
    $hash = Get-Sha256 $chainInput

    Add-Content -Path $logFile -Value $json -Encoding utf8
    @{ hash = $hash; previous = $previous } |
        ConvertTo-Json -Compress |
        Set-Content $stateFile -Encoding utf8

    $Event
}

do {
    $event = Get-WlanState
    Write-GuardianEvent $event | ConvertTo-Json -Compress
    if ($Once) {
        break
    }
    Start-Sleep -Seconds ([int]$config.intervalSeconds)
} while ($true)
