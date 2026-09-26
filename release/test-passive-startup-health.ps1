param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$EvidenceDirectory='.\test-evidence'
)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Passive startup gates require native Windows PowerShell 5.1.'}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force|Out-Null
$cases=New-Object 'Collections.Generic.List[object]'
$passed=$false
function Check([bool]$Value,[string]$Name){
    if(-not $Value){throw ('FAILED passive startup health: '+$Name)}
    $cases.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host ('PASS passive startup health: '+$Name)
}
function Decision([hashtable]$Values){
    $o=New-Object Tqr.PassiveStartupObservation
    $o.AppFilesReady=$true;$o.EngineReady=$true;$o.Config='Configured'
    $o.Service='Running';$o.Startup='Automatic';$o.Client='Running';$o.Backend='Running'
    foreach($key in $Values.Keys){$o.$key=$Values[$key]}
    return [Tqr.PassiveStartupHealth]::Evaluate($o)
}
$root=Join-Path $env:TEMP ('TqrPassiveStartup-'+[Guid]::NewGuid().ToString('N'))
try{
    $ordinary=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'TailscaleQuickRepair-*.zip' -File|Where-Object Name -notlike '*SetupPackage*')
    Check ($ordinary.Count -eq 1) 'One exact ordinary candidate package is available'
    New-Item -ItemType Directory -Path $root|Out-Null
    Expand-Archive -LiteralPath $ordinary[0].FullName -DestinationPath $root
    $uiPath=Join-Path $root 'app\Tailscale-Repair-UI.ps1'
    $dll=Join-Path $root 'app\TailscaleQuickRepair.Operations.dll'
    Add-Type -Path $dll
    Check ($null -ne ('Tqr.PassiveStartupHealth' -as [type]) -and $null -ne ('Tqr.PassiveStartupObservation' -as [type])) 'Delivered operations DLL contains typed passive startup policy'

    $d=Decision @{}
    Check ($d.Status -eq 'Healthy' -and $d.LocalHealthy -and [string]::IsNullOrEmpty($d.NotificationCode)) 'Healthy local startup is silent'
    $d=Decision @{Config='Missing'}
    Check ($d.Status -eq 'Healthy' -and $d.Reason -eq 'local_healthy_target_missing' -and [string]::IsNullOrEmpty($d.NotificationCode)) 'Missing target does not turn local health into a fault'
    $d=Decision @{Config='Invalid'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_config_attention') 'Invalid local config is actionable without a network check'
    $d=Decision @{AppFilesReady=$false}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_maintenance') 'Missing Quick Repair files require maintenance'
    $d=Decision @{EngineReady=$false}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_maintenance') 'Broken protected integration requires maintenance'
    $d=Decision @{Service='Missing'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_tailscale_missing') 'Missing Tailscale is actionable'
    $d=Decision @{Startup='Disabled'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_service_disabled') 'Disabled Tailscale service is preserved and actionable'
    $d=Decision @{Backend='NeedsLogin'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_sign_in') 'Sign-in state is preserved and actionable'
    $d=Decision @{Backend='NeedsMachineAuth'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_approval') 'Approval state is preserved and actionable'
    $d=Decision @{Backend='InUseOtherUser'}
    Check ($d.Status -eq 'Attention' -and $d.NotificationCode -eq 'startup_other_user') 'Another-user state is preserved and actionable'
    $d=Decision @{Backend='Stopped'}
    Check ($d.Status -eq 'Paused' -and $d.Reason -eq 'disconnected' -and [string]::IsNullOrEmpty($d.NotificationCode)) 'Intentional disconnect is quiet and never turned into startup repair'
    $d=Decision @{Service='Stopped';Backend='Unknown'}
    Check ($d.Status -eq 'Waiting' -and [string]::IsNullOrEmpty($d.NotificationCode)) 'Stopped service is observed without startup mutation'
    foreach($backend in @('Starting','NoState','Unknown')){
        $d=Decision @{Backend=$backend}
        Check ($d.Status -eq 'Waiting' -and [string]::IsNullOrEmpty($d.NotificationCode)) ('Backend '+$backend+' remains a quiet settling state')
    }
    $d=Decision @{Client='Closed'}
    Check ($d.Status -eq 'Waiting' -and [string]::IsNullOrEmpty($d.NotificationCode)) 'Closed desktop client is not reopened by passive startup health'

    foreach($code in @('startup_maintenance','startup_config_attention','startup_tailscale_missing','startup_service_disabled','startup_sign_in','startup_approval','startup_other_user')){
        $prompt=[Tqr.SmartNotifications]::Describe($code)
        Check ($prompt -and $prompt.Warning -and -not [string]::IsNullOrWhiteSpace($prompt.Title) -and -not [string]::IsNullOrWhiteSpace($prompt.Body)) ('Typed notification exists for '+$code)
    }

    $text=[IO.File]::ReadAllText($uiPath,[Text.Encoding]::UTF8)
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'Delivered passive-health UI parses on Windows PowerShell 5.1'
    foreach($name in @('Get-PassiveStartupConfigState','Test-PassiveStartupAppFiles','Update-PassiveTrayStatus','Apply-PassiveStartupPresentation','Invoke-PassiveStartupHealth')){
        $nodes=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
        Check ($nodes.Count -eq 1) ('Exactly one delivered '+$name)
    }
    $invoke=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-PassiveStartupHealth'},$true))[0].Extent.Text
    foreach($forbidden in @('Start-Repair','Invoke-AutoRepairMonitorNow','Advanced-Diagnostics','Repair-Backend.ps1','tailscale ping','peerReachable','RemoteStatus','route','latency')){
        Check (-not $invoke.Contains($forbidden)) ('Passive startup path excludes '+$forbidden)
    }
    Check ($invoke.Contains('New-Object Tqr.WindowsAutoRepairMachine') -and $invoke.Contains('[Tqr.PassiveStartupHealth]::Evaluate')) 'Passive startup uses the bounded local machine observer and pure typed policy'
    $queue=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Queue-StartupInitialization'},$true))
    Check ($queue.Count -eq 1 -and $queue[0].Extent.Text.Contains('Invoke-PassiveStartupHealth')) 'Startup queue invokes passive local health once'
    Check (-not $queue[0].Extent.Text.Contains('Start-Repair')) 'Startup queue never starts repair'

    $passed=$true
}finally{
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    [pscustomobject]@{
        passed=$passed
        source=$env:GITHUB_SHA
        scope='Typed local-only startup health policy and final packaged integration; no peer/network probe and no repair authority'
        cases=@($cases.ToArray())
    }|ConvertTo-Json -Depth 7|Set-Content (Join-Path $EvidenceDirectory 'passive-startup-health-results.json') -Encoding UTF8
}
if(-not $passed){throw 'Passive startup health acceptance failed.'}
