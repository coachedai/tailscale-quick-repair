param([Parameter(Mandatory=$true)][string]$UiPath,[Parameter(Mandatory=$true)][string]$LibraryPath,[Parameter(Mandatory=$true)][string]$WorkerPath,[Parameter(Mandatory=$true)][string]$EvidenceDirectory)
$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT' -or $PSVersionTable.PSVersion.Major -ne 5){throw 'Native Windows PowerShell 5.1 required.'}
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
if(-not ('Tqr.DiagnosticAnalysis' -as [type])){Add-Type -Path $LibraryPath}
$root=Join-Path $env:TEMP ('TQR-DiagnosticTest-'+[Guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $root | Out-Null
$cases=New-Object 'Collections.Generic.List[object]'
function Check([bool]$Good,[string]$Name){if(-not $Good){throw "FAILED diagnostics/polish: $Name"};$cases.Add([pscustomobject]@{name=$Name;passed=$true});Write-Host "PASS: $Name"}
function Command([string]$Text,[int]$Code=0){$c=New-Object Tqr.DiagnosticCommand;$c.Output=$Text;$c.ExitCode=$Code;return $c}
function Probe([string]$Via='127.0.0.1:41641',[string]$Type='disco'){[Tqr.DiagnosticAnalysis]::ParseProbe((Command "pong from fixture via $Via in 11ms"),$Type)}
try{
    $direct=Probe;$tunnel=Probe 'TSMP' 'tsmp';$icmp=Probe 'ICMP' 'icmp'
    $api=[Tqr.DiagnosticAnalysis]::ParseProbe((Command 'hit peerapi of fixture at endpoint in 12ms'),'peerapi')
    Check ($direct.Path -eq 'Direct' -and $direct.Status -eq 'Reachable') 'Direct endpoint output is recognized without the literal word direct'
    Check ((Probe '[::1]:41641').Path -eq 'Direct') 'Bracketed IPv6 endpoints identify a direct path'
    Check ((Probe '127.0.0.1:99999').Path -eq 'Unknown') 'Invalid endpoint ports cannot become direct evidence'
    Check ((Probe 'DERP(fra)').Path -eq 'Relay / FRA') 'DERP region is reported without exposing its endpoint'
    Check ((Probe 'peer-relay(endpoint:vni:7)').Path -eq 'Peer relay') 'Peer relay is distinct from DERP and direct'
    Check ((Probe 'something-direct-sounding').Path -eq 'Unknown') 'Unrecognized output does not infer a direct path'
    $sequence=Command "pong from fixture via DERP(fra) in 70ms`npong from fixture via 127.0.0.1:41641 in 11ms"
    Check ([Tqr.DiagnosticAnalysis]::ParseProbe($sequence,'disco').Path -eq 'Direct') 'Last valid reply determines the observed path'
    Check ([Tqr.DiagnosticAnalysis]::ParseProbe((Command 'all good'),'disco').Status -eq 'Unknown') 'Exit zero alone is not proof of a peer reply'
    Check ([Tqr.DiagnosticAnalysis]::ParseProbe((Command 'flag provided but not defined: peerapi' 1),'peerapi').Status -eq 'Not supported') 'Unsupported CLI flags are distinct from an unreachable peer'
    $bad=Command 'timeout' 1
    Check ([Tqr.DiagnosticAnalysis]::ParseProbe($bad,'icmp').Status -eq 'Timed out') 'Probe timeout is reported explicitly'
    $bad=Command 'output';$bad.Truncated=$true
    Check ([Tqr.DiagnosticAnalysis]::ParseProbe($bad,'disco').Status -eq 'Incomplete') 'Truncated output cannot yield a successful probe'
    $culture=[Globalization.CultureInfo]::CurrentCulture
    try{[Globalization.CultureInfo]::CurrentCulture=[Globalization.CultureInfo]::GetCultureInfo('de-DE');$fraction=[Tqr.DiagnosticAnalysis]::ParseProbe((Command 'pong from fixture via TSMP in 1.5ms'),'tsmp');Check ($fraction.Latency -eq '2 ms') 'Fractional milliseconds parse independently of Windows locale'}finally{[Globalization.CultureInfo]::CurrentCulture=$culture}
    $net=[Tqr.DiagnosticAnalysis]::ParseNetwork((Command "* UDP: true`n* IPv4: yes, 127.0.0.1:123`n* IPv6: no, unavailable`n* Nearest DERP: London`n* MappingVariesByDestIP: false`n* PortMapping: UPnP, NAT-PMP"))
    Check ($net.status -eq 'Complete' -and $net.ipv6 -eq 'Unavailable' -and $net.nearestDerp -eq 'London') 'Explicit network availability tokens parse without copying IP addresses'
    Check ([Tqr.DiagnosticAnalysis]::ParseNetwork((Command '* IPv4: maybe')).ipv4 -eq 'Unknown') 'Unexpected network values remain unknown rather than available'
    $verdict=[Tqr.DiagnosticAnalysis]::Explain($net,$direct,$tunnel,$icmp,$api)
    Check ($verdict.Severity -eq 'good' -and $verdict.Detail -match 'not a bandwidth or RDP test') 'Healthy probe evidence is distinct from a remote application test'
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,(Probe 'DERP(fra)'),$tunnel,$icmp,$api).Severity -eq 'info') 'A functioning relay is not labeled as failed'
    $unknown=New-Object Tqr.DiagnosticProbe
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,$unknown,$tunnel,$icmp,$api).Summary -match 'path was not identified') 'An unknown diagnostic path cannot borrow Direct from another check'
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,$direct,$tunnel,$unknown,$api).Summary -match 'ICMP was not confirmed') 'ICMP failure is not called a broken tunnel'
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,$direct,$tunnel,$icmp,$unknown).Summary -match 'Peer API was not confirmed') 'Optional Peer API failure has a separate explanation'
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,$direct,$unknown,$icmp,$api).Severity -eq 'warn') 'Discovery alone does not prove a working tunnel probe'
    Check ([Tqr.DiagnosticAnalysis]::Explain($net,$unknown,$unknown,$unknown,$unknown).Severity -eq 'warn') 'Missing evidence never becomes no obvious issue'
    Check (-not [Tqr.DiagnosticAnalysis]::ValidPeer('fixture" --extra') -and -not [Tqr.DiagnosticAnalysis]::ValidPeer('-other') -and [Tqr.DiagnosticAnalysis]::ValidPeer('fixture.example')) 'Peer arguments cannot introduce CLI switches or quotes'
    $fake=Join-Path $root 'fixture-cli.exe'
    $fakeCode=@'
