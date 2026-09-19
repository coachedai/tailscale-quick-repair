$ErrorActionPreference='Stop'
if($env:GITHUB_REPOSITORY -ne 'coachedai/tailscale-quick-repair' -or $env:GITHUB_REF_NAME -ne 'work/5.2-private-export'){throw 'Wrong repository or branch.'}
$repo=Split-Path -Parent $PSScriptRoot;$vp=Join-Path $repo 'version.json';$v=Get-Content $vp -Raw|ConvertFrom-Json
if($v.version -eq '3.0.0-phase5.2.1'){return}
if($v.version -ne '3.0.0-phase5.1.2'){throw 'Unexpected starting version.'}
function Replace-Reviewed([string]$Text,[string]$Old,[string]$New){
 if([regex]::Matches($Text,[regex]::Escape($Old)).Count -ne 1){throw ('Missing or duplicate integration anchor: '+$Old)}
 return $Text.Replace($Old,$New)
}
$rp=Join-Path $PSScriptRoot 'add-native-setup-routing.ps1';$route=[IO.File]::ReadAllText($rp)
$route=Replace-Reviewed $route @'
        ('"{0}"' -f (Join-Path $repo 'src\native\DiagnosticAnalysis.cs')))
'@ @'
        ('"{0}"' -f (Join-Path $repo 'src\native\DiagnosticAnalysis.cs')),
        ('"{0}"' -f (Join-Path $repo 'src\native\SupportReport.cs')),
        ('"{0}"' -f (Join-Path $repo 'src\native\SupportReportWindow.cs')))
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Xaml
    foreach($assembly in @([Windows.Window].Assembly,[Windows.Media.Brush].Assembly,[Windows.DependencyObject].Assembly,[System.Xaml.XamlServices].Assembly)){
        $libraryArgs += ('/reference:"{0}"' -f $assembly.Location)
    }
'@
$route=Replace-Reviewed $route @'
    & (Join-Path $PSScriptRoot 'add-progress-reset.ps1') -Path $uiPath
'@ @'
    & (Join-Path $PSScriptRoot 'add-progress-reset.ps1') -Path $uiPath
    & (Join-Path $PSScriptRoot 'add-support-export.ps1') -Path $uiPath
'@
$tp=Join-Path $PSScriptRoot 'test-packaged-runtime.ps1';$test=[IO.File]::ReadAllText($tp)
$test=Replace-Reviewed $test @'
    & (Join-Path $PSScriptRoot 'test-progress-reset.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -EvidenceDirectory $EvidenceDirectory
'@ @'
    & (Join-Path $PSScriptRoot 'test-progress-reset.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -EvidenceDirectory $EvidenceDirectory
    & (Join-Path $PSScriptRoot 'test-support-export.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
'@
$v.version='3.0.0-phase5.2.1';$v.versionCode=[int64]30000621
$pub=[ordered]@{publish=$false;channel='preview';version=$v.version;versionCode=$v.versionCode;requiresSetup=$false;publicInstaller=$true;notes='Privacy-safe support export. The existing diagnostic Copy report action becomes Share report: preview a frozen allowlisted snapshot, optionally include ten typed history events, then copy or save a new local .txt file. No addresses, device names, paths, raw logs, tokens or automatic upload. Pending/stale/missing observations are labelled rather than promoted to fresh results. Existing files are never overwritten by export. Five-file ordinary update, with no protected worker or network changes. Existing regression suites plus privacy-injection, native preview and save tests remain required.'}
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($rp,$route,$utf8);[IO.File]::WriteAllText($tp,$test,$utf8)
[IO.File]::WriteAllText($vp,($v|ConvertTo-Json -Depth 6),$utf8)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publish.json'),($pub|ConvertTo-Json -Depth 6),$utf8)
