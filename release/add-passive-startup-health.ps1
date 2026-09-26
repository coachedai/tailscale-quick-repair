param([Parameter(Mandatory=$true)][string]$Path)
$ErrorActionPreference='Stop'
$script:text=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
function Replace-One([string]$Old,[string]$New){
    if([regex]::Matches($script:text,[regex]::Escape($Old)).Count -ne 1){
        throw ('Passive startup anchor missing or duplicated: '+$Old.Substring(0,[Math]::Min(100,$Old.Length)))
    }
    $script:text=$script:text.Replace($Old,$New)
}

$functions=@'
    function Get-PassiveStartupConfigState {
        try {
            if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return 'Missing' }
            if (-not [string]::IsNullOrWhiteSpace([string]$Peer)) { return 'Configured' }
            return 'Invalid'
        } catch { return 'Unknown' }
    }

    function Test-PassiveStartupAppFiles {
        foreach($path in @($OperationsLibraryPath,$UpdaterHostPath,$SetupHostPath,$AdvancedDiagnosticsPath,$NativeHostPath)){
            try {
                if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
                $item=Get-Item -LiteralPath $path -ErrorAction Stop
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $item.Length -le 0) { return $false }
            } catch { return $false }
        }
        return $true
    }

    function Update-PassiveTrayStatus {
        param($Decision)
        if (-not $Decision -or -not $script:trayStatusItem) { return }
        if ($script:lastData -and [bool]$script:lastData.done) { return }
        try {
            $status='Local status unknown'
            $color=[System.Drawing.Color]::FromArgb(70,80,92)
            switch([string]$Decision.Status){
                'Healthy' {$status='Local healthy';$color=[System.Drawing.Color]::FromArgb(24,128,88)}
                'Attention' {$status='Local attention';$color=[System.Drawing.Color]::FromArgb(175,120,20)}
                'Paused' {$status='Local disconnected';$color=[System.Drawing.Color]::FromArgb(120,126,138)}
                'Waiting' {$status='Local check pending';$color=[System.Drawing.Color]::FromArgb(70,80,92)}
            }
            $script:trayStatusItem.Text=$status
            $script:trayStatusItem.ForeColor=$color
            if($script:notifyIcon){$script:notifyIcon.Text='Quick Repair - '+$status}
            Update-TrayFreshness
        } catch {}
    }

    function Apply-PassiveStartupPresentation {
        param($Decision,$Health,$EngineCheck)
        try {
            if($Health){
                $LocalAppValue.Text=[string]$Health.Client
                $LocalServiceValue.Text=[string]$Health.Service
                $LocalBackendValue.Text=[string]$Health.Backend
                $appState=if([string]$Health.Client -eq 'Running'){'good'}elseif([string]$Health.Client -eq 'Closed'){'warn'}else{'idle'}
                $serviceState=if([string]$Health.Service -eq 'Running'){'good'}elseif([string]$Health.Service -eq 'Stopped'){'warn'}elseif([string]$Health.Service -eq 'Missing'){'bad'}else{'idle'}
                $backendState=if([string]$Health.Backend -eq 'Running'){'good'}elseif([string]$Health.Backend -in @('NeedsLogin','NeedsMachineAuth','InUseOtherUser','Stopped')){'warn'}elseif([string]$Health.Backend -eq 'Starting'){'active'}else{'idle'}
                Set-Step $AppDot $AppStep $appState
                Set-Step $ServiceDot $ServiceStep $serviceState
                Set-Step $BackendDot $BackendStep $backendState
            }

            switch([string]$Decision.Status){
                'Healthy' { Set-Badge $LocalBadge $LocalBadgeText 'LOCAL HEALTHY' 'success' }
                'Attention' { Set-Badge $LocalBadge $LocalBadgeText 'LOCAL ATTENTION' 'warning' }
                'Paused' { Set-Badge $LocalBadge $LocalBadgeText 'DISCONNECTED' 'idle' }
                default { Set-Badge $LocalBadge $LocalBadgeText 'LOCAL CHECK' 'idle' }
            }

            if([string]$Decision.Reason -eq 'quick_repair_maintenance' -and $EngineCheck){
                Show-EngineIssue $EngineCheck
            }

            Update-PassiveTrayStatus $Decision
        } catch {}
    }

    function Invoke-PassiveStartupHealth {
        try {
            Initialize-OperationGate
            $engine=Test-RepairEngine
            $script:engineHealthy=[bool]$engine.Healthy
            $script:lastEngineCheckAt=Get-Date

            $health=$null
            try {
                $machine=New-Object Tqr.WindowsAutoRepairMachine
                $health=$machine.Observe()
            } catch {}

            $observation=New-Object Tqr.PassiveStartupObservation
            $observation.AppFilesReady=[bool](Test-PassiveStartupAppFiles)
            $observation.EngineReady=[bool]$engine.Healthy
            $observation.Config=Get-PassiveStartupConfigState
            if($health){
                $observation.Service=[string]$health.Service
                $observation.Startup=[string]$health.Startup
                $observation.Client=[string]$health.Client
                $observation.Backend=[string]$health.Backend
            }

            $decision=[Tqr.PassiveStartupHealth]::Evaluate($observation)
            Apply-PassiveStartupPresentation $decision $health $engine

            if(-not [string]::IsNullOrWhiteSpace([string]$decision.NotificationCode)){
                [void](Request-SmartNotification ([string]$decision.NotificationCode) ([DateTime]::UtcNow.ToString('o')))
            }
            return $decision
        } catch {
            try {
                Set-Badge $LocalBadge $LocalBadgeText 'LOCAL UNKNOWN' 'idle'
                if(-not ($script:lastData -and [bool]$script:lastData.done)){
                    $script:trayStatusItem.Text='Local status unknown'
                    if($script:notifyIcon){$script:notifyIcon.Text='Quick Repair - Local status unknown'}
                }
            } catch {}
            return $null
        }
    }

'@

Replace-One '    function Start-ResidentRuntime {' ($functions+'    function Start-ResidentRuntime {')
Replace-One @'
                if (-not (Attach-To-RunningRepair)) {
                    [void](Refresh-EngineCheck)
                }
'@ @'
                if (-not (Attach-To-RunningRepair)) {
                    [void](Invoke-PassiveStartupHealth)
                }
'@

foreach($required in @(
    'function Invoke-PassiveStartupHealth',
    'function Update-PassiveTrayStatus',
    '[Tqr.PassiveStartupHealth]::Evaluate',
    'New-Object Tqr.WindowsAutoRepairMachine',
    'Request-SmartNotification',
    'Invoke-PassiveStartupHealth'
)){
    if($script:text -notmatch [regex]::Escape($required)){throw ('Passive startup integration missing: '+$required)}
}

[void][scriptblock]::Create($script:text)
[IO.File]::WriteAllText($Path,$script:text,(New-Object Text.UTF8Encoding($true)))
Write-Host 'Local-only passive startup health integrated.'