using System;
using System.Threading;
public static class FixtureCli {
 public static int Main(string[] a) {
  string mode=Environment.GetEnvironmentVariable("TQR_DIAG_TEST");
  if(mode=="hang"){Thread.Sleep(5000);return 0;}
  if(mode=="large"){for(int i=0;i<3000;i++)Console.WriteLine(new String('x',100));return 0;}
  if(a[0]=="netcheck"){Console.WriteLine("* UDP: true\n* IPv4: yes\n* IPv6: no\n* Nearest DERP: London\n* MappingVariesByDestIP: false\n* PortMapping: UPnP");return 0;}
  string text=String.Join(" ",a);
  if(text.Contains("--peerapi")){Console.WriteLine("hit peerapi of fixture at endpoint in 11ms");return 0;}
  string via=text.Contains("--tsmp")?"TSMP":text.Contains("--icmp")?"ICMP":"127.0.0.1:41641";
  Console.WriteLine("pong from fixture via "+via+" in 11ms");return 0;
 }
}
'@
    Add-Type -TypeDefinition $fakeCode -OutputAssembly $fake -OutputType ConsoleApplication
    $prior=$env:TQR_DIAG_TEST
    try{
        $env:TQR_DIAG_TEST='normal';$r=[Tqr.DiagnosticAnalysis]::Run($fake,'disco','fixture',3000)
        Check ([Tqr.DiagnosticAnalysis]::ParseProbe($r,'disco').Path -eq 'Direct') 'Hidden native child output is collected and parsed'
        $env:TQR_DIAG_TEST='hang';$watch=[Diagnostics.Stopwatch]::StartNew();$r=[Tqr.DiagnosticAnalysis]::Run($fake,'disco','fixture',150)
        Check ($r.TimedOut -and $watch.Elapsed.TotalSeconds -lt 2) 'A stalled owned child is stopped within its time budget'
        $env:TQR_DIAG_TEST='large';$r=[Tqr.DiagnosticAnalysis]::Run($fake,'netcheck','fixture',3000)
        Check ($r.Truncated -and $r.Output.Length -le 65536) 'Retained CLI output is capped and marked incomplete on overflow'
        $env:TQR_DIAG_TEST='normal'
        $worker=[IO.File]::ReadAllText($WorkerPath,[Text.Encoding]::UTF8);$tk=$null;$er=$null
        $wa=[Management.Automation.Language.Parser]::ParseInput($worker,[ref]$tk,[ref]$er)
        Check ($er.Count -eq 0) 'Delivered diagnostic worker parses on Windows PowerShell 5.1'
        $cliNode=@($wa.FindAll({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-TailscaleCli'},$true))
        Check ($cliNode.Count -eq 1) 'Worker CLI discovery has one injectable fixture boundary'
        $replacement="function Get-TailscaleCli { return '"+$fake.Replace("'","''")+"' }"
        $worker=$worker.Remove($cliNode[0].Extent.StartOffset,$cliNode[0].Extent.EndOffset-$cliNode[0].Extent.StartOffset).Insert($cliNode[0].Extent.StartOffset,$replacement)
        # Retain exception detail ONLY in this synthetic worker; never change the installed worker's privacy policy.
        $worker=$worker.Replace('$script:Result.error=''inspection_incomplete''','$script:Result.error=$_.Exception.GetType().FullName + '': '' + $_.Exception.Message')
        $workerFile=Join-Path $root 'Advanced-Diagnostics.ps1';[IO.File]::WriteAllText($workerFile,$worker)
        Copy-Item $LibraryPath (Join-Path $root 'TailscaleQuickRepair.Operations.dll')
        $state=Join-Path $root 'diagnostics-result.json'
        $psi=New-Object Diagnostics.ProcessStartInfo
        $psi.FileName=Join-Path $PSHOME 'powershell.exe';$psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
        $psi.Arguments='-NoProfile -NonInteractive -File "'+$workerFile+'" -Peer fixture -OutputPath "'+$state+'" -RunId fixture-run'
        $child=[Diagnostics.Process]::Start($psi)
        try{if(-not $child.WaitForExit(25000)){$child.Kill();throw 'Fixture worker timed out'};Check ($child.ExitCode -eq 0) 'Native worker completes without changing live network state'}finally{$child.Dispose()}
        $r=Get-Content $state -Raw | ConvertFrom-Json
        Check ($r.done -and $r.schema -eq 2 -and $r.path -eq 'Direct' -and $r.severity -eq 'good' -and $r.runId -eq 'fixture-run') ("Actual worker writes the expected structured completed result; fixture reason: "+$r.error)
        Check ((Get-Content $state -Raw) -notmatch '127\.0\.0\.1|pong from|fixture-cli') 'Raw endpoints and CLI output are not persisted in the diagnostic report'
    }finally{$env:TQR_DIAG_TEST=$prior}
    $ui=[IO.File]::ReadAllText($UiPath,[Text.Encoding]::UTF8);$tk=$null;$er=$null
    $ast=[Management.Automation.Language.Parser]::ParseInput($ui,[ref]$tk,[ref]$er)
    Check ($er.Count -eq 0) 'Final themed UI parses on Windows PowerShell 5.1'
    $xm=[regex]::Match($ui,'(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@')
    [xml]$x=$xm.Groups['xaml'].Value;$reader=New-Object Xml.XmlNodeReader $x
    $window=[Windows.Markup.XamlReader]::Load($reader);$reader.Close()
    $HistoryPanel=$window.FindName('HistoryPanel');$HistoryText=$window.FindName('HistoryText')
    $DetailsPanel=$window.FindName('DetailsPanel');$DetailsPanel.Visibility='Visible';$HistoryPanel.Visibility='Visible'
    $HistoryText.Text=(1..40|ForEach-Object {"Event $_ - Connection check passed"}) -join "`n"
    $window.Width=1100;$window.Height=850;$window.Measure([Windows.Size]::new(1100,850));$window.Arrange([Windows.Rect]::new(0,0,1100,850));$window.UpdateLayout()
    $HistoryPanel.ApplyTemplate()|Out-Null;$HistoryPanel.UpdateLayout()
    $bar=$HistoryPanel.Template.FindName('PART_VerticalScrollBar',$HistoryPanel);$bar.ApplyTemplate()|Out-Null
    $track=$bar.Template.FindName('PART_Track',$bar)
    Check ($bar.Width -eq 12 -and $null -ne $track -and $track.Thumb.MinHeight -ge 28) 'History uses a slim themed scrollbar with a usable draggable thumb'
    Check ($bar.Background.Color.A -eq 0 -and $HistoryPanel.ScrollableHeight -gt 0) 'No white scrollbar rail is drawn and long history remains scrollable'
    $HistoryPanel.ScrollToEnd();$HistoryPanel.UpdateLayout()
    Check ($HistoryPanel.VerticalOffset -gt 0) 'History can scroll to the oldest retained event'
    $HistoryPanel.ScrollToHome();$HistoryPanel.UpdateLayout()
    Check ($HistoryPanel.VerticalOffset -eq 0) 'History can return to the newest retained event'
    [Windows.Controls.Primitives.ScrollBar]::PageDownCommand.Execute($null,$bar);$HistoryPanel.UpdateLayout()
    Check ($HistoryPanel.VerticalOffset -gt 0) 'Scrollbar page commands still reach the ScrollViewer'
    $HistoryPanel.ScrollToTop();$HistoryPanel.UpdateLayout()
    Check ($HistoryPanel.Focusable -and $HistoryPanel.PanningMode -eq 'VerticalOnly') 'Keyboard focus and touch scrolling remain enabled'
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new([int][Math]::Ceiling($HistoryPanel.ActualWidth),[int][Math]::Ceiling($HistoryPanel.ActualHeight),96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($HistoryPanel);$encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder;$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $png=[IO.File]::Create((Join-Path $EvidenceDirectory 'history-scrollbar.png'));try{$encoder.Save($png)}finally{$png.Dispose()}
    $HistoryText.Text='One saved event';$HistoryPanel.UpdateLayout()
    Check ($HistoryPanel.ComputedVerticalScrollBarVisibility -eq 'Collapsed') 'Scrollbar disappears when history fits without scrolling'
    Check ($window.FindName('AdvancedDiagnosticsDetailText') -ne $null -and $ui.Contains('VPN software')) 'Diagnostic explanation has one dedicated inline slot and honest VPN labeling'
    $window.Close()
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'diagnostics-polish-results.json'),(@{passed=$true;scope='Native parser, owned CLI fixture, actual worker and final WPF layout; not a live network or power-loss test';cases=$cases.ToArray()}|ConvertTo-Json -Depth 8))
}catch{
    [IO.File]::WriteAllText((Join-Path $EvidenceDirectory 'diagnostics-polish-results.json'),(@{passed=$false;failure=$_.Exception.Message;cases=$cases.ToArray()}|ConvertTo-Json -Depth 8));throw
}
