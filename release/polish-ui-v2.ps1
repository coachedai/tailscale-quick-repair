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

# UI-only 2.3.5 polish. Do not touch repair tasks, setup routing, networking or
# the proven repair engine. Keep new display strings ASCII-only for Windows
# PowerShell 5.1 packaging safety.
$activityHeader = @'
<StackPanel>
                                            <TextBlock Text="Activity" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>
                                            <TextBlock Text="Changes and repair actions from this app session."
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
    -Description 'activity heading'

$text = Replace-ExactOnce `
    -Text $text `
    -Find 'Text="No repair actions yet."/>' `
    -Replace 'Text="No activity yet."/>' `
    -Description 'activity empty state'

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

                # Reachability is already visible in Remote. Keep Activity for
                # changes and repair actions rather than duplicating status.
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
                    ForEach-Object { '- ' + [string]$_ }
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
            $SessionText.Text = 'Check in progress.'
        }

        $script:copyDiagnosticsText = @(
'@ `
    -Description 'activity feed logic'

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?m)^\s*''This session''\s*$' `
    -Replace "            'Activity'" `
    -Description 'activity copy heading'

# Reserve the small status rows instead of collapsing them. This keeps the
# hero and connection cards at one stable height while a check is running.
$lastCheckedXaml = @'
                            <TextBlock
                                x:Name="LastCheckedText"
                                Margin="0,9,0,0"
                                MinHeight="14"
                                FontSize="11"
                                Foreground="{StaticResource Faint}"
                                Visibility="Hidden"/>
'@
$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?s)\s*<TextBlock\s+x:Name="LastCheckedText"\s+Margin="0,9,0,0"\s+FontSize="11"\s+Foreground="\{StaticResource Faint\}"\s+Visibility="Collapsed"/>' `
    -Replace ([Environment]::NewLine + $lastCheckedXaml.TrimEnd("`r", "`n")) `
    -Description 'stable hero freshness row'

$connectionInsightXaml = @'
                            <TextBlock
                                x:Name="ConnectionInsightText"
                                Grid.Row="3"
                                Margin="0,15,0,0"
                                MinHeight="18"
                                FontSize="11.5"
                                Foreground="{StaticResource Faint}"
                                Visibility="Hidden"
                                TextWrapping="Wrap"/>
'@
$text = Replace-RegexOnce `
    -Text $text `
    -Pattern '(?s)\s*<TextBlock\s+x:Name="ConnectionInsightText"\s+Grid\.Row="3"\s+Margin="0,15,0,0"\s+FontSize="11\.5"\s+Foreground="\{StaticResource Faint\}"\s+Visibility="Collapsed"\s+TextWrapping="Wrap"/>' `
    -Replace ([Environment]::NewLine + $connectionInsightXaml.TrimEnd("`r", "`n")) `
    -Description 'stable connection insight row'

$text = $text.Replace(
    '$LastCheckedText.Visibility = [System.Windows.Visibility]::Collapsed',
    '$LastCheckedText.Visibility = [System.Windows.Visibility]::Hidden'
)

$text = Replace-ExactOnce `
    -Text $text `
    -Find '$ConnectionInsightText.Visibility = [System.Windows.Visibility]::Collapsed' `
    -Replace '$ConnectionInsightText.Visibility = [System.Windows.Visibility]::Hidden' `
    -Description 'stable connection insight visibility'

# 2.3.6 Tray Exit-only hardening. Keep repair/setup/network behavior frozen.
# Let the WinForms context-menu click unwind before WPF tears down the window
# and tray resources. This avoids shutdown-time errors from the live menu.
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
    -Description 'tray exit idle shutdown'

# Tell the native host that the WPF lifetime reached a normal close. The host
# can then distinguish a harmless shutdown-time PowerShell stream entry from a
# genuine failure to load the app.
$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
    if ($ownsWpfApp) {
        [void]$wpfApp.Run($window)
    }
    else {
        [void]$window.ShowDialog()
    }
'@ `
    -Replace @'
    if ($ownsWpfApp) {
        [void]$wpfApp.Run($window)
    }
    else {
        [void]$window.ShowDialog()
    }

    $global:TqrUiClosedNormally = $true
'@ `
    -Description 'native host normal-close marker'

