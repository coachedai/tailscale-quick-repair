param(
    [Parameter(Mandatory=$true)][string]$Peer,
    [Parameter(Mandatory=$true)][string]$OutputPath,
    [Parameter(Mandatory=$true)][string]$RunId
)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
$clock=[Diagnostics.Stopwatch]::StartNew()
$script:Result=[ordered]@{
    schema=2;runId=$RunId;done=$false;phase='Starting';progress=2;severity='checking'
    summary='Preparing read-only diagnostics.';detail='';updatedUtc=[DateTime]::UtcNow.ToString('o');durationSeconds=0
    udp='Unknown';ipv4='Unknown';ipv6='Unknown';nearestDerp='Unknown';mapping='Unknown';portMapping='Unknown'
    netcheckStatus='Incomplete';path='Unknown';latency='Unknown';disco='Unknown';tsmp='Unknown';icmp='Unknown';peerApi='Unknown'
    otherVpns=@();error=''
}
function Publish {
    param([string]$Phase,[int]$Progress,[bool]$Done=$false,[string]$Severity='checking',[string]$Summary='')
    $script:Result.phase=$Phase;$script:Result.progress=$Progress;$script:Result.done=$Done;$script:Result.severity=$Severity
    $script:Result.updatedUtc=[DateTime]::UtcNow.ToString('o')
    $script:Result.durationSeconds=[Math]::Round($clock.Elapsed.TotalSeconds,1)
    if($Summary){$script:Result.summary=$Summary}
    $temp=$OutputPath+'.'+[Guid]::NewGuid().ToString('N')+'.tmp'
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes(($script:Result|ConvertTo-Json -Depth 6 -Compress))
        $stream=[IO.File]::Open($temp,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)} finally {$stream.Dispose()}
        if(Test-Path -LiteralPath $OutputPath){[IO.File]::Replace($temp,$OutputPath,$null)}
        else{[IO.File]::Move($temp,$OutputPath)}
    } catch {} finally {if(Test-Path -LiteralPath $temp){Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue}}
}
function Get-TailscaleCli {
    foreach($candidate in @("$env:ProgramFiles\Tailscale\tailscale.exe","${env:ProgramFiles(x86)}\Tailscale\tailscale.exe","$env:LOCALAPPDATA\Tailscale\tailscale.exe")) {
        if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){return $candidate}
    }
    $command=Get-Command tailscale.exe -CommandType Application -ErrorAction SilentlyContinue
    if($command){return $command.Source}
    return $null
}
function Read-Probe {
    param([string]$Cli,[string]$Type,[int]$LimitMs=3000)
    $remaining=20000-[int]$clock.Elapsed.TotalMilliseconds
    if($remaining -lt 100){$r=New-Object Tqr.DiagnosticCommand;$r.TimedOut=$true;return $r}
    return [Tqr.DiagnosticAnalysis]::Run($Cli,$Type,$Peer,[Math]::Min($LimitMs,$remaining))
}
function Detect-OtherVpns {
    # Presence only: installed services do not prove a VPN is connected or conflicting.
    $known=[ordered]@{
        ProtonVPN=@('protonvpn','protonvpnservice');NordVPN=@('nordvpn','nordvpn-service')
        WireGuard=@('wireguard');OpenVPN=@('openvpn','openvpnservice');Mullvad=@('mullvad','mullvad-daemon')
    }
    $found=@()
    foreach($label in $known.Keys){
        foreach($name in $known[$label]){
            if((Get-Process -Name $name -ErrorAction SilentlyContinue) -or (Get-Service -Name $name -ErrorAction SilentlyContinue)){
                $found+=$label;break
            }
        }
    }
    return $found
}
try {
    Publish 'Finding Tailscale' 5
    Add-Type -Path (Join-Path $PSScriptRoot 'TailscaleQuickRepair.Operations.dll') -ErrorAction Stop
    if(-not [Tqr.DiagnosticAnalysis]::ValidPeer($Peer)){throw 'Invalid peer input.'}
    $cli=Get-TailscaleCli
    if(-not $cli){
        $script:Result.error='cli_missing';$script:Result.detail='The diagnostic CLI was not found. No network settings were changed.'
        Publish 'Complete' 100 $true 'warn' 'Diagnostics could not find the Tailscale CLI.'
        exit 0
    }
    Publish 'Inspecting network conditions' 15
    $net=[Tqr.DiagnosticAnalysis]::ParseNetwork((Read-Probe $cli 'netcheck' 8000))
    foreach($name in @('udp','ipv4','ipv6','nearestDerp','mapping','portMapping')){$script:Result[$name]=[string]$net.$name}
    $script:Result.netcheckStatus=$net.status
    Publish 'Probing the peer path' 40
    $disco=[Tqr.DiagnosticAnalysis]::ParseProbe((Read-Probe $cli 'disco'),'disco')
    $script:Result.disco=$disco.Status;$script:Result.path=$disco.Path;$script:Result.latency=$disco.Latency
    Publish 'Probing the tunnel' 55
    $tunnel=[Tqr.DiagnosticAnalysis]::ParseProbe((Read-Probe $cli 'tsmp'),'tsmp');$script:Result.tsmp=$tunnel.Status
    Publish 'Probing ICMP' 70
    $icmp=[Tqr.DiagnosticAnalysis]::ParseProbe((Read-Probe $cli 'icmp'),'icmp');$script:Result.icmp=$icmp.Status
    Publish 'Probing Peer API' 85
    $api=[Tqr.DiagnosticAnalysis]::ParseProbe((Read-Probe $cli 'peerapi'),'peerapi');$script:Result.peerApi=$api.Status
    $script:Result.otherVpns=@(Detect-OtherVpns)
    $verdict=[Tqr.DiagnosticAnalysis]::Explain($net,$disco,$tunnel,$icmp,$api)
    $script:Result.detail=$verdict.Detail
    if($script:Result.otherVpns.Count -gt 0){$script:Result.detail+=' Detected VPN software is not evidence of an active conflict.'}
    Publish 'Complete' 100 $true $verdict.Severity $verdict.Summary
} catch {
    $script:Result.error='inspection_incomplete'
    $script:Result.detail='One or more diagnostic steps could not complete. The main connection check and network settings were not changed.'
    Publish 'Complete' 100 $true 'warn' 'Diagnostics could not complete every step.'
}
