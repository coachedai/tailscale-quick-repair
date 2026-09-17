param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist-public')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

& (Join-Path $PSScriptRoot 'privacy-scan.ps1') `
    -Root $repo `
    -SkipRepositoryIdentity

$required = @(
    'src\app\Tailscale-Repair-UI.ps1',
    'src\program\Repair-Backend.ps1',
    'src\native\NativeHost.cs',
    'src\native\InstallerHost.cs',
    'src\native\UpdaterHost.cs',
    'src\native\UpdaterEntry.cs'
)

foreach ($relative in $required) {
    $path = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Public installer source is missing: $relative"
    }
}

$backendPath = Join-Path $repo 'src\program\Repair-Backend.ps1'
$backendText = [IO.File]::ReadAllText($backendPath, [Text.Encoding]::UTF8)
[void][scriptblock]::Create($backendText)

if (
    $backendText -match '(?m)^\s*\$Peer\s*=\s*[''\"]\d{1,3}(?:\.\d{1,3}){3}[''\"]' -or
    $backendText -match '100\.106\.128\.84'
) {
    throw 'Public repair backend still contains a baked-in peer address.'
}

if ($backendText -notmatch [regex]::Escape("Join-Path `$env:LOCALAPPDATA 'TailscaleQuickRepair'")) {
    throw 'Public repair backend does not load local Quick Repair configuration.'
}

$compiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object {
    Test-Path -LiteralPath $_
} | Select-Object -First 1

if (-not $compiler) {
    throw 'The .NET Framework C# compiler could not be located.'
}

$frameworkDir = Split-Path -Parent $compiler
$webExtensions = Join-Path $frameworkDir 'System.Web.Extensions.dll'
$compression = Join-Path $frameworkDir 'System.IO.Compression.dll'
$compressionFs = Join-Path $frameworkDir 'System.IO.Compression.FileSystem.dll'
$windowsForms = Join-Path $frameworkDir 'System.Windows.Forms.dll'
$drawing = Join-Path $frameworkDir 'System.Drawing.dll'

foreach ($assembly in @(
    $webExtensions,
    $compression,
    $compressionFs,
    $windowsForms,
    $drawing
)) {
    if (-not (Test-Path -LiteralPath $assembly)) {
        throw "Required .NET Framework reference is missing: $assembly"
    }
}

$automation = $null

try {
    $automation = [System.Management.Automation.PowerShell].Assembly.Location
}
catch {}

if ([string]::IsNullOrWhiteSpace($automation)) {
    $automation = Join-Path $PSHOME 'System.Management.Automation.dll'
}

if (-not (Test-Path -LiteralPath $automation -PathType Leaf)) {
    throw 'System.Management.Automation.dll could not be resolved for the native desktop host.'
}

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

function Invoke-CSharpBuild {
    param(
        [string]$Output,
        [string[]]$Sources,
        [string[]]$References,
        [string]$MainType
    )

    $stdout = "$Output.stdout.txt"
    $stderr = "$Output.stderr.txt"

    Remove-Item $Output,$stdout,$stderr -Force -ErrorAction SilentlyContinue

    $args = @(
        '/nologo'
        '/target:winexe'
        '/platform:anycpu'
        '/optimize+'
        ('/main:{0}' -f $MainType)
        ('/out:"{0}"' -f $Output)
    )

    foreach ($reference in $References) {
        $args += ('/reference:"{0}"' -f $reference)
    }

    foreach ($source in $Sources) {
        $args += ('"{0}"' -f $source)
    }

    $process = Start-Process `
        -FilePath $compiler `
        -ArgumentList ($args -join ' ') `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Output)) {
        $details = @()

        if (Test-Path -LiteralPath $stdout) {
            $details += Get-Content -LiteralPath $stdout -Raw
        }

        if (Test-Path -LiteralPath $stderr) {
            $details += Get-Content -LiteralPath $stderr -Raw
        }

        throw "Native compilation failed for $Output.`r`n$($details -join [Environment]::NewLine)"
    }

    Remove-Item $stdout,$stderr -Force -ErrorAction SilentlyContinue
}

$nativeHost = Join-Path $OutputDirectory 'TailscaleQuickRepair.exe'
$installerHost = Join-Path $OutputDirectory 'TailscaleQuickRepair-Setup.exe'

Invoke-CSharpBuild `
    -Output $nativeHost `
    -Sources @(
        (Join-Path $repo 'src\native\NativeHost.cs')
    ) `
    -References @(
        $automation,
        $windowsForms
    ) `
    -MainType 'NativeHost'

Invoke-CSharpBuild `
    -Output $installerHost `
    -Sources @(
        (Join-Path $repo 'src\native\InstallerHost.cs')
    ) `
    -References @(
        $webExtensions,
        $compression,
        $compressionFs,
        $windowsForms,
        $drawing
    ) `
    -MainType 'InstallerHost'

$hostTest = Start-Process `
    -FilePath $nativeHost `
    -ArgumentList '--self-test-host' `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

if ($hostTest.ExitCode -ne 0) {
    throw "Native desktop host self-test failed with exit code $($hostTest.ExitCode)."
}

$installerTest = Start-Process `
    -FilePath $installerHost `
    -ArgumentList '--self-test-installer' `
    -WindowStyle Hidden `
    -Wait `
    -PassThru

if ($installerTest.ExitCode -ne 0) {
    throw "Native installer self-test failed with exit code $($installerTest.ExitCode)."
}

& (Join-Path $PSScriptRoot 'privacy-scan.ps1') `
    -Root $OutputDirectory `
    -SkipRepositoryIdentity

Write-Host 'Public installer native validation passed.'
Write-Host "DESKTOP_HOST=$nativeHost"
Write-Host "SETUP_HOST=$installerHost"
