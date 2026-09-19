$ErrorActionPreference='Stop'
if($env:GITHUB_REPOSITORY -ne 'coachedai/tailscale-quick-repair' -or $env:GITHUB_REF_NAME -ne 'work/5.1.2-progress-reset'){throw 'Wrong project or branch.'}
$repo=Split-Path -Parent $PSScriptRoot;$versionPath=Join-Path $repo 'version.json'
$v=Get-Content $versionPath -Raw | ConvertFrom-Json
if($v.version -eq '3.0.0-phase5.1.2'){return}
if($v.version -ne '3.0.0-phase5.1.1'){throw 'Unexpected baseline.'}
function Replace-Reviewed([string]$Text,[string]$Old,[string]$New){
    if([regex]::Matches($Text,[regex]::Escape($Old)).Count -ne 1){throw ('Missing or duplicate integration anchor: '+$Old)}
    return $Text.Replace($Old,$New)
}
$p=Join-Path $PSScriptRoot 'add-native-setup-routing.ps1';$route=[IO.File]::ReadAllText($p)
$route=Replace-Reviewed $route @'
    & (Join-Path $PSScriptRoot 'add-diagnostics-polish.ps1') -Path $uiPath
'@ @'
    & (Join-Path $PSScriptRoot 'add-diagnostics-polish.ps1') -Path $uiPath
    & (Join-Path $PSScriptRoot 'add-progress-reset.ps1') -Path $uiPath
'@
$t=Join-Path $PSScriptRoot 'test-packaged-runtime.ps1';$tests=[IO.File]::ReadAllText($t)
$tests=Replace-Reviewed $tests @'
    & (Join-Path $PSScriptRoot 'test-diagnostics-polish.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -WorkerPath (Join-Path $normal 'app\Advanced-Diagnostics.ps1') -EvidenceDirectory $EvidenceDirectory
'@ @'
    & (Join-Path $PSScriptRoot 'test-diagnostics-polish.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -WorkerPath (Join-Path $normal 'app\Advanced-Diagnostics.ps1') -EvidenceDirectory $EvidenceDirectory
    & (Join-Path $PSScriptRoot 'test-progress-reset.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -EvidenceDirectory $EvidenceDirectory
'@
$v.version='3.0.0-phase5.1.2';$v.versionCode=[int64]30000612
$publish=[ordered]@{publish=$false;channel='preview';version=$v.version;versionCode=$v.versionCode;requiresSetup=$false;publicInstaller=$true;notes='Repeated-check progress fix. Previous completed results cannot repaint a new main check: embedded UTC timestamps, preserved watermarks and current-worker attachment boundaries exclude stale state before any rendering or History side effects. Diagnostics reset their measured fill before startup and retain prior result evidence behind a new run ID. The scoped diagnostic progress template has no completion animation. History scrollbar, Diagnostics 2.0, notifications and repair decisions are retained. Native repeated-click, state-file and rendered-progress tests join all existing release gates.'}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($p,$route,$utf8);[IO.File]::WriteAllText($t,$tests,$utf8)
[IO.File]::WriteAllText($versionPath,($v|ConvertTo-Json -Depth 6),$utf8)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publish.json'),($publish|ConvertTo-Json -Depth 6),$utf8)
