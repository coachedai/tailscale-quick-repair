[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$ResultPath = '',
    [switch]$ElevatedApply,
    [string]$RequesterSid = '',
    [switch]$CiNoElevation,
    [switch]$CiNoRelaunch
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version 2

$ExpectedVersion = '3.0.0-phase6.4.0-preview'
$ExpectedCode = [int64]30000740
$BaselineVersion = '3.0.0-phase5.2.1'
$BaselineCode = [int64]30000621
$StateDir = Join-Path $env:LOCALAPPDATA 'TailscaleQuickRepair'
$ProgramDir = Join-Path $env:ProgramData 'TailscaleQuickRepair'
$VersionPath = Join-Path $StateDir 'version.user.json'
$MarkerPath = Join-Path $StateDir 'protected-update.json'
$AutoRepairSettingsPath = Join-Path $StateDir 'auto-repair.json'
$RestartRegistryPath = 'HKCU:\Software\TailscaleQuickRepair'
$RestartRegistryName = 'PendingRestartVersionCode'
$script:WorkRoots = New-Object 'Collections.Generic.List[string]'
$script:LeaseType = $null
$script:LeaseHeld = $false

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path $OutputDirectory 'phase6.4-field-result.json'
}

$result = [ordered]@{
    schema = 1
    version = $ExpectedVersion
    versionCode = $ExpectedCode
    stage = 'preflight'
    baselineVerified = $false
    bridgeVerified = $false
    bridgeApplied = $false
    elevationRequested = $false
    elevationCancelled = $false
    protectedUnchangedOnCancel = $false
    requesterIdentityVerified = $false
    protectedPackageVerified = $false
    protectedApplied = $false
    restartAcknowledged = $false
    autoRepairWasOff = $false
    passed = $false
    error = ''
}

function Save-Result {
    try {
        $parent = Split-Path -Parent $ResultPath
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    } catch {}
}

function Fail([string]$Message) {
    $result.error = $Message
    Save-Result
    throw $Message
}

