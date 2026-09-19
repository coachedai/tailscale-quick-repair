$ErrorActionPreference='Stop'
if ($env:GITHUB_REPOSITORY -ne 'coachedai/tailscale-quick-repair' -or $env:GITHUB_REF_NAME -ne 'work/4.1-connection-quality') { throw 'Unexpected repository or development branch.' }
$repo=Split-Path -Parent $PSScriptRoot
$versionPath=Join-Path $repo 'version.json'
$version=Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
if ($version.version -eq '3.0.0-phase4.1.1') { Write-Host 'Source wiring already applied; validate existing source.'; return }
if ($version.version -ne '3.0.0-phase3.5.1') { throw 'Unexpected baseline version.' }
function Replace-One([string]$Text,[string]$Old,[string]$New) {
    if ([regex]::Matches($Text,[regex]::Escape($Old)).Count -ne 1) { throw ('Expected one preparation anchor: ' + $Old) }
    return $Text.Replace($Old,$New)
}
$routePath=Join-Path $PSScriptRoot 'add-native-setup-routing.ps1'
$route=[IO.File]::ReadAllText($routePath)
$old=@'
        ('"{0}"' -f (Join-Path $repo 'src\native\LocalHistory.cs')))
'@
$new=@'
        ('"{0}"' -f (Join-Path $repo 'src\native\LocalHistory.cs')),
        ('"{0}"' -f (Join-Path $repo 'src\native\ConnectionQuality.cs')))
'@
$route=Replace-One $route $old $new
$old=@'
    & (Join-Path $PSScriptRoot 'add-local-history.ps1') -Path $uiPath
'@
$new=@'
    & (Join-Path $PSScriptRoot 'add-local-history.ps1') -Path $uiPath
    & (Join-Path $PSScriptRoot 'add-connection-quality.ps1') -Path $uiPath
'@
$route=Replace-One $route $old $new
$testPath=Join-Path $PSScriptRoot 'test-packaged-runtime.ps1'
$test=[IO.File]::ReadAllText($testPath)
$old=@'
    & (Join-Path $PSScriptRoot 'test-update-routing.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -EvidenceDirectory $EvidenceDirectory
'@
$new=@'
    & (Join-Path $PSScriptRoot 'test-update-routing.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -EvidenceDirectory $EvidenceDirectory
    & (Join-Path $PSScriptRoot 'test-connection-quality.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
'@
$test=Replace-One $test $old $new
$version.version='3.0.0-phase4.1.1';$version.versionCode=[int64]30000511
$publish=[ordered]@{
    publish=$false;channel='preview';version=$version.version;versionCode=$version.versionCode
    requiresSetup=$false;publicInstaller=$false
    notes='Connection Intelligence 2.0 foundation. Passive session-only route-specific median baselines from completed checks, two-check latency confirmation, repeated observed fallback/switching explanations, reachability transitions and reset after target/network changes. Existing Remote insight and a distinct Baseline row replace duplicate session wording. No extra probes, notifications, repair actions or persistent peer samples. Existing Guardian, History, operation ownership and update paths retained; native package and quality regressions required before publication.'
}
$encoding=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($routePath,$route,$encoding)
[IO.File]::WriteAllText($testPath,$test,$encoding)
[IO.File]::WriteAllText($versionPath,($version|ConvertTo-Json -Depth 8),$encoding)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publish.json'),($publish|ConvertTo-Json -Depth 8),$encoding)
Write-Host 'Quality source wiring prepared with publication disabled.'
