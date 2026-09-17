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

Write-Host "Focused UI polish passed: $Version ($VersionCode)"
