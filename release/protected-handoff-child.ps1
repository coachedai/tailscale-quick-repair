param(
    [ValidateSet('InstallLegacy','ApplyBridge','CheckSetupMarker')][string]$Phase,
    [string]$LegacyPackage,
    [string]$CurrentPackage,
    [string]$Report
)
$ErrorActionPreference='Stop'
if($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or
   $env:GITHUB_REPOSITORY -cne 'coachedai/tailscale-quick-repair' -or
   $env:GITHUB_REF_NAME -cne 'work/6.1-auto-repair-safety' -or
   $env:TQR_NATIVE_LAB_RUN -cne $env:GITHUB_RUN_ID -or -not $env:GITHUB_RUN_ID -or
   $PSVersionTable.PSVersion.Major -ne 5){throw 'Protected handoff child refused this environment.'}

$app=Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$program=Join-Path $env:ProgramData 'TailscaleQuickRepair'
$cases=New-Object 'Collections.Generic.List[object]'
$passed=$false;$lease=$false;$failure=$null;$stage='start'
function Check([bool]$Value,[string]$Name){$script:stage=$Name;$cases.Add([pscustomobject]@{name=$Name;passed=$Value});if(-not $Value){throw 'Protected handoff assertion failed.'}}
function Invoke-Private($Type,[string]$Name,[object[]]$Arguments=@()){
    $script:stage='invoke_'+$Name
    $method=$Type.GetMethod($Name,[Reflection.BindingFlags]'NonPublic,Static')
    if(-not $method){throw 'Expected private boundary missing.'}
    $native=New-Object object[] $Arguments.Count
    for($i=0;$i -lt $Arguments.Count;$i++){
        if($null -eq $Arguments[$i]){$native[$i]=$null}else{$native[$i]=$Arguments[$i].PSObject.BaseObject}
    }
    return ,($method.Invoke($null,$native))
}
try{
    if($Phase -eq 'InstallLegacy'){
        Check (-not(Test-Path $app) -and -not(Test-Path $program)) 'Legacy handoff fixture starts from empty product roots'
        $type=[Reflection.Assembly]::LoadFile((Join-Path $LegacyPackage 'app\TailscaleQuickRepairSetup.exe')).GetType('PublicSetupHost')
        $lease=[bool](Invoke-Private $type 'TryAcquireOperationLock' @('setup'))
        Check $lease 'Published Setup acquires its real operation lease'
        $manifest=Invoke-Private $type 'ReadPackageManifest' @($LegacyPackage)
        $files=Invoke-Private $type 'VerifyPackage' @($LegacyPackage,$manifest)
        $work=Join-Path $env:TEMP ('TqrLegacyHandoff-'+[Guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($work)
        [void](Invoke-Private $type 'ApplyFiles' @($files,$work))
        [void](Invoke-Private $type 'WriteLocalConfig' @('handoff-fixture.invalid'))
        Check ((Get-Content (Join-Path $app 'version.user.json') -Raw|ConvertFrom-Json).version -ceq '3.0.0-phase5.2.1') 'Published 5.2.1 files are genuinely installed'
        Check (Test-Path (Join-Path $program 'Repair-Backend.ps1')) 'Published protected backend exists before the bridge'
    }
    elseif($Phase -eq 'ApplyBridge'){
        $type=[Reflection.Assembly]::LoadFile((Join-Path $LegacyPackage 'app\TailscaleQuickRepairUpdater.exe')).GetType('Program')
        $manifest=Invoke-Private $type 'ReadPackageManifest' @($CurrentPackage)
        $files=Invoke-Private $type 'VerifyPackageFiles' @($CurrentPackage,$manifest)
        Check (@($files).Count -gt 0) 'Published updater accepts the staged ordinary package'
        [void](Invoke-Private $type 'ApplyTransaction' @($files,[string]$manifest.Version,[int64]$manifest.VersionCode))
        Check ((Get-Content (Join-Path $app 'version.user.json') -Raw|ConvertFrom-Json).versionCode -eq [int64]$manifest.VersionCode) 'Published updater advances the user-level package to the staged version'
        Check (Test-Path (Join-Path $app 'protected-update.json') -PathType Leaf) 'Published updater installs the protected-update handoff marker'
    }
    else{
        $type=[Reflection.Assembly]::LoadFile((Join-Path $app 'TailscaleQuickRepairSetup.exe')).GetType('PublicSetupHost')
        $marker=Get-Content (Join-Path $app 'protected-update.json') -Raw|ConvertFrom-Json
        $wrong=$false
        try{[void](Invoke-Private $type 'ValidateProtectedUpdateMarker' @([int64]$marker.versionCode+1))}catch{$wrong=$true}
        Check $wrong 'Refreshed Setup rejects a handoff marker for another release'
        [void](Invoke-Private $type 'ValidateProtectedUpdateMarker' @([int64]$marker.versionCode))
        Check $true 'Refreshed Setup accepts the exact staged release marker'
        Check (([string](Invoke-Private $type 'ReadConfiguredPeer')).Trim() -ceq 'handoff-fixture.invalid') 'Upgrade mode can reuse the existing configured target'
        [void](Invoke-Private $type 'RemoveProtectedUpdateMarker')
        Check (-not(Test-Path (Join-Path $app 'protected-update.json'))) 'Protected marker is removed only by the refreshed Setup completion boundary'
    }
    $passed=$true
}catch{
    $chain=New-Object 'Collections.Generic.List[object]'
    for($ex=$_.Exception;$ex;$ex=$ex.InnerException){$chain.Add([pscustomobject]@{type=$ex.GetType().FullName;code=$ex.HResult})}
    $failure=[pscustomobject]@{stage=$stage;line=$_.InvocationInfo.ScriptLineNumber;exceptions=@($chain.ToArray())}
}finally{
    if($lease){
        try{
            $t=[Reflection.Assembly]::LoadFile((Join-Path $LegacyPackage 'app\TailscaleQuickRepairSetup.exe')).GetType('PublicSetupHost')
            [void](Invoke-Private $t 'ReleaseOperationLock')
        }catch{$passed=$false}
    }
    [pscustomobject]@{passed=$passed;source=$env:GITHUB_SHA;phase=$Phase;cases=@($cases.ToArray());failure=$failure}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $Report -Encoding UTF8
}
if(-not $passed){exit 21}
