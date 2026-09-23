Set-StrictMode -Version Latest

function Test-GuardianAuthorization {
    param(
        [ValidateSet('LEVEL0','LEVEL1','LEVEL2','LEVEL3')][string]$Required = 'LEVEL0',
        [string]$Granted = 'LEVEL0'
    )

    $rank = @{ LEVEL0 = 0; LEVEL1 = 1; LEVEL2 = 2; LEVEL3 = 3 }
    return $rank[$Granted] -ge $rank[$Required]
}

function Write-GuardianAudit {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Action,
        [string]$Level = 'LEVEL0'
    )

    [pscustomobject]@{
        TimestampUtc = (Get-Date).ToUniversalTime().ToString('o')
        Action = $Action
        Level = $Level
        Result = 'recorded'
    } | ConvertTo-Json -Compress | Add-Content -LiteralPath $Path -Encoding utf8
}

Export-ModuleMember -Function Test-GuardianAuthorization, Write-GuardianAudit