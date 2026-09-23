Set-StrictMode -Version Latest

function New-GuardianState {
    [pscustomobject]@{
        State = 'STARTING'
        PreviousState = $null
        UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
        Reason = 'startup'
    }
}

function Set-GuardianState {
    param(
        [Parameter(Mandatory)][object]$Context,
        [Parameter(Mandatory)][ValidateSet('STARTING','INITIALIZING','RUNNING','DEGRADED','FRITZBOX_OFFLINE','NETWORK_UNAVAILABLE','INCIDENT','RECOVERY','STOPPING','ERROR')][string]$State,
        [string]$Reason = ''
    )

    $Context.State.PreviousState = $Context.State.State
    $Context.State.State = $State
    $Context.State.UpdatedUtc = (Get-Date).ToUniversalTime().ToString('o')
    $Context.State.Reason = $Reason
    return $Context.State
}

function Read-GuardianConfig {
    param([Parameter(Mandatory)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration not found: $Path"
    }

    $config = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json

    if ([int]$config.intervalSeconds -lt 1) {
        throw 'intervalSeconds must be greater than zero'
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.logDirectory)) {
        throw 'logDirectory is required'
    }

    return $config
}

Export-ModuleMember -Function New-GuardianState, Set-GuardianState, Read-GuardianConfig