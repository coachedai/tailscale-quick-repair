param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionPath = Join-Path $repo 'version.json'
$packageSpecPath = Join-Path $repo 'release\package.json'

& (Join-Path $PSScriptRoot 'privacy-scan.ps1') `
    -Root $repo `
    -SkipRepositoryIdentity

$versionInfo = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
$packageSpec = Get-Content -LiteralPath $packageSpecPath -Raw | ConvertFrom-Json

$version = [string]$versionInfo.version
$versionCode = [int64]$versionInfo.versionCode

if ([string]::IsNullOrWhiteSpace($version) -or $versionCode -le 0) {
    throw 'version.json does not contain a valid version/versionCode.'
}

if ([int]$packageSpec.schema -ne 1) {
    throw 'release/package.json has an unsupported schema.'
}

$required = @(
    'src\app\Tailscale-Repair-UI.ps1',
    'src\program\Update-Installer.ps1',
    'src\native\UpdaterHost.cs'
)

foreach ($relative in $required) {
    $path = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required release source is missing: $relative"
    }
}

function Normalize-UiForWindowsPowerShell {
    param([string]$Text)

    # Two legacy helper-call forms survived from the pre-CI builds. They run
    # through the embedded host path but are not valid standalone Windows
    # PowerShell 5.1 syntax. Normalize them only for the shipped package.
    $oldResetApp = "        Set-Step `$AppDot `$AppStep (if ([string]`$preflight.Client -eq 'Running') { 'good' } elseif ([string]`$preflight.Client -eq 'Closed') { 'warn' } else { 'bad' })"
    $newResetApp = @"
        `$appStepState = if ([string]`$preflight.Client -eq 'Running') {
            'good'
        } elseif ([string]`$preflight.Client -eq 'Closed') {
            'warn'
        } else {
            'bad'
        }
        Set-Step `$AppDot `$AppStep `$appStepState
"@

    $oldResetService = "        Set-Step `$ServiceDot `$ServiceStep (if ([string]`$preflight.Service -eq 'Running') { 'good' } elseif ([string]`$preflight.Service -eq 'Stopped') { 'warn' } elseif ([string]`$preflight.Service -eq 'Missing') { 'bad' } else { 'idle' })"
    $newResetService = @"
        `$serviceStepState = if ([string]`$preflight.Service -eq 'Running') {
            'good'
        } elseif ([string]`$preflight.Service -eq 'Stopped') {
            'warn'
        } elseif ([string]`$preflight.Service -eq 'Missing') {
            'bad'
        } else {
            'idle'
        }
        Set-Step `$ServiceDot `$ServiceStep `$serviceStepState
"@

    $oldCardApp = @"
        Set-Step `$AppDot `$AppStep (
            if ([string]`$Data.client -eq 'Running') { 'good' }
            elseif ([string]`$Data.client -eq 'Closed') { 'warn' }
            elseif ([int]`$Data.progress -ge 22) { 'bad' }
            else { 'active' }
        )
"@
    $newCardApp = @"
        `$appStepState = if ([string]`$Data.client -eq 'Running') {
            'good'
        } elseif ([string]`$Data.client -eq 'Closed') {
            'warn'
        } elseif ([int]`$Data.progress -ge 22) {
            'bad'
        } else {
            'active'
        }
        Set-Step `$AppDot `$AppStep `$appStepState
"@

    $oldCardService = @"
        Set-Step `$ServiceDot `$ServiceStep (
            if ([string]`$Data.service -eq 'Running') { 'good' }
            elseif ([string]`$Data.service -eq 'Stopped') { 'warn' }
            elseif ([int]`$Data.progress -ge 48) { 'bad' }
            else { 'active' }
        )
