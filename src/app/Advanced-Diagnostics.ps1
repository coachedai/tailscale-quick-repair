param(
    [Parameter(Mandatory=$true)][string]$Peer,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$RunId
)

$ErrorActionPreference = 'SilentlyContinue'

$script:Result = [ordered]@{
    runId = $RunId
    done = $false
    phase = 'Starting'
    progress = 2
    severity = 'checking'
    summary = 'Preparing advanced diagnostics.'
    udp = 'Unknown'
    ipv4 = 'Unknown'
    ipv6 = 'Unknown'
    nearestDerp = 'Unknown'
    mapping = 'Unknown'
    portMapping = 'Unknown'
    path = 'Unknown'
    latency = 'Unknown'
    disco = 'Unknown'
    tsmp = 'Unknown'
    icmp = 'Unknown'
    peerApi = 'Unknown'
    otherVpns = @()
    error = ''
}

function Publish {
    param(
        [string]$Phase,
        [int]$Progress,
        [bool]$Done = $false,
        [string]$Severity = 'checking',
        [string]$Summary = ''
    )

    $script:Result.phase = $Phase
    $script:Result.progress = $Progress
    $script:Result.done = $Done
    $script:Result.severity = $Severity

    if ($Summary) {
        $script:Result.summary = $Summary
    }

    try {
        $tmp = $OutputPath + '.tmp'
        $script:Result |
            ConvertTo-Json -Depth 6 -Compress |
            Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $OutputPath -Force
    }
    catch {}
}

function Get-TailscaleCli {
    $candidates = @(
        "$env:ProgramFiles\Tailscale\tailscale.exe",
        "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe",
        "$env:LOCALAPPDATA\Tailscale\tailscale.exe"
    )

    foreach ($candidate in $candidates) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) {
            return $candidate
        }
    }

    $command = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    return $null
}

function Invoke-TailscalePing {
    param(
        [string]$Cli,
        [string]$PeerAddress,
        [ValidateSet('disco','tsmp','icmp','peerapi')]
        [string]$Type
    )

    try {
        switch ($Type) {
            'tsmp'    { $lines = & $Cli ping '--tsmp' '--c=1' '--timeout=3s' $PeerAddress 2>&1 }
            'icmp'    { $lines = & $Cli ping '--icmp' '--c=1' '--timeout=3s' $PeerAddress 2>&1 }
            'peerapi' { $lines = & $Cli ping '--peerapi' '--c=1' '--timeout=3s' $PeerAddress 2>&1 }
            default   { $lines = & $Cli ping '--until-direct=false' '--c=1' '--timeout=3s' $PeerAddress 2>&1 }
        }

        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = (($lines | Out-String).Trim())
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = -1
            Output = $_.Exception.Message
        }
    }
}

function Parse-Netcheck {
    param([string]$Text)

    foreach ($raw in @($Text -split "`r?`n")) {
        $line = $raw.Trim()

        if ($line -match '^\*\s*UDP:\s*(.+)$') {
            $script:Result.udp = if ($Matches[1] -match '^(?i:true|yes)') { 'Available' } else { 'Unavailable' }
            continue
        }

        if ($line -match '^\*\s*IPv4:\s*(.+)$') {
            $script:Result.ipv4 = if ($Matches[1] -match '^(?i:no|false)') { 'Unavailable' } else { 'Available' }
            continue
        }

        if ($line -match '^\*\s*IPv6:\s*(.+)$') {
            $script:Result.ipv6 = if ($Matches[1] -match '^(?i:no|false)') { 'Unavailable' } else { 'Available' }
            continue
        }

        if ($line -match '^\*\s*Nearest DERP:\s*(.+)$') {
            $script:Result.nearestDerp = $Matches[1].Trim()
            continue
        }

        if ($line -match '^\*\s*MappingVariesByDestIP:\s*(true|false)') {
            $script:Result.mapping = if ($Matches[1] -eq 'true') { 'Varies by destination' } else { 'Stable mapping' }
            continue
        }

        if ($line -match '^\*\s*PortMapping:\s*(.*)$') {
            $value = $Matches[1].Trim()
            $script:Result.portMapping = if ($value) { $value } else { 'None detected' }
        }
    }
}

