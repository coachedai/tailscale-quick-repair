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

$text = Replace-RegexOnce `
    -Text $text `
    -Pattern 'Text="Current [^"]+ · Check GitHub for updates\."' `
    -Replace ('Text="Current ' + $Version + ' · Check GitHub for updates."') `
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
            int caption = 0x00120D0A; // #0A0D12
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

$remoteHeader = @'
                                <StackPanel Grid.Column="2">
                                    <TextBlock Text="Remote" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>
                                    <Grid Margin="0,16,0,0">
'@

$remoteHeaderReplacement = @'
                                <StackPanel Grid.Column="2">
                                    <Grid>
                                        <Grid.ColumnDefinitions>
                                            <ColumnDefinition Width="*"/>
                                            <ColumnDefinition Width="Auto"/>
                                        </Grid.ColumnDefinitions>
                                        <TextBlock Text="Remote" FontSize="15" FontWeight="SemiBold" Foreground="{StaticResource Text}"/>
                                        <Button
                                            x:Name="ChangeTargetButton"
                                            Grid.Column="1"
                                            AutomationProperties.Name="Change target device"
                                            AutomationProperties.HelpText="Change the Tailscale IP used as the remote target."
                                            Style="{StaticResource GhostButtonStyle}"
                                            Content="Change"/>
                                    </Grid>
                                    <Grid Margin="0,16,0,0">
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $remoteHeader `
    -Replace $remoteHeaderReplacement `
    -Description 'remote target change button'

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
    -Description 'main-window dark chrome hook'

$bindingAnchor = @'
    $DetailPeerIp = $window.FindName('DetailPeerIp')
    $DetailPeerStatus = $window.FindName('DetailPeerStatus')
'@

$bindingReplacement = @'
    $DetailPeerIp = $window.FindName('DetailPeerIp')
    $ChangeTargetButton = $window.FindName('ChangeTargetButton')
    $DetailPeerStatus = $window.FindName('DetailPeerStatus')
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $bindingAnchor `
    -Replace $bindingReplacement `
    -Description 'target-change control binding'

