param(
    [Parameter(Mandatory=$true)]
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$output = (Resolve-Path -LiteralPath $OutputDirectory).Path
$zips = @(Get-ChildItem -LiteralPath $output -Filter 'TailscaleQuickRepair-*.zip' -File)

if ($zips.Count -ne 1) {
    throw "Expected exactly one normal update ZIP in $output; found $($zips.Count)."
}

$requiredSources = @(
    'src\native\PublicSetupHost.cs',
    'src\native\PublicSetupEntry.cs'
)

foreach ($relative in $requiredSources) {
    if (-not (Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf)) {
        throw "Native setup routing source is missing: $relative"
    }
}

$compiler = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1

if (-not $compiler) {
    throw 'The .NET Framework C# compiler could not be located.'
}

$frameworkDir = Split-Path -Parent $compiler
$refs = @(
    (Join-Path $frameworkDir 'System.Web.Extensions.dll'),
    (Join-Path $frameworkDir 'System.IO.Compression.dll'),
    (Join-Path $frameworkDir 'System.IO.Compression.FileSystem.dll'),
    (Join-Path $frameworkDir 'System.Windows.Forms.dll'),
    (Join-Path $frameworkDir 'System.Drawing.dll')
)

foreach ($reference in $refs) {
    if (-not (Test-Path -LiteralPath $reference)) {
        throw "Required setup reference is missing: $reference"
    }
}

function Get-TrustedRelativePath {
    param([string]$Root,[string]$FullName)

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    $fileFull = [IO.Path]::GetFullPath($FullName)

    if (-not $fileFull.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)) {
        throw "Package file escapes staging root: $fileFull"
    }

    return $fileFull.Substring($rootFull.Length).Replace('\','/')
}

function Replace-LiteralRegexOnce {
    param([string]$Text,[string]$Pattern,[string]$Replacement,[string]$Description)

    $regex = New-Object System.Text.RegularExpressions.Regex(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $matches = $regex.Matches($Text)
    if ($matches.Count -ne 1) {
        throw "Expected one $Description match; found $($matches.Count)."
    }

    $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return $Replacement
    }

    return $regex.Replace($Text,$evaluator,1)
}

$zip = $zips[0]
$work = Join-Path $env:TEMP ('TQR-SetupRoute-' + [Guid]::NewGuid().ToString('N'))
$root = Join-Path $work 'package'
New-Item -ItemType Directory -Path $root -Force | Out-Null

try {
    Expand-Archive -LiteralPath $zip.FullName -DestinationPath $root -Force

    $appDir = Join-Path $root 'app'
    $uiPath = Join-Path $appDir 'Tailscale-Repair-UI.ps1'
    $setupExe = Join-Path $appDir 'TailscaleQuickRepairSetup.exe'
    $versionPath = Join-Path $root 'version.json'

    foreach ($required in @($uiPath,$versionPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "Normal update package is incomplete: $required"
        }
    }

    $compileOut = Join-Path $work 'setup-compile.out'
    $compileErr = Join-Path $work 'setup-compile.err'
    $args = @(
        '/nologo',
        '/target:winexe',
        '/platform:anycpu',
        '/optimize+',
        '/main:PublicSetupEntry',
        ('/out:"{0}"' -f $setupExe)
    )
    foreach ($reference in $refs) { $args += ('/reference:"{0}"' -f $reference) }
    $args += ('"{0}"' -f (Join-Path $repo 'src\native\PublicSetupHost.cs'))
    $args += ('"{0}"' -f (Join-Path $repo 'src\native\PublicSetupEntry.cs'))

    $compile = Start-Process -FilePath $compiler -ArgumentList ($args -join ' ') `
        -RedirectStandardOutput $compileOut -RedirectStandardError $compileErr `
        -WindowStyle Hidden -Wait -PassThru

    if ($compile.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $setupExe)) {
        $details = @()
        if (Test-Path $compileOut) { $details += Get-Content $compileOut -Raw }
        if (Test-Path $compileErr) { $details += Get-Content $compileErr -Raw }
        throw "Native Setup host compilation failed.`r`n$($details -join [Environment]::NewLine)"
    }

    $setupTest = Start-Process -FilePath $setupExe -ArgumentList '--self-test-installer' `
        -WindowStyle Hidden -Wait -PassThru
    if ($setupTest.ExitCode -ne 0) {
        throw "Native Setup host self-test failed: $($setupTest.ExitCode)."
    }

    $ui = [IO.File]::ReadAllText($uiPath,[Text.Encoding]::UTF8)

    if ($ui -notmatch '(?m)^\$SetupHostPath\s*=') {
        $statePattern = '(?m)^\$StateDir\s*=\s*Join-Path\s+\$env:LOCALAPPDATA\s+''TailscaleQuickRepair''\s*$'
        $stateMatch = [regex]::Match($ui,$statePattern)
        if (-not $stateMatch.Success) { throw 'Could not locate Quick Repair StateDir declaration.' }

        $replacement = $stateMatch.Value + [Environment]::NewLine +
            '$SetupHostPath = Join-Path $StateDir ''TailscaleQuickRepairSetup.exe'''
        $ui = $ui.Remove($stateMatch.Index,$stateMatch.Length).Insert($stateMatch.Index,$replacement)
    }

    $installHeader = @'
    function Start-UpdateInstall {
        if (
            $script:repairActive -or
            -not $script:updateManifest
        ) {
            return
        }
'@

    $protectedRoute = @'
    function Start-UpdateInstall {
        if (
            $script:repairActive -or
            -not $script:updateManifest
        ) {
            return
        }

        $requiresSetup = $false
        try {
            if ($script:updateManifest.PSObject.Properties.Name -contains 'requiresSetup') {
                $requiresSetup = [bool]$script:updateManifest.requiresSetup
            }
        } catch {}

        if ($requiresSetup) {
            if (-not (Test-Path -LiteralPath $SetupHostPath)) {
                $UpdateStatusText.Text = 'Setup component is missing'
                $UpdateStatusText.Foreground = Get-Brush 'Amber'
                $UpdateDetailText.Text = 'Run Repair installation or the latest Setup before installing this system update.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                return
            }

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = $SetupHostPath
                $psi.Arguments = '--upgrade'
                $psi.UseShellExecute = $true
                $setupProcess = [System.Diagnostics.Process]::Start($psi)

                if (-not $setupProcess) {
                    throw 'The native Setup host could not start.'
                }

                $CheckForUpdatesButton.IsEnabled = $false
                $UpdateNowButton.IsEnabled = $false
                $UpdateNowButton.Content = 'Updating…'
                $UpdateStatusText.Text = 'Installing system update…'
                $UpdateStatusText.Foreground = Get-Brush 'Blue'
                $UpdateDetailText.Text = 'Approve the Windows prompt. The verified Setup host will update Quick Repair and restart it.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                $script:allowFullExit = $true

                $window.Dispatcher.BeginInvoke(
                    [System.Windows.Threading.DispatcherPriority]::Background,
                    [Action]{ $window.Close() }
                ) | Out-Null
                return
            }
            catch {
                $CheckForUpdatesButton.IsEnabled = $true
                $UpdateNowButton.IsEnabled = $true
                $UpdateNowButton.Content = 'Update now'
                $UpdateStatusText.Text = 'Could not start system update'
                $UpdateStatusText.Foreground = Get-Brush 'Amber'
                $UpdateDetailText.Text = 'Nothing was changed.'
                $UpdateDetailText.Visibility = [System.Windows.Visibility]::Visible
                return
            }
        }
'@

    $repairPattern = '(?s)    function Invoke-InstallationRepair \{.*?\r?\n    function Update-DetailsToggleText \{'
    $repairReplacement = @'
    function Invoke-InstallationRepair {
        if (-not (Test-Path -LiteralPath $SetupHostPath)) {
            Set-Badge $HeroBadge $HeroBadgeText 'SETUP ISSUE' 'failure'
            $HeroTitle.Text = 'Installation repair is unavailable'
            $HeroDetail.Text = 'Run the latest Tailscale Quick Repair Setup to restore the maintenance component.'
            return
        }

        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $SetupHostPath
            $psi.Arguments = '--repair'
            $psi.UseShellExecute = $true
            $process = [System.Diagnostics.Process]::Start($psi)
            if (-not $process) { throw 'The maintenance helper could not start.' }

            Set-Badge $HeroBadge $HeroBadgeText 'MAINTENANCE' 'repairing'
            $HeroTitle.Text = 'Repairing Quick Repair'
            $HeroDetail.Text = 'Approve the Windows prompt. Quick Repair will rebuild its protected integration and reopen automatically.'
            $RepairInstallationButton.IsEnabled = $false
            $script:allowFullExit = $true
            $global:TqrUiShutdownRequested = $true

            $window.Dispatcher.BeginInvoke(
                [System.Windows.Threading.DispatcherPriority]::Background,
                [Action]{
                    try { $window.Close() } catch {}
                }
            ) | Out-Null
        }
        catch {
            $RepairInstallationButton.IsEnabled = $true
            Set-Badge $HeroBadge $HeroBadgeText 'SETUP ISSUE' 'failure'
            $HeroTitle.Text = 'Could not start installation repair'
            $HeroDetail.Text = $_.Exception.Message
        }
    }

    function Update-DetailsToggleText {
'@

    if ($ui -notmatch [regex]::Escape("$psi.Arguments = '--repair'")) {
        $ui = Replace-LiteralRegexOnce `
            -Text $ui `
            -Pattern $repairPattern `
            -Replacement $repairReplacement `
            -Description 'native installation repair function'
    }
    if ($ui -notmatch [regex]::Escape('$requiresSetup = $false')) {
        if (-not $ui.Contains($installHeader)) {
            throw 'Could not locate native Start-UpdateInstall header.'
        }
        $ui = $ui.Replace($installHeader,$protectedRoute)
    }

    foreach ($required in @(
        '$SetupHostPath',
        '$requiresSetup = $false',
        "$psi.Arguments = '--upgrade'",
        "$psi.Arguments = '--repair'"
    )) {
        if ($ui -notmatch [regex]::Escape($required)) {
            throw "Native setup routing verification failed: $required"
        }
    }

    $headerCount = [regex]::Matches($ui,'(?m)^param\(\r?\n\s*\[switch\]\$StartInTray\r?\n\)').Count
    $xamlCount = [regex]::Matches($ui,'(?m)^\s*\[xml\]\$xaml\s*=\s*@"').Count
    if ($headerCount -ne 1 -or $xamlCount -ne 1) {
        throw "Routed UI must remain one script. Headers=$headerCount Xaml=$xamlCount"
    }

    [void][scriptblock]::Create($ui)
    $xamlMatch = [regex]::Match($ui,'(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@')
    if (-not $xamlMatch.Success) { throw 'Routed UI XAML was not found.' }
    [xml]$xamlDoc = $xamlMatch.Groups['xaml'].Value
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    $reader = New-Object System.Xml.XmlNodeReader $xamlDoc
    $testWindow = $null
    try {
        $testWindow = [Windows.Markup.XamlReader]::Load($reader)
        if (-not $testWindow) { throw 'Routed UI WPF validation returned no window.' }
    }
    finally {
        try { $reader.Close() } catch {}
        try { if ($testWindow -is [System.Windows.Window]) { $testWindow.Close() } } catch {}
    }

    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($uiPath,$ui,$utf8Bom)

    $version = Get-Content -LiteralPath $versionPath -Raw | ConvertFrom-Json

    # Phase 3.1 cryptographic integrity: create a release-matched manifest for
    # user-level Quick Repair components after all transforms have finished.
    $integrityManifestPath = Join-Path $appDir 'integrity-manifest.json'
    Remove-Item -LiteralPath $integrityManifestPath -Force -ErrorAction SilentlyContinue

    $integrityFiles = @(
        Get-ChildItem -LiteralPath $appDir -File |
            Where-Object { $_.Name -ne 'integrity-manifest.json' } |
            Sort-Object Name |
            ForEach-Object {
                [ordered]@{
                    path = $_.Name
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    size = [int64]$_.Length
                }
            }
    )

    foreach ($requiredIntegrityFile in @(
        'Tailscale-Repair-UI.ps1',
        'TailscaleQuickRepairUpdater.exe',
        'TailscaleQuickRepairSetup.exe'
    )) {
        if ($requiredIntegrityFile -notin @($integrityFiles | ForEach-Object { $_.path })) {
            throw "Integrity manifest is missing required app component: $requiredIntegrityFile"
        }
    }

    $integrityManifest = [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = [string]$version.version
        versionCode = [int64]$version.versionCode
        algorithm = 'SHA256'
        files = $integrityFiles
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText(
        $integrityManifestPath,
        ($integrityManifest | ConvertTo-Json -Depth 8),
        $utf8NoBom
    )

    $integrityRoundTrip = Get-Content -LiteralPath $integrityManifestPath -Raw | ConvertFrom-Json

    if (
        [int]$integrityRoundTrip.schema -ne 1 -or
        [int64]$integrityRoundTrip.versionCode -ne [int64]$version.versionCode -or
        [string]$integrityRoundTrip.algorithm -ne 'SHA256'
    ) {
        throw 'Integrity manifest round-trip validation failed.'
    }

    foreach ($integrityEntry in @($integrityRoundTrip.files)) {
        $name = [string]$integrityEntry.path
        $hash = ([string]$integrityEntry.sha256).ToLowerInvariant()
        $size = [int64]$integrityEntry.size

        if (
            [string]::IsNullOrWhiteSpace($name) -or
            $name -match '[\\/]' -or
            $hash -notmatch '^[a-f0-9]{64}
        Get-ChildItem -LiteralPath $root -File -Recurse |
            Where-Object { $_.Name -ne 'package-manifest.json' } |
            ForEach-Object {
                [ordered]@{
                    path = Get-TrustedRelativePath -Root $root -FullName $_.FullName
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    size = [int64]$_.Length
                }
            } |
            Sort-Object { $_.path }
    )

    if ('app/TailscaleQuickRepairSetup.exe' -notin @($entries | ForEach-Object { $_.path })) {
        throw 'Native Setup host did not enter the update package.'
    }

    $manifest = [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = [string]$version.version
        versionCode = [int64]$version.versionCode
        files = $entries
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'package-manifest.json') -Encoding UTF8

    & (Join-Path $PSScriptRoot 'privacy-scan.ps1') -Root $root -SkipRepositoryIdentity

    Remove-Item -LiteralPath $zip.FullName -Force
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $zip.FullName -CompressionLevel Optimal

    $sha = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha | Set-Content -LiteralPath ($zip.FullName + '.sha256') -Encoding ASCII

    Write-Host "Native setup routing passed: $($version.version) ($($version.versionCode))"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
 -or
            $size -lt 0
        ) {
            throw 'Integrity manifest contains invalid file metadata.'
        }

        $candidate = Join-Path $appDir $name

        if (
            -not (Test-Path -LiteralPath $candidate -PathType Leaf) -or
            (Get-Item -LiteralPath $candidate).Length -ne $size -or
            (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant() -ne $hash
        ) {
            throw "Integrity manifest verification failed: $name"
        }
    }

    Write-Host "Guardian integrity manifest passed: $($integrityFiles.Count) app files."

    $entries = @(
        Get-ChildItem -LiteralPath $root -File -Recurse |
            Where-Object { $_.Name -ne 'package-manifest.json' } |
            ForEach-Object {
                [ordered]@{
                    path = Get-TrustedRelativePath -Root $root -FullName $_.FullName
                    sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    size = [int64]$_.Length
                }
            } |
            Sort-Object { $_.path }
    )

    if ('app/TailscaleQuickRepairSetup.exe' -notin @($entries | ForEach-Object { $_.path })) {
        throw 'Native Setup host did not enter the update package.'
    }

    $manifest = [ordered]@{
        schema = 1
        product = 'Tailscale Quick Repair'
        version = [string]$version.version
        versionCode = [int64]$version.versionCode
        files = $entries
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $root 'package-manifest.json') -Encoding UTF8

    & (Join-Path $PSScriptRoot 'privacy-scan.ps1') -Root $root -SkipRepositoryIdentity

    Remove-Item -LiteralPath $zip.FullName -Force
    Compress-Archive -Path (Join-Path $root '*') -DestinationPath $zip.FullName -CompressionLevel Optimal

    $sha = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $sha | Set-Content -LiteralPath ($zip.FullName + '.sha256') -Encoding ASCII

    Write-Host "Native setup routing passed: $($version.version) ($($version.versionCode))"
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