function Summarize-Ping {
    param($Ping)

    if (-not $Ping) { return 'Unknown' }
    if ($Ping.ExitCode -eq 0) { return 'Reachable' }
    if ($Ping.Output -match '(?i)timeout|timed out|no reply|no response') { return 'Timed out' }
    if ($Ping.Output) { return 'Unavailable' }
    return 'Unknown'
}

function Detect-OtherVpns {
    $names = [ordered]@{
        'ProtonVPN' = @('protonvpn','protonvpnservice')
        'NordVPN' = @('nordvpn','nordvpn-service')
        'WireGuard' = @('wireguard')
        'OpenVPN' = @('openvpn','openvpnservice')
        'Mullvad' = @('mullvad','mullvad-daemon')
    }

    $found = @()

    foreach ($label in $names.Keys) {
        foreach ($name in $names[$label]) {
            $hasProcess = [bool](Get-Process -Name $name -ErrorAction SilentlyContinue)
            $hasService = [bool](Get-Service -Name $name -ErrorAction SilentlyContinue)

            if ($hasProcess -or $hasService) {
                $found += $label
                break
            }
        }
    }

    return @($found | Select-Object -Unique)
}

try {
    Publish 'Finding Tailscale' 5

    $cli = Get-TailscaleCli
    if (-not $cli) {
        $script:Result.error = 'tailscale.exe could not be found.'
        Publish 'Complete' 100 $true 'failure' 'Tailscale CLI could not be found.'
        exit
    }

    Publish 'Inspecting network conditions' 18

    try {
        $netcheck = & $cli netcheck 2>&1 | Out-String
        if ($netcheck) { Parse-Netcheck $netcheck }
    }
    catch {}

    Publish 'Checking direct path' 42

    $disco = Invoke-TailscalePing -Cli $cli -PeerAddress $Peer -Type disco
    $script:Result.disco = Summarize-Ping $disco

    if ($disco.Output -match '(?i)via DERP\(([^)]+)\)') {
        $script:Result.path = 'Relay · ' + $Matches[1]
    }
    elseif ($disco.Output -match '(?i)direct') {
        $script:Result.path = 'Direct'
    }

    if ($disco.Output -match '(?i)([0-9]+(?:\.[0-9]+)?)ms') {
        $roundedLatency = [Math]::Round([double]$Matches[1])
        $script:Result.latency = ([string]$roundedLatency) + ' ms'
    }

    Publish 'Checking peer protocols' 62

    $script:Result.tsmp = Summarize-Ping (Invoke-TailscalePing -Cli $cli -PeerAddress $Peer -Type tsmp)
    $script:Result.icmp = Summarize-Ping (Invoke-TailscalePing -Cli $cli -PeerAddress $Peer -Type icmp)
    $script:Result.peerApi = Summarize-Ping (Invoke-TailscalePing -Cli $cli -PeerAddress $Peer -Type peerapi)

    Publish 'Checking local VPN environment' 82
    $script:Result.otherVpns = @(Detect-OtherVpns)

    $issues = @()
    if ($script:Result.udp -eq 'Unavailable') { $issues += 'UDP unavailable' }
    if ($script:Result.path -like 'Relay*') { $issues += 'peer is relayed' }
    if ($script:Result.disco -ne 'Reachable') { $issues += 'peer path did not answer' }

    if ($issues.Count -gt 0) {
        Publish 'Complete' 100 $true 'warning' ($issues -join ' · ')
    }
    else {
        Publish 'Complete' 100 $true 'success' 'Advanced diagnostics found no obvious connection issue.'
    }
}
catch {
    $script:Result.error = $_.Exception.Message
    Publish 'Complete' 100 $true 'failure' 'Advanced diagnostics could not complete.'
}