"@
    $newCardService = @"
        `$serviceStepState = if ([string]`$Data.service -eq 'Running') {
            'good'
        } elseif ([string]`$Data.service -eq 'Stopped') {
            'warn'
        } elseif ([int]`$Data.progress -ge 48) {
            'bad'
        } else {
            'active'
        }
        Set-Step `$ServiceDot `$ServiceStep `$serviceStepState
"@

    $Text = $Text.Replace($oldResetApp, $newResetApp.TrimEnd("`r", "`n"))
    $Text = $Text.Replace($oldResetService, $newResetService.TrimEnd("`r", "`n"))
    $Text = $Text.Replace($oldCardApp.TrimEnd("`r", "`n"), $newCardApp.TrimEnd("`r", "`n"))
    $Text = $Text.Replace($oldCardService.TrimEnd("`r", "`n"), $newCardService.TrimEnd("`r", "`n"))

    if (
        $Text -match 'Set-Step\s+\$AppDot\s+\$AppStep\s+\(' -or
        $Text -match 'Set-Step\s+\$ServiceDot\s+\$ServiceStep\s+\('
    ) {
        throw 'Legacy Set-Step expression syntax remains after normalization.'
    }

    return $Text
}

$uiPath = Join-Path $repo 'src\app\Tailscale-Repair-UI.ps1'
$uiText = [IO.File]::ReadAllText($uiPath, [Text.Encoding]::UTF8)
$uiText = Normalize-UiForWindowsPowerShell $uiText

$updateInstallerPath = Join-Path $repo 'src\program\Update-Installer.ps1'
$updateInstallerText = [IO.File]::ReadAllText(
    $updateInstallerPath,
    [Text.Encoding]::UTF8
)

[void][scriptblock]::Create($uiText)
[void][scriptblock]::Create($updateInstallerText)

$xamlMatch = [regex]::Match(
    $uiText,
    '(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@'
)

if (-not $xamlMatch.Success) {
    throw 'Could not locate the Quick Repair XAML block.'
}

[xml]$xamlDocument = $xamlMatch.Groups['xaml'].Value

Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
Add-Type -AssemblyName PresentationCore -ErrorAction Stop
Add-Type -AssemblyName WindowsBase -ErrorAction Stop

$reader = New-Object System.Xml.XmlNodeReader $xamlDocument
$window = $null

try {
    $window = [Windows.Markup.XamlReader]::Load($reader)

    if (-not $window) {
        throw 'WPF XAML validation returned no Window.'
    }
}
finally {
    try { $reader.Close() } catch {}
    try {
        if ($window -is [System.Windows.Window]) {
            $window.Close()
        }
    } catch {}
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

$work = Join-Path $env:TEMP ('TQR-Release-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $work 'package'
$packageApp = Join-Path $packageRoot 'app'
$packageProgram = Join-Path $packageRoot 'program'

New-Item -ItemType Directory -Path $packageApp -Force | Out-Null
New-Item -ItemType Directory -Path $packageProgram -Force | Out-Null
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

try {
    $updaterSource = Join-Path $repo 'src\native\UpdaterHost.cs'
    $updaterExe = Join-Path $packageApp 'TailscaleQuickRepairUpdater.exe'
    $compileOut = Join-Path $work 'compile.out'
    $compileErr = Join-Path $work 'compile.err'

    $args = @(
        '/nologo'
        '/target:winexe'
        '/platform:anycpu'
        '/optimize+'
        ('/out:"{0}"' -f $updaterExe)
        ('"{0}"' -f $updaterSource)
    )

    $compile = Start-Process `
        -FilePath $compiler `
        -ArgumentList ($args -join ' ') `
        -RedirectStandardOutput $compileOut `
        -RedirectStandardError $compileErr `
        -WindowStyle Hidden `
        -Wait `
        -PassThru

    if (
        $compile.ExitCode -ne 0 -or
        -not (Test-Path -LiteralPath $updaterExe)
    ) {
        $details = @()

        if (Test-Path -LiteralPath $compileOut) {
            $details += Get-Content -LiteralPath $compileOut -Raw
        }

        if (Test-Path -LiteralPath $compileErr) {
            $details += Get-Content -LiteralPath $compileErr -Raw
        }

        throw "Updater host compilation failed.`r`n$($details -join [Environment]::NewLine)"
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)

    [IO.File]::WriteAllText(
        (Join-Path $packageApp 'Tailscale-Repair-UI.ps1'),
        $uiText,
        $utf8Bom
    )

    [IO.File]::WriteAllText(
        (Join-Path $packageProgram 'Update-Installer.ps1'),
        $updateInstallerText,
        $utf8Bom
    )

    Copy-Item $versionPath (Join-Path $packageRoot 'version.json') -Force

    $entries = @()

    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Where-Object { $_.Name -ne 'package-manifest.json' } |
        Sort-Object FullName |
        ForEach-Object {
            $relative = $_.FullName.Substring($packageRoot.Length).TrimStart('\') -replace '\\','/'

            $entries += [ordered]@{
                path = $relative
                sha256 = (
                    Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256
                ).Hash.ToLowerInvariant()
                size = $_.Length
            }
        }

    $manifest = [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = $version
        versionCode = $versionCode
        files = $entries
    }

    $manifest |
        ConvertTo-Json -Depth 8 |
        Set-Content `
            -LiteralPath (Join-Path $packageRoot 'package-manifest.json') `
            -Encoding UTF8

    & (Join-Path $PSScriptRoot 'privacy-scan.ps1') `
        -Root $packageRoot `
        -SkipRepositoryIdentity

    $safeVersion = $version -replace '[^A-Za-z0-9._-]', '-'
    $zipPath = Join-Path $OutputDirectory "TailscaleQuickRepair-$safeVersion.zip"

    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue

    Compress-Archive `
        -Path (Join-Path $packageRoot '*') `
        -DestinationPath $zipPath `
        -CompressionLevel Optimal

    $sha = (
        Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()

    $sha |
        Set-Content `
            -LiteralPath "$zipPath.sha256" `
            -Encoding ASCII

    Write-Host "PACKAGE=$zipPath"
    Write-Host "SHA256=$sha"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