$targetFunctions = @'
    function Test-TargetPeerInput {
        param([string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $false
        }

        $candidate = $Value.Trim()

        if (
            $candidate.Length -gt 255 -or
            $candidate -match '[\r\n\s]'
        ) {
            return $false
        }

        $address = $null

        if ([System.Net.IPAddress]::TryParse($candidate, [ref]$address)) {
            return $true
        }

        # MagicDNS names are also accepted for users who prefer names.
        return [bool](
            $candidate -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]{0,253}[A-Za-z0-9])?$'
        )
    }

    function Save-TargetPeer {
        param([string]$Value)

        $candidate = if ($Value) {
            $Value.Trim()
        } else {
            ''
        }

        if (-not (Test-TargetPeerInput $candidate)) {
            throw 'Enter a valid Tailscale IP or MagicDNS name.'
        }

        New-Item -ItemType Directory -Path $StateDir -Force | Out-Null

        $tempConfig = "$ConfigPath.$PID.tmp"
        $encoding = New-Object System.Text.UTF8Encoding($false)

        try {
            [IO.File]::WriteAllText(
                $tempConfig,
                ([ordered]@{ peer = $candidate } | ConvertTo-Json -Depth 3),
                $encoding
            )

            Move-Item `
                -LiteralPath $tempConfig `
                -Destination $ConfigPath `
                -Force
        }
        finally {
            Remove-Item `
                -LiteralPath $tempConfig `
                -Force `
                -ErrorAction SilentlyContinue
        }

        $script:Peer = $candidate
        $RemotePeerIpText.Text = $candidate
        $DetailPeerIp.Text = $candidate

        try {
            $script:lastAppliedStateWriteUtc = [DateTime]::MinValue
            $script:lastData = $null
            Reset-Ui -SkipEngineCheck
        }
        catch {}

        return $candidate
    }

    function Show-TargetPeerDialog {
        $dialogXamlText = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Target device"
    Width="470"
    Height="275"
    ResizeMode="NoResize"
    WindowStartupLocation="CenterOwner"
    Background="#0A0D12"
    Foreground="#F7F8FA"
    FontFamily="Segoe UI"
    ShowInTaskbar="False">
    <Border
        Margin="18"
        Padding="22"
        CornerRadius="12"
        Background="#11151B"
        BorderBrush="#29313C"
        BorderThickness="1">
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
            </Grid.RowDefinitions>

            <TextBlock
                Text="Target device"
                FontSize="18"
                FontWeight="SemiBold"/>

            <TextBlock
                Grid.Row="1"
                Margin="0,6,0,0"
                Text="Enter the Tailscale IP you connect to, for example your RDP machine."
                Foreground="#8F9BA8"
                FontSize="11"
                TextWrapping="Wrap"/>

            <StackPanel Grid.Row="2" Margin="0,18,0,0">
                <TextBox
                    x:Name="TargetPeerInput"
                    Height="38"
                    Padding="10,7"
                    Background="#151A21"
                    Foreground="#F7F8FA"
                    BorderBrush="#354052"
                    BorderThickness="1"
                    FontSize="13"/>
                <TextBlock
                    x:Name="TargetPeerError"
                    Margin="2,6,0,0"
                    Foreground="#FF6B78"
                    FontSize="10.5"
                    Visibility="Collapsed"/>
            </StackPanel>

            <StackPanel
                Grid.Row="3"
                Margin="0,18,0,0"
                Orientation="Horizontal"
                HorizontalAlignment="Right">
                <Button
                    x:Name="CancelTargetButton"
                    Width="86"
                    Height="34"
                    Margin="0,0,8,0"
                    Background="#1B222D"
                    Foreground="#D8E0EA"
                    BorderBrush="Transparent"
                    Content="Cancel"/>
                <Button
                    x:Name="SaveTargetButton"
                    Width="100"
                    Height="34"
                    Background="#0866FF"
                    Foreground="White"
                    BorderBrush="Transparent"
                    FontWeight="SemiBold"
                    Content="Save"/>
            </StackPanel>
        </Grid>
    </Border>
</Window>
"@

        try {
            [xml]$dialogXaml = $dialogXamlText
            $dialogReader = New-Object System.Xml.XmlNodeReader $dialogXaml
            $dialog = [Windows.Markup.XamlReader]::Load($dialogReader)
            $dialog.Owner = $window

            $input = $dialog.FindName('TargetPeerInput')
            $errorText = $dialog.FindName('TargetPeerError')
            $saveButton = $dialog.FindName('SaveTargetButton')
            $cancelButton = $dialog.FindName('CancelTargetButton')

            $input.Text = if ([string]::IsNullOrWhiteSpace($Peer)) {
                ''
            } else {
                $Peer
            }

            $dialog.Add_SourceInitialized({
                Set-DarkWindowChrome $dialog
            })

            $cancelButton.Add_Click({
                $dialog.DialogResult = $false
                $dialog.Close()
            })

            $saveButton.Add_Click({
                try {
                    [void](Save-TargetPeer $input.Text)
                    $errorText.Visibility = [System.Windows.Visibility]::Collapsed
                    $dialog.DialogResult = $true
                    $dialog.Close()
                }
                catch {
                    $errorText.Text = $_.Exception.Message
                    $errorText.Visibility = [System.Windows.Visibility]::Visible
                    $input.Focus() | Out-Null
                    $input.SelectAll()
                }
            })

            $dialog.Add_ContentRendered({
                $input.Focus() | Out-Null
                $input.SelectAll()
            })

            [void]$dialog.ShowDialog()
        }
        catch {
            try {
                [System.Windows.MessageBox]::Show(
                    'Quick Repair could not open the target-device editor.',
                    'Tailscale Quick Repair',
                    [System.Windows.MessageBoxButton]::OK,
                    [System.Windows.MessageBoxImage]::Warning
                ) | Out-Null
            }
            catch {}
        }
    }

'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find '    function Start-AdvancedDiagnostics {' `
    -Replace ($targetFunctions + '    function Start-AdvancedDiagnostics {') `
    -Description 'target-device functions'

$eventAnchor = @'
    $RepairInstallationButton.Add_Click({
        Invoke-InstallationRepair
    })

    $CheckForUpdatesButton.Add_Click({
'@

$eventReplacement = @'
    $RepairInstallationButton.Add_Click({
        Invoke-InstallationRepair
    })

    $ChangeTargetButton.Add_Click({
        Show-TargetPeerDialog
    })

    $CheckForUpdatesButton.Add_Click({
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $eventAnchor `
    -Replace $eventReplacement `
    -Description 'target-change event'

$firstRunAnchor = @'
                Initialize-AutoRepairLocalWatch
                Show-UpdateResult

                if (-not (Attach-To-RunningRepair)) {
'@

$firstRunReplacement = @'
                Initialize-AutoRepairLocalWatch
                Show-UpdateResult

                if (
                    -not $StartInTray -and
                    [string]::IsNullOrWhiteSpace($Peer)
                ) {
                    [void](Show-TargetPeerDialog)
                }

                if (-not (Attach-To-RunningRepair)) {
'@

$text = Replace-ExactOnce `
    -Text $text `
    -Find $firstRunAnchor `
    -Replace $firstRunReplacement `
    -Description 'first-run target prompt'

foreach ($required in @(
    'QuickRepairWindowTheme',
    'VerticalScrollBarVisibility="Hidden"',
    'x:Name="ChangeTargetButton"',
    'function Show-TargetPeerDialog',
    'function Save-TargetPeer',
    ('$ProductVersion = ''' + $Version + ''''),
    ('$ProductVersionCode = [int64]' + $VersionCode)
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

Write-Host "UI polish passed: $Version ($VersionCode)"
