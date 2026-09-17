param(
    [Parameter(Mandatory=$true)]
    [string]$PackagePath,

    [Parameter(Mandatory=$true)]
    [string]$ExpectedSha256,

    [Parameter(Mandatory=$true)]
    [Int64]$TargetVersionCode,

    [Parameter(Mandatory=$true)]
    [int]$CurrentProcessId
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$appDir = Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$programDir = Join-Path $env:ProgramData 'TailscaleQuickRepair'
$resultPath = Join-Path $appDir 'update-result.json'
$rollbackDir = Join-Path $programDir 'UpdateRollback'
$pendingMarker = Join-Path $programDir 'Update.pending'
$workDir = Join-Path $env:TEMP ('TailscaleQuickRepair-Apply-' + [Guid]::NewGuid().ToString('N'))

function Write-Result {
    param(
        [bool]$Success,
        [string]$Version = '',
        [string]$Message = ''
    )

    try {
        New-Item -ItemType Directory -Path $appDir -Force | Out-Null

        $obj = [ordered]@{
            success = $Success
            version = $Version
            message = $Message
            completedUtc = [DateTime]::UtcNow.ToString('o')
        }

        $tmp = "$resultPath.$PID.tmp"
        $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $tmp -Encoding UTF8
        Move-Item -LiteralPath $tmp -Destination $resultPath -Force
    }
    catch {}
}

function Get-TargetPath {
    param([string]$RelativePath)

    $normalized = $RelativePath -replace '\\','/'

    if ($normalized -eq 'version.json') {
        return Join-Path $programDir 'version.json'
    }

    if ($normalized.StartsWith('app/', [StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $appDir $normalized.Substring(4).Replace('/','\')
    }

    if ($normalized.StartsWith('program/', [StringComparison]::OrdinalIgnoreCase)) {
        return Join-Path $programDir $normalized.Substring(8).Replace('/','\')
    }

    if ($normalized.StartsWith('launchers/', [StringComparison]::OrdinalIgnoreCase)) {
        $leaf = [IO.Path]::GetFileName($normalized)

        if ($leaf -in @(
            'Launch-Tailscale-Quick-Repair.vbs',
            'Launch-Tailscale-Quick-Repair-Startup.vbs'
        )) {
            return Join-Path $appDir $leaf
        }

        return Join-Path $programDir $leaf
    }

    throw "Unsupported update path: $RelativePath"
}

function Restore-Backup {
    if (-not (Test-Path -LiteralPath $rollbackDir)) {
        return
    }

    $mapPath = Join-Path $rollbackDir 'rollback-map.json'

    if (-not (Test-Path -LiteralPath $mapPath)) {
        return
    }

    $map = Get-Content -LiteralPath $mapPath -Raw | ConvertFrom-Json

    foreach ($entry in @($map.files)) {
        try {
            $target = [string]$entry.target
            $backup = [string]$entry.backup
            $existed = [bool]$entry.existed

            if ($existed -and (Test-Path -LiteralPath $backup)) {
                $parent = Split-Path -Parent $target
                if ($parent) {
                    New-Item -ItemType Directory -Path $parent -Force | Out-Null
                }

                Copy-Item -LiteralPath $backup -Destination $target -Force
            }
            elseif (-not $existed) {
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            }
        }
        catch {}
    }
}

function Start-QuickRepair {
    try {
        $exe = Join-Path $appDir 'TailscaleQuickRepair.exe'

        if (Test-Path -LiteralPath $exe) {
            Start-Process -FilePath $exe | Out-Null
            return
        }

        $launcher = Join-Path $appDir 'Launch-Tailscale-Quick-Repair.vbs'

        if (Test-Path -LiteralPath $launcher) {
            Start-Process -FilePath 'wscript.exe' -ArgumentList ('"' + $launcher + '"') | Out-Null
        }
    }
    catch {}
}

try {
    $principal = New-Object Security.Principal.WindowsPrincipal(
        [Security.Principal.WindowsIdentity]::GetCurrent()
    )

    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'The updater is not running with Administrator approval.'
    }

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw 'The downloaded update package is missing.'
    }

    $expected = $ExpectedSha256.Trim().ToLowerInvariant()

    if ($expected -notmatch '^[a-f0-9]{64}$') {
        throw 'The expected package hash is invalid.'
    }

    if ($CurrentProcessId -gt 0) {
        try {
            $current = Get-Process -Id $CurrentProcessId -ErrorAction Stop

            if (-not $current.WaitForExit(20000)) {
                throw 'Quick Repair did not close in time.'
            }
        }
        catch [ArgumentException] {}
    }

    $actual = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($actual -ne $expected) {
        throw 'The downloaded package failed SHA-256 verification.'
    }

    New-Item -ItemType Directory -Path $workDir -Force | Out-Null
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $workDir -Force

    $manifestPath = Join-Path $workDir 'package-manifest.json'

    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw 'The update package has no package-manifest.json.'
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

    if (
        [int]$manifest.schema -ne 1 -or
        [int64]$manifest.versionCode -ne $TargetVersionCode -or
        [string]::IsNullOrWhiteSpace([string]$manifest.version)
    ) {
        throw 'The package manifest does not match the requested update.'
    }

    $root = [IO.Path]::GetFullPath($workDir)
    $verified = New-Object 'System.Collections.Generic.List[object]'

    foreach ($file in @($manifest.files)) {
        $relative = [string]$file.path
        $expectedFileHash = ([string]$file.sha256).ToLowerInvariant()

        if (
            [string]::IsNullOrWhiteSpace($relative) -or
            $expectedFileHash -notmatch '^[a-f0-9]{64}$'
        ) {
            throw 'The package contains an invalid file manifest entry.'
        }

        $source = [IO.Path]::GetFullPath(
            (Join-Path $workDir ($relative -replace '/','\'))
        )

        if (-not $source.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Package path escapes staging root: $relative"
        }

        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Package file is missing: $relative"
        }

        $hash = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()

        if ($hash -ne $expectedFileHash) {
            throw "Package file hash mismatch: $relative"
        }

        if ([IO.Path]::GetExtension($source) -ieq '.ps1') {
            $scriptText = Get-Content -LiteralPath $source -Raw
            [void][scriptblock]::Create($scriptText)
        }

        $target = Get-TargetPath $relative

        $verified.Add([pscustomobject]@{
            relative = $relative
            source = $source
            target = $target
            sha256 = $expectedFileHash
        })
    }

    $uiEntry = @($verified | Where-Object {
        $_.relative -ieq 'app/Tailscale-Repair-UI.ps1'
    } | Select-Object -First 1)

    if ($uiEntry) {
        $uiText = Get-Content -LiteralPath $uiEntry.source -Raw
        $match = [regex]::Match(
            $uiText,
            '(?s)\[xml\]\$xaml\s*=\s*@"\r?\n(?<xaml>.*?)\r?\n"@'
        )

        if (-not $match.Success) {
            throw 'The updated UI does not contain a valid XAML block.'
        }

        [xml]$xamlDocument = $match.Groups['xaml'].Value
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        Add-Type -AssemblyName PresentationCore -ErrorAction Stop
        Add-Type -AssemblyName WindowsBase -ErrorAction Stop

        $reader = New-Object System.Xml.XmlNodeReader $xamlDocument
        $testWindow = $null

        try {
            $testWindow = [Windows.Markup.XamlReader]::Load($reader)

            if (-not $testWindow) {
                throw 'The updated WPF UI failed its load test.'
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
    }

    $touchesProgram = @($verified | Where-Object {
        $_.relative -like 'program/*' -or $_.relative -like 'launchers/*'
    }).Count -gt 0

    if ($touchesProgram) {
        foreach ($taskName in @(
            'Tailscale Quick Repair',
            'Tailscale Quick Repair Auto Monitor'
        )) {
            try {
                Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            }
            catch {}
        }
    }

    Remove-Item -LiteralPath $rollbackDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $rollbackDir -Force | Out-Null

    $rollbackEntries = @()
    $counter = 0

    foreach ($entry in $verified) {
        $counter++
        $target = [string]$entry.target
        $exists = Test-Path -LiteralPath $target -PathType Leaf
        $backup = Join-Path $rollbackDir ("file-$counter.bak")

        if ($exists) {
            Copy-Item -LiteralPath $target -Destination $backup -Force
        }

        $rollbackEntries += [ordered]@{
            target = $target
            backup = $backup
            existed = $exists
        }
    }

    $rollbackMap = [ordered]@{
        version = [string]$manifest.version
        createdUtc = [DateTime]::UtcNow.ToString('o')
        files = $rollbackEntries
    }

    $rollbackMap |
        ConvertTo-Json -Depth 6 |
        Set-Content -LiteralPath (Join-Path $rollbackDir 'rollback-map.json') -Encoding UTF8

    [IO.File]::WriteAllText(
        $pendingMarker,
        ([DateTime]::UtcNow.ToString('o'))
    )

    try {
        foreach ($entry in $verified) {
            $target = [string]$entry.target
            $parent = Split-Path -Parent $target

            if ($parent) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }

            $newPath = "$target.$PID.new"
            Copy-Item -LiteralPath $entry.source -Destination $newPath -Force
            Move-Item -LiteralPath $newPath -Destination $target -Force
        }

        $userVersionPath = Join-Path $appDir 'version.user.json'
        $versionObject = [ordered]@{
            product = 'Tailscale Quick Repair'
            version = [string]$manifest.version
            versionCode = [int64]$manifest.versionCode
            channel = 'preview'
            updateSchema = 1
            configSchema = 1
        }

        $versionObject |
            ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $userVersionPath -Encoding UTF8

        foreach ($entry in $verified) {
            if (-not (Test-Path -LiteralPath $entry.target -PathType Leaf)) {
                throw "Installed update file is missing: $($entry.relative)"
            }

            $installedHash = (
                Get-FileHash -LiteralPath $entry.target -Algorithm SHA256
            ).Hash.ToLowerInvariant()

            if ($installedHash -ne $entry.sha256) {
                throw "Installed file verification failed: $($entry.relative)"
            }
        }

        Remove-Item -LiteralPath $pendingMarker -Force -ErrorAction SilentlyContinue

        Write-Result `
            -Success $true `
            -Version ([string]$manifest.version) `
            -Message 'Update installed successfully.'

        Remove-Item -LiteralPath $PackagePath -Force -ErrorAction SilentlyContinue
        Start-QuickRepair
        exit 0
    }
    catch {
        Restore-Backup
        Remove-Item -LiteralPath $pendingMarker -Force -ErrorAction SilentlyContinue

        Write-Result `
            -Success $false `
            -Version ([string]$manifest.version) `
            -Message ('Update failed and was rolled back: ' + $_.Exception.Message)

        Start-QuickRepair
        exit 20
    }
}
catch {
    Write-Result `
        -Success $false `
        -Message ('Update could not be installed: ' + $_.Exception.Message)

    Start-QuickRepair
    exit 10
}
finally {
    Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
}
