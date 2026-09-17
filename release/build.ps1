param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist')
)

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$versionPath = Join-Path $repo 'version.json'
$publishPath = Join-Path $repo 'release\publish.json'
$privacyScan = Join-Path $repo 'release\privacy-scan.ps1'

& $privacyScan -Root $repo

$versionInfo = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json
$publishInfo = Get-Content -LiteralPath $publishPath -Raw | ConvertFrom-Json

$version = [string]$versionInfo.version
$versionCode = [int64]$versionInfo.versionCode

if ([string]::IsNullOrWhiteSpace($version) -or $versionCode -le 0) {
    throw 'version.json does not contain a valid version/versionCode.'
}

if (
    [string]$publishInfo.version -ne $version -or
    [int64]$publishInfo.versionCode -ne $versionCode
) {
    throw 'release/publish.json version metadata does not match version.json.'
}

$requiredSource = @(
    'src\app\Tailscale-Repair-UI.ps1',
    'src\app\Advanced-Diagnostics.ps1',
    'src\program\Repair-Backend.ps1',
    'src\program\Auto-Repair-Monitor.ps1',
    'src\program\Repair-Installation.ps1',
    'src\native\NativeHost.cs',
    'src\launchers\Launch-Tailscale-Quick-Repair.vbs',
    'src\launchers\Launch-Tailscale-Quick-Repair-Startup.vbs',
    'src\launchers\Launch-Tailscale-Backend.vbs',
    'src\launchers\Launch-Tailscale-Auto-Repair.vbs'
)

$missing = @(
    $requiredSource |
        Where-Object { -not (Test-Path -LiteralPath (Join-Path $repo $_)) }
)

New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null

if ($missing.Count -gt 0) {
    if ([bool]$publishInfo.publish) {
        throw "Publishing is blocked because the source migration is incomplete. Missing: $($missing -join ', ')"
    }

    $bootstrap = [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = $version
        versionCode = $versionCode
        publish = $false
        status = 'update-channel-bootstrap'
        sourceComplete = $false
        missingSource = $missing
        validatedAt = [DateTime]::UtcNow.ToString('o')
    }

    $bootstrapPath = Join-Path $OutputDirectory 'channel-validation.json'
    $bootstrap | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $bootstrapPath -Encoding UTF8

    Write-Host 'Update-channel bootstrap validation passed. Publishing remains blocked until the full source tree is present.' -ForegroundColor Yellow
    return
}

# Parse PowerShell source.
foreach ($relative in $requiredSource | Where-Object { $_ -like '*.ps1' }) {
    $path = Join-Path $repo $relative
    $text = Get-Content -LiteralPath $path -Raw -ErrorAction Stop
    [void][scriptblock]::Create($text)
}

# Real WPF/XAML parse.
$uiPath = Join-Path $repo 'src\app\Tailscale-Repair-UI.ps1'
$uiText = Get-Content -LiteralPath $uiPath -Raw
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
    if (-not $window) { throw 'WPF XAML validation returned no Window.' }
}
finally {
    try { $reader.Close() } catch {}
    try { if ($window -is [System.Windows.Window]) { $window.Close() } } catch {}
}

$smaPath = [System.Management.Automation.PowerShell].Assembly.Location
if (-not $smaPath -or -not (Test-Path -LiteralPath $smaPath)) {
    throw 'System.Management.Automation.dll could not be located.'
}

$compiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $compiler) { throw 'The .NET Framework C# compiler could not be located.' }

$work = Join-Path $env:TEMP ('TQR-Release-' + [Guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $work 'package'
$packageApp = Join-Path $packageRoot 'app'
$packageProgram = Join-Path $packageRoot 'program'
$packageLaunchers = Join-Path $packageRoot 'launchers'

New-Item -ItemType Directory -Path $packageApp -Force | Out-Null
New-Item -ItemType Directory -Path $packageProgram -Force | Out-Null
New-Item -ItemType Directory -Path $packageLaunchers -Force | Out-Null

try {
    $nativeSource = Join-Path $repo 'src\native\NativeHost.cs'
    $nativeExe = Join-Path $packageApp 'TailscaleQuickRepair.exe'
    $compileOut = Join-Path $work 'compile.out'
    $compileErr = Join-Path $work 'compile.err'

    $args = @(
        '/nologo', '/target:winexe', '/platform:anycpu', '/optimize+',
        ('/reference:"{0}"' -f $smaPath),
        ('/out:"{0}"' -f $nativeExe),
        ('"{0}"' -f $nativeSource)
    )

    $compile = Start-Process -FilePath $compiler -ArgumentList ($args -join ' ') -RedirectStandardOutput $compileOut -RedirectStandardError $compileErr -WindowStyle Hidden -Wait -PassThru

    if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $nativeExe)) {
        $details = @()
        if (Test-Path $compileOut) { $details += Get-Content $compileOut -Raw }
        if (Test-Path $compileErr) { $details += Get-Content $compileErr -Raw }
        throw "Native host compilation failed.`r`n$($details -join [Environment]::NewLine)"
    }

    $hostTest = Start-Process -FilePath $nativeExe -ArgumentList '--self-test-host' -WindowStyle Hidden -Wait -PassThru
    if ($hostTest.ExitCode -ne 0) { throw 'Native embedded-host self-test failed.' }

    Copy-Item (Join-Path $repo 'src\app\Tailscale-Repair-UI.ps1') $packageApp -Force
    Copy-Item (Join-Path $repo 'src\app\Advanced-Diagnostics.ps1') $packageApp -Force
    Copy-Item (Join-Path $repo 'src\program\Repair-Backend.ps1') $packageProgram -Force
    Copy-Item (Join-Path $repo 'src\program\Auto-Repair-Monitor.ps1') $packageProgram -Force
    Copy-Item (Join-Path $repo 'src\program\Repair-Installation.ps1') $packageProgram -Force
    Copy-Item (Join-Path $repo 'src\launchers\Launch-Tailscale-Quick-Repair.vbs') $packageLaunchers -Force
    Copy-Item (Join-Path $repo 'src\launchers\Launch-Tailscale-Quick-Repair-Startup.vbs') $packageLaunchers -Force
    Copy-Item (Join-Path $repo 'src\launchers\Launch-Tailscale-Backend.vbs') $packageLaunchers -Force
    Copy-Item (Join-Path $repo 'src\launchers\Launch-Tailscale-Auto-Repair.vbs') $packageLaunchers -Force
    Copy-Item $versionPath (Join-Path $packageRoot 'version.json') -Force

    # Scan the exact staged package separately.
    & $privacyScan -Root $packageRoot -SkipRepositoryIdentity

    $entries = @()
    Get-ChildItem -LiteralPath $packageRoot -File -Recurse |
        Where-Object { $_.Name -ne 'package-manifest.json' } |
        ForEach-Object {
            $relative = $_.FullName.Substring($packageRoot.Length).TrimStart('\') -replace '\\','/'
            $entries += [ordered]@{
                path = $relative
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                size = $_.Length
            }
        }

    [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = $version
        versionCode = $versionCode
        files = $entries
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $packageRoot 'package-manifest.json') -Encoding UTF8

    $safeVersion = $version -replace '[^A-Za-z0-9._-]', '-'
    $zipPath = Join-Path $OutputDirectory "TailscaleQuickRepair-$safeVersion.zip"
    Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal

    $sha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha | Set-Content -LiteralPath "$zipPath.sha256" -Encoding ASCII

    Write-Host "PACKAGE=$zipPath"
    Write-Host "SHA256=$sha"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
