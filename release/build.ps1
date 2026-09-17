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

foreach ($relative in @(
    'src\app\Tailscale-Repair-UI.ps1',
    'src\program\Update-Installer.ps1'
)) {
    $path = Join-Path $repo $relative
    $text = [IO.File]::ReadAllText(
        $path,
        [Text.Encoding]::UTF8
    )
    [void][scriptblock]::Create($text)
}

$uiPath = Join-Path $repo 'src\app\Tailscale-Repair-UI.ps1'
$uiText = [IO.File]::ReadAllText(
    $uiPath,
    [Text.Encoding]::UTF8
)

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

    $uiPackagePath = Join-Path $packageApp 'Tailscale-Repair-UI.ps1'
    $installerPackagePath = Join-Path $packageProgram 'Update-Installer.ps1'

    [IO.File]::WriteAllText(
        $uiPackagePath,
        [IO.File]::ReadAllText(
            (Join-Path $repo 'src\app\Tailscale-Repair-UI.ps1'),
            [Text.Encoding]::UTF8
        ),
        $utf8Bom
    )

    [IO.File]::WriteAllText(
        $installerPackagePath,
        [IO.File]::ReadAllText(
            (Join-Path $repo 'src\program\Update-Installer.ps1'),
            [Text.Encoding]::UTF8
        ),
        $utf8Bom
    )

    Copy-Item $versionPath (Join-Path $packageRoot 'version.json') -Force

    $entries = @()

    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Where-Object {
            $_.Name -ne 'package-manifest.json'
        } |
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
