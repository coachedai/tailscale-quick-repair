param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$EvidenceDirectory='.\upgrade-evidence'
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$releaseValidation=($env:GITHUB_REF_NAME -ceq 'main' -and $env:TQR_RELEASE_VALIDATION -ceq $env:GITHUB_RUN_ID -and -not [string]::IsNullOrEmpty($env:GITHUB_RUN_ID))
$developmentValidation=($env:GITHUB_REF_NAME -ceq 'work/6.1-auto-repair-safety')
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:RUNNER_OS -cne 'Windows' -or
   $env:RUNNER_ARCH -cne 'X64' -or $env:GITHUB_REPOSITORY -cne 'coachedai/tailscale-quick-repair' -or
   -not ($developmentValidation -or $releaseValidation) -or $env:TQR_NATIVE_LAB_RUN -cne $env:GITHUB_RUN_ID -or
   -not $env:GITHUB_RUN_ID -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Interrupted Setup lab requires a disposable native Windows runner.'}

$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $repo rev-parse HEAD).Trim() -cne $env:GITHUB_SHA -or
   (git -C $repo remote get-url origin).Trim() -notmatch '^https://github.com/coachedai/tailscale-quick-repair(?:\.git)?$' -or
   ((Get-Content (Join-Path $repo 'release\publish.json') -Raw|ConvertFrom-Json).publish -and -not $releaseValidation)){
    throw 'Exact isolated source is required.'
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force|Out-Null
$evidence=(Resolve-Path $EvidenceDirectory).Path
$lab=Join-Path $env:RUNNER_TEMP ('TqrInterruptedSetup-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($lab)
$app=Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$program=Join-Path $env:ProgramData 'TailscaleQuickRepair'
$recovery=Join-Path $env:ProgramData 'TailscaleQuickRepair.SetupRecovery'
$taskNames=@('Tailscale Quick Repair','Tailscale Quick Repair Auto Monitor')
$cases=New-Object 'Collections.Generic.List[object]';$passed=$false;$cleanup=$true;$child=$null;$failure=$null;$stage='preflight'
$legacyHash='bad4deb522afd9442e918cacde1f58cc1509635de3be172626846060516df470'
function Check([bool]$Value,[string]$Name){$script:stage=$Name;$cases.Add([pscustomobject]@{name=$Name;passed=$Value});if(-not $Value){throw 'Interrupted Setup assertion failed.'};Write-Host ('PASS interrupted Setup: '+$Name)}
function Hash([string]$Path){return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()}
function Expand-Verified([string]$Zip,[string]$Destination){
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($Zip)
    $seen=New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    try{
        $total=0L
        foreach($entry in $archive.Entries){
            $name=$entry.FullName.Replace('\','/');if($name.EndsWith('/')){continue}
            $total+=$entry.Length
            if($name -match '(^/|:|(^|/)\.{1,2}(/|$))' -or -not $seen.Add($name) -or $total -gt 12MB -or $seen.Count -gt 96){throw 'Unsafe or oversized package.'}
        }
    }finally{$archive.Dispose()}
    Expand-Archive -LiteralPath $Zip -DestinationPath $Destination
    $manifest=Get-Content (Join-Path $Destination 'package-manifest.json') -Raw|ConvertFrom-Json
    if($manifest.schema -ne 1 -or $seen.Count -ne @($manifest.files).Count+1){throw 'Package envelope mismatch.'}
    foreach($f in $manifest.files){
        $name=([string]$f.path).Replace('\','/');$p=Join-Path $Destination $name
        if(-not $seen.Contains($name) -or (Get-Item $p).Length -ne $f.size -or (Hash $p) -cne ([string]$f.sha256).ToLowerInvariant()){throw 'Package file verification failed.'}
    }
    return $manifest
}
function Run-Child([string]$Phase,[string]$Package,[int]$PauseAfter=0,[string]$Ready='',[switch]$ExpectKill){
    $report=Join-Path $lab ($Phase+'-'+[Guid]::NewGuid().ToString('N')+'.json')
    $work=Join-Path $lab ($Phase+'-work-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($work)
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "'+(Join-Path $PSScriptRoot 'interrupted-setup-child.ps1')+
        '" -Phase '+$Phase+' -Package "'+$Package+'" -Work "'+$work+'" -PauseAfter '+$PauseAfter+
        ' -Ready "'+$Ready+'" -Report "'+$report+'"'
    $script:child=[Diagnostics.Process]::Start($psi)
    if($ExpectKill){
        $deadline=[DateTime]::UtcNow.AddSeconds(45)
        while(-not(Test-Path -LiteralPath $Ready) -and -not $script:child.HasExited -and [DateTime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 50}
        if(-not(Test-Path -LiteralPath $Ready)){throw ($Phase+' child did not reach the owned kill boundary.')}
        Check (-not $script:child.HasExited) ($Phase+' child is still active at the owned kill boundary')
        $script:child.Kill();[void]$script:child.WaitForExit(10000)
        Check $script:child.HasExited ($Phase+' child was terminated only after its explicit fixture marker')
        $script:child.Dispose();$script:child=$null
        return $null
    }
    if(-not $script:child.WaitForExit(120000)){throw ($Phase+' child exceeded its bound; no rerun.')}
    $result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
    Copy-Item $report (Join-Path $evidence ([IO.Path]::GetFileName($report)))
    Check ($script:child.ExitCode -eq 0 -and $result.passed -is [bool] -and $result.passed -and $result.source -ceq $env:GITHUB_SHA) ($Phase+' child completed its recorded boundary')
    $script:child.Dispose();$script:child=$null
    return $result
}
try{
    Check (-not(Test-Path $app) -and -not(Test-Path $program) -and -not(Test-Path $recovery) -and -not(Get-Service Tailscale -ErrorAction SilentlyContinue)) 'Interrupted Setup lab starts with empty owned product and recovery roots'
    $scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\')
    foreach($name in $taskNames){$exists=$false;try{[void]$folder.GetTask($name);$exists=$true}catch{};Check (-not $exists) 'No existing product task is reused'}

    [Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $url='https://github.com/coachedai/tailscale-quick-repair/releases/download/v3.0.0-phase5.2.1/TailscaleQuickRepair-SetupPackage-3.0.0-phase5.2.1.zip'
    $legacyZip=Join-Path $lab 'published-5.2.1.zip'
    $wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','TqrInterruptedSetupAcceptance');$wc.DownloadFile($url,$legacyZip);$wc.Dispose()
    Check ((Get-Item $legacyZip).Length -eq 140164 -and (Hash $legacyZip) -ceq $legacyHash) 'Published 5.2.1 package matches its pinned exact release digest'

    $legacy=Join-Path $lab 'legacy';$legacyManifest=Expand-Verified $legacyZip $legacy
    Check ($legacyManifest.version -ceq '3.0.0-phase5.2.1') 'Baseline is the genuine published 5.2.1 payload'

    $setupZip=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*SetupPackage-*.zip' -File)
    Check ($setupZip.Count -eq 1) 'Exactly one upstream-tested protected candidate is reused'
    $candidate=Join-Path $lab 'candidate';$candidateManifest=Expand-Verified $setupZip[0].FullName $candidate

    [void](Run-Child 'InstallLegacy' $legacy)
    Check (Test-Path $app -and Test-Path $program) 'Published baseline files are installed by their compiled Setup core'

    $candidateType=[Reflection.Assembly]::LoadFile((Join-Path $candidate 'app\TailscaleQuickRepairSetup.exe')).GetType('PublicSetupHost')
    $resolve=$candidateType.GetMethod('ResolveInstallTarget',[Reflection.BindingFlags]'NonPublic,Static')
    if(-not $resolve){throw 'Candidate target resolver unavailable.'}

    $baseline=@{}
    $changedIndex=0;$changedTarget='';$changedSha='';$index=0
    foreach($f in $candidateManifest.files){
        $index++
        $target=[string]$resolve.Invoke($null,@([string]$f.path))
        $exists=Test-Path -LiteralPath $target -PathType Leaf
        $oldHash=if($exists){Hash $target}else{'absent'}
        $baseline[[string]$f.path]=[pscustomobject]@{target=$target;existed=$exists;sha=$oldHash}
        if($changedIndex -eq 0 -and (-not $exists -or $oldHash -cne ([string]$f.sha256).ToLowerInvariant())){
            $changedIndex=$index;$changedTarget=$target;$changedSha=([string]$f.sha256).ToLowerInvariant()
        }
    }
    Check ($changedIndex -gt 0) 'Candidate contains at least one real payload change from published 5.2.1'

    $applyReady=Join-Path $lab 'apply.ready'
    [void](Run-Child 'ApplyPause' $candidate $changedIndex $applyReady -ExpectKill)
    Check (Test-Path (Join-Path $recovery 'transaction.json') -PathType Leaf) 'Killed Setup leaves its protected persistent recovery journal'
    Check ((Test-Path $changedTarget -PathType Leaf) -and (Hash $changedTarget) -ceq $changedSha) 'Killed Setup occurred after the selected changed file was actually replaced'

    $journal=Get-Content (Join-Path $recovery 'transaction.json') -Raw|ConvertFrom-Json
    Check ($journal.schema -eq 1 -and $journal.state -ceq 'prepared' -and @($journal.entries).Count -eq @($candidateManifest.files).Count) 'Recovery journal covers the complete candidate file set before mutation'

    $recoverReady=Join-Path $lab 'recover.ready'
    [void](Run-Child 'RecoveryPause' $candidate 1 $recoverReady -ExpectKill)
    Check (Test-Path (Join-Path $recovery 'transaction.json') -PathType Leaf) 'Killing recovery preserves the same transaction for another attempt'

    [void](Run-Child 'Recover' $candidate)
    Check (-not(Test-Path $recovery)) 'Successful retry removes only the completed recovery transaction'

    $allRestored=$true
    foreach($f in $candidateManifest.files){
        $before=$baseline[[string]$f.path]
        if($before.existed){
            if(-not(Test-Path $before.target -PathType Leaf) -or (Hash $before.target) -cne $before.sha){$allRestored=$false}
        }elseif(Test-Path $before.target){$allRestored=$false}
    }
    Check $allRestored 'Third process restores every published baseline file hash and removes files that did not previously exist'

    # Preserve the recovered installation intact, but move it out of the product
    # paths so the following handoff test starts from a genuinely empty install.
    $appArchive=Join-Path (Split-Path -Parent $app) ('TqrInterruptedEvidence-'+[Guid]::NewGuid().ToString('N'))
    $programArchive=Join-Path (Split-Path -Parent $program) ('TqrInterruptedEvidence-'+[Guid]::NewGuid().ToString('N'))
    [IO.Directory]::Move($app,$appArchive)
    [IO.Directory]::Move($program,$programArchive)
    Check (-not(Test-Path $app) -and -not(Test-Path $program)) 'Recovered installation is preserved by same-volume rename before the next independent compatibility test'

    $passed=$true
}catch{
    $chain=New-Object 'Collections.Generic.List[object]'
    for($ex=$_.Exception;$ex;$ex=$ex.InnerException){$chain.Add([pscustomobject]@{type=$ex.GetType().FullName;code=$ex.HResult})}
    $failure=[pscustomobject]@{stage=$stage;line=$_.InvocationInfo.ScriptLineNumber;exceptions=@($chain.ToArray())}
}finally{
    if($child){try{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}}catch{$cleanup=$false};$child.Dispose()}
    $cases.Add([pscustomobject]@{name='Interrupted Setup lab kills only its explicitly owned child processes; failed file evidence remains on the disposable runner';passed=$cleanup})
    [pscustomobject]@{passed=($passed -and $cleanup);source=$env:GITHUB_SHA;fromVersion='3.0.0-phase5.2.1';cases=@($cases.ToArray());failure=$failure;
      scope='Persistent payload-file transaction recovery after killed Setup and killed recovery processes';
      limits=@('This does not certify task, startup-registry or shortcut rollback after a kill','This does not simulate whole-PC power loss or storage-controller write loss','No live tailnet or user machine is touched','Recovery journal contains only fixed package-relative paths and file digest metadata')}|
      ConvertTo-Json -Depth 9|Set-Content (Join-Path $evidence 'interrupted-setup-results.json') -Encoding UTF8
}
if(-not $passed -or -not $cleanup){throw 'Interrupted Setup recovery acceptance failed; inspect preserved evidence.'}