function New-WorkRoot([string]$Name) {
    $root = Join-Path $env:TEMP ($Name + '-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $script:WorkRoots.Add($root)
    return $root
}

function Get-OneCandidate([string]$Pattern) {
    $items = @(Get-ChildItem -LiteralPath $OutputDirectory -Filter $Pattern -File -ErrorAction Stop)
    if ($items.Count -ne 1) { Fail "Expected exactly one candidate file matching $Pattern." }
    return $items[0].FullName
}

function Assert-Sidecar([string]$File) {
    $sidecar = $File + '.sha256'
    if (-not (Test-Path -LiteralPath $sidecar -PathType Leaf)) { Fail "Missing SHA-256 sidecar for $([IO.Path]::GetFileName($File))." }
    $expected = ([IO.File]::ReadAllText($sidecar,[Text.Encoding]::ASCII)).Trim().ToLowerInvariant()
    if ($expected -notmatch '^[0-9a-f]{64}$') { Fail 'Candidate SHA-256 sidecar is invalid.' }
    $actual = (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -cne $expected) { Fail "Candidate file hash mismatch: $([IO.Path]::GetFileName($File))." }
}

function Expand-Candidate([string]$Zip,[bool]$AllowProgram,[bool]$RequireMarker) {
    Assert-Sidecar $Zip
    $root = New-WorkRoot 'TqrFieldPreview'
    Expand-Archive -LiteralPath $Zip -DestinationPath $root -Force
    $manifestPath = Join-Path $root 'package-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { Fail 'Candidate package manifest is missing.' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    if ($manifest.schema -ne 1 -or [string]$manifest.version -cne $ExpectedVersion -or [int64]$manifest.versionCode -ne $ExpectedCode) {
        Fail 'Candidate package identity does not match the Phase 6.4 preview.'
    }
    $declared = @($manifest.files)
    if ($declared.Count -lt 1) { Fail 'Candidate package contains no declared files.' }
    $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    $markerCount = 0
    foreach ($entry in $declared) {
        $relative = ([string]$entry.path).Replace('\\','/')
        if ([string]::IsNullOrWhiteSpace($relative) -or $relative.Contains('..') -or $relative.StartsWith('/') -or $relative.Contains(':')) {
            Fail 'Candidate package contains an unsafe path.'
        }
        if (-not $seen.Add($relative)) { Fail 'Candidate package contains a duplicate path.' }
        if (-not $AllowProgram -and $relative.StartsWith('program/',[StringComparison]::OrdinalIgnoreCase)) {
            Fail 'The ordinary preview package unexpectedly contains protected program files.'
        }
        if ($relative -ieq 'app/protected-update.json') { $markerCount++ }
        $file = Join-Path $root ($relative.Replace('/',[IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Fail "Candidate package file is missing: $relative" }
        if ((Get-Item -LiteralPath $file).Length -ne [int64]$entry.size) { Fail "Candidate package file size mismatch: $relative" }
        if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne ([string]$entry.sha256).ToLowerInvariant()) {
            Fail "Candidate package file hash mismatch: $relative"
        }
    }
    $archive = [IO.Compression.ZipFile]::OpenRead($Zip)
    try {
        $members = New-Object 'Collections.Generic.List[string]'
        $manifestMembers = 0
        foreach ($zipEntry in $archive.Entries) {
            $name = ([string]$zipEntry.FullName).Replace('\','/')
            if ([string]::IsNullOrWhiteSpace($name) -or $name.Contains('..') -or $name.StartsWith('/') -or $name.Contains(':')) {
                Fail 'Candidate archive contains an unsafe member path.'
            }
            if ([string]::IsNullOrEmpty([string]$zipEntry.Name)) {
                continue
            }
            if ($name -ceq 'package-manifest.json') {
                $manifestMembers++
                continue
            }
            $members.Add($name)
        }
        if ($manifestMembers -ne 1) { Fail 'Candidate archive must contain exactly one package manifest.' }
        if ($members.Count -ne $seen.Count) {
            Fail "Candidate archive membership count does not match its manifest ($($members.Count) archive files / $($seen.Count) declared)."
        }
        foreach ($relative in $members) {
            if (-not $seen.Contains($relative)) { Fail "Candidate archive contains an undeclared payload file: $relative" }
        }
    }
    finally {
        $archive.Dispose()
    }
    if ($RequireMarker -and $markerCount -ne 1) { Fail 'The ordinary preview package must contain exactly one protected-update marker.' }
    if (-not $RequireMarker -and $markerCount -ne 0) { Fail 'The protected Setup package must not contain the bridge-only marker.' }
    return [pscustomobject]@{ root=$root; manifest=$manifest }
}

function Invoke-Private([Type]$Type,[string]$Name,[object[]]$Arguments=@()) {
    $method = $Type.GetMethod($Name,[Reflection.BindingFlags]'NonPublic,Static')
    if (-not $method) { Fail "Required preview boundary is missing: $Name" }
    try { return $method.Invoke($null,$Arguments) }
    catch {
        $ex = $_.Exception
        while ($ex.InnerException) { $ex = $ex.InnerException }
        throw $ex
    }
}

function Current-Sid {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $identity -or -not $identity.User) { Fail 'The current Windows account could not be verified.' }
    $sid = $identity.User.Value
    if ($sid -notmatch '^S-1-[0-9-]+$') { Fail 'The current Windows SID is invalid.' }
    return $sid
}

function Assert-AutoRepairOff {
    if (-not (Test-Path -LiteralPath $AutoRepairSettingsPath -PathType Leaf)) {
        $result.autoRepairWasOff = $true
        return
    }
    try {
        $settings = Get-Content -LiteralPath $AutoRepairSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $names = @($settings.PSObject.Properties.Name)
        if ('enabled' -notin $names -or $settings.enabled -isnot [bool]) { Fail 'Auto Repair settings are not readable safely.' }
        if ([bool]$settings.enabled) { Fail 'Turn Auto Repair off before the initial Phase 6.4 field upgrade.' }
        $result.autoRepairWasOff = $true
    } catch { Fail 'Auto Repair settings could not be verified. No field upgrade was started.' }
}

function Assert-NoQuickRepairUi {
    $busy = $false
    try {
        foreach ($p in Get-CimInstance Win32_Process -ErrorAction Stop) {
            $name = [string]$p.Name
            $line = [string]$p.CommandLine
            if ($name -ieq 'TailscaleQuickRepair.exe' -or $line -match 'Tailscale-Repair-UI\.ps1') { $busy = $true; break }
        }
    } catch { Fail 'Could not verify that Quick Repair is closed.' }
    if ($busy) { Fail 'Exit Quick Repair from its tray menu before running the Phase 6.4 field preview.' }
}

function Get-ProtectedBaselineHashes {
    $hashes = [ordered]@{}
    foreach ($name in @('Repair-Backend.ps1','Auto-Repair-Monitor.ps1','TailscaleQuickRepair.Operations.dll')) {
        $path = Join-Path $ProgramDir $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $hashes[$name] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        }
    }
    return $hashes
}

