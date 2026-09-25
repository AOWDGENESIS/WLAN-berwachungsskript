Set-StrictMode -Version Latest

function Write-GuardianEvidence {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object]$Event
    )

    $directory = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $directory -Force | Out-Null

    $json = $Event | ConvertTo-Json -Compress -Depth 10
    $previous = ''
    $statePath = "$Path.state.json"

    if (Test-Path -LiteralPath $statePath) {
        try {
            $previous = [string]((Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json).CurrentHash)
        }
        catch {
            $previous = ''
        }
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($previous + $json)
        $hash = ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }

    Add-Content -LiteralPath $Path -Value $json -Encoding utf8
    [pscustomobject]@{
        PreviousHash = $previous
        CurrentHash = $hash
        Event = $Event
    } | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding utf8

    return $hash
}

Export-ModuleMember -Function Write-GuardianEvidence