# Phase 3 Guardian foundation: explicit lifecycle markers. These are behind-
# the-scenes state signals only; they do not change repair/network behavior.
$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
        $script:trayExitItem.Add_Click({
            try {
                $script:allowFullExit = $true

                if ($script:notifyIcon) {
'@ `
    -Replace @'
        $script:trayExitItem.Add_Click({
            try {
                $script:allowFullExit = $true
                $global:TqrUiShutdownRequested = $true

                if ($script:notifyIcon) {
'@ `
    -Description 'tray shutdown lifecycle marker'

$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
    $window.Add_Closed({
        $script:allowFullExit = $true
'@ `
    -Replace @'
    $window.Add_Closed({
        $script:allowFullExit = $true
        $global:TqrUiShutdownRequested = $true
'@ `
    -Description 'window closed lifecycle marker'

$text = Replace-ExactOnce `
    -Text $text `
    -Find @'
        # Windows logoff/shutdown must always be allowed to close the resident app.
        $script:allowFullExit = $true
    })
'@ `
    -Replace @'
        # Windows logoff/shutdown must always be allowed to close the resident app.
        $script:allowFullExit = $true
        $global:TqrUiShutdownRequested = $true
    })
'@ `
    -Description 'session ending lifecycle marker'


# Phase 3.1 Integrity Guardian foundation. Read-only: inspect Quick Repair's
# own install/configuration/integration and surface one compact Maintenance
# status. Do not change repair, setup, updater or network behavior.
$guardianMaintenanceOld = @'
                                        <Button
                                            x:Name="RepairInstallationButton"
                                            AutomationProperties.Name="Repair Quick Repair installation"
                                            AutomationProperties.HelpText="Rebuilds Quick Repair shell integration, tasks and launchers."
                                            Margin="0,14,0,0"
                                            HorizontalAlignment="Left"
                                            Style="{StaticResource GhostButtonStyle}"
                                            Content="Repair installation"/>
'@

$guardianMaintenanceNew = @'
                                        <Grid Margin="0,14,0,0">
                                            <Grid.ColumnDefinitions>
                                                <ColumnDefinition Width="*"/>
                                                <ColumnDefinition Width="Auto"/>
                                            </Grid.ColumnDefinitions>

                                            <StackPanel>
                                                <TextBlock
                                                    Text="System integrity"
                                                    FontSize="12"
                                                    Foreground="{StaticResource Value}"/>
                                                <TextBlock
                                                    x:Name="GuardianStatusText"
                                                    Margin="0,4,0,0"
                                                    MinHeight="15"
                                                    FontSize="10.5"
                                                    Foreground="{StaticResource Faint}"
                                                    Text="Checking..."/>
                                            </StackPanel>

                                            <Button
                                                x:Name="GuardianCheckButton"
                                                Grid.Column="1"
                                                AutomationProperties.Name="Check Quick Repair system integrity"
                                                AutomationProperties.HelpText="Runs a read-only check of Quick Repair files, configuration and Windows integration."
                                                VerticalAlignment="Center"
                                                Style="{StaticResource GhostButtonStyle}"
                                                Content="Check"/>
                                        </Grid>

                                        <TextBlock
                                            x:Name="GuardianDetailText"
                                            Margin="0,5,0,0"
                                            MinHeight="15"
                                            FontSize="10.5"
                                            Foreground="{StaticResource Faint}"
                                            Text="Quick Repair files, configuration and Windows integration."
                                            TextWrapping="Wrap"/>

                                        <Button
                                            x:Name="RepairInstallationButton"
                                            AutomationProperties.Name="Repair Quick Repair installation"
                                            AutomationProperties.HelpText="Rebuilds Quick Repair shell integration, tasks and launchers."
                                            Margin="0,18,0,0"
                                            HorizontalAlignment="Left"
                                            Style="{StaticResource GhostButtonStyle}"
                                            Content="Repair installation"/>
'@
$text = Replace-ExactOnce -Text $text -Find $guardianMaintenanceOld -Replace $guardianMaintenanceNew -Description 'Guardian Maintenance UI'

$guardianBindingOld = @'
    $RepairInstallationButton = $window.FindName('RepairInstallationButton')
    $UpdateStatusText = $window.FindName('UpdateStatusText')
'@
$guardianBindingNew = @'
    $GuardianStatusText = $window.FindName('GuardianStatusText')
    $GuardianDetailText = $window.FindName('GuardianDetailText')
    $GuardianCheckButton = $window.FindName('GuardianCheckButton')
    $RepairInstallationButton = $window.FindName('RepairInstallationButton')
    $UpdateStatusText = $window.FindName('UpdateStatusText')
'@
$text = Replace-ExactOnce -Text $text -Find $guardianBindingOld -Replace $guardianBindingNew -Description 'Guardian control bindings'

$guardianStateOld = @'
    $script:repairActive = $false
    $script:actionMode = 'repair'
'@
$guardianStateNew = @'
    $script:repairActive = $false
    $script:lastGuardianCheckAt = [DateTime]::MinValue
    $script:lastGuardianResult = $null
    $script:actionMode = 'repair'
'@
$text = Replace-ExactOnce -Text $text -Find $guardianStateOld -Replace $guardianStateNew -Description 'Guardian runtime state'

$guardianFunctions = @'
    function Get-GuardianIntegrityResult {
        $issues = New-Object 'System.Collections.Generic.List[string]'

        try {
            $requiredFiles = @(
                $NativeHostPath,
                (Join-Path $StateDir 'Tailscale-Repair-UI.ps1'),
                $UpdaterHostPath,
                $SetupHostPath,
                $AdvancedDiagnosticsPath,
                $BackendPath,
                $AutoRepairMonitorPath
            )

            foreach ($file in $requiredFiles) {
                if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                    $issues.Add("Missing component: $([IO.Path]::GetFileName($file))")
                }
            }

            if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
                $issues.Add('Target configuration is missing.')
            }
            elseif ([string]::IsNullOrWhiteSpace($Peer)) {
                $issues.Add('Target configuration is invalid.')
            }

            $installedVersionPath = Join-Path $StateDir 'version.user.json'

            if (-not (Test-Path -LiteralPath $installedVersionPath -PathType Leaf)) {
                $issues.Add('Installed version metadata is missing.')
            }
            else {
                try {
                    $installedVersion = Get-Content -LiteralPath $installedVersionPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

                    if ([int64]$installedVersion.versionCode -ne $ProductVersionCode) {
                        $issues.Add('Installed version metadata does not match this build.')
                    }
                }
                catch {
                    $issues.Add('Installed version metadata is invalid.')
                }
            }

            if (Test-Path -LiteralPath (Join-Path $StateDir 'Update.pending') -PathType Leaf) {
                $issues.Add('An interrupted update marker is still present.')
            }

            if (-not (Test-Path -LiteralPath $StartMenuShortcutPath -PathType Leaf)) {
                $issues.Add('Start Menu integration is missing.')
            }

            try {
                if (Test-StartWithWindows) {
                    $startupValue = (Get-ItemProperty -Path $StartupRegistryPath -Name $StartupRegistryName -ErrorAction Stop).$StartupRegistryName

                    if ([string]$startupValue -notlike '*TailscaleQuickRepair.exe*' -or [string]$startupValue -notlike '*--start-in-tray*') {
                        $issues.Add('Windows startup integration is not configured correctly.')
                    }
                }
            }
            catch {
                $issues.Add('Windows startup integration could not be verified.')
            }

            try {
                $engine = Test-RepairEngine

                if (-not [bool]$engine.Healthy) {
                    $message = [string]$engine.Message
                    if ([string]::IsNullOrWhiteSpace($message)) {
                        $message = 'Protected repair integration needs maintenance.'
                    }
                    $issues.Add($message)
                }
            }
            catch {
                $issues.Add('Protected repair integration could not be verified.')
            }

            try {
                if (-not (Test-AutoRepairAvailable)) {
                    $issues.Add('Automatic repair integration is unavailable.')
                }
            }
            catch {
                $issues.Add('Automatic repair integration could not be verified.')
            }
        }
        catch {
            $issues.Add('Integrity check could not inspect all components.')
        }

        return [pscustomobject]@{
            Healthy = ($issues.Count -eq 0)
            Count = $issues.Count
            Issues = @($issues)
        }
    }

    function Update-GuardianStatus {
        param([switch]$Force)

        if (-not $GuardianStatusText -or -not $GuardianDetailText) {
            return
        }

        if (-not $Force -and $script:lastGuardianCheckAt -ne [DateTime]::MinValue -and ((Get-Date) - $script:lastGuardianCheckAt).TotalSeconds -lt 60) {
            return
        }

        try {
            $GuardianCheckButton.IsEnabled = $false
            $GuardianStatusText.Text = 'Checking...'
            $GuardianStatusText.Foreground = Get-Brush 'Blue'

            $result = Get-GuardianIntegrityResult
            $script:lastGuardianCheckAt = Get-Date
            $script:lastGuardianResult = $result

            if ([bool]$result.Healthy) {
                $GuardianStatusText.Text = 'Healthy'
                $GuardianStatusText.Foreground = Get-Brush 'Green'
                $GuardianDetailText.Text = 'Core files, target configuration and Windows integration verified.'
                $GuardianDetailText.Foreground = Get-Brush 'Faint'
            }
            else {
                $count = [int]$result.Count
                $GuardianStatusText.Text = if ($count -eq 1) { '1 issue needs attention' } else { "$count issues need attention" }
                $GuardianStatusText.Foreground = Get-Brush 'Amber'
                $firstIssues = @($result.Issues | Select-Object -First 2)
                $GuardianDetailText.Text = $firstIssues -join '; '
                $GuardianDetailText.Foreground = Get-Brush 'Amber'
            }
        }
        catch {
            $GuardianStatusText.Text = 'Check incomplete'
            $GuardianStatusText.Foreground = Get-Brush 'Amber'
            $GuardianDetailText.Text = 'Quick Repair could not verify every integrity item.'
            $GuardianDetailText.Foreground = Get-Brush 'Amber'
        }
        finally {
            $GuardianCheckButton.IsEnabled = $true
        }
    }

'@

$text = Replace-ExactOnce -Text $text -Find '    function Update-DetailsToggleText {' -Replace ($guardianFunctions + '    function Update-DetailsToggleText {') -Description 'Guardian integrity functions'

$guardianEventOld = @'
    $RepairInstallationButton.Add_Click({
        Invoke-InstallationRepair
    })
'@
$guardianEventNew = @'
    $GuardianCheckButton.Add_Click({
        Update-GuardianStatus -Force
    })

    $RepairInstallationButton.Add_Click({
        Invoke-InstallationRepair
    })
'@
$text = Replace-ExactOnce -Text $text -Find $guardianEventOld -Replace $guardianEventNew -Description 'Guardian check event'

$guardianDetailsOld = @'
            $CopyButton.Content = 'Copy'
            Update-Diagnostics $script:lastData
            Initialize-AutoRepairUi
'@
$guardianDetailsNew = @'
            $CopyButton.Content = 'Copy'
            Update-Diagnostics $script:lastData
            Initialize-AutoRepairUi
            Update-GuardianStatus
'@
$text = Replace-ExactOnce -Text $text -Find $guardianDetailsOld -Replace $guardianDetailsNew -Description 'Guardian Details refresh'

$guardianStartupOld = @'
                if (-not (Attach-To-RunningRepair)) {
                    [void](Refresh-EngineCheck)
                }
'@
$guardianStartupNew = @'
                if (-not (Attach-To-RunningRepair)) {
                    [void](Refresh-EngineCheck)
                }

                Update-GuardianStatus -Force
'@
$text = Replace-ExactOnce -Text $text -Find $guardianStartupOld -Replace $guardianStartupNew -Description 'Guardian startup check'


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

    function Set-QuickRepairWindowIcon {
        param([System.Windows.Window]$TargetWindow)

        if (-not $TargetWindow) {
            return
        }

        $icon = $null

        try {
            if (-not (Test-Path -LiteralPath $NativeHostPath -PathType Leaf)) {
                return
            }

            $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($NativeHostPath)

            if (-not $icon) {
                return
            }

            $source = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHIcon(
                $icon.Handle,
                [System.Windows.Int32Rect]::Empty,
                [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions()
            )

            if ($source) {
                $source.Freeze()
                $TargetWindow.Icon = $source
            }
        }
        catch {}
        finally {
            if ($icon) {
                try { $icon.Dispose() } catch {}
            }
        }
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

    $global:TqrUiStartedSuccessfully = $true

    $window.Add_SourceInitialized({
        Set-DarkWindowChrome $window
        Set-QuickRepairWindowIcon $window
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
    'Text="Activity"',
    'Check in progress.',
    'MinHeight="14"',
    'MinHeight="18"',
    'DispatcherPriority]::ApplicationIdle',
    'TqrUiClosedNormally',
    'TqrUiStartedSuccessfully',
    'TqrUiShutdownRequested',
    'Set-QuickRepairWindowIcon',
    'System integrity',
    'GuardianStatusText',
    'Get-GuardianIntegrityResult',
    'Update-GuardianStatus'
)) {
    if ($text -notmatch [regex]::Escape($required)) {
        throw "UI polish verification failed: $required"
    }
}

# Guard this release as UI-only. These strings belong to repair/setup behavior
# and must not be introduced by the polish transform.
foreach ($forbidden in @(
    'Ensure-SilentRepairIntegration',
    'HardenTaskLaunchers',
    'Launch-Tailscale-Backend.vbs'' -and'
)) {
    if ($text -match [regex]::Escape($forbidden)) {
        throw "UI-only polish unexpectedly contains repair migration code: $forbidden"
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
