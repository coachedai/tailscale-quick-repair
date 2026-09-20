param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$EvidenceDirectory='.\upgrade-evidence'
)
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:GITHUB_REPOSITORY -cne 'coachedai/tailscale-quick-repair' -or
   $env:GITHUB_REF_NAME -cne 'work/6.1-auto-repair-safety' -or
   $env:TQR_NATIVE_LAB_RUN -cne $env:GITHUB_RUN_ID -or -not $env:GITHUB_RUN_ID -or
   $PSVersionTable.PSVersion.Major -ne 5){throw 'Protected handoff acceptance refused this environment.'}
$repo=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if((git -C $repo rev-parse HEAD).Trim() -cne $env:GITHUB_SHA -or
   (Get-Content (Join-Path $repo 'release\publish.json') -Raw|ConvertFrom-Json).publish){throw 'Exact unpublished source required.'}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force|Out-Null
$evidence=(Resolve-Path $EvidenceDirectory).Path
$lab=Join-Path $env:RUNNER_TEMP ('TqrProtectedHandoff-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($lab)
$app=Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair';$program=Join-Path $env:ProgramData 'TailscaleQuickRepair'
$cases=New-Object 'Collections.Generic.List[object]';$passed=$false;$failure=$null;$stage='preflight';$child=$null;$cleanup=$true
$legacyHash='bad4deb522afd9442e918cacde1f58cc1509635de3be172626846060516df470'
function Check([bool]$Value,[string]$Name){$script:stage=$Name;$cases.Add([pscustomobject]@{name=$Name;passed=$Value});if(-not $Value){throw 'Protected handoff assertion failed.'};Write-Host ('PASS protected handoff: '+$Name)}
function Expand-Zip([string]$Zip,[string]$Destination){Expand-Archive -LiteralPath $Zip -DestinationPath $Destination;return (Get-Content (Join-Path $Destination 'package-manifest.json') -Raw|ConvertFrom-Json)}
function Run-Child([string]$Phase,[string]$Legacy,[string]$Current){
    $report=Join-Path $lab ($Phase+'.json')
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.Arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -STA -File "'+(Join-Path $PSScriptRoot 'protected-handoff-child.ps1')+'" -Phase '+$Phase+' -LegacyPackage "'+$Legacy+'" -CurrentPackage "'+$Current+'" -Report "'+$report+'"'
    $script:child=[Diagnostics.Process]::Start($psi)
    if(-not $script:child.WaitForExit(120000)){throw 'Owned handoff child exceeded its time bound; no rerun.'}
    $result=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
    foreach($item in $result.cases){$cases.Add($item)}
    Copy-Item $report (Join-Path $evidence ([IO.Path]::GetFileName($report)))
    Check ($script:child.ExitCode -eq 0 -and $result.passed -is [bool] -and $result.passed -and $result.source -cne '') ($Phase+' child passes its full recorded checks')
    $script:child.Dispose();$script:child=$null
}
try{
    Add-Type -AssemblyName System.IO.Compression.FileSystem,PresentationFramework
    $publish=Get-Content (Join-Path $repo 'release\publish.json') -Raw|ConvertFrom-Json
    Check ($publish.PSObject.Properties.Name -contains 'protectedHandoff' -and $publish.protectedHandoff -is [bool] -and [bool]$publish.protectedHandoff) 'Candidate explicitly uses the protected update handoff'
    Check ($publish.requiresSetup -is [bool] -and -not [bool]$publish.requiresSetup) 'Legacy-compatible bridge is not blocked by the 5.2.1 direct-Setup gate'
    Check (-not(Test-Path $app) -and -not(Test-Path $program) -and -not(Get-Service Tailscale -ErrorAction SilentlyContinue)) 'Handoff starts on an empty disposable installation'
    $url='https://github.com/coachedai/tailscale-quick-repair/releases/download/v3.0.0-phase5.2.1/TailscaleQuickRepair-SetupPackage-3.0.0-phase5.2.1.zip'
    $zip=Join-Path $lab 'published.zip';$wc=New-Object Net.WebClient;$wc.Headers.Add('User-Agent','TqrProtectedHandoffAcceptance');$wc.DownloadFile($url,$zip);$wc.Dispose()
    Check ((Get-Item $zip).Length -eq 140164 -and (Get-FileHash $zip).Hash -ieq $legacyHash) 'Published 5.2.1 package matches the pinned public release'
    $legacy=Join-Path $lab 'legacy';$old=Expand-Zip $zip $legacy
    Check ($old.version -ceq '3.0.0-phase5.2.1') 'Pinned package identifies the released starting version'
    $ordinary=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter 'TailscaleQuickRepair-*.zip' -File|Where-Object Name -notlike '*SetupPackage*')
    $setup=@(Get-ChildItem -LiteralPath $OutputDirectory -Filter '*SetupPackage-*.zip' -File)
    Check ($ordinary.Count -eq 1 -and $setup.Count -eq 1) 'One tested ordinary package and one protected package are reused'
    $bridge=Join-Path $lab 'bridge';$bridgeManifest=Expand-Zip $ordinary[0].FullName $bridge
    $protected=Join-Path $lab 'protected';$protectedManifest=Expand-Zip $setup[0].FullName $protected
    Check ($bridgeManifest.versionCode -eq $protectedManifest.versionCode) 'Bridge and protected package target the same release code'
    Check (@($bridgeManifest.files|Where-Object {[string]$_.path -like 'program/*'}).Count -eq 0) 'Bridge package contains no protected program file'
    $markerEntry=@($bridgeManifest.files|Where-Object {[string]$_.path -ceq 'app/protected-update.json'})
    Check ($markerEntry.Count -eq 1) 'Bridge package carries one protected-update marker'
    $marker=Get-Content (Join-Path $bridge 'app\protected-update.json') -Raw|ConvertFrom-Json
    Check ($marker.schema -eq 1 -and $marker.versionCode -eq $bridgeManifest.versionCode) 'Bridge marker targets exactly the package version'
    Run-Child 'InstallLegacy' $legacy $bridge
    $protectedBefore=@{};foreach($name in @('Repair-Backend.ps1','Auto-Repair-Monitor.ps1')){$protectedBefore[$name]=(Get-FileHash (Join-Path $program $name)).Hash}
    Run-Child 'ApplyBridge' $legacy $bridge
    foreach($name in $protectedBefore.Keys){Check ((Get-FileHash (Join-Path $program $name)).Hash -ceq $protectedBefore[$name]) ('Old updater leaves protected '+$name+' untouched')}
    Check ((Get-FileHash (Join-Path $app 'TailscaleQuickRepairSetup.exe')).Hash -ceq (Get-FileHash (Join-Path $bridge 'app\TailscaleQuickRepairSetup.exe')).Hash) 'Old updater installs the exact refreshed Setup host'
    $ui=[IO.File]::ReadAllText((Join-Path $app 'Tailscale-Repair-UI.ps1'))
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($ui,[ref]$tokens,[ref]$errors)
    Check ($errors.Count -eq 0) 'Bridged UI parses on native Windows PowerShell'
    $fn=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -ceq 'Invoke-PendingProtectedUpdate'},$true))
    Check ($fn.Count -eq 1) 'Bridged UI contains one pending protected-update handoff'
    $source=$fn[0].Extent.Text
    Check ($source.Contains('$psi.FileName = $SetupHostPath') -and $source.Contains("$psi.Arguments = '--upgrade'")) 'Handoff launches only the installed Setup host in upgrade mode'
    Check ($source.Contains('$ProtectedUpdateMarkerPath') -and -not $source.Contains('Repair-Backend.ps1')) 'Handoff uses the version marker and never runs a protected script directly'
    Run-Child 'CheckSetupMarker' $legacy $bridge
    Check (-not(Test-Path (Join-Path $app 'protected-update.json'))) 'Refreshed Setup owns marker completion after strict validation'
    Check ((Get-Content (Join-Path $app 'version.user.json') -Raw|ConvertFrom-Json).versionCode -eq $bridgeManifest.versionCode) 'Bridge leaves the user-level app on the intended release code'
    $passed=$true
}catch{
    $chain=New-Object 'Collections.Generic.List[object]';for($ex=$_.Exception;$ex;$ex=$ex.InnerException){$chain.Add([pscustomobject]@{type=$ex.GetType().FullName;code=$ex.HResult})}
    $failure=[pscustomobject]@{stage=$stage;line=$_.InvocationInfo.ScriptLineNumber;exceptions=@($chain.ToArray())}
}finally{
    if($child){try{if(-not $child.HasExited){$child.Kill();[void]$child.WaitForExit(5000)}}catch{$cleanup=$false};$child.Dispose()}
    $scheduler=$null
    try{$scheduler=New-Object -ComObject 'Schedule.Service';$scheduler.Connect();$folder=$scheduler.GetFolder('\');foreach($name in @('Tailscale Quick Repair','Tailscale Quick Repair Auto Monitor')){try{$t=$folder.GetTask($name);$t.Enabled=$false;$folder.DeleteTask($name,0)}catch{}}}catch{$cleanup=$false}
    $cases.Add([pscustomobject]@{name='Only fixture-owned scheduled tasks are removed after the handoff test';passed=$cleanup})
    [pscustomobject]@{passed=($passed -and $cleanup);source=$env:GITHUB_SHA;fromVersion='3.0.0-phase5.2.1';cases=@($cases.ToArray());failure=$failure;
      scope='Published updater applies only the user-level bridge; refreshed Setup marker and route are verified separately';
      limits=@('No live update manifest is changed','The final protected package is not applied through the public channel in this test','Interactive UAC approval, cancellation and relaunch remain separate acceptance','Existing protected files are compared and left untouched by the old updater')}|ConvertTo-Json -Depth 9|Set-Content (Join-Path $evidence 'protected-handoff-results.json') -Encoding UTF8
}
if(-not $passed -or -not $cleanup){throw 'Protected handoff acceptance failed; inspect preserved evidence.'}
