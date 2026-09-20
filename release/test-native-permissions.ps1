param([string]$EvidenceDirectory='.\test-evidence',[switch]$Child,[string]$Helper='', [string]$ExpectedSid='', [string]$Report='')
$ErrorActionPreference='Stop'
# This suite follows real Windows installation acceptance in the SAME disposable
# job. It must never repair, install onto or probe a user's working PC.
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:GITHUB_REPOSITORY -cne 'coachedai/tailscale-quick-repair' -or
   $env:GITHUB_REF_NAME -cne 'work/6.1-auto-repair-safety' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:TQR_NATIVE_LAB_RUN -cne $env:GITHUB_RUN_ID -or [string]::IsNullOrEmpty($env:GITHUB_RUN_ID) -or
   $PSVersionTable.PSVersion.Major -ne 5){throw 'Disposable permission acceptance guard refused this environment.'}
$program=Join-Path $env:ProgramData 'TailscaleQuickRepair'
$app=Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$taskNames=@('Tailscale Quick Repair','Tailscale Quick Repair Auto Monitor')
if($Child){
    $cases=New-Object 'Collections.Generic.List[object]';$complete=$false;$errorCode=0
    function Record([bool]$Value,[string]$Name){$cases.Add([pscustomobject]@{name=$Name;passed=$Value})}
    try{
        Add-Type -Path $Helper
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
        $principal=New-Object Security.Principal.WindowsPrincipal($identity)
        $low=-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        Record ($low -and $identity.User.Value -ceq $ExpectedSid) 'Child is the same user without an enabled Administrators group'
        Record ([TqrPermissionLab.Probe]::Integrity() -eq 8192) 'Child runs at medium integrity rather than elevated integrity'
        Record ([TqrPermissionLab.Probe]::PrivilegeCount() -le 1) 'Privileged token capabilities are removed, not merely unused'
        if(-not $low -or [TqrPermissionLab.Probe]::Integrity() -ne 8192){throw 'Invalid test token.'}
        $files=@('Auto-Repair-Monitor.ps1','Repair-Backend.ps1','TailscaleQuickRepair.Operations.dll','Launch-Auto-Repair-Monitor.vbs','Launch-Tailscale-Backend.vbs')
        foreach($name in $files){
            $path=Join-Path $program $name
            Record ([TqrPermissionLab.Probe]::Open($path,2147483648,$false).Allowed) ('Protected file remains readable: '+$name)
            foreach($right in @(@('write',2),@('append',4),@('delete',65536),@('change permissions',262144),@('take ownership',524288))){
                $r=[TqrPermissionLab.Probe]::Open($path,[uint32]$right[1],$false)
                Record (-not $r.Allowed -and $r.Error -eq 5) ('Ordinary user cannot '+$right[0]+' protected '+$name)
            }
        }
        foreach($right in @(@('add files',2),@('add directories',4),@('delete children',64),@('delete directory',65536),@('change permissions',262144),@('take ownership',524288))){
            $r=[TqrPermissionLab.Probe]::Open($program,[uint32]$right[1],$true)
            Record (-not $r.Allowed -and $r.Error -eq 5) ('Ordinary user cannot '+$right[0]+' in protected root')
        }
        $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\')
        foreach($name in $taskNames){
            $task=$folder.GetTask($name);$sddl=[string]$task.GetSecurityDescriptor(7)
            Record ($sddl.Length -gt 0 -and $task.Definition.Actions.Count -eq 1) ('Ordinary user can inspect fixed task: '+$name)
            $sd=New-Object Security.AccessControl.RawSecurityDescriptor($sddl)
            Record ($sd.Owner.Value -eq 'S-1-5-32-544' -or $sd.Owner.Value -eq 'S-1-5-18') ('Ordinary user does not own task permissions: '+$name)
            $denied=$false
            try{$task.SetSecurityDescriptor($sddl,16)}catch{$denied=($_.Exception.HResult -eq -2147024891 -or $_.Exception.InnerException.HResult -eq -2147024891)}
            Record $denied ('Ordinary user cannot rewrite task security descriptor: '+$name)
            $denied=$false
            try{$task.Enabled=[bool]$task.Enabled}catch{$denied=($_.Exception.HResult -eq -2147024891 -or $_.Exception.InnerException.HResult -eq -2147024891)}
            Record $denied ('Ordinary user cannot rewrite task settings: '+$name)
        }
        # Execute the actual installed UI's settings and task-dispatch functions,
        # with real COM discovery. No substituted scheduler or UAC is involved.
        $ui=[IO.File]::ReadAllText((Join-Path $app 'Tailscale-Repair-UI.ps1'))
        $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($ui,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw 'Installed UI parse failed.'}
        foreach($name in @('Initialize-OperationGate','Get-AutoRepairEnabled','Set-AutoRepairEnabled','Invoke-AutoRepairMonitorNow')){
            $nodes=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq $name},$true))
            if($nodes.Count -ne 1){throw 'Installed UI function count invalid.'}
            . ([scriptblock]::Create($nodes[0].Extent.Text))
        }
        $StateDir=$app;$OperationsLibraryPath=Join-Path $app 'TailscaleQuickRepair.Operations.dll';$AutoRepairTaskName=$taskNames[1]
        Record (Set-AutoRepairEnabled $true) 'Ordinary UI can persist explicit automatic-repair opt-in'
        $auto=$folder.GetTask($AutoRepairTaskName)
        $last=[Tqr.AutoRepairRecords]::Current($app)
        if($last){
            $remaining=31-([DateTime]::UtcNow-[DateTime]::Parse($last.lastCheckedUtc)).TotalSeconds
            if($remaining -gt 0 -and $remaining -le 36){Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining*1000))}
        }
        $start=[DateTime]::UtcNow
        Record (Invoke-AutoRepairMonitorNow) 'Actual ordinary UI function requests the protected monitor without elevation'
        $end=[DateTime]::UtcNow.AddSeconds(35);$observed=$null
        do{
            $observed=[Tqr.AutoRepairRecords]::Current($app)
            if($observed -and [DateTime]::Parse($observed.lastCheckedUtc).ToUniversalTime() -ge $start){break}
            Start-Sleep -Milliseconds 200
        }while([DateTime]::UtcNow -lt $end)
        Record ($observed -and [DateTime]::Parse($observed.lastCheckedUtc).ToUniversalTime() -ge $start -and $observed.phase -eq 'Complete' -and $observed.actionsAttempted -eq 0) 'Ordinary request produces a fresh protected local-only observation, not a forged success'
        Record (Set-AutoRepairEnabled $false) 'Ordinary UI can persist opt-out without protected-file write permission'
        Record (-not (Invoke-AutoRepairMonitorNow)) 'Ordinary opt-out prevents another monitor dispatch'
        $complete=$true
    }catch{$errorCode=$_.Exception.HResult}
    finally{
        [pscustomobject]@{complete=$complete;errorCode=$errorCode;cases=@($cases.ToArray())}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Report -Encoding UTF8
    }
    exit 0 # Parent inspects every recorded assertion and fails the workflow.
}
$evidence=(Resolve-Path $EvidenceDirectory).Path
$prior=Get-Content (Join-Path $evidence 'native-windows-results.json') -Raw|ConvertFrom-Json
if(-not $prior.passed -or $prior.source -cne $env:GITHUB_SHA){throw 'Same-run real installation acceptance is required first.'}
if(Get-Service 'Tailscale' -ErrorAction SilentlyContinue){throw 'The preceding lab must have removed its vendor installation.'}
$work=Join-Path $env:RUNNER_TEMP ('TqrPermissions-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $work|Out-Null
$reportPath=Join-Path $work 'restricted-results.json';$helperPath=Join-Path $work 'PermissionProbe.dll'
$created=New-Object 'Collections.Generic.List[string]';$cases=New-Object 'Collections.Generic.List[object]';$childProcess=$null;$all=$false;$errorCode=0;$cleanup=$true
try{
    $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\')
    foreach($name in $taskNames){$exists=$false;try{[void]$folder.GetTask($name);$exists=$true}catch{};if($exists){throw 'Existing task was not created by this permission fixture.'}}
    $hashes=@{};foreach($file in Get-ChildItem -LiteralPath $program -File){$hashes[$file.Name]=(Get-FileHash $file.FullName).Hash}
    $setup=[Reflection.Assembly]::LoadFile((Join-Path $app 'TailscaleQuickRepairSetup.exe')).GetType('PublicSetupHost')
    foreach($pair in @(@('RegisterRepairTask',$taskNames[0]),@('RegisterAutoRepairTask',$taskNames[1]))){
        [void]$setup.GetMethod($pair[0],[Reflection.BindingFlags]'NonPublic,Static').Invoke($null,@());$created.Add($pair[1])
    }
    $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    & $compiler /nologo /target:library ('/out:'+$helperPath) (Join-Path $PSScriptRoot 'NativePermissionProbe.cs')
    if($LASTEXITCODE -ne 0){throw 'Native token test helper did not compile.'}
    Add-Type -Path $helperPath
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $arguments='-NoProfile -NonInteractive -STA -File "'+$PSCommandPath+'" -Child -Helper "'+$helperPath+'" -ExpectedSid "'+$sid+'" -Report "'+$reportPath+'"'
    $childProcess=[TqrPermissionLab.Probe]::StartRestricted((Join-Path $PSHOME 'powershell.exe'),$arguments,$work)
    if(-not $childProcess.WaitForExit(120000)){throw 'Restricted child exceeded its time bound; no test rerun.'}
    $report=Get-Content -LiteralPath $reportPath -Raw|ConvertFrom-Json
    foreach($case in $report.cases){$cases.Add($case)}
    $cases.Add([pscustomobject]@{name='Restricted native child completes all probes';passed=($report.complete -and $childProcess.ExitCode -eq 0)})
    foreach($name in $hashes.Keys){$cases.Add([pscustomobject]@{name=('Non-destructive probes preserve protected bytes: '+$name);passed=((Get-FileHash (Join-Path $program $name)).Hash -ceq $hashes[$name])})}
    $all=(@($cases|Where-Object {-not $_.passed}).Count -eq 0)
}catch{$errorCode=$_.Exception.HResult}
finally{
    if($childProcess){try{if(-not $childProcess.HasExited){$childProcess.Kill();[void]$childProcess.WaitForExit(5000)}}catch{$cleanup=$false};$childProcess.Dispose()}
    foreach($name in $created){
        try{
            $task=$folder.GetTask($name);$task.Enabled=$false;$end=[DateTime]::UtcNow.AddSeconds(120)
            while([int]$task.State -in @(2,4) -and [DateTime]::UtcNow -lt $end){Start-Sleep -Milliseconds 200}
            if([int]$task.State -in @(2,4)){throw 'Owned task still active.'}
            $folder.DeleteTask($name,0)
        }catch{$cleanup=$false}
    }
    $cases.Add([pscustomobject]@{name='Only this permission fixture tasks and child are cleaned up';passed=$cleanup})
    [pscustomobject]@{passed=($all -and $cleanup);source=$env:GITHUB_SHA;scope='Same-user medium-integrity restricted process, real file access opens, COM task protection and exact installed UI dispatch';cases=@($cases.ToArray());errorCode=$errorCode;limits=@('Restricted token is not a claim of every Windows standard-user or split-token configuration','No file content is written or deleted by permission probes; task writes submit only unchanged values','No live Tailscale or tailnet; protected task observes the missing installation','Unrelated-user, alternate-admin, hostile pre-existing paths and signed provenance remain separate acceptance')}|ConvertTo-Json -Depth 9|Set-Content (Join-Path $evidence 'native-permission-results.json') -Encoding UTF8
}
if(-not $all -or -not $cleanup){throw 'Native permission acceptance did not pass; preserve and inspect the typed report.'}
