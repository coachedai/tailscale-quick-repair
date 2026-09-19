$ErrorActionPreference='Stop'
if ($env:GITHUB_REPOSITORY -ne 'coachedai/tailscale-quick-repair' -or $env:GITHUB_REF_NAME -ne 'work/4.2-smart-notifications') { throw 'Wrong project or development branch.' }
$repo=Split-Path -Parent $PSScriptRoot
$versionPath=Join-Path $repo 'version.json';$version=Get-Content $versionPath -Raw | ConvertFrom-Json
if ($version.version -eq '3.0.0-phase4.2.1') { Write-Host 'Integration already applied; validate committed source.';return }
if ($version.version -ne '3.0.0-phase4.1.1') { throw 'Unexpected source baseline.' }
function Replace-One([string]$Text,[string]$Old,[string]$New) {
    if ([regex]::Matches($Text,[regex]::Escape($Old)).Count -ne 1) { throw ('Preparation anchor missing or duplicated: '+$Old) }
    return $Text.Replace($Old,$New)
}
$routePath=Join-Path $PSScriptRoot 'add-native-setup-routing.ps1';$route=[IO.File]::ReadAllText($routePath)
$route=Replace-One $route @'
        ('"{0}"' -f (Join-Path $repo 'src\native\ConnectionQuality.cs')))
'@ @'
        ('"{0}"' -f (Join-Path $repo 'src\native\ConnectionQuality.cs')),
        ('"{0}"' -f (Join-Path $repo 'src\native\SmartNotifications.cs')))
'@
$route=Replace-One $route @'
    & (Join-Path $PSScriptRoot 'add-connection-quality.ps1') -Path $uiPath
'@ @'
    & (Join-Path $PSScriptRoot 'add-connection-quality.ps1') -Path $uiPath
    $notificationTransform=[scriptblock]::Create([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'add-smart-notifications.ps1'),[Text.Encoding]::UTF8))
    & $notificationTransform -Path $uiPath
'@
$testPath=Join-Path $PSScriptRoot 'test-packaged-runtime.ps1';$test=[IO.File]::ReadAllText($testPath)
$test=Replace-One $test "@('Initialize-LocalHistory','Write-LocalHistoryEvent')" "@('Initialize-LocalHistory','Write-LocalHistoryEvent','Request-SmartNotification')"
$test=Replace-One $test @'
    & $qualityTest -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
'@ @'
    & $qualityTest -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
    & (Join-Path $PSScriptRoot 'test-smart-notifications.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
'@
$qualityPath=Join-Path $PSScriptRoot 'test-connection-quality.ps1';$quality=[IO.File]::ReadAllText($qualityPath)
$quality=Replace-One $quality "@('Set-ConnectionInsight','Add-ConnectionEvent','Update-ConnectionIntelligence','Reset-ConnectionQuality')" "@('Set-ConnectionInsight','Add-ConnectionEvent','Update-ConnectionIntelligence','Reset-ConnectionQuality','Observe-SmartConnectionNotification','Request-SmartNotification')"
$version.version='3.0.0-phase4.2.1';$version.versionCode=[int64]30000521
$publish=[ordered]@{publish=$false;channel='preview';version=$version.version;versionCode=$version.versionCode;requiresSetup=$false;publicInstaller=$true;notes='Smart Notifications foundation: off by default, one preference and a test action. Meaningful events observed while running can request a tray notification, with persistent two-minute global, thirty-minute category and three-per-hour limits. No routine healthy alerts, startup replay, extra peer polling or network changes. Windows availability gates requests; banners and sound remain under Windows control. Local Auto Repair recovery requires a later explicit healthy observation, not merely a started task. Guardian, History, quality baselines and operation safety remain intact. Native policy, persistence and packaged WPF adapter tests join the existing release gates.'}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($routePath,$route,$utf8)
[IO.File]::WriteAllText($testPath,$test,$utf8)
[IO.File]::WriteAllText($qualityPath,$quality,$utf8)
[IO.File]::WriteAllText($versionPath,($version|ConvertTo-Json -Depth 8),$utf8)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publish.json'),($publish|ConvertTo-Json -Depth 8),$utf8)
Write-Host 'Notification source integration prepared, publication disabled.'