function Assert-ProtectedHashesUnchanged($Before) {
    if (-not $Before) { return $true }
    foreach ($name in $Before.Keys) {
        $path = Join-Path $ProgramDir $name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() -cne [string]$Before[$name]) { return $false }
    }
    return $true
}

function Read-InstalledVersion {
    if (-not (Test-Path -LiteralPath $VersionPath -PathType Leaf)) { Fail 'Quick Repair is not installed for this Windows account.' }
    try { return (Get-Content -LiteralPath $VersionPath -Raw | ConvertFrom-Json -ErrorAction Stop) }
    catch { Fail 'The installed Quick Repair version record is invalid.' }
}

function Stage-Bridge($ordinary) {
    $installed = Read-InstalledVersion
    if ([int64]$installed.versionCode -eq $ExpectedCode -and (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        $result.bridgeApplied = $true
        return
    }
    if ([int64]$installed.versionCode -ne $BaselineCode -or [string]$installed.version -cne $BaselineVersion) {
        Fail 'Field preview staging requires the genuine 5.2.1 starting version, or an already-staged 6.4 bridge.'
    }
    $result.baselineVerified = $true
    Assert-NoQuickRepairUi
    $installedUpdater = Join-Path $StateDir 'TailscaleQuickRepairUpdater.exe'
    if (-not (Test-Path -LiteralPath $installedUpdater -PathType Leaf)) { Fail 'The installed 5.2.1 updater is missing.' }
    $tempUpdater = Join-Path (New-WorkRoot 'TqrFieldUpdater') 'TailscaleQuickRepairUpdater.exe'
    Copy-Item -LiteralPath $installedUpdater -Destination $tempUpdater -Force
    $type = [Reflection.Assembly]::LoadFile($tempUpdater).GetType('Program')
    if (-not $type) { Fail 'The installed 5.2.1 updater host is not valid.' }
    $manifest = Invoke-Private $type 'ReadPackageManifest' @($ordinary.root)
    if ([string]$manifest.Version -cne $ExpectedVersion -or [int64]$manifest.VersionCode -ne $ExpectedCode) { Fail 'The staged package identity is wrong.' }
    $files = Invoke-Private $type 'VerifyPackageFiles' @($ordinary.root,$manifest)
    if (@($files).Count -lt 1) { Fail 'The released updater rejected the preview bridge.' }
    $lease = [bool](Invoke-Private $type 'TryAcquireOperationLock' @('update'))
    if (-not $lease) { Fail 'Another Quick Repair operation is active. No bridge was applied.' }
    $script:LeaseType = $type
    $script:LeaseHeld = $true
    try {
        [void](Invoke-Private $type 'ApplyTransaction' @($files,[string]$manifest.Version,[int64]$manifest.VersionCode))
    } finally {
        [void](Invoke-Private $type 'ReleaseOperationLock')
        $script:LeaseHeld = $false
    }
    $after = Read-InstalledVersion
    if ([int64]$after.versionCode -ne $ExpectedCode -or -not (Test-Path -LiteralPath $MarkerPath -PathType Leaf)) {
        Fail 'The 5.2.1 updater did not leave the expected protected bridge state.'
    }
    $result.bridgeApplied = $true
}

function Apply-Protected($protected,[string]$ExpectedRequesterSid) {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Fail 'The protected field stage is not running with administrator approval.'
    }
    $currentSid = Current-Sid
    if ([string]::IsNullOrWhiteSpace($ExpectedRequesterSid) -or $currentSid -cne $ExpectedRequesterSid) {
        Fail 'Administrator approval used a different Windows account. Protected changes were refused.'
    }
    $result.requesterIdentityVerified = $true
    $setup = Join-Path $StateDir 'TailscaleQuickRepairSetup.exe'
    if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { Fail 'The refreshed Setup host is missing after bridge staging.' }
    $type = [Reflection.Assembly]::LoadFile($setup).GetType('PublicSetupHost')
    if (-not $type) { Fail 'The refreshed Setup host is invalid.' }
    [void](Invoke-Private $type 'RequireRequesterIdentity' @($ExpectedRequesterSid))
    [void](Invoke-Private $type 'RecoverInterruptedFileTransaction')
    $manifest = Invoke-Private $type 'ReadPackageManifest' @($protected.root)
    if ([string]$manifest.Version -cne $ExpectedVersion -or [int64]$manifest.VersionCode -ne $ExpectedCode) { Fail 'The protected package identity is wrong.' }
    $files = Invoke-Private $type 'VerifyPackage' @($protected.root,$manifest)
    [void](Invoke-Private $type 'ValidateProtectedUpdateMarker' @([int64]$manifest.VersionCode))
    $result.protectedPackageVerified = $true
    $peer = [string](Invoke-Private $type 'ReadConfiguredPeer')
    $startup = [bool](Invoke-Private $type 'IsStartupEnabled')
    $lease = [bool](Invoke-Private $type 'TryAcquireUpgradeOperationLock')
    if (-not $lease) { Fail 'Another Quick Repair operation is active. Protected changes were not started.' }
    $script:LeaseType = $type
    $script:LeaseHeld = $true
    $work = New-WorkRoot 'TqrFieldProtected'
    try {
        [void](Invoke-Private $type 'StopQuickRepair')
        [void](Invoke-Private $type 'ApplyFiles' @($files,$work))
        [void](Invoke-Private $type 'CompleteInstalledIntegration' @($peer,$startup,$true,[int64]$manifest.VersionCode))
        $result.protectedApplied = $true
        if (-not $CiNoRelaunch) { [void](Invoke-Private $type 'StartQuickRepair') }
    } finally {
        [void](Invoke-Private $type 'ReleaseOperationLock')
        $script:LeaseHeld = $false
    }
}

