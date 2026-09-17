param(
    [Parameter(Mandatory=$true)]
    [string]$Path,

    [Parameter(Mandatory=$true)]
    [string]$Version,

    [Parameter(Mandatory=$true)]
    [int64]$VersionCode
)

$ErrorActionPreference = 'Stop'

function Replace-ExactOnce {
    param(
        [string]$Text,
        [string]$Find,
        [string]$Replace,
        [string]$Description
    )

    $index = $Text.IndexOf($Find, [StringComparison]::Ordinal)

    if ($index -lt 0) {
        throw "UI polish marker was not found: $Description"
    }

    return $Text.Remove($index, $Find.Length).Insert($index, $Replace)
}

function Replace-RegexOnce {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replace,
        [string]$Description
    )

    $match = [regex]::Match($Text, $Pattern)

    if (-not $match.Success) {
        throw "UI polish pattern was not found: $Description"
    }

    return $Text.Remove($match.Index, $match.Length).Insert($match.Index, $Replace)
}

$text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?m)^\$ProductVersion\s*=\s*''[^'']+''\s*$' `
    -Replace ('$ProductVersion = ''' + $Version + '''') `
    -Description 'product version'

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?m)^\$ProductVersionCode\s*=\s*\[int64\]\d+\s*$' `
    -Replace ('$ProductVersionCode = [int64]' + $VersionCode) `
    -Description 'product version code'

# Keep this replacement ASCII-only so Windows PowerShell 5.1 never depends on
# source-file encoding to identify the existing middle-dot separator.
$text = Replace-RegexOnce `
    -Text $text `
    -Pattern 'Text="Current [^"]*Check GitHub for updates\."' `
    -Replace ('Text="Current ' + $Version + ' - Check GitHub for updates."') `
    -Description 'maintenance version label'

$text = Replace-ExactOnce `
    -Text $text `
    -Find 'VerticalScrollBarVisibility="Auto"' `
    -Replace 'VerticalScrollBarVisibility="Hidden"' `
    -Description 'main scrollbar visibility'

$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
HorizontalScrollBarVisibility="Disabled"
            Background="{StaticResource Bg}">
'@ `
    -Replace @'
HorizontalScrollBarVisibility="Disabled"
            PanningMode="VerticalOnly"
            Background="{StaticResource Bg}">
'@ `
    -Description 'main vertical panning'

# Normalize only the semantic Remote-details header. This makes the later
# public-target transform independent of cosmetic indentation in source.
$remoteHeaderPattern = '(?s)<StackPanel\s+Grid\.Column="2">\s*<TextBlock\s+Text="Remote"\s+FontSize="15"\s+FontWeight="SemiBold"\s+Foreground="\{StaticResource Text\}"\s*/>\s*<Grid\s+Margin="0,16,0,0">'
$remoteHeaderNormalized = @'
<StackPanel Grid.Column="2">
                                <TextBlock Text="Remote" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>
                                <Grid Margin="0,16,0,0">
'@
$text = Replace-RegexOnce `
    -Text $text `
    -Pattern $remoteHeaderPattern `
    -Replace $remoteHeaderNormalized `
    -Description 'Remote details header normalization'

# Turn the ambiguous session column into a compact activity feed. Current
# status already lives in Local/Remote, so this column only shows changes and
# repair actions that actually happened while Quick Repair is open.
$activityHeader = @'
<StackPanel>
                                            <TextBlock Text="Activity" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>
                                            <TextBlock Text="Only meaningful changes and repair actions from this session."
                                                       Margin="0,4,0,0"
                                                       FontSize="11"
                                                       Foreground="{StaticResource Faint}"
                                                       TextWrapping="Wrap"/>
                                        </StackPanel>
'@
$text = Replace-ExactOnce `
    -Text $text `
    -Find '<TextBlock Text="This session" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>' `
    -Replace $activityHeader `
    -Description 'activity details heading'

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?s)\s*\$eventsText = ''''\s*\r?\n\s*if \(\$Data\.events\) \{.*?\r?\n\s*\$script:copyDiagnosticsText = @\(' `
    -Replace @'

        $activityItems = @()

        if ($Data.events) {
            foreach ($eventLine in @($Data.events)) {
                $line = [string]$eventLine

                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }

                # Reachability is already displayed in the Remote column. Do
                # not repeat it here unless something actually changed.
                if ($line -match '\s+Peer reachable(?: via .+)?$') {
                    continue
                }

                $activityItems += $line
            }
        }

        if ($script:reliabilityEvents.Count -gt 0) {
            $activityItems += @(
                $script:reliabilityEvents |
                    Select-Object -Last 3
            )
        }

        if ($script:connectionEvents.Count -gt 0) {
            $activityItems += @(
                $script:connectionEvents |
                    Select-Object -Last 3
            )
        }

        $activityItems = @(
            $activityItems |
                Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                Select-Object -Unique |
                Select-Object -Last 5
        )

        if ($activityItems.Count -gt 0) {
            $SessionText.Text = @(
                $activityItems |
                    ForEach-Object { "• $([string]$_)" }
            ) -join [Environment]::NewLine
        }
        elseif ([bool]$Data.done) {
            $SessionText.Text = if ([bool]$Data.repairPerformed) {
                'Repair completed successfully.'
            }
            else {
                'No changes were needed.'
            }
        }
        else {
            $SessionText.Text = 'Check in progress…'
        }

        $script:copyDiagnosticsText = @(
'@ `
    -Description 'activity feed logic'

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?m)^\s*''This session''\s*$' `
    -Replace "            'Activity'" `
    -Description 'activity copy heading'

$sessionTextLayout = 'x:Name="SessionText"' + [Environment]::NewLine +
    '                                        Margin="0,12,0,0"'
$text = Replace-RegexOnce `
    -Text $text `
    -Pattern 'x:Name="SessionText"\s+Margin="0,16,0,0"' `
    -Replace $sessionTextLayout `
    -Description 'activity spacing'

# The tray Exit callback used to dispose WinForms tray objects while the menu
# click itself was still unwinding. Queue the WPF close at ApplicationIdle and
# detach the menu first so Exit is quiet and deterministic.
$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
        $script:trayExitItem.Add_Click({
            $window.Dispatcher.BeginInvoke(
                [Action]{
                    $script:allowFullExit = $true
                    $window.Close()
                }
            ) | Out-Null
        })
'@ `
    -Replace @'
        $script:trayExitItem.Add_Click({
            try {
                $script:allowFullExit = $true

                if ($script:notifyIcon) {
                    $script:notifyIcon.ContextMenuStrip = $null
                    $script:notifyIcon.Visible = $false
                }

                if ($script:trayMenu) {
                    $script:trayMenu.Close()
                }

                $window.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::ApplicationIdle,
                    [Action]{
                        try { $window.Close() } catch {}
                    }
                ) | Out-Null
            }
            catch {
                try { $window.Close() } catch {}
            }
        })
