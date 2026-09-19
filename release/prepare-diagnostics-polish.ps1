$ErrorActionPreference='Stop'
if($env:GITHUB_REPOSITORY -ne 'coachedai/tailscale-quick-repair' -or $env:GITHUB_REF_NAME -ne 'work/5.1-diagnostics-polish'){throw 'Wrong project or branch.'}
$repo=Split-Path -Parent $PSScriptRoot;$vp=Join-Path $repo 'version.json';$v=Get-Content $vp -Raw | ConvertFrom-Json
if($v.version -eq '3.0.0-phase5.1.1'){Write-Host 'Integration already committed; validate current source.';return}
if($v.version -ne '3.0.0-phase4.2.1'){throw 'Unexpected baseline.'}
function Replace-Reviewed([string]$Text,[string]$Old,[string]$New){if([regex]::Matches($Text,[regex]::Escape($Old)).Count -ne 1){throw ('Missing or duplicate preparation anchor: '+$Old)};return $Text.Replace($Old,$New)}
$path=Join-Path $PSScriptRoot 'add-native-setup-routing.ps1';$route=[IO.File]::ReadAllText($path)
$route=Replace-Reviewed $route @'
        ('"{0}"' -f (Join-Path $repo 'src\native\SmartNotifications.cs')))
'@ @'
        ('"{0}"' -f (Join-Path $repo 'src\native\SmartNotifications.cs')),
        ('"{0}"' -f (Join-Path $repo 'src\native\DiagnosticAnalysis.cs')))
'@
$route=Replace-Reviewed $route '    & $notificationTransform -Path $uiPath' @'
    & $notificationTransform -Path $uiPath
    & (Join-Path $PSScriptRoot 'add-diagnostics-polish.ps1') -Path $uiPath
    Copy-Item -LiteralPath (Join-Path $repo 'src\app\Advanced-Diagnostics.ps1') -Destination (Join-Path $appDir 'Advanced-Diagnostics.ps1') -Force
'@
$writerPath=Join-Path $PSScriptRoot 'write-integrity-manifest.ps1';$writer=[IO.File]::ReadAllText($writerPath)
$writer=Replace-Reviewed $writer "    'TailscaleQuickRepair.Operations.dll'" "    'TailscaleQuickRepair.Operations.dll',`n    'Advanced-Diagnostics.ps1'"
$writer=Replace-Reviewed $writer "    `$required += 'TailscaleQuickRepair.exe','Advanced-Diagnostics.ps1'" "    `$required += 'TailscaleQuickRepair.exe'"
$testPath=Join-Path $PSScriptRoot 'test-packaged-runtime.ps1';$test=[IO.File]::ReadAllText($testPath)
$test=Replace-Reviewed $test @'
    & (Join-Path $PSScriptRoot 'test-smart-notifications.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
'@ @'
    & (Join-Path $PSScriptRoot 'test-smart-notifications.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -EvidenceDirectory $EvidenceDirectory
    & (Join-Path $PSScriptRoot 'test-diagnostics-polish.ps1') -UiPath (Join-Path $normal 'app\Tailscale-Repair-UI.ps1') -LibraryPath $dll -WorkerPath (Join-Path $normal 'app\Advanced-Diagnostics.ps1') -EvidenceDirectory $EvidenceDirectory
'@
$analysisPath=Join-Path $repo 'src\native\DiagnosticAnalysis.cs';$analysis=[IO.File]::ReadAllText($analysisPath)
$analysis=Replace-Reviewed $analysis 'object sync = new object(); StringBuilder captured = new StringBuilder(); bool clipped = false;' 'object sync = new object(); StringBuilder captured = new StringBuilder(); bool clipped = false; int completedReaders = 0;'
$analysis=Replace-Reviewed $analysis 'if (e.Data == null) return;' 'if (e.Data == null) { Interlocked.Increment(ref completedReaders); return; }'
$analysis=Replace-Reviewed $analysis 'else process.WaitForExit(); // The known CLI has exited; drain its async stdout/stderr.' @'
else
                    {
                        Stopwatch drain = Stopwatch.StartNew();
                        while (Interlocked.CompareExchange(ref completedReaders, 0, 0) < 2 && drain.ElapsedMilliseconds < 500) Thread.Sleep(5);
                        if (Interlocked.CompareExchange(ref completedReaders, 0, 0) < 2) clipped = true;
                    }
'@
$visualPath=Join-Path $PSScriptRoot 'test-diagnostics-polish.ps1';$visual=[IO.File]::ReadAllText($visualPath)
$visual=Replace-Reviewed $visual @'
    function Settle-Layout {
        $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
        $window.UpdateLayout()
    }
'@ @'
    function Settle-Layout {
        # ScrollViewer applies queued commands over multiple layout passes.
        for($pass=0;$pass -lt 8;$pass++){
            $window.UpdateLayout()
            $window.Dispatcher.Invoke([Action]{},[Windows.Threading.DispatcherPriority]::ApplicationIdle)
            [Threading.Thread]::Sleep(8)
        }
    }
'@
$visual=Replace-Reviewed $visual @'
    $HistoryPanel.ScrollToEnd();Settle-Layout
    Check ($HistoryPanel.VerticalOffset -gt 0) 'History can scroll to the oldest retained event'
'@ @'
    $HistoryPanel.ScrollToEnd();Settle-Layout
    $presenter=$HistoryPanel.Template.FindName('PART_ScrollContentPresenter',$HistoryPanel)
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'history-scroll-end.json'),(@{offset=$HistoryPanel.VerticalOffset;presenterOffset=$presenter.VerticalOffset;canScroll=$presenter.CanVerticallyScroll;ownerMatches=[object]::ReferenceEquals($presenter.ScrollOwner,$HistoryPanel);barValue=$bar.Value}|ConvertTo-Json))
    Save-HistoryImage 'history-scroll-end.png'
    Check ($HistoryPanel.VerticalOffset -gt 0) 'History can scroll to the oldest retained event'
'@
$v.version='3.0.0-phase5.1.1';$v.versionCode=[int64]30000611
$publish=[ordered]@{publish=$false;channel='preview';version=$v.version;versionCode=$v.versionCode;requiresSetup=$false;publicInstaller=$true;notes='Diagnostics 2.0 foundation and History polish. History has a slim rounded theme-aware scrollbar with standard scrolling retained, and opens at the newest events. Optional diagnostics now recognize direct endpoint replies, DERP and peer-relay paths, explain independent probe results without inventing a connection failure, and bound CLI execution/output. Raw command output and endpoints are not saved. The unprivileged diagnostics worker is delivered with ordinary updates: five app files are verified, six for Setup. No Tailscale recovery, protected worker, notification preference or network setting changes. Existing native suites plus diagnostic/scroll rendering gates are required.'}
$utf8=New-Object Text.UTF8Encoding($false)
foreach($entry in @(@($path,$route),@($writerPath,$writer),@($testPath,$test),@($analysisPath,$analysis),@($visualPath,$visual))){[IO.File]::WriteAllText($entry[0],$entry[1],$utf8)}
[IO.File]::WriteAllText($vp,($v|ConvertTo-Json -Depth 8),$utf8)
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'publish.json'),($publish|ConvertTo-Json -Depth 8),$utf8)
Write-Host 'Diagnostics/History source integration prepared; publication remains disabled.'
