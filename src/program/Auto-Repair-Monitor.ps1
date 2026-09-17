$ErrorActionPreference = 'SilentlyContinue'

$RepairTaskName = 'Tailscale Quick Repair'
$AppDir = Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$SettingsPath = Join-Path $AppDir 'auto-repair.json'
$StatePath = Join-Path $AppDir 'auto-repair-state.json'
$CooldownMinutes = 15

function Write-State {
    param(
        [string]$Status,
        [string]$Message,
        [string]$Service = 'Unknown',
        [string]$Client = 'Unknown',
        [string]$Backend = 'Unknown',
        [string]$Reason = '',
        [bool]$RepairStarted = $false,
        [int]$CooldownRemainingMinutes = 0
    )

    $lastRepairUtc = ''
    $lastRepairReason = ''

    try {
        if (Test-Path -LiteralPath $StatePath) {
            $previous = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
            $lastRepairUtc = [string]$previous.lastRepairUtc
            $lastRepairReason = [string]$previous.lastRepairReason
        }
    }
    catch {}

    if ($RepairStarted) {
        $lastRepairUtc = [DateTime]::UtcNow.ToString('o')
        $lastRepairReason = $Reason
    }

    $state = [ordered]@{
        lastCheckedUtc = [DateTime]::UtcNow.ToString('o')
        status = $Status
        message = $Message
        service = $Service
        client = $Client
        backend = $Backend
        lastRepairUtc = $lastRepairUtc
        lastRepairReason = $lastRepairReason
        cooldownRemainingMinutes = $CooldownRemainingMinutes
    }

    try {
        New-Item -ItemType Directory -Path $AppDir -Force | Out-Null
        $tmp = $StatePath + '.tmp'
        $state | ConvertTo-Json -Compress | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $StatePath -Force
    }
    catch {}
}

function Get-Enabled {
    try {
        if (-not (Test-Path -LiteralPath $SettingsPath)) { return $false }
        $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
        return [bool]$settings.enabled
    }
    catch {
        return $false
    }
}

function Get-TailscaleCli {
    foreach ($candidate in @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
        "$env:LOCALAPPDATA\Tailscale\tailscale.exe"
    )) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Get-LocalHealth {
    $service = Get-Service -Name 'Tailscale' -ErrorAction SilentlyContinue
    $serviceState = if (-not $service) { 'Missing' } elseif ($service.Status -eq 'Running') { 'Running' } else { 'Stopped' }

    $clientState = if (Get-Process -Name 'tailscale-ipn' -ErrorAction SilentlyContinue) { 'Running' } else { 'Closed' }
    $backendState = 'Unknown'

    $cli = Get-TailscaleCli
    if ($cli -and $serviceState -eq 'Running') {
        try {
            $statusRaw = & $cli status '--json' 2>$null | Out-String
            if ($LASTEXITCODE -eq 0 -and $statusRaw) {
                $status = $statusRaw | ConvertFrom-Json
                $backendState = if ([string]$status.BackendState) { [string]$status.BackendState } else { 'Running' }
            }
        }
        catch {}
    }

    return [pscustomobject]@{
        Service = $serviceState
        Client = $clientState
        Backend = $backendState
    }
}

function Get-CooldownRemainingMinutes {
    try {
        if (-not (Test-Path -LiteralPath $StatePath)) { return 0 }
        $state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
        if (-not $state.lastRepairUtc) { return 0 }

        $when = [DateTime]::Parse(
            [string]$state.lastRepairUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        )

        $remaining = $CooldownMinutes - ([DateTime]::UtcNow - $when.ToUniversalTime()).TotalMinutes
        if ($remaining -le 0) { return 0 }
        return [int][Math]::Ceiling($remaining)
    }
    catch {
        return 0
    }
}

function Start-ProtectedRepair {
    $service = $null
    $folder = $null
    $task = $null

    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        $task = $folder.GetTask($RepairTaskName)

        if (-not $task) { return $false }
        [void]$task.Run($null)
        return $true
    }
    catch {
        return $false
    }
    finally {
        foreach ($item in @($task,$folder,$service)) {
            if ($item) {
                try { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($item) } catch {}
            }
        }
    }
}

if (-not (Get-Enabled)) {
    Write-State -Status 'disabled' -Message 'Automatic repair is off.'
    exit 0
}

$health = Get-LocalHealth
$reason = ''

if ($health.Service -eq 'Missing') {
    $reason = 'Tailscale service is missing.'
}
elseif ($health.Service -ne 'Running') {
    $reason = 'Tailscale service is stopped.'
}
elseif ($health.Client -ne 'Running') {
    $reason = 'Tailscale desktop client is closed.'
}
elseif (
    $health.Backend -and
    $health.Backend -notin @('Running','Unknown')
) {
    $reason = 'Tailscale backend is not running.'
}

if (-not $reason) {
    Write-State `
        -Status 'healthy' `
        -Message 'Local Tailscale is healthy.' `
        -Service $health.Service `
        -Client $health.Client `
        -Backend $health.Backend
    exit 0
}

$cooldown = Get-CooldownRemainingMinutes
if ($cooldown -gt 0) {
    Write-State `
        -Status 'cooldown' `
        -Message 'A recent automatic repair is still in cooldown.' `
        -Service $health.Service `
        -Client $health.Client `
        -Backend $health.Backend `
        -Reason $reason `
        -CooldownRemainingMinutes $cooldown
    exit 0
}

if (Start-ProtectedRepair) {
    Write-State `
        -Status 'repaired' `
        -Message 'Automatic repair started.' `
        -Service $health.Service `
        -Client $health.Client `
        -Backend $health.Backend `
        -Reason $reason `
        -RepairStarted $true
}
else {
    Write-State `
        -Status 'error' `
        -Message 'The protected repair task could not be started.' `
        -Service $health.Service `
        -Client $health.Client `
        -Backend $health.Backend `
        -Reason $reason
}