'@ `
    -Description 'quiet tray exit'

$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
        try {
            if ($script:trayMenu) {
                $script:trayMenu.Dispose()
            }
        } catch {}
'@ `
    -Replace @'
        # NotifyIcon owns the native tray resources. Avoid disposing the
        # context menu synchronously during a menu click; process shutdown will
        # release it after the callback has returned.
        $script:trayMenu = $null
'@ `
    -Description 'tray menu shutdown cleanup'

# Existing 2.3.2 machines still have a scheduled task that launches
# powershell.exe directly. 2.3.3 carries a Setup bridge that converts it to a
# WScript launcher. On the first repair after the bridge lands, request the
# one-time UAC repair before running the task, so the old console never flashes
# again.
$repairCoreAnchor = @'
    function Start-RepairCore {
        if (Attach-To-RunningRepair) {
            return
        }

        if (-not (Ensure-EngineReadyCached)) {
'@

$repairCoreReplacement = @'
    function Test-SilentRepairTask {
        $scheduler = $null
        $folder = $null
        $task = $null
        $definition = $null
        $actions = $null
        $action = $null

        try {
            $scheduler = New-Object -ComObject 'Schedule.Service'
            $scheduler.Connect()
            $folder = $scheduler.GetFolder('\')
            $task = $folder.GetTask($TaskName)

            if (-not $task) {
                return $false
            }

            $definition = $task.Definition
            $actions = $definition.Actions

            if (-not $actions -or [int]$actions.Count -lt 1) {
                return $false
            }

            $action = $actions.Item(1)
            $actionPath = [string]$action.Path
            $actionArgs = [string]$action.Arguments

            return (
                [IO.Path]::GetFileName($actionPath) -ieq 'wscript.exe' -and
                $actionArgs -match 'Launch-Tailscale-Backend\.vbs'
            )
        }
        catch {
            return $false
        }
        finally {
            foreach ($obj in @($action, $actions, $definition, $task, $folder, $scheduler)) {
                if ($obj) {
                    try {
                        [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($obj)
                    } catch {}
                }
            }
        }
    }

    function Ensure-SilentRepairIntegration {
        if (Test-SilentRepairTask) {
            return $true
        }

        if (-not (Test-Path -LiteralPath $SetupHostPath -PathType Leaf)) {
            Set-Badge $HeroBadge $HeroBadgeText 'ATTENTION' 'warning'
            $HeroTitle.Text = 'Repair integration needs attention'
            $HeroDetail.Text = 'Run Repair installation once to restore the silent repair launcher.'
            Set-ActionButton 'Repair installation' 'repair-install' $true 'primary'
            return $false
        }

        try {
            Set-Badge $HeroBadge $HeroBadgeText 'ONE-TIME SETUP' 'checking'
            $HeroTitle.Text = 'Finishing Quick Repair setup'
            $HeroDetail.Text = 'Approve the Windows prompt once. Future repairs will run without a PowerShell window.'
            Set-ActionButton 'Waiting for Windows…' 'repair' $false

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SetupHostPath
            $psi.Arguments = '--repair'
            $psi.UseShellExecute = $true

            $setupProcess = [System.Diagnostics.Process]::Start($psi)

            if (-not $setupProcess) {
                throw 'The Setup bridge could not start.'
            }

            $script:allowFullExit = $true
            $window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{
                    try { $window.Close() } catch {}
                }
            ) | Out-Null

            return $false
        }
        catch {
            Set-Badge $HeroBadge $HeroBadgeText 'ATTENTION' 'warning'
            $HeroTitle.Text = 'One-time setup was not completed'
            $HeroDetail.Text = 'Nothing was changed. Try again when you are ready to approve the Windows prompt.'
            Set-ActionButton 'Try Again' 'repair' $true 'primary'
            return $false
        }
    }

    function Start-RepairCore {
        if (Attach-To-RunningRepair) {
            return
        }

        if (-not (Ensure-SilentRepairIntegration)) {
            $script:repairActive = $false
            return
        }

        if (-not (Ensure-EngineReadyCached)) {
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $repairCoreAnchor `
    -Replace $repairCoreReplacement `
    -Description 'silent repair integration migration'

$themeAnchor = @'
    Add-Type -AssemblyName System.Drawing

    # --------------------------------------------------------------
    # Helpers
'@

$themeReplacement = @'
    Add-Type -AssemblyName System.Drawing

    if (-not ('QuickRepairWindowTheme' -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public static class QuickRepairWindowTheme
{
    [DllImport("dwmapi.dll")]
    private static extern int DwmSetWindowAttribute(
        IntPtr hwnd,
        int attribute,
        ref int value,
        int size
    );

    public static void Apply(IntPtr hwnd)
    {
        try
        {
            int enabled = 1;
            DwmSetWindowAttribute(hwnd, 20, ref enabled, sizeof(int));
            DwmSetWindowAttribute(hwnd, 19, ref enabled, sizeof(int));

            // DWM COLORREF uses 0x00BBGGRR.
            int caption = 0x00120D0A;
            int text = 0x00FFFFFF;

            DwmSetWindowAttribute(hwnd, 35, ref caption, sizeof(int));
            DwmSetWindowAttribute(hwnd, 36, ref text, sizeof(int));
        }
        catch
        {
        }
    }
}
"@
    }

    function Set-DarkWindowChrome {
        param([System.Windows.Window]$TargetWindow)

        if (-not $TargetWindow) {
            return
        }

        try {
            $interop = New-Object System.Windows.Interop.WindowInteropHelper($TargetWindow)
            [QuickRepairWindowTheme]::Apply($interop.Handle)
        }
        catch {}
    }

    # --------------------------------------------------------------
    # Helpers
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $themeAnchor `
    -Replace $themeReplacement `
    -Description 'dark window chrome helper'

$windowLoadAnchor = @'
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    # --------------------------------------------------------------
    # Bind UI controls
'@

$windowLoadReplacement = @'
    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [Windows.Markup.XamlReader]::Load($reader)

    $window.Add_SourceInitialized({
        Set-DarkWindowChrome $window
    })

    # --------------------------------------------------------------
    # Bind UI controls
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $windowLoadAnchor `
    -Replace $windowLoadReplacement `
    -Description 'dark title-bar hook'

foreach ($required in @(
    'QuickRepairWindowTheme',
    'VerticalScrollBarVisibility="Hidden"',
    ('Current ' + $Version + ' - Check GitHub for updates.'),
    ('$ProductVersion = ''' + $Version + ''''),
    ('$ProductVersionCode = [int64]' + $VersionCode),
    'Only meaningful changes and repair actions from this session.',
    'Ensure-SilentRepairIntegration',
    'DispatcherPriority]::ApplicationIdle'
)) {
    if ($text -notmatch [regex]::Escape($required)) {
        throw "UI polish verification failed: $required"
    }
}

[void][scriptblock]::Create($text)

$xamlMatch = [regex]::Match(
    $text,
    '(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@'
)

if (-not $xamlMatch.Success) {
    throw 'Could not locate polished Quick Repair XAML.'
}

[xml]$xamlDocument = $xamlMatch.Groups['xaml'].Value

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop

$reader = New-Object System.Xml.XmlNodeReader $xamlDocument
$testWindow = $null

try {
    $testWindow = [Windows.Markup.XamlReader]::Load($reader)

    if (-not $testWindow) {
        throw 'Polished WPF XAML validation returned no Window.'
    }
}
finally {
    try { $reader.Close() } catch {}
    try {
        if ($testWindow -is [System.Windows.Window]) {
            $testWindow.Close()
        }
    } catch {}
}

$utf8Bom = New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText($Path, $text, $utf8Bom)

Write-Host "Focused UI polish passed: $Version ($VersionCode)"