try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) { Fail 'The validated candidate folder was not found.' }
    $OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
    $ordinaryZip = Get-OneCandidate 'TailscaleQuickRepair-3.0.0-phase6.4.0-preview.zip'
    $setupZip = Get-OneCandidate 'TailscaleQuickRepair-SetupPackage-3.0.0-phase6.4.0-preview.zip'
    $ordinary = Expand-Candidate $ordinaryZip $false $true
    $protected = Expand-Candidate $setupZip $true $false
    $result.bridgeVerified = $true
    $result.protectedPackageVerified = $true

    if ($ElevatedApply) {
        $result.stage = 'protected_apply'
        Apply-Protected $protected $RequesterSid
        $result.passed = $true
        Save-Result
        exit 0
    }

    $result.stage = 'baseline'
    Assert-AutoRepairOff
    $sid = Current-Sid
    $protectedBefore = Get-ProtectedBaselineHashes
    Stage-Bridge $ordinary

    if ($CiNoElevation) {
        if ($env:GITHUB_ACTIONS -cne 'true' -or $env:RUNNER_ENVIRONMENT -cne 'github-hosted' -or $env:GITHUB_REPOSITORY -cne 'coachedai/tailscale-quick-repair') {
            Fail 'No-elevation mode is restricted to the disposable GitHub acceptance runner.'
        }
        $result.stage = 'ci_protected_apply'
        Apply-Protected $protected $sid
    } else {
        $result.stage = 'uac'
        $result.elevationRequested = $true
        Save-Result
        $powershell = Join-Path $PSHOME 'powershell.exe'
        $args = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '" -OutputDirectory "' + $OutputDirectory + '" -ResultPath "' + $ResultPath + '" -ElevatedApply -RequesterSid "' + $sid + '"'
        try {
            $process = Start-Process -FilePath $powershell -ArgumentList $args -Verb RunAs -PassThru -Wait -ErrorAction Stop
        } catch {
            if ($_.Exception.HResult -eq -2147467259 -or $_.Exception.Message -match 'cancel') {
                $result.elevationCancelled = $true
                $result.protectedUnchangedOnCancel = Assert-ProtectedHashesUnchanged $protectedBefore
                if (-not $result.protectedUnchangedOnCancel) {
                    Fail 'Windows approval was cancelled, but protected files did not remain unchanged.'
                }
                $result.error = ''
                Save-Result
                Write-Host 'Windows approval was cancelled. The verified user-level bridge remains staged; protected files were unchanged. Rerun this field tool to retry.'
                exit 2
            }
            throw
        }
        if (-not $process -or $process.ExitCode -ne 0) { Fail 'The protected field stage did not complete.' }
        if (Test-Path -LiteralPath $ResultPath -PathType Leaf) {
            $child = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if (-not [bool]$child.passed -or -not [bool]$child.protectedApplied) { Fail 'The elevated protected stage did not report success.' }
            $result.requesterIdentityVerified = [bool]$child.requesterIdentityVerified
            $result.protectedApplied = [bool]$child.protectedApplied
        }
    }

    $result.stage = 'restart_acknowledgement'
    if (-not $CiNoRelaunch) {
        $deadline = [DateTime]::UtcNow.AddSeconds(30)
        do {
            Start-Sleep -Milliseconds 500
            $pending = Get-ItemProperty -LiteralPath $RestartRegistryPath -Name $RestartRegistryName -ErrorAction SilentlyContinue
            if (-not $pending -or $null -eq $pending.$RestartRegistryName) { $result.restartAcknowledged = $true; break }
        } while ([DateTime]::UtcNow -lt $deadline)
        if (-not $result.restartAcknowledged) { Fail 'The preview installed, but the restarted app did not acknowledge the protected update.' }
    }

    if (Test-Path -LiteralPath $MarkerPath) { Fail 'The protected-update marker still exists after protected completion.' }
    $installed = Read-InstalledVersion
    if ([int64]$installed.versionCode -ne $ExpectedCode -or [string]$installed.version -cne $ExpectedVersion) { Fail 'The installed preview version record is wrong.' }
    $result.passed = $true
    $result.stage = 'complete'
    Save-Result
    Write-Host 'Phase 6.4 field preview completed successfully.'
    exit 0
}
catch {
    if ([string]::IsNullOrWhiteSpace([string]$result.error)) { $result.error = $_.Exception.Message }
    Save-Result
    Write-Error $_.Exception.Message
    exit 1
}
finally {
    if ($script:LeaseHeld -and $script:LeaseType) {
        try { [void](Invoke-Private $script:LeaseType 'ReleaseOperationLock') } catch {}
    }
    foreach ($root in @($script:WorkRoots.ToArray())) {
        try { if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force } } catch {}
    }
}
